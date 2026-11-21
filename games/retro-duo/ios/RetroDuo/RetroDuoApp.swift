import SwiftUI

@main
struct RetroDuoApp: App {
    @StateObject private var library = GameLibrary()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in library.importFiles([url]) }
        }
    }
}

enum Theme {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.11)
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.20)
    static let bezel = Color(red: 0.02, green: 0.02, blue: 0.05)
    static let accent = Color(red: 1.0, green: 0.78, blue: 0.22)
    static let buttonA = Color(red: 0.93, green: 0.27, blue: 0.40)
    static let buttonB = Color(red: 0.36, green: 0.42, blue: 0.95)
    static let pad = Color(red: 0.20, green: 0.23, blue: 0.33)
}
