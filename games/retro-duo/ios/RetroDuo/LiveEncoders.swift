import AVFoundation
import CoreMedia
import VideoToolbox

// Hardware H.264 and AAC encoders for live streaming. Platform-neutral (tests/live runs them
// on a Mac).

struct EncodedVideoFrame {
    /// Length-prefixed (AVCC) NAL units.
    var data: Data
    var keyframe: Bool
    /// Present when the encoder's parameter sets are new (the first frame, or after a reset).
    var sps: Data?
    var pps: Data?
    var frameIndex: Int64
}

/// H.264 (Main profile, no B-frames so decode order is display order) at a constant frame rate.
final class H264Encoder {
    private var session: VTCompressionSession?
    private let onFrame: (EncodedVideoFrame) -> Void
    private var lastSPS = Data()
    private var lastPPS = Data()
    private let lock = NSLock()

    init?(width: Int, height: Int, fps: Int, bitrate: Int, onFrame: @escaping (EncodedVideoFrame) -> Void) {
        self.onFrame = onFrame
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                                codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                                imageBufferAttributes: nil, compressedDataAllocator: nil,
                                                outputCallback: nil, refcon: nil, compressionSessionOut: &created)
        guard status == noErr, let created else { return nil }
        session = created
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Main_AutoLevel,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_AverageBitRate: bitrate,
            kVTCompressionPropertyKey_DataRateLimits: [bitrate * 3 / 2 / 8, 1] as CFArray,
            kVTCompressionPropertyKey_ExpectedFrameRate: fps,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: fps * 2,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 2,
        ]
        for (key, value) in properties {
            VTSessionSetProperty(created, key: key, value: value as CFTypeRef)
        }
        VTCompressionSessionPrepareToEncodeFrames(created)
    }

    deinit { finish() }

    func encode(_ pixels: CVPixelBuffer, frameIndex: Int64, fps: Int, forceKeyframe: Bool = false) {
        guard let session else { return }
        let pts = CMTime(value: frameIndex, timescale: CMTimeScale(fps))
        let options = forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixels, presentationTimeStamp: pts,
                                        duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                                        frameProperties: options, infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            self.output(sample, frameIndex: frameIndex)
        }
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    private func output(_ sample: CMSampleBuffer, frameIndex: Int64) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let copied = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        guard copied == kCMBlockBufferNoErr else { return }
        var keyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first, first[kCMSampleAttachmentKey_NotSync] as? Bool == true {
            keyframe = false
        }
        var frame = EncodedVideoFrame(data: data, keyframe: keyframe, frameIndex: frameIndex)
        if keyframe, let format = CMSampleBufferGetFormatDescription(sample),
           let sps = Self.parameterSet(format, 0), let pps = Self.parameterSet(format, 1),
           sps != lastSPS || pps != lastPPS {
            lastSPS = sps; lastPPS = pps
            frame.sps = sps; frame.pps = pps
        }
        onFrame(frame)
    }

    private static func parameterSet(_ format: CMFormatDescription, _ index: Int) -> Data? {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index,
                                                                        parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                                                                        parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        guard status == noErr, let pointer else { return nil }
        return Data(bytes: pointer, count: size)
    }
}

/// AAC LC, 48 kHz stereo: feed interleaved Float32 samples, get one packet per 1024 frames.
final class AACEncoder {
    static let sampleRate = 48_000.0
    static let framesPerPacket = 1024
    private let converter: AVAudioConverter
    private let input: AVAudioPCMBuffer
    private let outputFormat: AVAudioFormat
    private var pendingSamples: [Float] = []

    init?(bitrate: Int) {
        guard let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 2, interleaved: true),
              let aac = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Self.sampleRate,
                                                 AVNumberOfChannelsKey: 2]),
              let converter = AVAudioConverter(from: pcm, to: aac),
              let input = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(Self.framesPerPacket)) else { return nil }
        converter.bitRate = bitrate
        self.converter = converter
        self.input = input
        outputFormat = aac
    }

    /// The packets' format and the decoder setup (an ES descriptor), for writing clips.
    var streamDescription: AudioStreamBasicDescription { outputFormat.streamDescription.pointee }
    var magicCookie: Data? { converter.magicCookie }

    /// Interleaved stereo samples (L R L R ...); returns finished AAC packets in order.
    func encode(_ samples: [Float]) -> [Data] {
        pendingSamples.append(contentsOf: samples)
        var packets: [Data] = []
        let chunk = Self.framesPerPacket * 2
        while pendingSamples.count >= chunk {
            input.frameLength = AVAudioFrameCount(Self.framesPerPacket)
            pendingSamples.withUnsafeBufferPointer { source in
                input.floatChannelData![0].update(from: source.baseAddress!, count: chunk)
            }
            pendingSamples.removeFirst(chunk)
            packets += convertOne()
        }
        return packets
    }

    private func convertOne() -> [Data] {
        let output = AVAudioCompressedBuffer(format: outputFormat, packetCapacity: 4,
                                             maximumPacketSize: max(converter.maximumOutputPacketSize, 1536))
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return self.input
        }
        guard status != .error, output.packetCount > 0, let descriptions = output.packetDescriptions else { return [] }
        var packets: [Data] = []
        for i in 0..<Int(output.packetCount) {
            let description = descriptions[i]
            packets.append(Data(bytes: output.data.advanced(by: Int(description.mStartOffset)),
                                count: Int(description.mDataByteSize)))
        }
        return packets
    }
}
