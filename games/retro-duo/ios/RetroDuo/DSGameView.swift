import SwiftUI

/// The DS top picture fills the upper Duo panel. The lower panel contains the
/// touch screen, D-pad, A/B/X/Y, shoulder buttons and game menu.
struct DSGameView: View {
    @StateObject private var session: DSSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var hinge = HingeState()
    @State private var showingMenu = false
    @AppStorage("retroDuoTwoPanels") private var useTwoPanels = true
    @AppStorage("retroDuoOriginalProportions") private var originalProportions = false
    @State private var diagnostics = ""

    init(session: @autoclosure @escaping () -> DSSession) {
        _session = StateObject(wrappedValue: session())
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Group {
                if let error = session.errorMessage {
                    errorView(error)
                } else if useTwoPanels || hinge.isHalfOpen {
                    if size.width > size.height {
                        tabletopLayout(size)
                    } else {
                        portraitLayout(size)
                    }
                } else if size.width > size.height * 1.15 {
                    landscapeLayout(size)
                } else {
                    portraitLayout(size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .background(ConsoleBackdrop())
        .overlay(alignment: .top) { toastView }
        .overlay(alignment: .bottom) {
            if ProcessInfo.processInfo.arguments.contains("-RetroDuoUITests") {
                Text(diagnostics).font(.system(size: 6)).accessibilityIdentifier("rd-diagnostics")
                    .allowsHitTesting(false)
                    .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in diagnostics = session.diagnostics }
            }
        }
        .modifier(HingeReader(state: $hinge))
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if !showingMenu { session.setPaused(false) }
            case .inactive:
                session.setPaused(true)
            case .background:
                session.setPaused(true)
                session.persistNow()
            @unknown default:
                break
            }
        }
        .confirmationDialog(session.game.name, isPresented: $showingMenu, titleVisibility: .visible) {
            Button(originalProportions ? "Fill entire upper screen" : "Use original screen proportions") {
                originalProportions.toggle()
            }
            Button(useTwoPanels ? "Use side controls in landscape" : "Use two-panel Duo layout") {
                useTwoPanels.toggle()
            }
            Button("Quick Save") { session.quickSave() }
            Button("Quick Load") { session.quickLoad() }
                .disabled(!session.hasQuickSave)
            Button(session.isMuted ? "Turn Sound On" : "Turn Sound Off") { session.toggleMute() }
            Button("Restart Game", role: .destructive) { session.restart() }
            Button("Back to Library") { dismiss() }
            Button("Resume", role: .cancel) {}
        }
        .onChange(of: showingMenu) { _, open in
            session.setPaused(open)
        }
    }

    // MARK: Layouts

    private func portraitLayout(_ size: CGSize) -> some View { twoPanelLayout(size) }
    private func tabletopLayout(_ size: CGSize) -> some View { twoPanelLayout(size) }

    /// The upper physical panel is only gameplay. Header and controls live below.
    private func twoPanelLayout(_ size: CGSize) -> some View {
        let half = size.height / 2
        let usable = max(70, half - 112)
        let side = min(150, size.width * 0.25)
        let touchWidth = max(40, min(size.width - 2 * side - 12, (usable - 8) * 4 / 3))
        let pad = max(44, min(side * 0.90, usable - 40, 150))
        let button = max(20, min((side - 8) / 2.56, (usable - 40) / 2.56, 58))
        return VStack(spacing: 0) {
            upperPanel(width: size.width, height: half)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 2)
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        ShoulderButton(label: "L", key: Int(MD_KEY_L), session: session)
                        DPad(session: session).frame(width: pad, height: pad)
                    }.frame(width: side)
                    Spacer(minLength: 0)
                    touchScreen(width: touchWidth)
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        ShoulderButton(label: "R", key: Int(MD_KEY_R), session: session)
                        DiamondButtons(session: session, diameter: button)
                    }.frame(width: side)
                }
                Spacer(minLength: 2)
                MenuButtons(session: session, selectKey: Int(MD_KEY_SELECT), startKey: Int(MD_KEY_START))
            }
            .padding(.bottom, 10)
            .frame(width: size.width, height: half)
        }
    }

    private func upperPanel(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            let pictureWidth = originalProportions ? min(width, height * 4 / 3) : width
            let pictureHeight = originalProportions ? pictureWidth * 0.75 : height
            DSScreen(session: session, which: .top)
                .frame(width: pictureWidth, height: pictureHeight)
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upperGamePanel")
        .accessibilityLabel("Top screen")
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let screenHeight = max(80, (size.height - 44) / 2) // two bezels, gap and padding
        let screenWidth = screenHeight * 4 / 3
        let side = max(140, (size.width - screenWidth - 10) / 2)
        let pad = max(96, min(side * 0.72, size.height * 0.42, 160))
        let button = max(38, min(pad * 0.36, 58))
        return HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    menuButton
                    Spacer()
                }
                .padding(.leading, 12)
                ShoulderButton(label: "L", key: Int(MD_KEY_L), session: session)
                Spacer(minLength: 0)
                DPad(session: session).frame(width: pad, height: pad)
                Spacer(minLength: 0)
                PillButton(label: "SELECT", key: Int(MD_KEY_SELECT), session: session)
            }
            .frame(width: side)
            VStack(spacing: 6) {
                screen(.top, width: screenWidth)
                touchScreen(width: screenWidth)
            }
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    muteButton
                }
                .padding(.trailing, 12)
                ShoulderButton(label: "R", key: Int(MD_KEY_R), session: session)
                Spacer(minLength: 0)
                DiamondButtons(session: session, diameter: button)
                Spacer(minLength: 0)
                PillButton(label: "START", key: Int(MD_KEY_START), session: session)
            }
            .frame(width: side)
        }
        .padding(.vertical, 6)
    }

    // MARK: Pieces

    /// A DS screen with a slim bezel. `width` is the picture; the bezel adds 8 points.
    private func screen(_ which: DSScreen.Which, width: CGFloat) -> some View {
        DSScreen(session: session, which: which)
            .frame(width: width, height: width * 0.75)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bezel.gradient))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 10, y: 5)
            .accessibilityLabel(which == .top ? "Top screen" : "Touch screen")
    }

    /// The bottom screen; touches go straight to the game in DS pixels.
    private func touchScreen(width: CGFloat) -> some View {
        screen(.bottom, width: width)
            .overlay(
                TouchSurface(label: "Touch screen") { point, bounds in
                    session.setTouch(point.map { p in
                        // The picture sits inside a 4-point bezel.
                        let inner = CGSize(width: bounds.width - 8, height: bounds.height - 8)
                        return CGPoint(x: (p.x - 4) / inner.width * 256, y: (p.y - 4) / inner.height * 192)
                    })
                }
            )
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            menuButton
            Spacer(minLength: 0)
            Text(session.game.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            muteButton
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private var muteButton: some View {
        Button { session.toggleMute() } label: {
            Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(session.isMuted ? .white.opacity(0.4) : Theme.accent)
                .frame(width: 44, height: 40)
        }
        .accessibilityLabel(session.isMuted ? "Turn sound on" : "Mute sound")
    }

    private var menuButton: some View {
        Button { showingMenu = true } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 36)
                .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.08)))
        }
        .accessibilityLabel("Game menu")
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = session.toast {
            Text(toast)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 52)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            Button("Back to Library") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A, B, X and Y in the DS diamond: X on top, A right, B bottom, Y left.
struct DiamondButtons: View {
    let session: any PadInput
    let diameter: CGFloat

    var body: some View {
        let reach = diameter * 0.78
        ZStack {
            ActionButton(label: "X", key: Int(MD_KEY_X), color: Color(red: 0.55, green: 0.58, blue: 0.66), diameter: diameter, session: session)
                .offset(y: -reach)
            ActionButton(label: "A", key: Int(MD_KEY_A), color: Theme.buttonA, diameter: diameter, session: session)
                .offset(x: reach)
            ActionButton(label: "B", key: Int(MD_KEY_B), color: Theme.buttonB, diameter: diameter, session: session)
                .offset(y: reach)
            ActionButton(label: "Y", key: Int(MD_KEY_Y), color: Color(red: 0.40, green: 0.45, blue: 0.55), diameter: diameter, session: session)
                .offset(x: -reach)
        }
        .frame(width: diameter + reach * 2, height: diameter + reach * 2)
    }
}

/// L or R shoulder button.
struct ShoulderButton: View {
    let label: String
    let key: Int
    let session: any PadInput
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(pressed ? Theme.background : .white.opacity(0.8))
            .frame(width: 78, height: 28)
            .background(Capsule().fill(pressed ? Theme.accent : Theme.pad))
            .overlay(Capsule().stroke(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
            .overlay(TouchSurface(label: "\(label) button") { point, _ in
                let down = point != nil
                guard pressed != down else { return }
                pressed = down
                if down { haptics.impactOccurred(intensity: 0.5) }
                session.setKey(key, pressed: down)
            })
    }
}
