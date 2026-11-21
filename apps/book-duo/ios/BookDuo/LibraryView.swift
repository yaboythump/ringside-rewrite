import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var settings: ReaderSettings
    @State private var importing = false
    @State private var reading: Book?
    @State private var demoChapter: Int?
    @State private var bookToDelete: Book?
    @State private var showingAbout = false
    @State private var startedDemo = false

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 150), spacing: 18, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let book = library.sortedBooks.first, let position = library.position(for: book) {
                        ContinueCard(book: book, progress: position.progress) { open(book) }
                    }
                    if library.books.isEmpty && !library.isWorking {
                        emptyState
                    } else {
                        Text("Library")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(library.sortedBooks) { book in
                                Button { open(book) } label: {
                                    BookCell(book: book, progress: library.position(for: book)?.progress)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { bookToDelete = book } label: {
                                        Label("Remove from Library", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    if library.isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing books…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .background(Palette.libraryBackground.ignoresSafeArea())
            .navigationTitle("Book Duo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About Book Duo")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add books")
                }
            }
            .refreshable { await library.refresh() }
        }
        .tint(Palette.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.epub], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.importFiles(urls) }
        }
        .fullScreenCover(item: $reading) { book in
            ReaderView(book: book, library: library, startAt: demoChapter)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .confirmationDialog("Remove \(bookToDelete?.title ?? "this book")?", isPresented: Binding(
            get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let book = bookToDelete { library.delete(book) }
                bookToDelete = nil
            }
        } message: {
            Text("The book file is deleted from Book Duo's folder.")
        }
        .alert("Book Duo", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.message ?? "")
        }
        .onChange(of: library.books, initial: true) { _, books in startDemoIfAsked(books) }
    }

    private func open(_ book: Book) {
        demoChapter = nil
        reading = book
    }

    /// `-BookDuoDemo` opens the sample at chapter one, for simulator previews.
    private func startDemoIfAsked(_ books: [Book]) {
        guard !startedDemo, ProcessInfo.processInfo.arguments.contains("-BookDuoDemo"),
              let book = books.first(where: { $0.id == BookLibrary.sampleFileName }) ?? books.first else { return }
        startedDemo = true
        if ProcessInfo.processInfo.arguments.contains("-BookDuoLandscape"),
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
        demoChapter = book.manifest.spine.firstIndex { $0.path.contains("chapter-1.") }
        reading = book
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical").font(.system(size: 44)).foregroundStyle(Palette.accent)
            Text("No books yet").font(.system(size: 20, weight: .semibold, design: .serif))
            Text("Tap + to add EPUB books, or drop them into Files › On My iPhone › Book Duo.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add Books") { importing = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

private struct ContinueCard: View {
    let book: Book
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                CoverView(book: book).frame(width: 74, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE READING").font(.system(size: 11, weight: .bold)).kerning(1.2)
                        .foregroundStyle(Palette.accent)
                    Text(book.title).font(.system(size: 19, weight: .semibold, design: .serif)).lineLimit(2)
                    if !book.author.isEmpty {
                        Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ProgressView(value: progress).tint(Palette.accent)
                    Text("\(Int(progress * 100))% read").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct BookCell: View {
    let book: Book
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book)
                .aspectRatio(2 / 3, contentMode: .fit)
            Text(book.title).font(.system(size: 14, weight: .semibold, design: .serif)).lineLimit(2)
            HStack {
                Text(book.author.isEmpty ? " " : book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                if let progress, progress > 0 {
                    Text(progress >= 0.995 ? "Done" : "\(Int(progress * 100))%")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Palette.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The book's own cover, or a plain cloth cover with its title when it has none.
struct CoverView: View {
    let book: Book
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Palette.cloth(for: book.title), Palette.cloth(for: book.title).opacity(0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Text(book.title).font(.system(size: 14, weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center).lineLimit(5)
                    Text(book.author).font(.system(size: 10)).lineLimit(2)
                }
                .foregroundStyle(Color(hex: "#F4ECD8"))
                .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)
        .task(id: book.coverURL) {
            if let url = book.coverURL { image = await CoverCache.shared.image(for: url) }
        }
    }
}

enum Palette {
    static let accent = Color(hex: "#9A5B1E")
    static let libraryBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.075, blue: 0.065, alpha: 1)
            : UIColor(red: 0.965, green: 0.945, blue: 0.905, alpha: 1)
    })
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 1)
            : UIColor(red: 1, green: 0.99, blue: 0.975, alpha: 1)
    })

    static func cloth(for title: String) -> Color {
        let colors = ["#6B2E2E", "#2E4A3F", "#2F3E5C", "#5B4A2E", "#4A2F5C", "#2E5559"]
        let index = title.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 } % colors.count
        return Color(hex: colors[index])
    }
}
