import AVFoundation
import GameController
import QuartzCore
import SwiftUI
import UIKit

/// Runs one single-screen game (Game Boy or NES): owns the console, paces it, and keeps its saves.
@MainActor
final class EmulatorSession: NSObject, ObservableObject, PadInput {
    @Published private(set) var isPaused = false
    @Published private(set) var hasQuickSave = false
    @Published private(set) var isMuted = UserDefaults.standard.bool(forKey: "muted")
    @Published private(set) var errorMessage: String?
    @Published var toast: String?

    let game: Game
    private let library: GameLibrary
    private var core: ConsoleBackend?
    private var displayLink: CADisplayLink?
    private let audio = AudioOutput()
    private var input = InputState()
    private var deliveredActions = 0
    private var deliveredDirections = 0
    var diagnostics: String {
        "frames:\(core?.frameCount ?? 0) audio:\(audio.isRunning) actions:\(deliveredActions) directions:\(deliveredDirections)"
    }
    private var lastFrameTime: CFTimeInterval = 0
    private var frameDebt: Double = 0
    private var savedBattery = Data()
    private var framesSinceSaveCheck = 0
    private var lastResumeCheckpoint = Date()
    private var lastRumble = Date.distantPast
    private let rumble = UIImpactFeedbackGenerator(style: .rigid)
    private var toastTask: Task<Void, Never>?
    // Old and replacement views can overlap during SwiftUI's rotation transition.
    // A late update from the old view must not disconnect the visible one.
    private let screens = NSHashTable<PixelScreenView>.weakObjects()

    func attachScreen(_ view: PixelScreenView) {
        screens.add(view)
        if let core { core.show(on: view) }
    }

    /// Picture height / width: 10:9 for Game Boy, 8:7 for the NES.
    var aspect: CGFloat { game.system.aspect }

    /// When this game was opened (the tracker shows the session's length).
    let openedAt = Date()

    /// One byte of the running game's work RAM, for the tracker (nil while nothing runs).
    func peek(_ address: UInt32) -> UInt8? { core?.peek(address) }

    init(game: Game, library: GameLibrary) {
        self.game = game
        self.library = library
        super.init()
        hasQuickSave = FileManager.default.fileExists(atPath: library.stateURL(for: game, slot: "quick").path)
    }

    // MARK: Lifecycle

    func start() {
        guard core == nil else { return }
        let scoped = game.url.startAccessingSecurityScopedResource()
        defer { if scoped { game.url.stopAccessingSecurityScopedResource() } }
        guard let rom = try? Data(contentsOf: game.url) else {
            errorMessage = "\(game.name) couldn't be opened. The file may be damaged."
            return
        }
        let battery = try? Data(contentsOf: library.batteryURL(for: game))
        switch ConsoleBackends.make(for: game, rom: rom, battery: battery) {
        case .failure(let error):
            errorMessage = error.message
            return
        case .success(let backend):
            core = backend
            savedBattery = battery ?? Data()
        }

        if library.restoreProtectedResume(for: game, using: { [weak self] data in
            self?.core?.loadState(data) == true
        }) {
            show(toast: "Protected session restored")
        }
        lastResumeCheckpoint = Date()

        core?.startAudio(audio)
        audio.setMuted(isMuted)
        rumble.prepare()
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)),
                                               name: AVAudioSession.routeChangeNotification, object: nil)

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Saves everything and shuts the console down.
    /// `keepResume`: a console that stopped on an error must not replace the resume point.
    func stop(keepResume: Bool = false) {
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
        displayLink = nil
        guard let core else { return }
        writeBattery(force: true)
        if !keepResume { saveProtectedResume() }
        audio.stop()
        core.destroy()
        self.core = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if !paused { HingeControl.shared.recenter() } // learn how the phone is held now
        lastFrameTime = 0
        frameDebt = 0
        if paused {
            input.clear()
            writeBattery(force: true)
            audio.setMuted(true)
        } else {
            if let core, !audio.isRunning { core.startAudio(audio) }
            audio.setMuted(isMuted)
        }
    }

    @objc private func audioInterrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            audio.stop()
        } else if !isPaused, let core {
            core.startAudio(audio)
            audio.setMuted(isMuted)
        }
    }

    @objc private func audioRouteChanged(_ notification: Notification) {
        // Our own category/activation changes must not recursively restart audio.
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .newDeviceAvailable || reason == .oldDeviceUnavailable,
              !isPaused, let core else { return }
        core.startAudio(audio)
        audio.setMuted(isMuted)
    }

    /// Called when the app goes to the background, so nothing is lost if iOS closes it.
    func persistNow() {
        guard core != nil else { return }
        writeBattery(force: true)
        saveProtectedResume()
    }

    // MARK: Controls

    func setKey(_ key: Int, pressed: Bool) {
        input.set(UInt32(truncatingIfNeeded: key), pressed: pressed)
    }

    func setDirections(_ mask: UInt8) { input.directions(mask) }

    // MARK: Menu actions

    func quickSave() {
        if saveSlot("quick") {
            hasQuickSave = true
            show(toast: "Game saved to the quick slot")
        }
    }

    func quickLoad() {
        show(toast: loadSlot("quick") ? "Quick save loaded" : "No quick save yet")
    }

    @discardableResult
    func saveSlot(_ slot: String) -> Bool {
        guard ["quick", "slot1", "slot2", "slot3"].contains(slot), saveState(slot: slot) else { return false }
        if let preview = screens.allObjects.first?.screenshotPNG() {
            try? preview.write(to: library.statePreviewURL(for: game, slot: slot), options: .atomic)
        }
        if slot == "quick" { hasQuickSave = true }
        return true
    }

    @discardableResult
    func loadSlot(_ slot: String) -> Bool {
        guard ["quick", "slot1", "slot2", "slot3"].contains(slot) else { return false }
        return loadState(slot: slot)
    }

    func restart() {
        guard let core else { return }
        writeBattery(force: true)
        core.reset()
        library.clearProtectedResume(for: game)
        lastResumeCheckpoint = Date()
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
        // The console clock must never stop when audio is interrupted or its queue fills.
        let elapsed = lastFrameTime == 0 ? 1.0 / 60 : min(0.1, link.timestamp - lastFrameTime)
        lastFrameTime = link.timestamp
        frameDebt += elapsed * core.frameRate
        var frames = 0
        while frameDebt >= 1 && frames < 6 {
            let keys = input.nextFrame() | controllerKeys()
            if keys & ~0x0F != 0 { deliveredActions += 1 }
            if keys & 0x0F != 0 { deliveredDirections += 1 }
            core.setKeys(keys)
            core.runFrame()
            frameDebt -= 1
            frames += 1
        }
        if let reason = core.failure {
            // The emulator hit something it can't continue from. Stop here with a message
            // (and without saving the broken machine over the resume point).
            stop(keepResume: true)
            errorMessage = "\(game.name) stopped: the emulator ran into a problem it can't recover from.\n\n\(reason)\n\nYour last resume point and save slots are untouched."
            return
        }
        for screen in screens.allObjects { core.show(on: screen) }

        let strength = core.rumble
        if strength > 0.1, Date().timeIntervalSince(lastRumble) > 0.08 {
            rumble.impactOccurred(intensity: CGFloat(min(1, strength)))
            lastRumble = Date()
        }

        // Rolling checkpoint protects play when iOS terminates a suspended session.
        if Date().timeIntervalSince(lastResumeCheckpoint) >= 120 {
            lastResumeCheckpoint = Date()
            saveProtectedResume()
        }
        framesSinceSaveCheck += 1
        if framesSinceSaveCheck >= 300 {
            framesSinceSaveCheck = 0
            writeBattery(force: false)
        }
    }

    private func controllerKeys() -> UInt32 {
        var mask = 0
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            if pad.dpad.right.isPressed || pad.leftThumbstick.right.isPressed { mask |= Int(RD_KEY_RIGHT) }
            if pad.dpad.left.isPressed || pad.leftThumbstick.left.isPressed { mask |= Int(RD_KEY_LEFT) }
            if pad.dpad.up.isPressed || pad.leftThumbstick.up.isPressed { mask |= Int(RD_KEY_UP) }
            if pad.dpad.down.isPressed || pad.leftThumbstick.down.isPressed { mask |= Int(RD_KEY_DOWN) }
            // Match the handheld's layout: the right face button is A, the bottom one is B.
            if AVControllerMapping.pressed("A", pad: pad, system: game.system) { mask |= Int(RD_KEY_A) }
            if AVControllerMapping.pressed("B", pad: pad, system: game.system) { mask |= Int(RD_KEY_B) }
            if pad.buttonMenu.isPressed { mask |= Int(RD_KEY_START) }
            if pad.buttonOptions?.isPressed == true { mask |= Int(RD_KEY_SELECT) }
            if game.system.hasShoulders {
                if pad.leftShoulder.isPressed || pad.leftTrigger.isPressed { mask |= PadKey.l }
                if pad.rightShoulder.isPressed || pad.rightTrigger.isPressed { mask |= PadKey.r }
            }
            if game.system == .genesis {
                // Genesis 6-button pad: shoulders are Z and C, the menu button is MODE.
                if pad.leftShoulder.isPressed || pad.leftTrigger.isPressed { mask |= PadKey.z }
                if pad.rightShoulder.isPressed || pad.rightTrigger.isPressed { mask |= PadKey.c }
                if pad.buttonOptions?.isPressed == true { mask |= PadKey.mode }
            }
            if game.system.faceKeys.count > 2 {
                if AVControllerMapping.pressed("X", pad: pad, system: game.system) { mask |= PadKey.x }
                if AVControllerMapping.pressed("Y", pad: pad, system: game.system) { mask |= PadKey.y }
            }
        }
        mask |= HingeControl.shared.keys(for: game.system, left: Int(RD_KEY_LEFT), right: Int(RD_KEY_RIGHT)) { label in
            switch label {
            case "L": return PadKey.l
            case "R": return PadKey.r
            default:
                return game.system.faceKeys.first { $0.label == label }?.key
                    ?? game.system.menuKeys.first { $0.label == label }?.key ?? 0
            }
        }
        return UInt32(truncatingIfNeeded: mask)
    }

    // MARK: Saves

    private func writeBattery(force: Bool) {
        guard let data = core?.battery() else { return }
        // `force` writes even when unchanged so the file always exists after a session.
        guard force || data != savedBattery else { return }
        if (try? data.write(to: library.batteryURL(for: game), options: .atomic)) != nil {
            savedBattery = data
        }
    }

    private func saveProtectedResume() {
        guard let data = core?.saveState() else { return }
        _ = library.saveProtectedResume(data, for: game)
    }

    @discardableResult
    private func saveState(slot: String) -> Bool {
        guard let data = core?.saveState() else { return false }
        return (try? data.write(to: library.stateURL(for: game, slot: slot), options: .atomic)) != nil
    }

    private func loadState(slot: String) -> Bool {
        guard let core, let data = try? Data(contentsOf: library.stateURL(for: game, slot: slot)) else { return false }
        let loaded = core.loadState(data)
        if loaded {
            for screen in screens.allObjects { core.show(on: screen) }
        }
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
