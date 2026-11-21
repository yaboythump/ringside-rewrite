import SwiftUI

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
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Book Duo").font(.system(size: 28, weight: .bold, design: .serif))
                        Text("An EPUB reader made for iPhone Duo. Unfold it and the book opens into a two-page spread, with the fold as the spine.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Reading") {
                    Label("Tap the right side or swipe left to turn the page", systemImage: "hand.tap")
                    Label("Tap the middle for contents, appearance and progress", systemImage: "list.bullet")
                    Label("Touch and hold a word to look it up or highlight it to copy", systemImage: "character.book.closed")
                }
                Section("Adding books") {
                    Label("Tap + in the library, or share an EPUB to Book Duo", systemImage: "plus")
                    Label("Or drop .epub files into Files › On My iPhone › Book Duo", systemImage: "folder")
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
