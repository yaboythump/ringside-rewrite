import SwiftUI
import UIKit

/// Where the pages go. On iPhone Duo the two pages sit either side of the fold;
/// on a wide screen without a fold they share it with a small gutter.
struct PaneLayout: Equatable {
    enum Kind: Equatable { case single, sideBySide, stacked }

    var kind: Kind
    var frames: [CGRect]
    var fold: CGRect?

    var paneCount: Int { frames.count }

    static func make(size: CGSize, fold: CGRect?, mode: SpreadMode) -> PaneLayout {
        let full = CGRect(origin: .zero, size: size)
        guard mode == .auto, size.width > 200, size.height > 200 else {
            return PaneLayout(kind: .single, frames: [full], fold: nil)
        }
        if let fold, full.intersects(fold), fold.width < size.width, fold.height < size.height {
            if fold.height >= fold.width {
                // Fold runs top to bottom: a left page and a right page, like an open book.
                let width = min(fold.minX, size.width - fold.maxX)
                if width > 180 {
                    return PaneLayout(kind: .sideBySide,
                                      frames: [CGRect(x: fold.minX - width, y: 0, width: width, height: size.height),
                                               CGRect(x: fold.maxX, y: 0, width: width, height: size.height)],
                                      fold: fold)
                }
            } else {
                // Fold runs across: one page above it and the next page below it.
                let height = min(fold.minY, size.height - fold.maxY)
                if height > 180 {
                    return PaneLayout(kind: .stacked,
                                      frames: [CGRect(x: 0, y: fold.minY - height, width: size.width, height: height),
                                               CGRect(x: 0, y: fold.maxY, width: size.width, height: height)],
                                      fold: fold)
                }
            }
        }
        if size.width >= 600, size.width > size.height * 1.2 {
            let gutter: CGFloat = 24
            let width = (size.width - gutter) / 2
            return PaneLayout(kind: .sideBySide,
                              frames: [CGRect(x: 0, y: 0, width: width, height: size.height),
                                       CGRect(x: width + gutter, y: 0, width: width, height: size.height)],
                              fold: CGRect(x: width, y: 0, width: gutter, height: size.height))
        }
        return PaneLayout(kind: .single, frames: [full], fold: nil)
    }

    /// The fold reported by iPhone Duo (iOS 27.1 and later), if this view crosses it.
    static func fold(in proxy: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).first?.frame
        }
        return nil
    }
}

struct AnchorRequest: Equatable {
    var id: String
    var token: Int
    var loadToken: Int
}

struct PaneRequest: Equatable {
    var chapterURL: URL
    var bookFolder: URL
    var loadToken: Int
    var page: Int
    var settingsJSON: String
    var revealed: Bool
    var anchor: AnchorRequest?
}

enum PaneEvent {
    case layout(pages: Int, token: Int)
    case anchor(page: Int, token: Int)
    case tap(x: Double, y: Double)
    case swipe(forward: Bool)
    case link(URL)
}

/// Reading state for one open book: which chapter, which page, and how far through.
@MainActor
final class ReaderModel: ObservableObject {
    enum Target: Equatable {
        case start, end
        case fraction(Double)
        case anchor(String)
    }

    let book: Book
    private weak var library: BookLibrary?

    @Published private(set) var chapter: Int
    @Published private(set) var page = 0
    @Published private(set) var pageCount = 1
    @Published private(set) var loadToken = 0
    @Published private(set) var resolvedToken = -1
    @Published private(set) var anchorRequest: AnchorRequest?
    @Published private(set) var paneCount = 1
    @Published private(set) var layoutKind: PaneLayout.Kind = .single
    @Published var chromeVisible = false

    private var target: Target
    private var anchorToken = 0
    private let chapterStarts: [Double]

    init(book: Book, library: BookLibrary?, startAt override: Int? = nil) {
        self.book = book
        self.library = library
        var starts: [Double] = []
        var running = 0
        for item in book.manifest.spine {
            starts.append(Double(running) / Double(book.manifest.totalSize))
            running += max(1, item.size)
        }
        chapterStarts = starts
        let lastChapter = book.manifest.spine.count - 1
        if let override {
            chapter = min(max(0, override), lastChapter)
            target = .start
        } else if let saved = library?.position(for: book) {
            chapter = min(max(0, saved.chapter), lastChapter)
            target = .fraction(saved.fraction)
        } else {
            chapter = 0
            target = .start
        }
    }

    var chapterURL: URL { book.url(for: book.manifest.spine[chapter].path) }
    var isRevealed: Bool { resolvedToken == loadToken }
    var isAtEnd: Bool { chapter == book.manifest.spine.count - 1 && page + paneCount >= pageCount }

    /// How far through the whole book, weighting chapters by length.
    var progress: Double {
        let start = chapterStarts[chapter]
        let end = chapter + 1 < chapterStarts.count ? chapterStarts[chapter + 1] : 1
        let within = pageCount > 0 ? Double(min(page + paneCount, pageCount)) / Double(pageCount) : 0
        return min(1, max(0, start + (end - start) * within))
    }

    var chapterTitle: String {
        let toc = book.manifest.toc
        var best: TOCEntry?
        for entry in toc {
            guard let index = book.manifest.spineIndex(for: entry.path), index <= chapter else { continue }
            if best == nil || index >= (book.manifest.spineIndex(for: best!.path) ?? 0) { best = entry }
        }
        return best?.title ?? book.title
    }

    var currentTOCEntry: TOCEntry? {
        book.manifest.toc.last { (book.manifest.spineIndex(for: $0.path) ?? Int.max) <= chapter }
    }

    func request(for pane: Int, settingsJSON: String) -> PaneRequest {
        PaneRequest(chapterURL: chapterURL,
                    bookFolder: book.folder,
                    loadToken: loadToken,
                    page: page + pane,
                    settingsJSON: settingsJSON,
                    revealed: isRevealed,
                    anchor: pane == 0 ? anchorRequest : nil)
    }

    func setLayout(_ layout: PaneLayout, rawFold: CGRect? = nil) {
        if ProcessInfo.processInfo.arguments.contains("-BookDuoSnapshot") {
            let line = "layout \(layout.kind) panes=\(layout.frames.map { NSCoder.string(for: $0) }) fold=\(layout.fold.map { NSCoder.string(for: $0) } ?? "none") reported=\(rawFold.map { NSCoder.string(for: $0) } ?? "none")\n"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("layout.txt")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        layoutKind = layout.kind
        guard paneCount != layout.paneCount else { return }
        paneCount = layout.paneCount
        page = align(page)
    }

    // MARK: Events from the pages

    func handle(_ event: PaneEvent, pane: Int) {
        switch event {
        case .layout(let pages, let token):
            guard pane == 0, token == loadToken else { return }
            pageCount = max(1, pages)
            switch target {
            case .start: page = 0
            case .end: page = align(pageCount - 1)
            case .fraction(let f): page = align(Int((f * Double(pageCount)).rounded(.down)))
            case .anchor: if anchorRequest != nil { return }
            }
            settle()
        case .anchor(let found, let token):
            guard token == anchorRequest?.token else { return }
            anchorRequest = nil
            page = align(found)
            settle()
        case .tap(let x, _):
            tap(x: x, pane: pane)
        case .swipe(let forward):
            if chromeVisible { chromeVisible = false }
            forward ? next() : previous()
        case .link(let url):
            follow(url)
        }
    }

    private func tap(x: Double, pane: Int) {
        if chromeVisible {
            withAnimation(.easeOut(duration: 0.2)) { chromeVisible = false }
            return
        }
        let back: Bool, forward: Bool
        switch layoutKind {
        case .sideBySide:
            back = pane == 0 && x < 0.4
            forward = pane == 1 && x > 0.6
        case .single, .stacked:
            back = x < 0.3
            forward = x > 0.7
        }
        if back {
            previous()
        } else if forward {
            next()
        } else {
            withAnimation(.easeOut(duration: 0.2)) { chromeVisible = true }
        }
    }

    // MARK: Moving around

    func next() {
        guard isRevealed else { return }
        if page + paneCount < pageCount {
            page += paneCount
            remember()
        } else if chapter + 1 < book.manifest.spine.count {
            open(chapter + 1, at: .start)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func previous() {
        guard isRevealed else { return }
        if page > 0 {
            page = max(0, page - paneCount)
            remember()
        } else if chapter > 0 {
            open(chapter - 1, at: .end)
        }
    }

    func open(_ index: Int, at target: Target) {
        let index = min(max(0, index), book.manifest.spine.count - 1)
        if index == chapter, case .anchor(let id) = target, isRevealed {
            anchorToken += 1
            anchorRequest = AnchorRequest(id: id, token: anchorToken, loadToken: loadToken)
            self.target = .fraction(Double(page) / Double(max(pageCount, 1)))
            return
        }
        chapter = index
        self.target = target
        loadToken += 1
        if case .anchor(let id) = target {
            anchorToken += 1
            anchorRequest = AnchorRequest(id: id, token: anchorToken, loadToken: loadToken)
        } else {
            anchorRequest = nil
        }
    }

    func jump(to entry: TOCEntry) {
        guard let index = book.manifest.spineIndex(for: entry.path) else { return }
        open(index, at: entry.fragment.map { .anchor($0) } ?? .start)
    }

    func jump(toProgress value: Double) {
        let value = min(max(0, value), 0.9999)
        let index = max(0, (chapterStarts.lastIndex { $0 <= value }) ?? 0)
        let start = chapterStarts[index]
        let end = index + 1 < chapterStarts.count ? chapterStarts[index + 1] : 1
        let fraction = end > start ? (value - start) / (end - start) : 0
        if index == chapter, isRevealed {
            page = align(Int((fraction * Double(pageCount)).rounded(.down)))
            remember()
        } else {
            open(index, at: .fraction(fraction))
        }
    }

    func follow(_ url: URL) {
        if url.isFileURL {
            let folder = book.folder.standardizedFileURL.resolvingSymlinksInPath().path
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(folder + "/") else { return }
            let relative = String(path.dropFirst(folder.count + 1))
            guard let index = book.manifest.spineIndex(for: relative) else { return }
            if let fragment = url.fragment, !fragment.isEmpty {
                open(index, at: .anchor(fragment))
            } else if index != chapter {
                open(index, at: .start)
            }
        } else if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Saving

    func save() {
        guard isRevealed else { return }
        library?.save(ReadingPosition(chapter: chapter,
                                      fraction: Double(page) / Double(max(pageCount, 1)),
                                      progress: progress,
                                      updated: Date()), for: book)
    }

    private func settle() {
        page = align(page)
        if resolvedToken != loadToken { resolvedToken = loadToken }
        remember()
    }

    private func remember() {
        // A hair past the page start so the same page comes back after a reflow.
        target = .fraction((Double(page) + 0.01) / Double(max(pageCount, 1)))
        save()
    }

    private func align(_ value: Int) -> Int {
        let clamped = min(max(0, value), max(0, pageCount - 1))
        return paneCount == 2 ? clamped - clamped % 2 : clamped
    }
}
