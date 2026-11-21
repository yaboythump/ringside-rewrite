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
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) { toastView }
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
        let screenWidth = min(size.width - 28, size.height * 0.46 * 10 / 9)
        let button = min(size.width * 0.19, 78)
        return VStack(spacing: 0) {
            topBar
            screen(width: screenWidth)
                .padding(.top, 4)
            Spacer(minLength: 12)
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
                .padding(.bottom, 18)
        }
    }

    private func tabletopLayout(_ size: CGSize) -> some View {
        let half = size.height / 2
        let screenHeight = half - 56
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
        let screenHeight = size.height - 36
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
        PixelScreen(session: session)
            .aspectRatio(10 / 9, contentMode: .fit)
            .frame(width: max(width, 80))
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.bezel)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            )
            .accessibilityLabel("Game screen")
    }

    private var topBar: some View {
        HStack {
            menuButton
            Spacer()
            Text(session.game.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }

    private var menuButton: some View {
        Button {
            showingMenu = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)
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
