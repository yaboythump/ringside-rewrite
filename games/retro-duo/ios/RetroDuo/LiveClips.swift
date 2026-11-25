import AVFoundation
import CoreMedia
import Foundation

/// Keeps the last stretch of a live stream exactly as it was sent (H.264 + AAC), so a clip of the
/// last 30 seconds can be saved as an MP4 without encoding anything again.
/// Not thread-safe: LiveStreamCore uses it on its own queue.
final class ClipRecorder {
    struct VideoSample {
        var data: Data
        var keyframe: Bool
        var time: Double
        /// Exactly (frame number / fps): rounded seconds would let samples overlap by a tick,
        /// which the MP4 writer refuses.
        var stamp: CMTime
    }

    struct AudioSample {
        var data: Data
        var time: Double
        var stamp: CMTime
    }

    /// Everything needed to write one clip.
    struct Clip {
        var sps: Data
        var pps: Data
        var audioDescription: AudioStreamBasicDescription
        var audioCookie: Data?
        var fps: Int
        var video: [VideoSample]
        var audio: [AudioSample]
        var duration: Double { (video.last?.time ?? 0) - (video.first?.time ?? 0) + 1 / Double(max(fps, 1)) }
    }

    enum Failure: Error, Equatable {
        case nothingYet
        case writer(String)
    }

    /// Seconds kept (a little more than a clip, so a clip can start on a keyframe).
    let keep: Double
    let fps: Int
    private(set) var sps: Data?
    private(set) var pps: Data?
    var audioDescription: AudioStreamBasicDescription?
    var audioCookie: Data?
    private(set) var video: [VideoSample] = []
    private(set) var audio: [AudioSample] = []

    init(keep: Double = 36, fps: Int) {
        self.keep = keep
        self.fps = fps
    }

    var latest: Double { max(video.last?.time ?? 0, audio.last?.time ?? 0) }

    func add(video frame: EncodedVideoFrame) {
        if let sps = frame.sps, let pps = frame.pps {
            // New parameter sets: earlier frames can't be decoded with them.
            if sps != self.sps || pps != self.pps { video.removeAll() }
            self.sps = sps
            self.pps = pps
        }
        guard sps != nil, frame.keyframe || !video.isEmpty else { return }
        video.append(VideoSample(data: frame.data, keyframe: frame.keyframe, time: Double(frame.frameIndex) / Double(fps),
                                 stamp: CMTime(value: frame.frameIndex, timescale: CMTimeScale(fps))))
        prune()
    }

    /// The `index`th AAC packet of the stream (1024 frames at 48 kHz each).
    func add(audio packet: Data, index: Int64) {
        let stamp = CMTime(value: index * Int64(AACEncoder.framesPerPacket), timescale: 48_000)
        audio.append(AudioSample(data: packet, time: stamp.seconds, stamp: stamp))
        prune()
    }

    /// Drops what's older than `keep`, always leaving the video starting on a keyframe.
    private func prune() {
        let cutoff = latest - keep
        if let index = video.lastIndex(where: { $0.keyframe && $0.time <= cutoff }), index > 0 {
            video.removeFirst(index)
        }
        let audioCutoff = min(cutoff, video.first?.time ?? cutoff) - 0.5
        if let index = audio.firstIndex(where: { $0.time >= audioCutoff }), index > 0 {
            audio.removeFirst(index)
        }
    }

    /// The last `seconds` (from the keyframe at or just before that point).
    func clip(seconds: Double) -> Clip? {
        guard let sps, let pps, let audioDescription, !video.isEmpty else { return nil }
        let start = latest - seconds
        let index = video.lastIndex(where: { $0.keyframe && $0.time <= start })
            ?? video.firstIndex(where: \.keyframe) ?? 0
        let frames = Array(video[index...])
        guard let first = frames.first else { return nil }
        let end = frames.last!.time + 1 / Double(fps)
        let sound = audio.filter { $0.time >= first.time && $0.time < end }
        return Clip(sps: sps, pps: pps, audioDescription: audioDescription, audioCookie: audioCookie,
                    fps: fps, video: frames, audio: sound)
    }

    /// Writes a clip to an MP4 file (blocking: call it off the main thread). If the sound can't be
    /// written with the encoder's decoder setup, it tries the plain AAC config, then picture only.
    static func write(_ clip: Clip, to url: URL) throws {
        var attempts: [(cookie: Data?, sound: Bool)] = []
        if let cookie = clip.audioCookie, !cookie.isEmpty { attempts.append((cookie, true)) }
        attempts.append((Data([0x11, 0x90]), true)) // AAC LC, 48 kHz, stereo
        attempts.append((nil, false))
        var problems: [String] = []
        for attempt in attempts {
            do {
                try write(clip, to: url, cookie: attempt.cookie, sound: attempt.sound)
                lastProblems = problems
                return
            } catch {
                problems.append("\(error)")
            }
        }
        lastProblems = problems
        throw Failure.writer(problems.joined(separator: " | "))
    }

    /// What went wrong in the attempts before the one that worked (diagnostics for tests).
    static var lastProblems: [String] = []

    private static func describe(_ stage: String, _ error: Error?) -> Failure {
        guard let error = error as NSError? else { return .writer(stage) }
        var text = "\(stage): \(error.domain) \(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (\(underlying.domain) \(underlying.code))"
        }
        return .writer(text)
    }

    private static func write(_ clip: Clip, to url: URL, cookie: Data?, sound: Bool) throws {
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mp4) } catch { throw describe("create", error) }

        var videoFormat: CMFormatDescription?
        let status = clip.sps.withUnsafeBytes { sps in
            clip.pps.withUnsafeBytes { pps in
                let pointers = [sps.bindMemory(to: UInt8.self).baseAddress!, pps.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [clip.sps.count, clip.pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &videoFormat)
            }
        }
        guard status == noErr, let videoFormat else { throw Failure.writer("video format \(status)") }

        var asbd = clip.audioDescription
        var audioFormat: CMAudioFormatDescription?
        let cookieData = cookie ?? Data()
        let audioStatus = cookieData.withUnsafeBytes { bytes in
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                           magicCookieSize: cookieData.count, magicCookie: cookieData.isEmpty ? nil : bytes.baseAddress,
                                           extensions: nil, formatDescriptionOut: &audioFormat)
        }
        guard audioStatus == noErr, let audioFormat else { throw Failure.writer("audio format \(audioStatus)") }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
        videoInput.expectsMediaDataInRealTime = false
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), !sound || writer.canAdd(audioInput) else { throw Failure.writer("inputs") }
        writer.add(videoInput)
        if sound { writer.add(audioInput) }
        guard writer.startWriting() else { throw describe("start", writer.error) }
        let origin = clip.video[0].stamp
        writer.startSession(atSourceTime: .zero)

        func cmTime(_ stamp: CMTime) -> CMTime { CMTimeSubtract(stamp, origin) }
        func wait(_ input: AVAssetWriterInput) -> Bool {
            var tries = 0
            while !input.isReadyForMoreMediaData {
                if writer.status != .writing || tries > 5_000 { return false }
                Thread.sleep(forTimeInterval: 0.001)
                tries += 1
            }
            return true
        }

        // Interleaved by time, so neither input waits for the other.
        var v = 0, a = 0
        let audio = sound ? clip.audio : []
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(clip.fps))
        while v < clip.video.count || a < audio.count {
            let takeVideo = a >= audio.count || (v < clip.video.count && clip.video[v].time <= audio[a].time)
            if takeVideo {
                let sample = clip.video[v]
                v += 1
                guard let buffer = sampleBuffer(sample.data, format: videoFormat, time: cmTime(sample.stamp),
                                                duration: frameDuration, sync: sample.keyframe),
                      wait(videoInput) else { throw describe("video \(v)", writer.error) }
                guard videoInput.append(buffer) else { throw describe("append video \(v)", writer.error) }
            } else {
                let sample = audio[a]
                a += 1
                guard let buffer = audioBuffer(sample.data, format: audioFormat, time: cmTime(sample.stamp)),
                      wait(audioInput) else { throw describe("audio \(a)", writer.error) }
                guard audioInput.append(buffer) else {
                    let previous = a >= 2 ? cmTime(audio[a - 2].stamp).value : -1
                    let duration = CMSampleBufferGetDuration(buffer)
                    throw describe("append audio \(a) at \(cmTime(sample.stamp).value)/48000 after \(previous), lasting "
                                   + "\(duration.value)/\(duration.timescale), \(sample.data.count) bytes; format "
                                   + "\(asbd.mSampleRate) Hz \(asbd.mFramesPerPacket) frames/packet \(asbd.mChannelsPerFrame) ch", writer.error)
                }
            }
        }
        videoInput.markAsFinished()
        if sound { audioInput.markAsFinished() }
        writer.endSession(atSourceTime: cmTime(clip.video.last!.stamp) + frameDuration)
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw describe("finish", writer.error) }
    }

    private static func blockBuffer(_ data: Data) -> CMBlockBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count,
                                                 blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: data.count, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let copied = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        return copied == noErr ? block : nil
    }

    private static func sampleBuffer(_ data: Data, format: CMFormatDescription, time: CMTime, duration: CMTime,
                                     sync: Bool) -> CMSampleBuffer? {
        guard let block = blockBuffer(data) else { return nil }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var size = data.count
        var buffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &buffer) == noErr,
              let buffer else { return nil }
        if !sync, let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return buffer
    }

    private static func audioBuffer(_ data: Data, format: CMAudioFormatDescription, time: CMTime) -> CMSampleBuffer? {
        guard let block = blockBuffer(data) else { return nil }
        var description = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(data.count))
        var buffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format,
                                                                   sampleCount: 1, presentationTimeStamp: time,
                                                                   packetDescriptions: &description, sampleBufferOut: &buffer) == noErr
        else { return nil }
        return buffer
    }
}
