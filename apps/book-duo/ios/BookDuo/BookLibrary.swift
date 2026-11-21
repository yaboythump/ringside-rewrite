import Foundation
import UIKit
import UniformTypeIdentifiers

struct Book: Identifiable, Hashable {
    /// The file name in Documents/Books; reading positions are kept under it.
    let id: String
    let file: URL
    let folder: URL
    let manifest: BookManifest

    var title: String { manifest.title }
    var author: String { manifest.author }
    var coverURL: URL? { manifest.cover.map { folder.appendingPathComponent($0) } }

    func url(for path: String) -> URL { folder.appendingPathComponent(path) }
}

struct ReadingPosition: Codable, Hashable {
    var chapter: Int
    var fraction: Double
    var progress: Double
    var updated: Date
}

/// Books live in Documents/Books (Files › On My iPhone › Book Duo › Books).
/// Each one is unpacked once into Application Support so WebKit can show it.
@MainActor
final class BookLibrary: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var positions: [String: ReadingPosition] = [:]
    @Published private(set) var isWorking = false
    @Published var message: String?

    let documents: URL
    let booksFolder: URL
    let unpackedFolder: URL
    private let positionsURL: URL

    static let sampleFileName = "Alice’s Adventures in Wonderland.epub"

    init() {
        let files = FileManager.default
        documents = files.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksFolder = documents.appendingPathComponent("Books", isDirectory: true)
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookDuo", isDirectory: true)
        unpackedFolder = support.appendingPathComponent("Unpacked", isDirectory: true)
        positionsURL = support.appendingPathComponent("positions.json")
        for folder in [booksFolder, unpackedFolder] {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        if let data = try? Data(contentsOf: positionsURL),
           let saved = try? JSONDecoder().decode([String: ReadingPosition].self, from: data) {
            positions = saved
        }
        installSampleIfNeeded()
        Task { await refresh() }
    }

    /// Recently read first, then the rest by title.
    var sortedBooks: [Book] {
        books.sorted { a, b in
            let da = positions[a.id]?.updated, db = positions[b.id]?.updated
            switch (da, db) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }

    func refresh() async {
        collectLooseFiles()
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: booksFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension.lowercased() == "epub" }
        let root = unpackedFolder
        isWorking = true
        let results: [(URL, Result<(folder: URL, manifest: BookManifest), Error>)] = await Task.detached(priority: .userInitiated) {
            urls.map { url in (url, Result { try BookUnpacker.load(url, into: root) }) }
        }.value
        isWorking = false

        var loaded: [Book] = []
        var problems: [String] = []
        for (url, result) in results {
            switch result {
            case .success(let unpacked):
                loaded.append(Book(id: url.lastPathComponent, file: url, folder: unpacked.folder, manifest: unpacked.manifest))
            case .failure(let error):
                problems.append("\(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)")
            }
        }
        books = loaded
        if !problems.isEmpty { message = problems.joined(separator: "\n") }
        removeStaleUnpackedFolders()
    }

    /// Copies picked or shared EPUB files into the library.
    func importFiles(_ urls: [URL]) {
        let files = FileManager.default
        var skipped: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "epub" else {
                skipped.append(url.lastPathComponent)
                continue
            }
            let destination = uniqueDestination(for: url.lastPathComponent)
            do {
                try files.copyItem(at: url, to: destination)
                if url.path.contains("/Inbox/") { try? files.removeItem(at: url) }
            } catch {
                skipped.append(url.lastPathComponent)
            }
        }
        if !skipped.isEmpty {
            message = "Book Duo opens EPUB books. Skipped: " + skipped.joined(separator: ", ")
        }
        Task { await refresh() }
    }

    func delete(_ book: Book) {
        try? FileManager.default.removeItem(at: book.file)
        try? FileManager.default.removeItem(at: book.folder)
        positions[book.id] = nil
        savePositions()
        books.removeAll { $0.id == book.id }
    }

    func position(for book: Book) -> ReadingPosition? { positions[book.id] }

    func save(_ position: ReadingPosition, for book: Book) {
        positions[book.id] = position
        savePositions()
    }

    // MARK: Private

    private func savePositions() {
        if let data = try? JSONEncoder().encode(positions) {
            try? data.write(to: positionsURL, options: .atomic)
        }
    }

    private func installSampleIfNeeded() {
        let key = "BookDuo.installedSample"
        guard !UserDefaults.standard.bool(forKey: key),
              let sample = Bundle.main.url(forResource: "Alice", withExtension: "epub") else { return }
        let destination = booksFolder.appendingPathComponent(Self.sampleFileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.copyItem(at: sample, to: destination)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// EPUBs dropped straight into the app's Files folder, or handed over by "Open in", move into Books.
    private func collectLooseFiles() {
        let files = FileManager.default
        for folder in [documents, documents.appendingPathComponent("Inbox", isDirectory: true)] {
            let urls = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])) ?? []
            for url in urls where url.pathExtension.lowercased() == "epub" {
                try? files.moveItem(at: url, to: uniqueDestination(for: url.lastPathComponent))
            }
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        var candidate = booksFolder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = booksFolder.appendingPathComponent("\(base) \(number).epub")
            number += 1
        }
        return candidate
    }

    private func removeStaleUnpackedFolders() {
        let keep = Set(books.map { $0.folder.lastPathComponent })
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: unpackedFolder, includingPropertiesForKeys: nil, options: [])) ?? []
        for folder in folders where !keep.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

/// Loads cover images off the main thread, shrunk for the grid, and keeps them.
final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let full = UIImage(contentsOfFile: url.path) else { return nil }
            return full.preparingThumbnail(of: CGSize(width: 360, height: 360 * full.size.height / max(full.size.width, 1)))
                ?? full
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
