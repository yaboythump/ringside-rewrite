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

    private func portraitLayout(_ size: CGSize) -> some View {
        let screenWidth = min(size.width - 56, size.height * 0.40 * 10 / 9)
        let button = min(size.width * 0.19, 78)
        return VStack(spacing: 0) {
            topBar
            screen(width: screenWidth)
                .padding(.top, 4)
            deckDivider.padding(.top, 16)
            Spacer(minLength: 10)
            HStack(alignment: .center) {
                DPad(session: session)
                    .frame(width: min(size.width * 0.42, 170), height: min(size.width * 0.42, 170))
                Spacer()
                FaceButtons(session: session, diameter: button)
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 22)
            Spacer(minLength: 10)
            MenuButtons(session: session)
            consoleFooter.padding(.top, 12).padding(.bottom, 12)
        }
    }

    private func tabletopLayout(_ size: CGSize) -> some View {
        let half = size.height / 2
        let screenHeight = max(60, half - 106)
        let button = min(half * 0.3, 84)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                screen(width: screenHeight * 10 / 9)
                Spacer(minLength: 0)
            }
            .frame(height: half)
            HStack(alignment: .center) {
                DPad(session: session)
                    .frame(width: half * 0.62, height: half * 0.62)
                Spacer()
                MenuButtons(session: session)
                Spacer()
                FaceButtons(session: session, diameter: button)
            }
            .padding(.horizontal, 48)
            .frame(height: half)
        }
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let screenHeight = max(60, size.height - 82)
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

    private func screen(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 5)
                Text("RETRO DUO").tracking(2)
                Spacer()
                Text("PIXEL ENGINE").tracking(1)
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
            PixelScreen(session: session)
                .aspectRatio(10 / 9, contentMode: .fit)
                .frame(width: max(width, 80))
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black, lineWidth: 3))
            HStack {
                Text("CTINTERACTIVE").tracking(2)
                Spacer()
                Text(session.game.isColor ? "COLOR / 60" : "CLASSIC / 60")
            }
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.accent.opacity(0.6))
        }
        .padding(12)
        .frame(width: max(width, 80) + 24)
        .background(RoundedRectangle(cornerRadius: 19).fill(Theme.bezel.gradient))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.02), Theme.accent.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 15, y: 9)
        .accessibilityLabel("Game screen")
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            menuButton
            VStack(alignment: .leading, spacing: 3) {
                Text("RETRO DUO").font(.system(size: 14, weight: .black, design: .rounded)).tracking(2)
                    .foregroundStyle(Theme.accent)
                Text(session.game.name).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { session.toggleMute() } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(session.isMuted ? .white.opacity(0.4) : Theme.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(session.isMuted ? "Turn sound on" : "Mute sound")
        }
        .padding(.horizontal, 14).frame(height: 56)
    }

    private var menuButton: some View {
        Button { showingMenu = true } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.08)))
        }
        .accessibilityLabel("Game menu")
    }

    private var deckDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            Text("CONTROL DECK").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(3)
                .fixedSize().foregroundStyle(.white.opacity(0.3))
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }.padding(.horizontal, 24)
    }

    private var consoleFooter: some View {
        HStack {
            Image(systemName: "plus.circle").foregroundStyle(.white.opacity(0.2))
            Spacer()
            Text("CT / HANDHELD SYSTEM").font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(2)
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<5) { _ in Capsule().fill(.black.opacity(0.5)).frame(width: 3, height: 17) }
            }.rotationEffect(.degrees(-20))
        }.padding(.horizontal, 26)
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
