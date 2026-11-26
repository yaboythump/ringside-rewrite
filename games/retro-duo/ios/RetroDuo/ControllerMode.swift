import Combine
import GameController
import SwiftUI

/// Controller mode: with a Bluetooth controller (SCUF, Xbox, PlayStation, Backbone...) the touch
/// controls go away and the game fills the screen. Home on the controller (or clicking both
/// sticks) opens the game menu; a tap on the screen shows the top bar for a few seconds.
enum ControllerMode: String, CaseIterable, Identifiable {
    /// On whenever a controller is connected.
    case auto
    case on
    case off

    static let key = "avydrix.controllerMode"
    /// Turn the game sideways in controller mode, so it fills the screen.
    static let landscapeKey = "avydrix.controllerMode.landscape"

    static var turnsSideways: Bool { UserDefaults.standard.object(forKey: landscapeKey) as? Bool ?? true }

    /// Holds the screen in landscape (or lets it turn freely again).
    @MainActor
    static func holdLandscape(_ hold: Bool) {
        // UI tests check the layouts in the orientation they set themselves.
        if hold && ProcessInfo.processInfo.arguments.contains("-RetroDuoUITests") { return }
        let mask: UIInterfaceOrientationMask = hold ? .landscape : .allButUpsideDown
        guard AppDelegate.orientations != mask else { return }
        AppDelegate.orientations = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: hold ? .landscape : .portrait)) { _ in }
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "When a controller is connected"
        case .on: return "Always"
        case .off: return "Off"
        }
    }

    static var current: ControllerMode {
        ControllerMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto
    }

    func isActive(controllerConnected: Bool) -> Bool {
        switch self {
        case .auto: return controllerConnected
        case .on: return true
        case .off: return false
        }
    }
}

/// Which controllers are connected, and the controller's "open the menu" presses.
@MainActor
final class ControllerWatcher: ObservableObject {
    static let shared = ControllerWatcher()

    @Published private(set) var connected = false
    @Published private(set) var name: String?
    /// Home, both sticks clicked together, or Select + Start (View + Menu, Share + Options).
    let menuPressed = PassthroughSubject<Void, Never>()

    /// UI tests stand in a controller with this launch argument.
    private let simulated = ProcessInfo.processInfo.arguments.contains("-AvydrixSimulateController")
    private let uiTests = ProcessInfo.processInfo.arguments.contains("-RetroDuoUITests")

    private init() {
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ControllerWatcher.shared.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        pads.forEach(configure)
        // UI tests only see the stand-in (a simulator can report a controller of its own).
        connected = simulated || (!uiTests && !pads.isEmpty)
        name = simulated ? "Test controller" : pads.first?.vendorName
    }

    private func configure(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        if let home = pad.buttonHome {
            // Let the app have Home instead of iOS's game overlay.
            home.preferredSystemGestureState = .disabled
            home.pressedChangedHandler = { _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { ControllerWatcher.shared.menuPressed.send() }
            }
        }
        // Some controllers' Home stays with iOS: the extended profile's and the physical
        // profile's Home are watched, plus two button pairs that always reach the app.
        if let home = controller.physicalInputProfile.buttons[GCInputButtonHome], home !== pad.buttonHome {
            home.preferredSystemGestureState = .disabled
            home.pressedChangedHandler = { _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { ControllerWatcher.shared.menuPressed.send() }
            }
        }
        let pairs: GCControllerButtonValueChangedHandler = { [weak pad] _, _, pressed in
            guard pressed, let pad else { return }
            let sticks = pad.leftThumbstickButton?.isPressed == true && pad.rightThumbstickButton?.isPressed == true
            let selectStart = pad.buttonOptions?.isPressed == true && pad.buttonMenu.isPressed
            guard sticks || selectStart else { return }
            MainActor.assumeIsolated { ControllerWatcher.shared.menuPressed.send() }
        }
        pad.leftThumbstickButton?.pressedChangedHandler = pairs
        pad.rightThumbstickButton?.pressedChangedHandler = pairs
        pad.buttonOptions?.pressedChangedHandler = pairs
        pad.buttonMenu.pressedChangedHandler = pairs
    }
}

/// The top bar in controller mode: shown at first and after a tap, then out of the way.
struct ControllerChrome<Bar: View>: ViewModifier {
    @ViewBuilder var bar: () -> Bar
    @State private var visible = true
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // Alongside the game's own touches (the DS touch screen still works).
            .simultaneousGesture(TapGesture().onEnded { show() })
            .overlay(alignment: .top) {
                if visible {
                    bar()
                        .background(LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0)],
                                                   startPoint: .top, endPoint: .bottom))
                        .transition(.opacity)
                }
            }
            .onAppear { show() }
    }

    private func show() {
        withAnimation(.easeOut(duration: 0.2)) { visible = true }
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard mine == generation else { return }
            withAnimation(.easeIn(duration: 0.4)) { visible = false }
        }
    }
}

/// What the lower screen shows in controller mode when the Duo is folded like a laptop.
struct ControllerModeHint: View {
    @ObservedObject private var controllers = ControllerWatcher.shared

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(controllers.name.map { "\($0) connected" } ?? "Controller mode")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Press Select + Start together (or Home, or both sticks) for the game menu.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("controller-mode-hint")
    }
}
