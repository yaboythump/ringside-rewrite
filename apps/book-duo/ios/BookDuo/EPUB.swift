import Foundation

struct SpineItem: Codable, Hashable {
    var path: String
    var size: Int
    var linear: Bool
}

struct TOCEntry: Codable, Hashable, Identifiable {
    var id: Int
    var title: String
    var path: String
    var fragment: String?
    var level: Int
}

/// Everything Book Duo needs from an EPUB, saved next to the unpacked files.
struct BookManifest: Codable, Hashable {
    static let currentVersion = 3

    var version: Int
    var title: String
    var author: String
    var language: String?
    var spine: [SpineItem]
    var toc: [TOCEntry]
    var cover: String?

    var totalSize: Int { max(1, spine.reduce(0) { $0 + max(1, $1.size) }) }

    func spineIndex(for path: String) -> Int? {
        spine.firstIndex { $0.path == path } ?? spine.firstIndex { $0.path.lowercased() == path.lowercased() }
    }
}

// MARK: - A tiny XML tree

final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""
    weak var parent: XMLNode?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    subscript(_ attribute: String) -> String? { attributes[attribute] }

    /// All descendants (depth first) with this local name.
    func all(_ name: String) -> [XMLNode] {
        var found: [XMLNode] = []
        for child in children {
            if child.name == name { found.append(child) }
            found += child.all(name)
        }
        return found
    }

    func first(_ name: String) -> XMLNode? {
        for child in children {
            if child.name == name { return child }
            if let deeper = child.first(name) { return deeper }
        }
        return nil
    }

    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }

    var allText: String {
        let raw = text + children.map(\.allText).joined()
        return raw
    }

    var cleanText: String {
        allText.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func parse(_ data: Data) -> XMLNode? {
        if let root = TreeBuilder.build(data) { return root }
        // HTML entities such as &nbsp; aren't defined in XML; swap the common ones and retry.
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        let entities = ["&nbsp;": "&#160;", "&mdash;": "&#8212;", "&ndash;": "&#8211;", "&rsquo;": "&#8217;",
                        "&lsquo;": "&#8216;", "&rdquo;": "&#8221;", "&ldquo;": "&#8220;", "&hellip;": "&#8230;",
                        "&copy;": "&#169;", "&eacute;": "&#233;", "&shy;": "&#173;"]
        for (entity, number) in entities { text = text.replacingOccurrences(of: entity, with: number) }
        return TreeBuilder.build(Data(text.utf8))
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    private var root: XMLNode?
    private var current: XMLNode?

    static func build(_ data: Data) -> XMLNode? {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    private static func local(_ name: String) -> String {
        if let colon = name.lastIndex(of: ":") { return String(name[name.index(after: colon)...]) }
        return name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        var attributes: [String: String] = [:]
        for (key, value) in attributeDict { attributes[Self.local(key)] = value }
        let node = XMLNode(name: Self.local(elementName), attributes: attributes)
        node.parent = current
        if let current { current.children.append(node) } else { root = node }
        current = node
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        current = current?.parent
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let current else { return }
        if current.children.isEmpty {
            current.text += string
        } else {
            // Keep text order roughly right for titles like "<span>I</span>: Down the Rabbit-Hole".
            let textNode = XMLNode(name: "#text", attributes: [:])
            textNode.text = string
            textNode.parent = current
            current.children.append(textNode)
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: string) }
    }
}

// MARK: - Reading an EPUB

enum EPUBError: LocalizedError {
    case missing(String)
    case protected

    var errorDescription: String? {
        switch self {
        case .missing(let what): return "This EPUB is missing its \(what)."
        case .protected: return "This book is protected with DRM, so it can only be read in the store's own app."
        }
    }
}

enum EPUBParser {
    /// Resolves `href` (relative to the file at `base`) to a path from the book root, plus any #fragment.
    static func resolve(_ href: String, relativeTo base: String) -> (path: String, fragment: String?) {
        var reference = href
        var fragment: String?
        if let hash = reference.firstIndex(of: "#") {
            fragment = String(reference[reference.index(after: hash)...])
            reference = String(reference[..<hash])
            if fragment?.isEmpty == true { fragment = nil }
        }
        reference = reference.removingPercentEncoding ?? reference
        if reference.isEmpty { return (base, fragment) }
        var parts: [String] = reference.hasPrefix("/") ? [] : base.split(separator: "/").dropLast().map(String.init)
        for piece in reference.split(separator: "/") {
            if piece == "." { continue }
            if piece == ".." { _ = parts.popLast(); continue }
            parts.append(String(piece))
        }
        return (parts.joined(separator: "/"), fragment)
    }

    static func read(zip: ZipReader) throws -> BookManifest {
        guard let container = XMLNode.parse(try zip.read("META-INF/container.xml")),
              let opfPath = container.first("rootfile")?["full-path"] else {
            throw EPUBError.missing("container")
        }
        if let encryption = zip.entry("META-INF/encryption.xml"),
           let tree = XMLNode.parse(try zip.read(encryption)) {
            // Font obfuscation is fine; anything else means the text itself is encrypted.
            let fontOnly = ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"]
            let methods = tree.all("EncryptionMethod").compactMap { $0["Algorithm"] }
            if methods.contains(where: { !fontOnly.contains($0) }) { throw EPUBError.protected }
        }
        guard let opf = XMLNode.parse(try zip.read(opfPath)) else { throw EPUBError.missing("package file") }

        let metadata = opf.first("metadata")
        let title = metadata?.first("title")?.cleanText
        let author = metadata?.all("creator").first?.cleanText
        let language = metadata?.first("language")?.cleanText

        struct Item { let path: String; let type: String; let properties: [String] }
        var items: [String: Item] = [:]
        for node in opf.first("manifest")?.all("item") ?? [] {
            guard let id = node["id"], let href = node["href"] else { continue }
            items[id] = Item(path: resolve(href, relativeTo: opfPath).path,
                             type: node["media-type"] ?? "",
                             properties: (node["properties"] ?? "").split(separator: " ").map(String.init))
        }

        var spine: [SpineItem] = []
        let spineNode = opf.first("spine")
        for ref in spineNode?.all("itemref") ?? [] {
            guard let id = ref["idref"], let item = items[id] else { continue }
            let size = zip.entry(item.path)?.uncompressedSize ?? 1
            spine.append(SpineItem(path: item.path, size: size, linear: ref["linear"] != "no"))
        }
        guard !spine.isEmpty else { throw EPUBError.missing("chapters") }

        var cover = items.values.first { $0.properties.contains("cover-image") }?.path
        if cover == nil,
           let coverID = metadata?.all("meta").first(where: { $0["name"] == "cover" })?["content"] {
            cover = items[coverID]?.path
        }
        if cover == nil {
            cover = items.first { $0.key.lowercased().contains("cover") && $0.value.type.hasPrefix("image/") }?.value.path
        }

        var toc: [TOCEntry] = []
        if let nav = items.values.first(where: { $0.properties.contains("nav") }),
           let data = try? zip.read(nav.path), let tree = XMLNode.parse(data) {
            toc = navEntries(tree, base: nav.path)
        }
        if toc.isEmpty, let ncxID = spineNode?["toc"] ?? items.first(where: { $0.value.type == "application/x-dtbncx+xml" })?.key,
           let ncx = items[ncxID], let data = try? zip.read(ncx.path), let tree = XMLNode.parse(data) {
            toc = ncxEntries(tree, base: ncx.path)
        }

        let fallbackTitle = (opfPath as NSString).deletingPathExtension
        return BookManifest(version: BookManifest.currentVersion,
                            title: title?.isEmpty == false ? title! : fallbackTitle,
                            author: author ?? "",
                            language: language,
                            spine: spine,
                            toc: toc,
                            cover: cover)
    }

    private static func navEntries(_ tree: XMLNode, base: String) -> [TOCEntry] {
        let navs = tree.all("nav")
        guard let nav = navs.first(where: { ($0["type"] ?? "").split(separator: " ").contains("toc") }) ?? navs.first,
              let list = nav.first("ol") else { return [] }
        var entries: [TOCEntry] = []
        func walk(_ ol: XMLNode, level: Int) {
            for li in ol.children where li.name == "li" {
                let heading = li.children.first { $0.name == "a" }
                    ?? li.children.lazy.filter { $0.name != "ol" }.compactMap { $0.name == "a" ? $0 : $0.first("a") }.first
                if let link = heading, let href = link["href"] {
                    let target = resolve(href, relativeTo: base)
                    let title = link.cleanText
                    entries.append(TOCEntry(id: entries.count, title: title.isEmpty ? "Untitled" : title,
                                            path: target.path, fragment: target.fragment, level: level))
                }
                if let nested = li.child("ol") { walk(nested, level: level + 1) }
            }
        }
        walk(list, level: 0)
        return entries
    }

    private static func ncxEntries(_ tree: XMLNode, base: String) -> [TOCEntry] {
        guard let map = tree.first("navMap") else { return [] }
        var entries: [TOCEntry] = []
        func walk(_ node: XMLNode, level: Int) {
            for point in node.children where point.name == "navPoint" {
                if let src = point.child("content")?["src"] {
                    let target = resolve(src, relativeTo: base)
                    let title = point.child("navLabel")?.first("text")?.cleanText ?? ""
                    entries.append(TOCEntry(id: entries.count, title: title.isEmpty ? "Untitled" : title,
                                            path: target.path, fragment: target.fragment, level: level))
                }
                walk(point, level: level + 1)
            }
        }
        walk(map, level: 0)
        return entries
    }
}

// MARK: - Unpacking into the app's private folder

enum BookUnpacker {
    static let viewport = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no\"/>"

    /// Unpacks (once) and returns the manifest. The folder name changes whenever the file does.
    static func load(_ file: URL, into root: URL) throws -> (folder: URL, manifest: BookManifest) {
        let files = FileManager.default
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(file.lastPathComponent)|\(values.fileSize ?? 0)|\(Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0))"
        let folder = root.appendingPathComponent(folderName(for: stamp), isDirectory: true)
        let manifestURL = folder.appendingPathComponent("bookduo-manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(BookManifest.self, from: data),
           manifest.version == BookManifest.currentVersion {
            return (folder, manifest)
        }

        let zip = try ZipReader(url: file)
        let manifest = try EPUBParser.read(zip: zip)
        let temporary = root.appendingPathComponent(".unpacking-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            try zip.extractAll(to: temporary)
            for item in manifest.spine { addViewport(to: temporary.appendingPathComponent(item.path)) }
            try JSONEncoder().encode(manifest).write(to: temporary.appendingPathComponent("bookduo-manifest.json"))
            if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
            try files.moveItem(at: temporary, to: folder)
        } catch {
            try? files.removeItem(at: temporary)
            throw error
        }
        return (folder, manifest)
    }

    static func folderName(for stamp: String) -> String {
        // FNV-1a: stable across launches (unlike Hasher).
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in stamp.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// Chapters need a viewport tag before their first layout, or WebKit lays them out 980 points wide.
    static func addViewport(to url: URL) {
        guard var html = try? String(contentsOf: url, encoding: .utf8), !html.contains("name=\"viewport\"") else { return }
        guard let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) else { return }
        html.insert(contentsOf: viewport, at: head.upperBound)
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }
}
