// AVYDRIX Play - the list of box art names for each system.
// Copyright 2026 CT Network Studios. GPL v3 or later.
import Foundation

/// Each system's box art names in libretro-thumbnails, so covers can be found for files whose
/// names don't match exactly (see CoverMatcher). Lists come from GitHub's API (two requests per
/// system), are kept in Caches for a week, and an older list is used when offline.
actor CoverIndex {
    static let shared = CoverIndex()

    private var loads: [String: Task<[String]?, Never>] = [:]

    /// `repo` is the libretro-thumbnails repository, e.g. "Sega_-_Mega_Drive_-_Genesis".
    func names(repo: String) async -> [String]? {
        if let load = loads[repo] { return await load.value }
        let load = Task { await Self.load(repo: repo) }
        loads[repo] = load
        let names = await load.value
        if names == nil { loads[repo] = nil }  // try again next time
        return names
    }

    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private static func cacheFile(_ repo: String) -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoverIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(repo).appendingPathExtension("txt")
    }

    private static func load(repo: String) async -> [String]? {
        let file = cacheFile(repo)
        let cached = (try? String(contentsOf: file, encoding: .utf8))?
            .split(separator: "\n").map(String.init)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached, !cached.isEmpty, let modified, Date().timeIntervalSince(modified) < maxAge {
            return cached
        }
        if let fresh = await fetch(repo: repo), !fresh.isEmpty {
            try? fresh.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return fresh
        }
        return cached.flatMap { $0.isEmpty ? nil : $0 }
    }

    private struct Tree: Decodable {
        struct Entry: Decodable { let path: String; let sha: String }
        let tree: [Entry]
    }

    private static func tree(_ path: String) async -> Tree? {
        guard let url = URL(string: "https://api.github.com/repos/libretro-thumbnails/" + path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Tree.self, from: data)
    }

    private static func fetch(repo: String) async -> [String]? {
        guard let root = await tree("\(repo)/git/trees/master"),
              let boxarts = root.tree.first(where: { $0.path == "Named_Boxarts" }),
              let folder = await tree("\(repo)/git/trees/\(boxarts.sha)") else { return nil }
        return folder.tree.compactMap { entry in
            entry.path.hasSuffix(".png") ? String(entry.path.dropLast(4)) : nil
        }
    }
}
