import AVFoundation
import os

/// Plays the console's sound. Deliberately not tied to the main actor: the render
/// block runs on Core Audio's real-time thread and only reads the core's lock-free buffer.
final class AudioOutput {
    static let sampleRate: Double = 48_000

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    var isRunning: Bool { engine.isRunning }
    private(set) var lastError: String?

    /// Which emulator the speaker reads from.
    enum Source {
        case gameBoy(OpaquePointer)
        case nintendoDS(OpaquePointer)
        case nes(OpaquePointer)
        case gameBoyAdvance(OpaquePointer)
        case libretro(OpaquePointer)
    }

    func start(core: OpaquePointer) { start(.gameBoy(core)) }
    func start(dsCore: OpaquePointer) { start(.nintendoDS(dsCore)) }
    func start(nesCore: OpaquePointer) { start(.nes(nesCore)) }
    func start(gbaCore: OpaquePointer) { start(.gameBoyAdvance(gbaCore)) }
    /// libretro cores pick their own output rate (bsnes: 48 kHz); the mixer converts it.
    func start(libretroCore: OpaquePointer, rate: Double) { start(.libretro(libretroCore), rate: rate) }

    // Live streaming (LiveStreamer): while on, the game's sound is also handed to the stream,
    // and the session allows recording so the streamer's voice can be mixed in.
    private static let sinkLock = NSLock()
    private static var streamSink: ((AVAudioPCMBuffer) -> Void)?
    static var recordsMicrophone = false

    static func setStreamSink(_ sink: ((AVAudioPCMBuffer) -> Void)?) {
        sinkLock.lock(); streamSink = sink; sinkLock.unlock()
    }

    private static func forward(_ buffer: AVAudioPCMBuffer) {
        sinkLock.lock(); let sink = streamSink; sinkLock.unlock()
        sink?(buffer)
    }

    func start(_ sourceCore: Source, rate: Double = AudioOutput.sampleRate) {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            // A game should remain audible with the phone's silent switch enabled.
            if Self.recordsMicrophone {
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setPreferredSampleRate(Self.sampleRate)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
            return
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let node = Self.makeSource(sourceCore, format: format, flush: flushRequest)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        // The stream hears the game before the mute switch, so muting the phone keeps viewers' sound.
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in AudioOutput.forward(buffer) }
        do {
            engine.prepare()
            try engine.start()
            source = node
            lastError = nil
        } catch {
            node.removeTap(onBus: 0)
            engine.detach(node)
            lastError = error.localizedDescription
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if let source {
            source.removeTap(onBus: 0)
            engine.detach(source)
        }
        source = nil
    }

    func setMuted(_ muted: Bool) {
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }

    /// Throws away the sound already queued (after rewinding or fast-forwarding, so play
    /// picks up in sync instead of a fraction of a second behind).
    func dropQueuedSound() {
        flushRequest.withLock { $0 = true }
    }

    private let flushRequest = OSAllocatedUnfairLock(initialState: false)

    private static func makeSource(_ sourceCore: Source, format: AVAudioFormat,
                                   flush: OSAllocatedUnfairLock<Bool>) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            func read() -> Int {
                switch sourceCore {
                case .gameBoy(let core): return RDCoreReadAudio(core, left, right, Int(frameCount))
                case .nintendoDS(let core): return MDCoreReadAudio(core, left, right, Int(frameCount))
                case .nes(let core): return NESCoreReadAudio(core, left, right, Int(frameCount))
                case .gameBoyAdvance(let core): return RDGBAReadAudio(core, left, right, Int(frameCount))
                case .libretro(let core): return RDLRReadAudio(core, left, right, Int(frameCount))
                }
            }
            // Only this thread reads the queue, so emptying it here is safe.
            if flush.withLock({ let asked = $0; $0 = false; return asked }) {
                var rounds = 0
                while read() == Int(frameCount) && rounds < 64 { rounds += 1 }
            }
            _ = read()
            return noErr
        }
    }
}
