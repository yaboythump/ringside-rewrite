import Compression
import Foundation

enum ZipError: LocalizedError {
    case notZip
    case unsupported(String)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .notZip: return "This file isn't a valid EPUB (it isn't a ZIP archive)."
        case .unsupported(let why): return why
        case .corrupt(let what): return "The book file is damaged (\(what))."
        }
    }
}

/// A small read-only ZIP reader: enough for EPUB files (stored and deflated entries).
struct ZipReader {
    struct Entry {
        let path: String
        let method: UInt16
        let flags: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int

        var isDirectory: Bool { path.hasSuffix("/") }
    }

    let data: Data
    let entries: [Entry]

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readDirectory(data)
    }

    func entry(_ path: String) -> Entry? {
        entries.first { $0.path == path } ?? entries.first { $0.path.lowercased() == path.lowercased() }
    }

    func read(_ entry: Entry) throws -> Data {
        guard entry.flags & 1 == 0 else {
            throw ZipError.unsupported("This book is encrypted and can't be opened.")
        }
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, data.u32(header) == 0x0403_4b50 else {
            throw ZipError.corrupt("bad entry header")
        }
        let start = header + 30 + Int(data.u16(header + 26)) + Int(data.u16(header + 28))
        let end = start + entry.compressedSize
        guard start <= end, end <= data.count else { throw ZipError.corrupt("entry outside the file") }
        let raw = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
        switch entry.method {
        case 0:
            return raw
        case 8:
            return try Self.inflate(raw, expected: entry.uncompressedSize)
        default:
            throw ZipError.unsupported("This book uses a compression method Book Duo can't read.")
        }
    }

    func read(_ path: String) throws -> Data {
        guard let entry = entry(path) else { throw ZipError.corrupt("missing \(path)") }
        return try read(entry)
    }

    /// Writes every file into `folder`, refusing paths that would escape it.
    func extractAll(to folder: URL) throws {
        let files = FileManager.default
        for entry in entries where !entry.isDirectory {
            guard let relative = Self.safeRelativePath(entry.path) else { continue }
            let destination = folder.appendingPathComponent(relative)
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try read(entry).write(to: destination, options: .atomic)
        }
    }

    static func safeRelativePath(_ path: String) -> String? {
        let parts = path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }
        return parts.joined(separator: "/")
    }

    private static func readDirectory(_ data: Data) throws -> [Entry] {
        let count = data.count
        guard count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        var position = count - 22
        let lowest = max(0, count - 22 - 65_535)
        while position >= lowest {
            if data.u32(position) == 0x0605_4b50 { eocd = position; break }
            position -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let total = Int(data.u16(eocd + 10))
        let directoryOffset = data.u32(eocd + 16)
        guard directoryOffset != 0xFFFF_FFFF, total != 0xFFFF else {
            throw ZipError.unsupported("This book is too large for Book Duo (ZIP64).")
        }
        var entries: [Entry] = []
        entries.reserveCapacity(total)
        var p = Int(directoryOffset)
        for _ in 0..<total {
            guard p + 46 <= count, data.u32(p) == 0x0201_4b50 else { throw ZipError.corrupt("bad directory") }
            let nameLength = Int(data.u16(p + 28))
            let extraLength = Int(data.u16(p + 30))
            let commentLength = Int(data.u16(p + 32))
            guard p + 46 + nameLength <= count else { throw ZipError.corrupt("bad file name") }
            let nameBytes = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nameLength))
            let name = String(data: nameBytes, encoding: .utf8) ?? String(decoding: nameBytes, as: UTF8.self)
            entries.append(Entry(
                path: name,
                method: data.u16(p + 10),
                flags: data.u16(p + 8),
                compressedSize: Int(data.u32(p + 20)),
                uncompressedSize: Int(data.u32(p + 24)),
                localHeaderOffset: Int(data.u32(p + 42))))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func inflate(_ input: Data, expected: Int) throws -> Data {
        if expected == 0 { return Data() }
        guard expected <= 512 * 1024 * 1024, !input.isEmpty else { throw ZipError.corrupt("bad sizes") }
        var output = Data(count: expected)
        let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let destination = out.bindMemory(to: UInt8.self).baseAddress,
                      let from = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what ZIP stores.
                return compression_decode_buffer(destination, expected, from, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expected else { throw ZipError.corrupt("couldn't decompress") }
        return output
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
