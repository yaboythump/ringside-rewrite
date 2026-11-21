import SwiftUI
import UIKit

@main
struct BookDuoApp: App {
    @StateObject private var library = BookLibrary()
    @StateObject private var settings = ReaderSettings()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(settings)
                .onOpenURL { url in library.importFiles([url]) }
                .task { await DebugSnapshot.runIfAsked() }
        }
    }
}

/// `-BookDuoSnapshot` saves pictures of the app into its tmp folder, for checking
/// builds on simulators that can't take screenshots themselves.
enum DebugSnapshot {
    @MainActor
    static func runIfAsked() async {
        guard ProcessInfo.processInfo.arguments.contains("-BookDuoSnapshot") else { return }
        for (index, delay) in [7.0, 5.0].enumerated() {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            save(name: "snapshot-\(index + 1)")
        }
    }

    @MainActor
    static func save(name: String) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            for window in windows.sorted(by: { $0.windowLevel < $1.windowLevel }) where !window.isHidden {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try? image.pngData()?.write(to: url)
        print("BookDuo snapshot \(name) \(window.bounds.size)")
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quilune").font(.system(size: 28, weight: .bold, design: .serif))
                        Text("A beautiful, private EPUB library from CTInteractive, made for iPhone Duo. Unfold it and the book opens into a two-page spread, with the fold as the spine.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Reading") {
                    Label("Tap the right side or swipe left to turn the page", systemImage: "hand.tap")
                    Label("Tap the middle for contents, appearance and progress", systemImage: "list.bullet")
                    Label("Choose Focus in the controls for uninterrupted full-screen reading", systemImage: "arrow.up.left.and.arrow.down.right")
                    Label("Touch and hold a word to look it up or highlight it to copy", systemImage: "character.book.closed")
                }
                Section("Personal shelves & reading rhythm") {
                    Label("Create named shelves and long-press any book to organize it", systemImage: "books.vertical")
                    Label("Turn pages on different days to grow your reading streak", systemImage: "flame")
                }
                Section("Adding books") {
                    Label("Tap + in the library, or share an EPUB to Quilune", systemImage: "plus")
                    Label("Or drop .epub files into Files › On My iPhone › Quilune (formerly Book Duo)", systemImage: "folder")
                    Text("Books bought from stores with DRM can't be opened. Free, DRM-free books are available from Standard Ebooks and Project Gutenberg.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Included book") {
                    Text("Alice’s Adventures in Wonderland by Lewis Carroll, illustrated by John Tenniel, from Standard Ebooks. Public domain in the United States; Standard Ebooks’ edition is dedicated to the public domain under CC0 1.0.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
