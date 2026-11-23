import SwiftUI

@main
struct RetroDuoApp: App {
    @StateObject private var library = GameLibrary()
    @AppStorage("avydrix.skin") private var skinName = "obsidian"
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
                .tint(AVConsoleSkin.selected(skinName).accent)
                .onOpenURL { url in
                    if url.scheme == "avydrix" {
                        // From the widget: skip the boot sequence and open the game.
                        showingBoot = false
                        if url.host == "play",
                           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                               .queryItems?.first(where: { $0.name == "id" })?.value {
                            library.requestedGameID = id
                        }
                    } else {
                        library.importFiles([url])
                    }
                }
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
    static let buttonX = Color(red: 0.42, green: 0.38, blue: 0.80)
    static let buttonY = Color(red: 0.30, green: 0.62, blue: 0.36)
    static let pad = Color(red: 0.24, green: 0.29, blue: 0.36)
}

/// Brushed midnight-metal shell with restrained technical detailing.
struct ConsoleBackdrop: View {
    @AppStorage("avydrix.skin") private var skinName = "obsidian"

    var body: some View {
        let skin = AVConsoleSkin.selected(skinName)
        ZStack {
            LinearGradient(colors: [skin.secondary.opacity(0.5), skin.shell, skin.accent.opacity(0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                var lines = Path()
                for y in stride(from: 0.0, to: size.height, by: 4) {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(skin.accent.opacity(0.024)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
