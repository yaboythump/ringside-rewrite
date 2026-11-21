import SwiftUI

@main
struct RetroDuoApp: App {
    @StateObject private var library = GameLibrary()
    /// Shows the AVYDRIX console boot sequence on a normal app launch.
    /// Skip when launched by simulator snapshots or automated UI tests.
    @State private var showingBoot = !ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-RetroDuo") }

    var body: some Scene {
        WindowGroup {
            ZStack {
                LibraryView()
                if showingBoot {
                    AvydrixBootView { showingBoot = false }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in library.importFiles([url]) }
        }
    }
}

enum Theme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.06)
    static let panel = Color(red: 0.09, green: 0.12, blue: 0.18)
    static let bezel = Color(red: 0.02, green: 0.02, blue: 0.05)
    static let accent = Color(red: 1.0, green: 0.78, blue: 0.22)
    static let buttonA = Color(red: 0.82, green: 0.55, blue: 0.18)
    static let buttonB = Color(red: 0.12, green: 0.63, blue: 0.76)
    static let pad = Color(red: 0.24, green: 0.29, blue: 0.36)
}

/// Brushed midnight-metal shell with restrained technical detailing.
struct ConsoleBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.15, green: 0.19, blue: 0.26), Theme.background, Color(red: 0.10, green: 0.13, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                var lines = Path()
                for y in stride(from: 0.0, to: size.height, by: 4) {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(.white.opacity(0.018)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
