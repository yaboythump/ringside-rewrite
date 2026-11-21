import GameController
import QuartzCore
import SwiftUI
import UIKit

/// Runs one game: owns the emulated console, paces it, and keeps its saves.
@MainActor
final class EmulatorSession: NSObject, ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var hasQuickSave = false
    @Published private(set) var isMuted = UserDefaults.standard.bool(forKey: "muted")
    @Published private(set) var errorMessage: String?
    @Published var toast: String?

    let game: Game
    private let library: GameLibrary
    private var core: OpaquePointer?
    private var displayLink: CADisplayLink?
    private let audio = AudioOutput()
    private var touchKeys: UInt8 = 0
    private var savedBattery = Data()
    private var framesSinceSaveCheck = 0
    private var lastRumble = Date.distantPast
    private let rumble = UIImpactFeedbackGenerator(style: .rigid)
    private var toastTask: Task<Void, Never>?
    weak var screen: PixelScreenView?

    init(game: Game, library: GameLibrary) {
        self.game = game
        self.library = library
        super.init()
        hasQuickSave = FileManager.default.fileExists(atPath: library.stateURL(for: game, slot: "quick").path)
    }

    // MARK: Lifecycle

    func start() {
        guard core == nil else { return }
        guard let bootURL = Bundle.main.url(forResource: "cgb_boot", withExtension: "bin"),
              let boot = try? Data(contentsOf: bootURL) else {
            errorMessage = "Retro Duo is missing its start-up file. Reinstall the app."
            return
        }
        let scoped = game.url.startAccessingSecurityScopedResource()
        defer { if scoped { game.url.stopAccessingSecurityScopedResource() } }
        guard let rom = try? Data(contentsOf: game.url), GameLibrary.looksLikeROM(rom) else {
            errorMessage = "\(game.name) couldn't be opened. The file may be damaged or not a Game Boy game."
            return
        }
        let created = boot.withUnsafeBytes { bytes in
            RDCoreCreate(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, UInt32(AudioOutput.sampleRate))
        }
        guard let created else {
            errorMessage = "The emulator couldn't start."
            return
        }
        let loaded = rom.withUnsafeBytes { bytes in
            RDCoreLoadROM(created, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard loaded else {
            RDCoreDestroy(created)
            errorMessage = "\(game.name) isn't a Game Boy game Retro Duo can run."
            return
        }
        core = created

        if let battery = try? Data(contentsOf: library.batteryURL(for: game)), !battery.isEmpty {
            battery.withUnsafeBytes { RDCoreLoadBattery(created, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
            savedBattery = battery
        }
        if loadState(slot: "resume") {
            show(toast: "Picked up where you left off")
        }

        audio.start(core: created)
        audio.setMuted(isMuted)
        rumble.prepare()

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Saves everything and shuts the console down.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        guard let core else { return }
        writeBattery(force: true)
        saveState(slot: "resume")
        audio.stop()
        RDCoreDestroy(core)
        self.core = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            touchKeys = 0
            writeBattery(force: true)
            audio.setMuted(true)
        } else {
            audio.setMuted(isMuted)
        }
    }

    /// Called when the app goes to the background, so nothing is lost if iOS closes it.
    func persistNow() {
        guard core != nil else { return }
        writeBattery(force: true)
        saveState(slot: "resume")
    }

    // MARK: Controls

    func setKey(_ key: Int, pressed: Bool) {
        let bit = UInt8(key)
        if pressed { touchKeys |= bit } else { touchKeys &= ~bit }
    }

    func setDirections(_ mask: UInt8) {
        let directions = UInt8(RD_KEY_RIGHT | RD_KEY_LEFT | RD_KEY_UP | RD_KEY_DOWN)
        touchKeys = (touchKeys & ~directions) | (mask & directions)
    }

    // MARK: Menu actions

    func quickSave() {
        if saveState(slot: "quick") {
            hasQuickSave = true
            show(toast: "Game saved to the quick slot")
        }
    }

    func quickLoad() {
        show(toast: loadState(slot: "quick") ? "Quick save loaded" : "No quick save yet")
    }

    func restart() {
        guard let core else { return }
        writeBattery(force: true)
        RDCoreReset(core)
        try? FileManager.default.removeItem(at: library.stateURL(for: game, slot: "resume"))
        show(toast: "Restarted")
    }

    func toggleMute() {
        isMuted.toggle()
        UserDefaults.standard.set(isMuted, forKey: "muted")
        if !isPaused { audio.setMuted(isMuted) }
    }

    // MARK: Frame loop

    @objc private func step(_ link: CADisplayLink) {
        guard let core, !isPaused else { return }
        RDCoreSetKeys(core, touchKeys | controllerKeys())

        if audio.isRunning {
            // Keep about 50 ms of sound queued. Tying emulation to the audio clock gives
            // exact speed on 60 Hz and 120 Hz screens and avoids crackles.
            var frames = 0
            while frames < 3 && RDCoreBufferedAudioFrames(core) < 2_400 {
                RDCoreRunFrame(core)
                frames += 1
            }
        } else {
            RDCoreRunFrame(core)
        }
        screen?.show(core)

        let strength = RDCoreRumble(core)
        if strength > 0.1, Date().timeIntervalSince(lastRumble) > 0.08 {
            rumble.impactOccurred(intensity: CGFloat(min(1, strength)))
            lastRumble = Date()
        }

        framesSinceSaveCheck += 1
        if framesSinceSaveCheck >= 300 {
            framesSinceSaveCheck = 0
            writeBattery(force: false)
        }
    }

    private func controllerKeys() -> UInt8 {
        var mask = 0
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            if pad.dpad.right.isPressed || pad.leftThumbstick.right.isPressed { mask |= Int(RD_KEY_RIGHT) }
            if pad.dpad.left.isPressed || pad.leftThumbstick.left.isPressed { mask |= Int(RD_KEY_LEFT) }
            if pad.dpad.up.isPressed || pad.leftThumbstick.up.isPressed { mask |= Int(RD_KEY_UP) }
            if pad.dpad.down.isPressed || pad.leftThumbstick.down.isPressed { mask |= Int(RD_KEY_DOWN) }
            // Match the handheld's layout: the right face button is A, the bottom one is B.
            if pad.buttonB.isPressed { mask |= Int(RD_KEY_A) }
            if pad.buttonA.isPressed || pad.buttonX.isPressed { mask |= Int(RD_KEY_B) }
            if pad.buttonY.isPressed { mask |= Int(RD_KEY_A) }
            if pad.buttonMenu.isPressed { mask |= Int(RD_KEY_START) }
            if pad.buttonOptions?.isPressed == true { mask |= Int(RD_KEY_SELECT) }
        }
        return UInt8(truncatingIfNeeded: mask)
    }

    // MARK: Saves

    private func writeBattery(force: Bool) {
        guard let core else { return }
        let size = RDCoreBatterySize(core)
        guard size > 0 else { return }
        var data = Data(count: size)
        let written = data.withUnsafeMutableBytes {
            RDCoreSaveBattery(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        guard written > 0 else { return }
        data = data.prefix(written)
        // `force` writes even when unchanged so the file always exists after a session.
        guard force || data != savedBattery else { return }
        if (try? data.write(to: library.batteryURL(for: game), options: .atomic)) != nil {
            savedBattery = data
        }
    }

    @discardableResult
    private func saveState(slot: String) -> Bool {
        guard let core else { return false }
        let size = RDCoreStateSize(core)
        guard size > 0 else { return false }
        var data = Data(count: size)
        data.withUnsafeMutableBytes { RDCoreSaveState(core, $0.bindMemory(to: UInt8.self).baseAddress) }
        return (try? data.write(to: library.stateURL(for: game, slot: slot), options: .atomic)) != nil
    }

    private func loadState(slot: String) -> Bool {
        guard let core, let data = try? Data(contentsOf: library.stateURL(for: game, slot: slot)) else { return false }
        let loaded = data.withUnsafeBytes {
            RDCoreLoadState(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        if loaded { screen?.show(core) }
        return loaded
    }

    private func show(toast text: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { self?.toast = nil }
        }
    }
}
