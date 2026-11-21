import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: BookLibrary
    @EnvironmentObject private var settings: ReaderSettings
    @State private var importing = false
    @State private var reading: OpenBook?
    @State private var bookToDelete: Book?
    @State private var showingAbout = false
    @State private var startedDemo = false
    @State private var searchText = ""
    @State private var shelfFilter: ShelfFilter = .all
    @State private var shelfSort: ShelfSort = .recent

    private var readingCount: Int {
        library.books.filter {
            let progress = library.position(for: $0)?.progress ?? 0
            return progress > 0 && progress < 0.995
        }.count
    }

    private var finishedCount: Int {
        library.books.filter { (library.position(for: $0)?.progress ?? 0) >= 0.995 }.count
    }

    private var visibleBooks: [Book] {
        let found = library.sortedBooks.filter { book in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesText = query.isEmpty || book.title.localizedStandardContains(query) ||
                book.author.localizedStandardContains(query)
            let progress = library.position(for: book)?.progress ?? 0
            let matchesFilter: Bool
            switch shelfFilter {
            case .all: matchesFilter = true
            case .reading: matchesFilter = progress > 0 && progress < 0.995
            case .finished: matchesFilter = progress >= 0.995
            }
            return matchesText && matchesFilter
        }
        switch shelfSort {
        case .recent: return found
        case .title: return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: return found.sorted {
            ($0.author.isEmpty ? $0.title : $0.author)
                .localizedStandardCompare($1.author.isEmpty ? $1.title : $1.author) == .orderedAscending
        }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 190), spacing: 18, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    masthead
                    intro
                    collectionStats
                    if let book = library.sortedBooks.first {
                        ContinueCard(book: book, progress: library.position(for: book)?.progress ?? 0) {
                            open(book)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("YOUR SHELF")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(2.6)
                            .foregroundStyle(Palette.softWhite)
                        Spacer()
                        Text("\(visibleBooks.count) \(visibleBooks.count == 1 ? "TITLE" : "TITLES")")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(Palette.muted)
                    }
                    shelfSearch
                    shelfControls
                    if library.books.isEmpty && !library.isWorking {
                        emptyState
                    } else if visibleBooks.isEmpty && !library.isWorking {
                        noMatches
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            ForEach(visibleBooks) { book in
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
                            ProgressView().tint(Palette.accent)
                            Text("Preparing your collection…")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                        Text("QUILUNE  •  STORIES, BEAUTIFULLY UNFOLDED.")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Palette.muted.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 23)
                .padding(.top, 20)
            }
            .background(libraryBackdrop)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await library.refresh() }
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.epub], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.importFiles(urls) }
        }
        .fullScreenCover(item: $reading) { request in
            ReaderView(book: request.book, library: library, startAt: request.chapter)
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
        .alert("Quilune", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.message ?? "")
        }
        .onChange(of: library.books, initial: true) { _, books in startDemoIfAsked(books) }
    }

    private var libraryBackdrop: some View {
        ZStack {
            Palette.libraryBackground
            RadialGradient(colors: [Color(hex: "#35305B").opacity(0.72), .clear],
                           center: .topTrailing, startRadius: 5, endRadius: 430)
            RadialGradient(colors: [Color(hex: "#104553").opacity(0.31), .clear],
                           center: .bottomLeading, startRadius: 10, endRadius: 490)
        }
        .ignoresSafeArea()
    }

    private var masthead: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#352C5C"), Color(hex: "#142B43")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Q")
                    .font(.system(size: 31, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.softWhite)
                    .offset(x: -1, y: -2)
                Capsule().fill(Palette.accentBlue)
                    .frame(width: 16, height: 3)
                    .rotationEffect(.degrees(-35))
                    .offset(x: 11, y: 12)
            }
            .frame(width: 48, height: 48)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text("QUILUNE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Palette.softWhite)
                Text("BY CTINTERACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Palette.accent)
            }

            Spacer(minLength: 2)

            Button { showingAbout = true } label: {
                Image(systemName: "info")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.softWhite)
                    .frame(width: 43, height: 43)
                    .background(Palette.card, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.1)))
            }
            .accessibilityLabel("About Quilune")

            Button { importing = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: "#090D17"))
                    .frame(width: 43, height: 43)
                    .background(Palette.accent, in: Circle())
            }
            .accessibilityLabel("Add EPUB books")
        }
        .buttonStyle(.plain)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("YOUR PERSONAL LIBRARY")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(Palette.accentBlue)
            Text("Lose yourself in\na good story.")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .tracking(-0.9)
                .foregroundStyle(Palette.softWhite)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your private library, extraordinary when unfolded.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
        }
        .padding(.top, 12)
    }

    private var collectionStats: some View {
        HStack(spacing: 0) {
            shelfStat(value: library.books.count, title: "IN LIBRARY")
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 38)
            shelfStat(value: readingCount, title: "READING")
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 38)
            shelfStat(value: finishedCount, title: "FINISHED")
        }
        .padding(.vertical, 16)
        .background(Palette.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.11)))
    }

    private func shelfStat(value: Int, title: String) -> some View {
        VStack(spacing: 5) {
            Text("\(value)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.softWhite)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var shelfSearch: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.accentBlue)
            TextField("Search titles or authors", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(Palette.softWhite)
                .tint(Palette.accent)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.11)))
    }

    private var shelfControls: some View {
        HStack(spacing: 7) {
            ForEach(ShelfFilter.allCases) { filter in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { shelfFilter = filter }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(shelfFilter == filter ? Color(hex: "#0D1220") : Palette.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(shelfFilter == filter ? Palette.accent : Palette.card, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(shelfFilter == filter ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Sort books", selection: $shelfSort) {
                    ForEach(ShelfSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.softWhite)
                    .frame(width: 36, height: 34)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
            }
            .accessibilityLabel("Sort books")
        }
        .padding(.top, -11)
    }

    private var noMatches: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 31))
                .foregroundStyle(Palette.accent)
            Text("Nothing on this shelf yet")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.softWhite)
            Text("Try another search or show all your books.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button("Show all books") {
                searchText = ""
                shelfFilter = .all
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.accentBlue)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Palette.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))
    }

    private func open(_ book: Book) {
        reading = OpenBook(book: book, chapter: nil)
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
        reading = OpenBook(book: book, chapter: book.manifest.spine.firstIndex { $0.path.contains("chapter-1.") })
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 42))
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 4)
            Text("A library of possibilities")
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.softWhite)
            Text("Start with an EPUB. Quilune keeps your books and progress on your iPhone.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.muted)
            Button { importing = true } label: {
                Label("Add your first book", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#101225"))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Palette.accent, in: Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 26)
        .padding(.vertical, 48)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.09)))
    }
}

private enum ShelfFilter: String, CaseIterable, Identifiable {
    case all, reading, finished
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .reading: return "Reading"
        case .finished: return "Finished"
        }
    }
}

private enum ShelfSort: String, CaseIterable, Identifiable {
    case recent, title, author
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "Recently opened"
        case .title: return "Title A to Z"
        case .author: return "Author A to Z"
        }
    }
}

struct OpenBook: Identifiable {
    let book: Book
    let chapter: Int?
    var id: String { book.id }
}

private struct ContinueCard: View {
    let book: Book
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                CoverView(book: book)
                    .frame(width: 103, height: 154)
                    .rotationEffect(.degrees(-3))
                    .shadow(color: .black.opacity(0.4), radius: 18, x: 4, y: 8)

                VStack(alignment: .leading, spacing: 10) {
                    Label(progress > 0 ? "CONTINUE READING" : "FEATURED BOOK", systemImage: "sparkle")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Palette.accentBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(book.title)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.softWhite)
                        .lineLimit(3)

                    Text(book.author.isEmpty ? "Your next escape" : book.author)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)

                    ProgressView(value: max(0, min(progress, 1)))
                        .tint(Palette.accent)
                    HStack {
                        Text("\(Int(progress * 100))% complete")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#282347"), Color(hex: "#131D32")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.13)))
            .shadow(color: Color(hex: "#161332").opacity(0.42), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(progress > 0 ? "Continue" : "Start") reading \(book.title)")
    }
}

private struct BookCell: View {
    let book: Book
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(book: book)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if let progress, progress >= 0.995 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#0E1621"))
                            .frame(width: 25, height: 25)
                            .background(Palette.accentBlue, in: Circle())
                            .padding(8)
                    }
                }
            Text(book.title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.softWhite)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(book.author.isEmpty ? "Unknown author" : book.author)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            if let progress, progress > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(Palette.accent)
                            .frame(width: proxy.size.width * max(0, min(progress, 1)))
                    }
                }
                .frame(height: 3)
                Text("\(Int(progress * 100))% READ")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Palette.accent)
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
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.30), .white.opacity(0.12), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 12)
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.13)))
        .shadow(color: .black.opacity(0.31), radius: 10, x: 1, y: 7)
        .task(id: book.coverURL) {
            if let url = book.coverURL { image = await CoverCache.shared.image(for: url) }
        }
    }
}

enum Palette {
    static let accent = Color(hex: "#C3ACFF")
    static let accentBlue = Color(hex: "#7CE4F2")
    static let softWhite = Color(hex: "#F3F0FB")
    static let muted = Color(hex: "#A8ACC0")
    static let libraryBackground = Color(hex: "#090E1B")
    static let card = Color(hex: "#192035")

    static func cloth(for title: String) -> Color {
        let colors = ["#593C71", "#2D6870", "#34496B", "#69523E", "#563A63", "#315766"]
        let index = title.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 } % colors.count
        return Color(hex: colors[index])
    }
}
