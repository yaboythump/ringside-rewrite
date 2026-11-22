import AVFoundation
import Foundation
import SwiftUI

/// Runs the one emulated Macintosh II. Mini vMac keeps its state in globals, so
/// there is a single session per launch: leaving the Mac screen just pauses it,
/// and Restart works like the Mac's reset switch.
@MainActor
final class MacSession: ObservableObject {
    static let shared = MacSession()

    enum Speed: Int, CaseIterable, Identifiable {
        case actual = 0, double = 1, quadruple = 2, eight = 3, unlimited = -1
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .actual: return "Actual speed (1×)"
            case .double: return "2×"
            case .quadruple: return "4×"
            case .eight: return "8×"
            case .unlimited: return "As fast as possible"
            }
        }
    }

    @Published private(set) var state: MVState = MVStateNotStarted
    @Published private(set) var insertedDisks: [String] = []
    @Published var message: String?
    @Published var speed: Speed {
        didSet {
            UserDefaults.standard.set(speed.rawValue, forKey: "speed")
            MVCoreSetSpeed(Int32(speed.rawValue))
        }
    }
    @Published var muted: Bool {
        didSet {
            UserDefaults.standard.set(muted, forKey: "muted")
            audio.setMuted(muted)
        }
    }

    var isStarted: Bool { state == MVStateRunning || state == MVStatePoweredOff }

    private let control = EmulationControl()
    private let audio = MacAudio()
    private var thread: Thread?
    private var pollTimer: Timer?

    private init() {
        let stored = UserDefaults.standard.object(forKey: "speed") as? Int ?? Speed.quadruple.rawValue
        speed = Speed(rawValue: stored) ?? .quadruple
        muted = UserDefaults.standard.bool(forKey: "muted")
    }

    /// Starts the Mac with this ROM and inserts the disks (the first one boots).
    @discardableResult
    func start(rom: URL, disks: [URL]) -> Bool {
        if isStarted {
            resume()
            return true
        }
        guard MVCoreStart(rom.path) == 1 else {
            message = Self.takeMessage() ?? "The Mac couldn't start with this ROM."
            refreshState()
            return false
        }
        MVCoreSetSpeed(Int32(speed.rawValue))
        for disk in disks { _ = MVCoreInsertDisk(disk.path) }

        let control = self.control
        let worker = Thread { MacSession.emulationLoop(control) }
        worker.name = "Mac Duo emulation"
        worker.qualityOfService = .userInteractive
        worker.start()
        thread = worker

        audio.start()
        audio.setMuted(muted)
        startPolling()
        refreshState()
        return true
    }

    func pause() {
        guard isStarted else { return }
        MVCoreReleaseAll()
        control.paused = true
        audio.stop()
    }

    func resume() {
        guard isStarted else { return }
        control.paused = false
        if !audio.isRunning {
            audio.start()
            audio.setMuted(muted)
        }
    }

    func restart() {
        MVCoreReleaseAll()
        MVCoreReset()
        resume()
        refreshState()
    }

    func interrupt() { MVCoreInterrupt() }

    func insert(_ url: URL) {
        guard isStarted else { return }
        if MVCoreInsertDisk(url.path) == 0 {
            message = "Couldn't insert \(url.lastPathComponent)."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refreshState() }
    }

    func isInserted(_ url: URL) -> Bool { insertedDisks.contains(url.path) }

    // MARK: - Emulation thread

    /// Mac time advances 60.15 times a second. Each tick gets the rest of its
    /// time slot (minus a margin) for running faster than 1× when that's chosen.
    nonisolated private static func emulationLoop(_ control: EmulationControl) {
        let period = 1.0 / MV_TICK_HZ
        var next = CFAbsoluteTimeGetCurrent()
        while true {
            if control.paused {
                Thread.sleep(forTimeInterval: 0.05)
                next = CFAbsoluteTimeGetCurrent()
                continue
            }
            let started = CFAbsoluteTimeGetCurrent()
            let budget = max(0, (next + period - started) * 0.75)
            MVCoreRunTick(Int32(budget * 1_000_000))
            next += period
            let now = CFAbsoluteTimeGetCurrent()
            if next > now {
                Thread.sleep(forTimeInterval: next - now)
            } else if now - next > 0.25 {
                next = now // fell far behind (e.g. the app was busy): don't race to catch up
            }
        }
    }

    // MARK: - Status

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in MacSession.shared.refreshState() }
        }
    }

    func refreshState() {
        let newState = MVCoreGetState()
        if newState != state { state = newState }
        var disks: [String] = []
        var buffer = [CChar](repeating: 0, count: 1024)
        for i in 0..<Int32(MV_MAX_DISKS) where MVCoreDiskPath(i, &buffer, Int32(buffer.count)) == 1 {
            disks.append(String(cString: buffer))
        }
        if disks != insertedDisks { insertedDisks = disks }
        if let text = Self.takeMessage() { message = text }
    }

    private static func takeMessage() -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard MVCoreTakeMessage(&buffer, Int32(buffer.count)) == 1 else { return nil }
        return String(cString: buffer)
    }
}

/// Shared between the main thread and the emulation thread.
final class EmulationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var _paused = false
    var paused: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _paused }
        set { lock.lock(); _paused = newValue; lock.unlock() }
    }
}

/// Plays the Mac's 22 kHz sound. The render block runs on Core Audio's
/// real-time thread and only reads the core's lock-free buffer.
final class MacAudio {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    var isRunning: Bool { engine.isRunning }

    func start() {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
        } catch {
            return
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(MV_AUDIO_RATE), channels: 2) else { return }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            _ = MVCoreReadAudio(left, right, Int32(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            engine.prepare()
            try engine.start()
            source = node
        } catch {
            engine.detach(node)
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if let source { engine.detach(source) }
        source = nil
    }

    func setMuted(_ muted: Bool) {
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
    }
}
