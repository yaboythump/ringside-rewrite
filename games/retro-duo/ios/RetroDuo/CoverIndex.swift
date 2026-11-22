// AVYDRIX Play - the list of box art names for each system.
// Copyright 2026 CT Network Studios. GPL v3 or later.
import Foundation

/// Each system's box art names in libretro-thumbnails, so covers can be found for files whose
/// names don't match exactly (see CoverMatcher). Lists come from GitHub's API (two requests per
/// system) or, when GitHub refuses (it allows only 60 requests an hour per network, which a
/// phone carrier's shared address runs out of), from the libretro thumbnail server's own file
/// list. They're kept in Caches for a week, and an older list is used when offline.
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
        if let names = await fetchFromGitHub(repo: repo), !names.isEmpty { return names }
        return await fetchFromLibretro(system: repo.replacingOccurrences(of: "_", with: " "))
    }

    /// thumbnails.libretro.com keeps a plain ".index" list in each folder (RetroArch reads it);
    /// the folder's web page lists the same files if the index is missing.
    private static func fetchFromLibretro(system: String) async -> [String]? {
        for file in [".index", ""] {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "thumbnails.libretro.com"
            components.path = "/\(system)/Named_Boxarts/\(file)"
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { continue }
            let names = file.isEmpty ? namesInPage(text) : namesInIndex(text)
            if !names.isEmpty { return names }
        }
        return nil
    }

    static func namesInIndex(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            return name.lowercased().hasSuffix(".png") ? String(name.dropLast(4)) : nil
        }
    }

    static func namesInPage(_ html: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: #"href="([^"?/][^"]*?)\.png""#, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        return pattern.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: html),
                  let name = String(html[r]).removingPercentEncoding?
                    .replacingOccurrences(of: "&amp;", with: "&"),
                  seen.insert(name).inserted else { return nil }
            return name
        }
    }

    private static func fetchFromGitHub(repo: String) async -> [String]? {
        guard let root = await tree("\(repo)/git/trees/master"),
              let boxarts = root.tree.first(where: { $0.path == "Named_Boxarts" }),
              let folder = await tree("\(repo)/git/trees/\(boxarts.sha)") else { return nil }
        return folder.tree.compactMap { entry in
            entry.path.hasSuffix(".png") ? String(entry.path.dropLast(4)) : nil
        }
    }
}
