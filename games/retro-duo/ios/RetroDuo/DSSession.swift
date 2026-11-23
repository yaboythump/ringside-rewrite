import GameController
import QuartzCore
import SwiftUI
import UIKit

/// Runs one Nintendo DS game. melonDS runs on its own thread (see MDCore.cpp);
/// this class feeds it input, shows its two screens and keeps its saves.
@MainActor
final class DSSession: NSObject, ObservableObject, PadInput {
    @Published private(set) var hasQuickSave = false
    @Published private(set) var isMuted = UserDefaults.standard.bool(forKey: "muted")
    @Published private(set) var errorMessage: String?
    @Published var toast: String?

    let game: Game
    private let library: GameLibrary
    private var core: OpaquePointer?
    private var displayLink: CADisplayLink?
    private let audio = AudioOutput()
    private var isPaused = false
    private var held: UInt32 = 0
    private var pressedAt: [Int: CFTimeInterval] = [:]
    private var top = [UInt32](repeating: 0xFF000000, count: Int(MD_SCREEN_WIDTH) * Int(MD_SCREEN_HEIGHT))
    private var bottom = [UInt32](repeating: 0xFF000000, count: Int(MD_SCREEN_WIDTH) * Int(MD_SCREEN_HEIGHT))
    private var lastFrame: UInt64 = 0
    private var ticks = 0
    private var lastResumeCheckpoint = Date()
    private var toastTask: Task<Void, Never>?
    private let topScreens = NSHashTable<PixelScreenView>.weakObjects()
    private let bottomScreens = NSHashTable<PixelScreenView>.weakObjects()

    func attachScreen(_ view: PixelScreenView, top isTop: Bool) {
        view.streamSlot = isTop ? 0 : 1
        (isTop ? topScreens : bottomScreens).add(view)
        // Repaint even while paused or when the DS has not produced a new frame.
        let pixels = isTop ? top : bottom
        pixels.withUnsafeBufferPointer {
            view.show(pixels: $0.baseAddress!, width: Int(MD_SCREEN_WIDTH), height: Int(MD_SCREEN_HEIGHT))
        }
    }

    var diagnostics: String {
        "frames:\(lastFrame) speed:\(Int(core.map { MDCoreSpeed($0) } ?? 0)) audio:\(audio.isRunning)"
    }

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
        guard let rom = try? Data(contentsOf: game.url, options: .alwaysMapped),
              GameLibrary.looksLikeDSROM(rom.prefix(0x200)) else {
            errorMessage = "\(game.name) couldn't be opened. The file may be damaged or not a DS game."
            return
        }
        guard let created = MDCoreCreate(UInt32(AudioOutput.sampleRate)) else {
            errorMessage = "The DS emulator couldn't start."
            return
        }
        let save = (try? Data(contentsOf: library.batteryURL(for: game))) ?? Data()
        let loaded = rom.withUnsafeBytes { romBytes in
            save.withUnsafeBytes { saveBytes in
                MDCoreLoadROM(created,
                              romBytes.bindMemory(to: UInt8.self).baseAddress, romBytes.count,
                              saveBytes.bindMemory(to: UInt8.self).baseAddress, saveBytes.count,
                              game.name)
            }
        }
        guard loaded else {
            MDCoreDestroy(created)
            errorMessage = "\(game.name) isn't a DS game AVYDRIX Play can run."
            return
        }
        core = created
        if library.restoreProtectedResume(for: game, using: { [weak self] data in
            guard let core = self?.core else { return false }
            return data.withUnsafeBytes {
                MDCoreLoadState(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
            }
        }) {
            show(toast: "Protected session restored")
        }
        lastResumeCheckpoint = Date()
        MDCoreSetRunning(created, true)
        audio.start(dsCore: created)
        audio.setMuted(isMuted)

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        guard let core else { return }
        MDCoreSetRunning(core, false)
        writeSave(force: true)
        saveProtectedResume()
        audio.stop()
        MDCoreDestroy(core)
        self.core = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if !paused { HingeControl.shared.recenter() } // learn how the phone is held now
        guard let core else { return }
        MDCoreSetRunning(core, !paused)
        if paused {
            held = 0
            pressedAt.removeAll()
            MDCoreSetKeys(core, 0)
            MDCoreSetTouch(core, false, 0, 0)
            writeSave(force: false)
            audio.setMuted(true)
        } else {
            if !audio.isRunning { audio.start(dsCore: core) }
            audio.setMuted(isMuted)
        }
    }

    /// Starts the sound again with the current audio session settings (live streaming
    /// switches the microphone on and off).
    func restartAudio() {
        guard let core else { return }
        audio.start(dsCore: core)
        audio.setMuted(isPaused || isMuted)
    }

    func persistNow() {
        guard core != nil else { return }
        writeSave(force: true)
        saveProtectedResume()
    }

    // MARK: Input

    func setKey(_ key: Int, pressed: Bool) {
        let bit = UInt32(key)
        if pressed {
            held |= bit
            pressedAt[key] = CACurrentMediaTime()
        } else {
            // A very quick tap could start and end between two console frames;
            // keep it held for at least 50 ms so the game always sees it.
            let heldFor = CACurrentMediaTime() - (pressedAt[key] ?? 0)
            let delay = max(0, 0.05 - heldFor)
            if delay == 0 {
                held &= ~bit
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, (self.pressedAt[key] ?? 0) + 0.05 <= CACurrentMediaTime() + 0.001 else { return }
                    self.held &= ~bit
                    self.pushKeys()
                }
            }
        }
        pushKeys()
    }

    func setDirections(_ mask: UInt8) {
        let directions = UInt32(MD_KEY_RIGHT | MD_KEY_LEFT | MD_KEY_UP | MD_KEY_DOWN)
        var bits: UInt32 = 0
        if mask & 1 != 0 { bits |= UInt32(MD_KEY_RIGHT) }
        if mask & 2 != 0 { bits |= UInt32(MD_KEY_LEFT) }
        if mask & 4 != 0 { bits |= UInt32(MD_KEY_UP) }
        if mask & 8 != 0 { bits |= UInt32(MD_KEY_DOWN) }
        held = (held & ~directions) | bits
        pushKeys()
    }

    /// `point` is in DS pixels on the bottom screen, or nil when the finger lifts.
    func setTouch(_ point: CGPoint?) {
        guard let core, !isPaused else { return }
        if let point {
            MDCoreSetTouch(core, true, Int32(point.x.rounded(.down)), Int32(point.y.rounded(.down)))
        } else {
            MDCoreSetTouch(core, false, 0, 0)
        }
    }

    private func pushKeys() {
        guard let core, !isPaused else { return }
        MDCoreSetKeys(core, held | controllerKeys())
    }

    private func controllerKeys() -> UInt32 {
        var mask = 0
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            if pad.dpad.right.isPressed || pad.leftThumbstick.right.isPressed { mask |= Int(MD_KEY_RIGHT) }
            if pad.dpad.left.isPressed || pad.leftThumbstick.left.isPressed { mask |= Int(MD_KEY_LEFT) }
            if pad.dpad.up.isPressed || pad.leftThumbstick.up.isPressed { mask |= Int(MD_KEY_UP) }
            if pad.dpad.down.isPressed || pad.leftThumbstick.down.isPressed { mask |= Int(MD_KEY_DOWN) }
            // Face buttons by position, like the DS: right A, bottom B, top X, left Y.
            if AVControllerMapping.pressed("A", pad: pad, system: game.system) { mask |= Int(MD_KEY_A) }
            if AVControllerMapping.pressed("B", pad: pad, system: game.system) { mask |= Int(MD_KEY_B) }
            if AVControllerMapping.pressed("X", pad: pad, system: game.system) { mask |= Int(MD_KEY_X) }
            if AVControllerMapping.pressed("Y", pad: pad, system: game.system) { mask |= Int(MD_KEY_Y) }
            if pad.leftShoulder.isPressed || pad.leftTrigger.isPressed { mask |= Int(MD_KEY_L) }
            if pad.rightShoulder.isPressed || pad.rightTrigger.isPressed { mask |= Int(MD_KEY_R) }
            if pad.buttonMenu.isPressed { mask |= Int(MD_KEY_START) }
            if pad.buttonOptions?.isPressed == true { mask |= Int(MD_KEY_SELECT) }
        }
        mask |= HingeControl.shared.keys(for: game.system, left: Int(MD_KEY_LEFT), right: Int(MD_KEY_RIGHT)) { label in
            switch label {
            case "A": return Int(MD_KEY_A)
            case "B": return Int(MD_KEY_B)
            case "X": return Int(MD_KEY_X)
            case "Y": return Int(MD_KEY_Y)
            case "L": return Int(MD_KEY_L)
            case "R": return Int(MD_KEY_R)
            case "START": return Int(MD_KEY_START)
            case "SELECT": return Int(MD_KEY_SELECT)
            default: return 0
            }
        }
        return UInt32(truncatingIfNeeded: mask)
    }

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
        if let preview = topScreens.allObjects.first?.screenshotPNG() {
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
        writeSave(force: true)
        MDCoreReset(core)
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
        pushKeys() // picks up game controllers
        let frame = top.withUnsafeMutableBufferPointer { topBuffer in
            bottom.withUnsafeMutableBufferPointer { bottomBuffer in
                MDCoreCopyScreens(core, topBuffer.baseAddress, bottomBuffer.baseAddress)
            }
        }
        if frame != lastFrame {
            lastFrame = frame
            top.withUnsafeBufferPointer { buffer in
                for screen in topScreens.allObjects {
                    screen.show(pixels: buffer.baseAddress!, width: Int(MD_SCREEN_WIDTH), height: Int(MD_SCREEN_HEIGHT))
                }
            }
            bottom.withUnsafeBufferPointer { buffer in
                for screen in bottomScreens.allObjects {
                    screen.show(pixels: buffer.baseAddress!, width: Int(MD_SCREEN_WIDTH), height: Int(MD_SCREEN_HEIGHT))
                }
            }
        }
        ticks += 1
        if ticks % 120 == 0 { writeSave(force: false) }
        if Date().timeIntervalSince(lastResumeCheckpoint) >= 120 {
            lastResumeCheckpoint = Date()
            saveProtectedResume()
        }
    }

    // MARK: Saves

    private func writeSave(force: Bool) {
        guard let core else { return }
        let changed = MDCoreSaveChanged(core)
        guard changed || force else { return }
        let size = MDCoreSaveSize(core)
        guard size > 0 else { return }
        var data = Data(count: size)
        let copied = data.withUnsafeMutableBytes {
            MDCoreCopySave(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        guard copied == size else { return }
        try? data.write(to: library.batteryURL(for: game), options: .atomic)
    }

    private func saveProtectedResume() {
        guard let core else { return }
        var length = 0
        guard let buffer = MDCoreSaveState(core, &length) else { return }
        defer { MDCoreFreeBuffer(buffer) }
        guard length >= 32 else { return }
        _ = library.saveProtectedResume(Data(bytes: buffer, count: length), for: game)
    }

    @discardableResult
    private func saveState(slot: String) -> Bool {
        guard let core else { return false }
        var length = 0
        guard let buffer = MDCoreSaveState(core, &length) else { return false }
        defer { MDCoreFreeBuffer(buffer) }
        let data = Data(bytes: buffer, count: length)
        return (try? data.write(to: library.stateURL(for: game, slot: slot), options: .atomic)) != nil
    }

    private func loadState(slot: String) -> Bool {
        guard let core, let data = try? Data(contentsOf: library.stateURL(for: game, slot: slot)) else { return false }
        return data.withUnsafeBytes {
            MDCoreLoadState(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
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
