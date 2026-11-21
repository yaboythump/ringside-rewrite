import AVFoundation

/// Plays the console's sound. Deliberately not tied to the main actor: the render
/// block runs on Core Audio's real-time thread and only reads the core's lock-free buffer.
final class AudioOutput {
    static let sampleRate: Double = 48_000

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private(set) var isRunning = false

    func start(core: OpaquePointer) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setPreferredIOBufferDuration(0.01)
        try? session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else { return }
        let node = Self.makeSource(core: core, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            source = node
            isRunning = true
        } catch {
            engine.detach(node)
            isRunning = false
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if let source {
            engine.detach(source)
        }
        source = nil
        isRunning = false
    }

    func setMuted(_ muted: Bool) {
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }

    private static func makeSource(core: OpaquePointer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            _ = RDCoreReadAudio(core, left, right, Int(frameCount))
            return noErr
        }
    }
}
