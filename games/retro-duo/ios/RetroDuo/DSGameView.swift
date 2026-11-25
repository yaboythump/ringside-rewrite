import SwiftUI

/// The DS top picture fills the upper Duo panel. The lower panel contains the
/// touch screen, D-pad, A/B/X/Y, shoulder buttons and game menu.
struct DSGameView: View {
    @StateObject private var session: DSSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var hinge = HingeState()
    @State private var showingMenu = false
    @State private var showingLive = false
    @State private var showingCheats = false
    @StateObject private var tuning: AVControlTuning
    @StateObject private var controlLayout: ControlLayout
    @AppStorage("avydrix.duo.mode") private var duoMode = "auto"
    @AppStorage("avydrix.dsSwapScreens") private var swapScreens = false
    @AppStorage("avydrix.dsTouchScale") private var touchScale = 1.0
    @AppStorage("retroDuoTwoPanels") private var useTwoPanels = true
    @AppStorage("retroDuoOriginalProportions") private var originalProportions = false
    @State private var diagnostics = ""

    init(session: @autoclosure @escaping () -> DSSession) {
        let dsSession = session()
        _session = StateObject(wrappedValue: dsSession)
        _tuning = StateObject(wrappedValue: AVControlTuning(system: dsSession.game.system))
        _controlLayout = StateObject(wrappedValue: ControlLayout(system: dsSession.game.system))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Group {
                if let error = session.errorMessage {
                    errorView(error)
                } else if hinge.isHalfOpen || duoMode == "stacked" || (duoMode == "auto" && useTwoPanels) {
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
        .overlay(alignment: .top) {
            if controlLayout.editing {
                ControlLayoutEditBar(layout: controlLayout) {
                    controlLayout.editing = false
                    session.setPaused(false)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if ProcessInfo.processInfo.arguments.contains("-RetroDuoUITests") &&
                !ProcessInfo.processInfo.arguments.contains("-AvydrixStoreScreenshots") {
                Text(diagnostics).font(.system(size: 6)).accessibilityIdentifier("rd-diagnostics")
                    .allowsHitTesting(false)
                    .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in diagnostics = session.diagnostics }
            }
        }
        .modifier(HingeReader(state: $hinge))
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { session.start() }
        .onDisappear {
            LiveStreamer.shared.stop()
            session.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if !showingMenu && !controlLayout.editing { session.setPaused(false) }
            case .inactive:
                session.setPaused(true)
            case .background:
                LiveStreamer.shared.stopForBackground()
                session.setPaused(true)
                session.persistNow()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showingMenu) {
            AVInGameCommandCenter(
                game: session.game,
                muted: session.isMuted,
                quickAvailable: session.hasQuickSave,
                tuning: tuning,
                originalProportions: $originalProportions,
                useTwoPanels: $useTwoPanels,
                save: { session.saveSlot($0) },
                load: { session.loadSlot($0) },
                quickSave: { session.quickSave() },
                quickLoad: { session.quickLoad() },
                toggleMute: { session.toggleMute() },
                restart: { session.restart() },
                exit: {
                    session.persistNow()
                    showingMenu = false
                    dismiss()
                },
                editControls: {
                    controlLayout.editing = true
                    showingMenu = false
                },
                goLive: {
                    showingMenu = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showingLive = true }
                },
                openCheats: {
                    showingMenu = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showingCheats = true }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingCheats) {
            CheatsSheet(host: session)
                .onAppear { session.setPaused(true) }
                .onDisappear { session.setPaused(false) }
        }
        .sheet(isPresented: $showingLive) {
            LiveStreamSheet(screens: 2, restartAudio: { session.restartAudio() })
                .presentationDetents([.medium, .large])
        }
        .onChange(of: showingMenu) { _, open in
            session.setPaused(open || controlLayout.editing)
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
        let touchWidth = max(40, min(size.width - 2 * side - 12, (usable - 8) * 4 / 3 * touchScale))
        let pad = max(44, min(side * 0.90, usable - 40, 150))
        let button = max(20, min((side - 8) / 2.56, (usable - 40) / 2.56, 58))
        return VStack(spacing: 0) {
            upperPanel(width: size.width, height: half)
            VStack(spacing: 0) {
                topBar
                    .zIndex(2) // Keep the menu above the controls: a big or moved D-pad must never cover it.
                Spacer(minLength: 2)
                HStack(spacing: 0) {
                    if tuning.mirrored {
                        VStack(spacing: 8) {
                            ShoulderButton(label: "R", key: Int(MD_KEY_R), session: session)
                            actionButtons(diameter: button)
                        }
                        .placed(.buttons, "ds-panels", layout: controlLayout, area: size)
                        .frame(width: side)
                        Spacer(minLength: 0)
                        touchScreen(width: touchWidth)
                        Spacer(minLength: 0)
                        VStack(spacing: 8) {
                            ShoulderButton(label: "L", key: Int(MD_KEY_L), session: session)
                            directionPad(size: pad)
                        }
                        .placed(.dpad, "ds-panels", layout: controlLayout, area: size)
                        .frame(width: side)
                    } else {
                        VStack(spacing: 8) {
                            ShoulderButton(label: "L", key: Int(MD_KEY_L), session: session)
                            directionPad(size: pad)
                        }
                        .placed(.dpad, "ds-panels", layout: controlLayout, area: size)
                        .frame(width: side)
                        Spacer(minLength: 0)
                        touchScreen(width: touchWidth)
                        Spacer(minLength: 0)
                        VStack(spacing: 8) {
                            ShoulderButton(label: "R", key: Int(MD_KEY_R), session: session)
                            actionButtons(diameter: button)
                        }
                        .placed(.buttons, "ds-panels", layout: controlLayout, area: size)
                        .frame(width: side)
                    }
                }
                Spacer(minLength: 2)
                MenuButtons(session: session, selectKey: Int(MD_KEY_SELECT), startKey: Int(MD_KEY_START))
                    .placed(.menu, "ds-panels", layout: controlLayout, area: size)
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
            DSScreen(session: session, which: swapScreens ? .bottom : .top)
                .overlay(AVDisplayFilter())
                .overlay {
                    if swapScreens { dsTouchOverlay(inset: 0) }
                }
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
                HStack(spacing: 6) {
                    menuButton
                    TimeControlButtons(session: session)
                    Spacer()
                }
                .padding(.leading, 12)
                .zIndex(2) // Keep the menu above the controls: a big or moved D-pad must never cover it.
                ShoulderButton(label: "L", key: Int(MD_KEY_L), session: session)
                Spacer(minLength: 0)
                directionPad(size: pad)
                    .placed(.dpad, "ds-landscape", layout: controlLayout, area: size)
                Spacer(minLength: 0)
                PillButton(label: "SELECT", key: Int(MD_KEY_SELECT), session: session)
                    .placed(.select, "ds-landscape", layout: controlLayout, area: size)
            }
            .frame(width: side)
            VStack(spacing: 6) {
                swappedUpperLandscape(width: screenWidth)
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
                actionButtons(diameter: button)
                    .placed(.buttons, "ds-landscape", layout: controlLayout, area: size)
                Spacer(minLength: 0)
                PillButton(label: "START", key: Int(MD_KEY_START), session: session)
                    .placed(.start, "ds-landscape", layout: controlLayout, area: size)
            }
            .frame(width: side)
        }
        .padding(.vertical, 6)
    }

    private func directionPad(size: CGFloat) -> some View {
        DPad(session: session)
            .frame(width: size, height: size)
            .scaleEffect(tuning.size)
            .opacity(tuning.opacity)
            .offset(y: tuning.directionOffset)
    }

    private func actionButtons(diameter: CGFloat) -> some View {
        DiamondButtons(session: session, diameter: diameter)
            .scaleEffect(tuning.size)
            .opacity(tuning.opacity)
            .offset(y: tuning.actionOffset)
    }

    private func swappedUpperLandscape(width: CGFloat) -> some View {
        screen(swapScreens ? .bottom : .top, width: width)
            .overlay {
                if swapScreens { dsTouchOverlay(inset: 4) }
            }
    }

    private func dsTouchOverlay(inset: CGFloat) -> some View {
        TouchSurface(label: "Touch screen") { point, bounds in
            session.setTouch(point.map { p in
                let width = max(bounds.width - inset * 2, 1)
                let height = max(bounds.height - inset * 2, 1)
                return CGPoint(x: (p.x - inset) / width * 256,
                               y: (p.y - inset) / height * 192)
            })
        }
    }

    // MARK: Pieces

    /// A DS screen with a slim bezel. `width` is the picture; the bezel adds 8 points.
    private func screen(_ which: DSScreen.Which, width: CGFloat) -> some View {
        DSScreen(session: session, which: which)
            .overlay(AVDisplayFilter())
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
        screen(swapScreens ? .top : .bottom, width: width)
            .overlay {
                if !swapScreens { dsTouchOverlay(inset: 4) }
            }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            menuButton
            TimeControlButtons(session: session)
            Spacer(minLength: 0)
            Text(session.game.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            LiveBadge { showingLive = true }
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
