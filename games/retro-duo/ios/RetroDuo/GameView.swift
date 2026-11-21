import SwiftUI

/// The Duo play screen dedicates the full upper panel to gameplay.
/// The lower panel holds the controls, game menu and sound toggle.
/// Side controls and original picture proportions remain available in the menu.
struct GameView: View {
    @StateObject private var session: EmulatorSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var hinge = HingeState()
    @State private var showingMenu = false
    @State private var showingOptions = false
    @State private var showingSaves = false
    @StateObject private var tuning: AVControlTuning
    @AppStorage("avydrix.duo.mode") private var duoMode = "auto"
    @AppStorage("avydrix.gba.landscapeControls") private var gbaLandscapeControls = true
    @AppStorage("retroDuoTwoPanels") private var useTwoPanels = true
    @AppStorage("retroDuoOriginalProportions") private var originalProportions = false
    @State private var diagnostics = ""

    init(session: @autoclosure @escaping () -> EmulatorSession) {
        let gameSession = session()
        _session = StateObject(wrappedValue: gameSession)
        _tuning = StateObject(wrappedValue: AVControlTuning(system: gameSession.game.system))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Group {
                if let error = session.errorMessage {
                    errorView(error)
                } else if system == .gameBoyAdvance &&
                            size.width > size.height * 1.15 &&
                            !hinge.isHalfOpen &&
                            duoMode != "stacked" &&
                            gbaLandscapeControls {
                    // Landscape GBA always keeps touch controls on the visible screen.
                    // Preserve explicit tabletop/hinge mode and the existing side-layout opt out.
                    gbaLandscapeLayout(size)
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
        .sheet(isPresented: $showingOptions) {
            AVGameSettings(tuning: tuning)
        }
        .sheet(isPresented: $showingSaves) {
            AVSaveManager(game: session.game, save: { session.saveSlot($0) },
                          load: { session.loadSlot($0) })
        }
        .onChange(of: showingSaves) { _, shown in session.setPaused(shown) }
        .onChange(of: showingOptions) { _, shown in session.setPaused(shown) }
        .confirmationDialog(session.game.name, isPresented: $showingMenu, titleVisibility: .visible) {
            Button(originalProportions ? "Fill entire upper screen" : "Use original screen proportions") {
                originalProportions.toggle()
            }
            Button(useTwoPanels ? "Use side controls in landscape" : "Use two-panel Duo layout") {
                useTwoPanels.toggle()
            }
            Button("Game Settings") { showingOptions = true }
            Button("Visual Save Manager") { showingSaves = true }
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

    // Fill the upper half by default, with optional original picture proportions.
    private func portraitLayout(_ size: CGSize) -> some View {
        let half = size.height / 2
        let pad = min(size.width * 0.40, max(60, half - 100) * 0.65, 170)
        let button = min(size.width * 0.17, pad * 0.46, 76)
        return VStack(spacing: 0) {
            gameplayPanel(width: size.width, height: half)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)
                HStack(alignment: .center) {
                    if tuning.mirrored {
                        actionButtons(diameter: button)
                        Spacer(minLength: 8)
                        directionPad(size: pad)
                    } else {
                        directionPad(size: pad)
                        Spacer(minLength: 8)
                        actionButtons(diameter: button)
                    }
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 4)
                MenuButtons(session: session, keys: system.menuKeys)
                Spacer(minLength: 4)
            }
            .frame(width: size.width, height: half)
        }
    }

    private func tabletopLayout(_ size: CGSize) -> some View {
        let half = size.height / 2
        let pad = min(max(60, half - 70), size.width * 0.25, 160)
        let button = min(pad * 0.46, 76)
        return VStack(spacing: 0) {
            gameplayPanel(width: size.width, height: half)
            VStack(spacing: 0) {
                if system == .snes {
                    // Four full-sized SNES face buttons need room. Put L/R in
                    // the slim top row instead of stacking them above the diamond.
                    HStack(spacing: 4) {
                        ShoulderButton(label: "L", key: PadKey.l, session: session)
                        topBar
                        ShoulderButton(label: "R", key: PadKey.r, session: session)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                } else {
                    topBar
                }
                HStack(alignment: .center) {
                    if tuning.mirrored {
                        actionButtons(diameter: button, showShoulder: system != .snes)
                        Spacer(minLength: 4)
                        MenuButtons(session: session, keys: system.menuKeys)
                        Spacer(minLength: 4)
                        directionPad(size: pad, showShoulder: system != .snes)
                    } else {
                        directionPad(size: pad, showShoulder: system != .snes)
                        Spacer(minLength: 4)
                        MenuButtons(session: session, keys: system.menuKeys)
                        Spacer(minLength: 4)
                        actionButtons(diameter: button, showShoulder: system != .snes)
                    }
                }
                .padding(.horizontal, system == .snes ? 12 : 24)
                .frame(maxHeight: .infinity)
            }
            .padding(.bottom, system == .snes ? 0 : 10)
            .frame(width: size.width, height: half)
        }
    }

    private func gameplayPanel(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            GeometryReader { available in
                let gameWidth = originalProportions ? min(available.size.width, available.size.height / session.aspect) : available.size.width
                let gameHeight = originalProportions ? gameWidth * session.aspect : available.size.height
                PixelScreen(session: session)
                    .overlay(AVDisplayFilter())
                    .frame(width: gameWidth, height: gameHeight)
                    .position(x: available.size.width / 2, y: available.size.height / 2)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upperGamePanel")
        .accessibilityLabel("Game screen")
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let screenHeight = max(60, size.height - 34)
        let side = max(120, (size.width - screenHeight / session.aspect) / 2 - 12)
        let button = min(side * 0.36, 72)
        return HStack(spacing: 0) {
            VStack {
                menuButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                Spacer()
                directionPad(size: min(side * 0.82, 170))
                Spacer()
                if let first = system.menuKeys.first, system.menuKeys.count > 1 {
                    PillButton(label: first.label, key: first.key, session: session)
                }
            }
            .frame(width: side)
            screen(width: screenHeight / session.aspect)
            VStack {
                Spacer()
                actionButtons(diameter: button)
                Spacer()
                if let last = system.menuKeys.last {
                    PillButton(label: last.label, key: last.key, session: session)
                }
            }
            .frame(width: side)
        }
        .padding(.vertical, 10)
    }

    /// GBA landscape is an AVYDRIX handheld shell, not a transparent gamepad
    /// covering the ROM's picture. Gameplay and touch targets never overlap.
    /// User's tabletop/folded layout still uses the existing upper/lower panels.
    private func gbaLandscapeLayout(_ size: CGSize) -> some View {
        let side = min(210, max(108, size.width * 0.175))
        let horizontalInset = min(24, max(12, size.width * 0.018))
        let pictureWidth = max(145, min(
            size.width - 2 * side - 2 * horizontalInset - 32,
            (size.height - 180) / session.aspect - 10
        ))
        let padSize = min(154, max(88, side - 31))
        let faceSize = min(76, max(52, (side - 13) / 2.15))

        return ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.18, blue: 0.31),
                            Color(red: 0.035, green: 0.05, blue: 0.12),
                            Color(red: 0.12, green: 0.075, blue: 0.23)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 26)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .cyan.opacity(0.20), .white.opacity(0.07)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1
                )

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    menuButton
                        .background(.black.opacity(0.27), in: RoundedRectangle(cornerRadius: 11))
                    Spacer(minLength: 4)
                    HStack(spacing: 7) {
                        Circle().fill(Color.cyan).frame(width: 6, height: 6)
                        Text("AVYDRIX  /  GAME BOY ADVANCE")
                            .font(.system(size: size.width < 700 ? 9 : 12,
                                          weight: .heavy, design: .monospaced))
                            .tracking(size.width < 700 ? 0.5 : 1.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    Spacer(minLength: 4)
                    Button { session.toggleMute() } label: {
                        Image(systemName: session.isMuted
                              ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 40)
                            .foregroundStyle(.white.opacity(0.83))
                            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.isMuted ? "Turn sound on" : "Mute sound")
                }
                .frame(height: 48)

                HStack(alignment: .center, spacing: 10) {
                    gbaShellControls(
                        side: side,
                        label: "D-PAD",
                        shoulder: "L",
                        shoulderKey: PadKey.l,
                        isDirection: !tuning.mirrored,
                        padSize: padSize,
                        faceSize: faceSize
                    )

                    VStack(spacing: 7) {
                        // GBA picture has its own bezel and exclusive frame.
                        // Buttons are siblings outside this region, never overlays.
                        screen(width: pictureWidth)
                            .accessibilityIdentifier("gbaLandscapeGameScreen")
                        MenuButtons(session: session, keys: system.menuKeys)
                            .scaleEffect(0.86)
                            .frame(height: 45)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .contain)

                    gbaShellControls(
                        side: side,
                        label: "A / B",
                        shoulder: "R",
                        shoulderKey: PadKey.r,
                        isDirection: tuning.mirrored,
                        padSize: padSize,
                        faceSize: faceSize
                    )
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Text("CTINTERACTIVE")
                    Spacer()
                    Text("PLAY WITHOUT LIMITS")
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.40))
                .frame(height: 22)
                .padding(.horizontal, 7)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 10)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gba-landscape-with-controls")
    }

    private func gbaShellControls(
        side: CGFloat,
        label: String,
        shoulder: String,
        shoulderKey: Int,
        isDirection: Bool,
        padSize: CGFloat,
        faceSize: CGFloat
    ) -> some View {
        VStack(spacing: 8) {
            ShoulderButton(label: shoulder, key: shoulderKey, session: session)
                .padding(.top, 9)
            Spacer(minLength: 6)
            if isDirection {
                directionPad(size: padSize, showShoulder: false)
            } else {
                actionButtons(diameter: faceSize, showShoulder: false)
            }
            Spacer(minLength: 6)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.48))
                .padding(.bottom, 10)
        }
        .frame(width: side)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.19))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var system: GameSystem { session.game.system }

    /// The D-pad, with the L shoulder button above it on systems that have one.
    private func directionPad(size: CGFloat, showShoulder: Bool = true) -> some View {
        let withShoulder = system.hasShoulders && showShoulder
        return VStack(spacing: 6) {
            if withShoulder {
                ShoulderButton(label: "L", key: PadKey.l, session: session)
            }
            DPad(session: session)
                .frame(width: withShoulder ? size - 34 : size, height: withShoulder ? size - 34 : size)
        }
        .scaleEffect(tuning.size)
        .opacity(tuning.opacity)
        .offset(y: tuning.directionOffset)
    }

    /// The face buttons, with the R shoulder button above them on systems that have one.
    private func actionButtons(diameter: CGFloat, showShoulder: Bool = true) -> some View {
        let faces = system.faceKeys
        let withShoulder = system.hasShoulders && showShoulder
        // Before: SNES four-button diamond was reduced to 62%, then again to
        // 85% due to shoulder controls. A 52pt control became just 27pt.
        // Keep SNES touch targets 44pt minimum, with larger portrait targets.
        let size: CGFloat = system == .snes
            ? (showShoulder ? min(58, max(48, diameter)) : min(50, max(44, diameter)))
            : (faces.count >= 4 ? diameter * 0.62 : faces.count == 3 ? diameter * 0.78 : diameter)
        return VStack(spacing: 6) {
            if withShoulder {
                ShoulderButton(label: "R", key: PadKey.r, session: session)
            }
            FaceButtons(session: session, diameter: system == .snes ? size : (withShoulder ? size * 0.85 : size), keys: faces)
        }
        .scaleEffect(tuning.size)
        .opacity(tuning.opacity)
        .offset(y: tuning.actionOffset)
    }

    // MARK: Pieces

    /// The game picture with a slim bezel. `width` is the picture itself; the bezel adds 10 points.
    private func screen(width: CGFloat) -> some View {
        let width = max(width, 80)
        return PixelScreen(session: session)
            .overlay(AVDisplayFilter())
            .frame(width: width, height: width * session.aspect)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bezel.gradient))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02), Theme.accent.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
            .accessibilityLabel("Game screen")
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
            Button { session.toggleMute() } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(session.isMuted ? .white.opacity(0.4) : Theme.accent)
                    .frame(width: 44, height: 40)
            }
            .accessibilityLabel(session.isMuted ? "Turn sound on" : "Mute sound")
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
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
