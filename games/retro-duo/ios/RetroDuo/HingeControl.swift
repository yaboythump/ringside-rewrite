// AVYDRIX Play - applies the hinge gesture to the running game.
// Copyright 2026 CT Network Studios. GPL v3 or later.
import Foundation

/// The hinge as a game control. HingeReader feeds it every hinge update; the game sessions
/// ask it for keys every frame (which also lets the resting angle be learned while the
/// phone sits perfectly still and no updates arrive).
@MainActor
final class HingeControl {
    static let shared = HingeControl()

    private var tracker = HingeTracker()
    private var angle: Double?
    private var partiallyOpen = false

    func update(angleDegrees: Double?, partiallyOpen: Bool) {
        angle = angleDegrees
        self.partiallyOpen = partiallyOpen
    }

    /// Learn the resting angle again (when a game starts or resumes).
    func recenter() { tracker.recenter() }

    // MARK: Settings (per system)

    static func modeKey(_ system: GameSystem) -> String { "avydrix.hinge.\(system.rawValue).mode" }
    static func buttonKey(_ system: GameSystem) -> String { "avydrix.hinge.\(system.rawValue).button" }

    static func mode(for system: GameSystem) -> HingeMode {
        HingeMode(rawValue: UserDefaults.standard.string(forKey: modeKey(system)) ?? "") ?? .off
    }

    /// The buttons a squeeze can press on this system.
    static func buttonChoices(for system: GameSystem) -> [String] {
        if system == .nintendoDS { return ["A", "B", "X", "Y", "L", "R", "START", "SELECT"] }
        // A first where there is one (the usual "action" button), then the rest in pad order.
        var choices = system.faceKeys.map(\.label)
        if let a = choices.firstIndex(of: "A") { choices.insert(choices.remove(at: a), at: 0) }
        if system.hasShoulders { choices += ["L", "R"] }
        choices += system.menuKeys.map(\.label)
        return choices
    }

    static func button(for system: GameSystem) -> String {
        let choices = buttonChoices(for: system)
        if let saved = UserDefaults.standard.string(forKey: buttonKey(system)), choices.contains(saved) {
            return saved
        }
        return choices.first ?? "A"
    }

    // MARK: Per frame

    /// The keys the hinge holds down this frame. `left` / `right` are the session's direction
    /// bits; `bit` turns a button label from `buttonChoices` into the session's bit.
    func keys(for system: GameSystem, left: Int, right: Int, bit: (String) -> Int) -> Int {
        let mode = Self.mode(for: system)
        guard mode != .off else { return 0 }
        let fold = tracker.update(angle: angle, partiallyOpen: partiallyOpen,
                                  at: ProcessInfo.processInfo.systemUptime)
        switch mode {
        case .off: return 0
        case .steer: return fold == .closer ? left : fold == .wider ? right : 0
        case .button: return fold == .closer ? bit(Self.button(for: system)) : 0
        }
    }
}
