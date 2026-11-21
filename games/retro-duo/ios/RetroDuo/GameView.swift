import SwiftUI

/// The play screen. Three layouts:
/// - Portrait (outer screen or unfolded): picture on top, controls below, like the original handheld.
/// - iPhone Duo half-folded with the fold across the middle: picture on the top half,
///   controls on the bottom half, so the fold sits between them.
/// - Landscape flat: picture in the middle, D-pad on the left, buttons on the right.
struct GameView: View {
    @StateObject private var session: EmulatorSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var hinge = HingeState()
    @State private var showingMenu = false
    @State private var diagnostics = ""

    init(session: @autoclosure @escaping () -> EmulatorSession) {
        _session = StateObject(wrappedValue: session())
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Group {
                if let error = session.errorMessage {
                    errorView(error)
                } else if hinge.isHalfOpen && size.width > size.height {
                    tabletopLayout(size)
                } else if size.width > size.height * 1.15 {
                    landscapeLayout(size)
                } else {
                    portraitLayout(size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
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

    // The unfolded Duo dedicates its entire upper half to the game, not a small
    // simulated handheld bezel. The native 160:144 image is scaled to fit without
    // cropping or distorting pixels; only unavoidable aspect-ratio bars remain.
    private func portraitLayout(_ size: CGSize) -> some View {
        let half = size.height / 2
        let pad = min(size.width * 0.40, half * 0.55, 170)
        let button = min(size.width * 0.17, pad * 0.46, 76)
        return VStack(spacing: 0) {
            gameplayPanel(width: size.width, height: half)
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    DPad(session: session).frame(width: pad, height: pad)
                    Spacer(minLength: 8)
                    FaceButtons(session: session, diameter: button)
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 4)
                MenuButtons(session: session)
                Spacer(minLength: 4)
            }
            .frame(width: size.width, height: half)
        }
    }

    private func tabletopLayout(_ size: CGSize) -> some View {
        let half = size.height / 2
        let pad = min(half * 0.62, size.width * 0.26, 170)
        let button = min(half * 0.30, 84)
        return VStack(spacing: 0) {
            gameplayPanel(width: size.width, height: half)
            HStack(alignment: .center) {
                DPad(session: session).frame(width: pad, height: pad)
                Spacer(minLength: 4)
                MenuButtons(session: session)
                Spacer(minLength: 4)
                FaceButtons(session: session, diameter: button)
            }
            .padding(.horizontal, 24)
            .frame(width: size.width, height: half)
        }
    }

    private func gameplayPanel(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            GeometryReader { available in
                let gameWidth = min(available.size.width, available.size.height * 10 / 9)
                PixelScreen(session: session)
                    .frame(width: gameWidth, height: gameWidth * 0.9)
                    .position(x: available.size.width / 2, y: available.size.height / 2)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(alignment: .topLeading) {
            menuButton.padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Button { session.toggleMute() } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 40)
            }
            .accessibilityLabel(session.isMuted ? "Turn sound on" : "Mute sound")
            .padding(8)
        }
        .accessibilityLabel("Game screen")
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let screenHeight = max(60, size.height - 34)
        let side = max(120, (size.width - screenHeight * 10 / 9) / 2 - 12)
        let button = min(side * 0.36, 72)
        return HStack(spacing: 0) {
            VStack {
                menuButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                Spacer()
                DPad(session: session)
                    .frame(width: min(side * 0.82, 170), height: min(side * 0.82, 170))
                Spacer()
                PillButton(label: "SELECT", key: Int(RD_KEY_SELECT), session: session)
            }
            .frame(width: side)
            screen(width: screenHeight * 10 / 9)
            VStack {
                Spacer()
                FaceButtons(session: session, diameter: button)
                Spacer()
                PillButton(label: "START", key: Int(RD_KEY_START), session: session)
            }
            .frame(width: side)
        }
        .padding(.vertical, 10)
    }

    // MARK: Pieces

    /// The game picture with a slim bezel. `width` is the picture itself; the bezel adds 10 points.
    private func screen(width: CGFloat) -> some View {
        let width = max(width, 80)
        return PixelScreen(session: session)
            .frame(width: width, height: width * 0.9)
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
