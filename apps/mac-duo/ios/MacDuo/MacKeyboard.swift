import SwiftUI
import UIKit

/// Macintosh virtual key codes (US layout), as Mini vMac expects them.
enum MacKey {
    static let returnKey: Int32 = 0x24, tab: Int32 = 0x30, space: Int32 = 0x31, delete: Int32 = 0x33
    static let escape: Int32 = 0x35, command: Int32 = 0x37, shift: Int32 = 0x38, capsLock: Int32 = 0x39
    static let option: Int32 = 0x3A, control: Int32 = 0x3B
    static let left: Int32 = 0x7B, right: Int32 = 0x7C, down: Int32 = 0x7D, up: Int32 = 0x7E
    static let forwardDelete: Int32 = 0x75, home: Int32 = 0x73, end: Int32 = 0x77
    static let pageUp: Int32 = 0x74, pageDown: Int32 = 0x79, enter: Int32 = 0x4C

    /// Unshifted and shifted characters for each key on a US keyboard.
    private static let layout: [(Int32, Character, Character)] = [
        (0x00, "a", "A"), (0x0B, "b", "B"), (0x08, "c", "C"), (0x02, "d", "D"), (0x0E, "e", "E"),
        (0x03, "f", "F"), (0x05, "g", "G"), (0x04, "h", "H"), (0x22, "i", "I"), (0x26, "j", "J"),
        (0x28, "k", "K"), (0x25, "l", "L"), (0x2E, "m", "M"), (0x2D, "n", "N"), (0x1F, "o", "O"),
        (0x23, "p", "P"), (0x0C, "q", "Q"), (0x0F, "r", "R"), (0x01, "s", "S"), (0x11, "t", "T"),
        (0x20, "u", "U"), (0x09, "v", "V"), (0x0D, "w", "W"), (0x07, "x", "X"), (0x10, "y", "Y"),
        (0x06, "z", "Z"),
        (0x12, "1", "!"), (0x13, "2", "@"), (0x14, "3", "#"), (0x15, "4", "$"), (0x17, "5", "%"),
        (0x16, "6", "^"), (0x1A, "7", "&"), (0x1C, "8", "*"), (0x19, "9", "("), (0x1D, "0", ")"),
        (0x1B, "-", "_"), (0x18, "=", "+"), (0x21, "[", "{"), (0x1E, "]", "}"), (0x2A, "\\", "|"),
        (0x29, ";", ":"), (0x27, "'", "\""), (0x2B, ",", "<"), (0x2F, ".", ">"), (0x2C, "/", "?"),
        (0x32, "`", "~"), (0x31, " ", " "),
    ]

    private static let characters: [Character: (code: Int32, shift: Bool)] = {
        var map: [Character: (code: Int32, shift: Bool)] = [:]
        for (code, plain, shifted) in layout {
            map[plain] = (code, false)
            if map[shifted] == nil { map[shifted] = (code, true) }
        }
        // Typographic characters the iPhone keyboard likes to produce.
        map["\u{2018}"] = (0x27, false); map["\u{2019}"] = (0x27, false)
        map["\u{201C}"] = (0x27, true); map["\u{201D}"] = (0x27, true)
        map["\u{2014}"] = (0x1B, true); map["\u{2013}"] = (0x1B, false)
        map["\n"] = (returnKey, false); map["\r"] = (returnKey, false); map["\t"] = (tab, false)
        return map
    }()

    static func code(for character: Character) -> (code: Int32, shift: Bool)? { characters[character] }

    /// USB HID usage (UIKeyboardHIDUsage) to Mac key code, for hardware keyboards.
    static func code(forHID usage: Int) -> Int32? {
        switch usage {
        case 0x04...0x1D: // A...Z
            let letters: [Int32] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                    0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
            return letters[usage - 0x04]
        case 0x1E...0x27: // 1...0
            let digits: [Int32] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
            return digits[usage - 0x1E]
        case 0x28: return returnKey
        case 0x29: return escape
        case 0x2A: return delete
        case 0x2B: return tab
        case 0x2C: return space
        case 0x2D: return 0x1B
        case 0x2E: return 0x18
        case 0x2F: return 0x21
        case 0x30: return 0x1E
        case 0x31: return 0x2A
        case 0x33: return 0x29
        case 0x34: return 0x27
        case 0x35: return 0x32
        case 0x36: return 0x2B
        case 0x37: return 0x2F
        case 0x38: return 0x2C
        case 0x39: return capsLock
        case 0x3A...0x45: // F1...F12
            let function: [Int32] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
            return function[usage - 0x3A]
        case 0x49: return 0x72 // Insert -> Help
        case 0x4A: return home
        case 0x4B: return pageUp
        case 0x4C: return forwardDelete
        case 0x4D: return end
        case 0x4E: return pageDown
        case 0x4F: return right
        case 0x50: return left
        case 0x51: return down
        case 0x52: return up
        case 0x58: return enter
        case 0xE0, 0xE4: return control
        case 0xE1, 0xE5: return shift
        case 0xE2, 0xE6: return option
        case 0xE3, 0xE7: return command
        default: return nil
        }
    }
}

/// Modifier keys on the on-screen bar. Tap once to hold for the next key,
/// or double-tap to lock (like Caps Lock).
@MainActor
final class ModifierState: ObservableObject {
    enum Modifier: CaseIterable, Identifiable {
        case command, option, control, shift
        var id: Self { self }
        var symbol: String {
            switch self { case .command: return "⌘"; case .option: return "⌥"; case .control: return "⌃"; case .shift: return "⇧" }
        }
        var name: String {
            switch self { case .command: return "Command"; case .option: return "Option"; case .control: return "Control"; case .shift: return "Shift" }
        }
        var code: Int32 {
            switch self { case .command: return MacKey.command; case .option: return MacKey.option; case .control: return MacKey.control; case .shift: return MacKey.shift }
        }
    }

    @Published private(set) var held: Set<Modifier> = []
    @Published private(set) var locked: Set<Modifier> = []
    private var lastTap: [Modifier: Date] = [:]

    func tap(_ modifier: Modifier) {
        if locked.contains(modifier) {
            locked.remove(modifier)
            held.remove(modifier)
        } else if held.contains(modifier) {
            if let last = lastTap[modifier], Date().timeIntervalSince(last) < 0.4 {
                locked.insert(modifier)
            } else {
                held.remove(modifier)
            }
        } else {
            held.insert(modifier)
        }
        lastTap[modifier] = Date()
        Haptics.tap()
    }

    /// Presses a key with the chosen modifiers, then releases one-shot modifiers.
    func press(_ code: Int32, shift extraShift: Bool = false) {
        let active = held.union(locked)
        let mods = active.map(\.code) + (extraShift && !active.contains(.shift) ? [MacKey.shift] : [])
        for m in mods { MVCoreKey(m, 1) }
        MVCoreKey(code, 1)
        // Hold briefly so the Mac (polling at 60 Hz) sees the key go down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            MVCoreKey(code, 0)
            for m in mods.reversed() { MVCoreKey(m, 0) }
        }
        held.subtract(held.subtracting(locked))
    }

    func clear() {
        held = []
        locked = []
    }
}

/// An invisible view that receives the iPhone keyboard's typing and any
/// hardware keyboard. With `showsKeyboard` off it still listens to hardware
/// keys but keeps the on-screen keyboard hidden.
struct KeyCapture: UIViewRepresentable {
    @Binding var showsKeyboard: Bool
    var isActive: Bool
    let modifiers: ModifierState

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.modifiers = modifiers
        view.onKeyboardDismissed = { showsKeyboard = false }
        return view
    }

    func updateUIView(_ view: KeyCaptureUIView, context: Context) {
        view.modifiers = modifiers
        view.setSoftwareKeyboard(visible: showsKeyboard)
        DispatchQueue.main.async {
            if isActive {
                if !view.isFirstResponder { view.becomeFirstResponder() }
            } else if view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }
}

final class KeyCaptureUIView: UIView, UIKeyInput {
    var modifiers: ModifierState?
    var onKeyboardDismissed: (() -> Void)?
    private var softwareKeyboard = false
    private let hiddenInput = UIView(frame: .zero)
    private var pressedHardware: Set<Int32> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardHidden),
                                               name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var canBecomeFirstResponder: Bool { true }
    override var inputView: UIView? { softwareKeyboard ? nil : hiddenInput }
    override var inputAccessoryView: UIView? { nil }

    func setSoftwareKeyboard(visible: Bool) {
        guard visible != softwareKeyboard else { return }
        softwareKeyboard = visible
        if isFirstResponder { reloadInputViews() }
    }

    @objc private func keyboardHidden() {
        // The person swiped the keyboard away.
        if softwareKeyboard && isFirstResponder == false { onKeyboardDismissed?() }
    }

    // UITextInputTraits: type exactly what was pressed.
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .asciiCapable
    var returnKeyType: UIReturnKeyType = .default
    var inlinePredictionType: UITextInlinePredictionType = .no

    var hasText: Bool { true }

    func insertText(_ text: String) {
        for character in text {
            guard let key = MacKey.code(for: character) else { continue }
            if let modifiers {
                modifiers.press(key.code, shift: key.shift)
            }
        }
    }

    func deleteBackward() {
        modifiers?.press(MacKey.delete)
    }

    // MARK: - Hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            if let usage = press.key?.keyCode.rawValue, let code = MacKey.code(forHID: usage) {
                pressedHardware.insert(code)
                MVCoreKey(code, 1)
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            if let usage = press.key?.keyCode.rawValue, let code = MacKey.code(forHID: usage) {
                pressedHardware.remove(code)
                MVCoreKey(code, 0)
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for code in pressedHardware { MVCoreKey(code, 0) }
        pressedHardware.removeAll()
        super.pressesCancelled(presses, with: event)
    }
}

/// Esc, Tab, modifiers, arrows and the keyboard button.
struct KeyBar: View {
    @ObservedObject var modifiers: ModifierState
    @Binding var showsKeyboard: Bool

    var body: some View {
        HStack(spacing: 6) {
            key("esc") { modifiers.press(MacKey.escape) }
            key("⇥") { modifiers.press(MacKey.tab) }
            ForEach(ModifierState.Modifier.allCases) { modifier in
                let on = modifiers.held.contains(modifier) || modifiers.locked.contains(modifier)
                Button { modifiers.tap(modifier) } label: {
                    Text(modifier.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(alignment: .bottom) {
                            if modifiers.locked.contains(modifier) {
                                Capsule().fill(.white).frame(width: 12, height: 3).padding(.bottom, 4)
                            }
                        }
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .accessibilityLabel(modifier.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            key("←") { modifiers.press(MacKey.left) }
            VStack(spacing: 2) {
                smallKey("↑") { modifiers.press(MacKey.up) }
                smallKey("↓") { modifiers.press(MacKey.down) }
            }
            key("→") { modifiers.press(MacKey.right) }
            Button {
                showsKeyboard.toggle()
            } label: {
                Image(systemName: showsKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(showsKeyboard ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .accessibilityLabel(showsKeyboard ? "Hide keyboard" : "Show keyboard")
        }
        .buttonStyle(.plain)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: label.count > 1 ? 13 : 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func smallKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 18)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
