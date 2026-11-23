import AVFoundation
import CoreVideo
import Foundation

/// One live stream: takes the game's frames, the game's sound and (optionally) the
/// microphone, and sends 1280x720 H.264 + AAC to an RTMP server at a steady 30 frames a
/// second. Video and sound are paced by the clock, not the game, so the stream keeps going
/// (last picture, silence plus voice) while the game is paused in its menu.
/// Platform-neutral so tests/live can run it on a Mac against a stand-in server.
final class LiveStreamCore {
    struct Config {
        var destination: RTMPDestination
        var width = 1280
        var height = 720
        var fps = 30
        var videoBitrate = 3_000_000
        var audioBitrate = 128_000
        /// 2 for the DS: both screens side by side.
        var screens = 1
    }

    struct Stats: Equatable {
        var seconds: Double = 0
        var sentFrames = 0
        var droppedFrames = 0
        /// Measured upload rate over the last few seconds.
        var kilobitsPerSecond = 0
        /// Time spent per tick (diagnostics): building the picture, handing it to the encoder, sound.
        var composeMs = 0.0
        var encodeMs = 0.0
        var audioMs = 0.0
        var ticks = 0
    }

    enum State: Equatable {
        case connecting
        case live
        case failed(String)
        case ended
    }

    let config: Config
    /// Called on the stream's queue.
    var onState: ((State) -> Void)?
    private(set) var state: State = .connecting

    private let publisher: RTMPPublisher
    private let queue = DispatchQueue(label: "avydrix.live.core", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var startTime: DispatchTime?
    private var videoEncoder: H264Encoder?
    private var audioEncoder: AACEncoder?
    private var pool: CVPixelBufferPool?
    private var frameIndex: Int64 = 0
    private var sentSequenceHeader = false
    private var audioFramesSent: Int64 = 0
    private var audioPackets: Int64 = 0
    private var stats = Stats()
    private var rateWindow: [(Double, UInt64)] = []

    // Latest picture of each screen (RGBX, red byte first), written from any thread.
    private let frameLock = NSLock()
    private var screens: [(pixels: [UInt32], width: Int, height: Int)?]
    private var screenChanged = true

    // Sound: 48 kHz, game interleaved stereo and mic mono.
    private let audioLock = NSLock()
    private var gameSamples: [Float] = []
    private var micSamples: [Float] = []
    private var gameConverter: (format: AVAudioFormat, converter: AVAudioConverter)?
    private var micConverter: (format: AVAudioFormat, converter: AVAudioConverter)?
    private let stereo48k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true)!
    private let mono48k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    /// Voice level relative to the game.
    var micGain: Float = 1.2

    /// Sound is sent this far behind the clock so bursty audio callbacks never run dry.
    private let audioDelay = 0.2

    init(config: Config) {
        self.config = config
        publisher = RTMPPublisher(destination: config.destination)
        screens = Array(repeating: nil, count: max(1, config.screens))
    }

    func start() {
        publisher.onState = { [weak self] state in
            guard let self else { return }
            self.queue.async { self.publisherChanged(state) }
        }
        publisher.start()
    }

    func stop() {
        queue.async { [self] in
            guard state == .connecting || state == .live else { return }
            timer?.cancel()
            timer = nil
            videoEncoder?.finish()
            publisher.close()
            set(.ended)
        }
    }

    var currentStats: Stats { queue.sync { stats } }

    // MARK: Input (any thread)

    func pushVideo(pixels: UnsafePointer<UInt32>, width: Int, height: Int, screen: Int) {
        guard width > 0, height > 0, width <= 1024, height <= 1024 else { return }
        let copy = Array(UnsafeBufferPointer(start: pixels, count: width * height))
        frameLock.lock()
        if screen >= 0 && screen < screens.count {
            screens[screen] = (copy, width, height)
            screenChanged = true
        }
        frameLock.unlock()
    }

    /// The game's sound in any PCM format AVAudioEngine produces.
    func pushGameAudio(_ buffer: AVAudioPCMBuffer) {
        guard let samples = convert(buffer, isMic: false) else { return }
        audioLock.lock()
        gameSamples.append(contentsOf: samples)
        if gameSamples.count > 48_000 * 2 { gameSamples.removeFirst(gameSamples.count - 48_000) } // keep under a second
        audioLock.unlock()
    }

    func pushMicrophone(_ buffer: AVAudioPCMBuffer) {
        guard let samples = convert(buffer, isMic: true) else { return }
        audioLock.lock()
        micSamples.append(contentsOf: samples)
        if micSamples.count > 48_000 { micSamples.removeFirst(micSamples.count - 24_000) }
        audioLock.unlock()
    }

    /// 48 kHz Float32: interleaved stereo for the game, mono for the mic.
    private func convert(_ buffer: AVAudioPCMBuffer, isMic: Bool) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }
        let target = isMic ? mono48k : stereo48k
        audioLock.lock()
        var entry = isMic ? micConverter : gameConverter
        if entry?.format != buffer.format {
            entry = AVAudioConverter(from: buffer.format, to: target).map { (buffer.format, $0) }
            if isMic { micConverter = entry } else { gameConverter = entry }
        }
        audioLock.unlock()
        guard let converter = entry?.converter else { return nil }
        let ratio = 48_000 / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0, let data = output.floatChannelData else { return nil }
        let count = Int(output.frameLength) * Int(target.channelCount)
        return Array(UnsafeBufferPointer(start: data[0], count: count))
    }

    // MARK: Stream

    private func publisherChanged(_ newState: RTMPPublisher.State) {
        switch newState {
        case .publishing:
            guard state == .connecting else { return }
            let config = self.config
            videoEncoder = H264Encoder(width: config.width, height: config.height, fps: config.fps,
                                       bitrate: config.videoBitrate) { [weak self] frame in
                self?.queue.async { self?.sendVideo(frame) }
            }
            audioEncoder = AACEncoder(bitrate: config.audioBitrate)
            guard videoEncoder != nil, audioEncoder != nil else {
                set(.failed("This device's video encoder couldn't start."))
                publisher.close()
                return
            }
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: config.width, kCVPixelBufferHeightKey: config.height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            publisher.sendMetadata(FLV.metadata(width: config.width, height: config.height, fps: config.fps,
                                                videoKbps: config.videoBitrate / 1000, audioKbps: config.audioBitrate / 1000))
            publisher.sendAudio(FLV.audioSequenceHeader(), timestamp: 0)
            startTime = .now()
            // Strict: the system mustn't coalesce these ticks, or the stream's frame rate drops.
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / config.fps), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
            set(.live)
        case .failed(let message):
            timer?.cancel(); timer = nil
            videoEncoder?.finish()
            if state == .connecting || state == .live { set(.failed(message)) }
        case .closed, .connecting:
            break
        }
    }

    private func tick() {
        guard state == .live, let startTime else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1e9
        stats.seconds = elapsed
        stats.ticks += 1
        let audioStart = DispatchTime.now().uptimeNanoseconds
        sendAudio(upTo: elapsed - audioDelay)
        stats.audioMs += Double(DispatchTime.now().uptimeNanoseconds - audioStart) / 1e6

        // One video frame per tick, numbered by the clock so the frame rate holds even when a tick is late.
        let due = Int64(elapsed * Double(config.fps))
        guard due >= frameIndex else { return }
        // Back off while the upload can't keep up (more than ~2 seconds queued).
        if publisher.pendingBytes > config.videoBitrate / 4 {
            stats.droppedFrames += 1
            frameIndex = due + 1
            return
        }
        let composeStart = DispatchTime.now().uptimeNanoseconds
        if let buffer = composeFrame() {
            let encodeStart = DispatchTime.now().uptimeNanoseconds
            stats.composeMs += Double(encodeStart - composeStart) / 1e6
            videoEncoder?.encode(buffer, frameIndex: frameIndex, fps: config.fps)
            stats.encodeMs += Double(DispatchTime.now().uptimeNanoseconds - encodeStart) / 1e6
        }
        frameIndex = due + 1
        updateRate(elapsed)
    }

    private func updateRate(_ now: Double) {
        rateWindow.append((now, publisher.bytesSent))
        while let first = rateWindow.first, now - first.0 > 3 { rateWindow.removeFirst() }
        if let first = rateWindow.first, now - first.0 > 0.5 {
            stats.kilobitsPerSecond = Int(Double(publisher.bytesSent - first.1) * 8 / 1000 / (now - first.0))
        }
    }

    private func sendVideo(_ frame: EncodedVideoFrame) {
        guard state == .live else { return }
        if let sps = frame.sps, let pps = frame.pps {
            publisher.sendVideo(FLV.videoSequenceHeader(sps: sps, pps: pps), timestamp: timestamp(frame.frameIndex))
            sentSequenceHeader = true
        }
        guard sentSequenceHeader else { return }
        publisher.sendVideo(FLV.videoFrame(frame.data, keyframe: frame.keyframe), timestamp: timestamp(frame.frameIndex))
        stats.sentFrames += 1
    }

    private func timestamp(_ frame: Int64) -> UInt32 {
        UInt32(truncatingIfNeeded: frame * 1000 / Int64(config.fps))
    }

    /// Mixes game and mic up to `time` seconds into the stream (silence fills any gap).
    private func sendAudio(upTo time: Double) {
        guard let audioEncoder, time > 0 else { return }
        let wanted = Int64(time * 48_000) - audioFramesSent
        guard wanted >= Int64(AACEncoder.framesPerPacket) else { return }
        let frames = Int(wanted)
        audioLock.lock()
        let gameTake = min(frames * 2, gameSamples.count)
        var mix = Array(gameSamples.prefix(gameTake))
        gameSamples.removeFirst(gameTake)
        // The game runs a little ahead or behind real time; trim what piles up.
        if gameSamples.count > 48_000 / 2 * 2 { gameSamples.removeFirst(gameSamples.count - 48_000 / 10 * 2) }
        let micTake = min(frames, micSamples.count)
        let mic = Array(micSamples.prefix(micTake))
        micSamples.removeFirst(micTake)
        audioLock.unlock()
        if mix.count < frames * 2 { mix += [Float](repeating: 0, count: frames * 2 - mix.count) }
        for i in 0..<mic.count {
            let voice = mic[i] * micGain
            mix[i * 2] = max(-1, min(1, mix[i * 2] + voice))
            mix[i * 2 + 1] = max(-1, min(1, mix[i * 2 + 1] + voice))
        }
        audioFramesSent += Int64(frames)
        for packet in audioEncoder.encode(mix) {
            let ms = UInt32(truncatingIfNeeded: audioPackets * Int64(AACEncoder.framesPerPacket) * 1000 / 48_000)
            publisher.sendAudio(FLV.audioFrame(packet), timestamp: ms)
            audioPackets += 1
        }
    }

    // MARK: Picture

    /// The latest game picture(s), scaled up with sharp pixels and centred on black.
    private func composeFrame() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var created: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
        guard let buffer = created else { return nil }
        frameLock.lock()
        let pictures = screens
        screenChanged = false
        frameLock.unlock()
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer) / 4
        let out = base.assumingMemoryBound(to: UInt32.self)
        let width = config.width, height = config.height
        for y in 0..<height { (out + y * stride).update(repeating: 0xFF00_0000, count: width) }
        let slotWidth = width / pictures.count
        for (slot, picture) in pictures.enumerated() {
            guard let picture else { continue }
            Self.draw(picture.pixels, width: picture.width, height: picture.height,
                      into: out, stride: stride, x: slot * slotWidth, y: 0, boxWidth: slotWidth, boxHeight: height)
        }
        return buffer
    }

    /// Nearest-neighbour scale to fit the box, RGBX in, BGRA out.
    static func draw(_ pixels: [UInt32], width: Int, height: Int, into out: UnsafeMutablePointer<UInt32>, stride: Int,
                     x boxX: Int, y boxY: Int, boxWidth: Int, boxHeight: Int) {
        let scale = min(Double(boxWidth) / Double(width), Double(boxHeight) / Double(height))
        let drawWidth = max(1, Int(Double(width) * scale)), drawHeight = max(1, Int(Double(height) * scale))
        let left = boxX + (boxWidth - drawWidth) / 2, top = boxY + (boxHeight - drawHeight) / 2
        let columns = (0..<drawWidth).map { min(width - 1, Int(Double($0) / scale)) }
        pixels.withUnsafeBufferPointer { source in
            for row in 0..<drawHeight {
                let sourceRow = source.baseAddress! + min(height - 1, Int(Double(row) / scale)) * width
                let target = out + (top + row) * stride + left
                for column in 0..<drawWidth {
                    let p = sourceRow[columns[column]]
                    // Bytes R,G,B,X -> B,G,R,A.
                    target[column] = 0xFF00_0000 | (p & 0x0000_FF00) | ((p & 0xFF) << 16) | ((p >> 16) & 0xFF)
                }
            }
        }
    }

    private func set(_ newState: State) {
        state = newState
        onState?(newState)
    }
}
