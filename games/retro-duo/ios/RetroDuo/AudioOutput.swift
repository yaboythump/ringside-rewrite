import AVFoundation

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

    func start(_ sourceCore: Source, rate: Double = AudioOutput.sampleRate) {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            // A game should remain audible with the phone's silent switch enabled.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(Self.sampleRate)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
            return
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let node = Self.makeSource(sourceCore, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            engine.prepare()
            try engine.start()
            source = node
            lastError = nil
        } catch {
            engine.detach(node)
            lastError = error.localizedDescription
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if let source {
            engine.detach(source)
        }
        source = nil
    }

    func setMuted(_ muted: Bool) {
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }

    private static func makeSource(_ sourceCore: Source, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            switch sourceCore {
            case .gameBoy(let core): _ = RDCoreReadAudio(core, left, right, Int(frameCount))
            case .nintendoDS(let core): _ = MDCoreReadAudio(core, left, right, Int(frameCount))
            case .nes(let core): _ = NESCoreReadAudio(core, left, right, Int(frameCount))
            case .gameBoyAdvance(let core): _ = RDGBAReadAudio(core, left, right, Int(frameCount))
            case .libretro(let core): _ = RDLRReadAudio(core, left, right, Int(frameCount))
            }
            return noErr
        }
    }
}
