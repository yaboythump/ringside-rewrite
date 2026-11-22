import Foundation
import UniformTypeIdentifiers

/// The ROM and disk images the person has added. Everything lives in the app's
/// Documents folder (visible in Files › On My iPhone › Mac Duo):
///   ROM/   the Macintosh II-family ROM (256 KB)
///   Disks/ disk images (.dsk, .img, .image, .hfv, .hda, Disk Copy 4.2)
@MainActor
final class MacLibrary: ObservableObject {
    struct Disk: Identifiable, Hashable {
        let url: URL
        let size: Int64
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
        /// Floppies are 400K/800K/1.4MB; anything larger is a hard disk image.
        var isFloppy: Bool { size <= 1_474_560 + 84 }
    }

    struct ROMInfo: Equatable {
        let url: URL
        let check: MVRomCheck
        let checksum: UInt32

        var isUsable: Bool { check == MVRomOK || check == MVRomUnknown }
        var modelName: String {
            switch checksum {
            case 0x9779D2C4: return "Macintosh II"
            case 0x97221136: return "Macintosh IIx / IIcx / SE/30"
            default: return "Unrecognized 256 KB ROM"
            }
        }
        var problem: String? {
            switch check {
            case MVRomOK: return nil
            case MVRomUnknown: return "This ROM isn't one Mac Duo has been tested with. It may still work."
            case MVRomWrongSize: return "This file isn't 256 KB. Mac Duo needs a Macintosh II-family ROM (Mac Plus and SE ROMs are 128 KB and won't work)."
            case MVRomBadChecksum: return "This file failed the ROM checksum. It may be damaged or not a Macintosh ROM."
            default: return "The ROM file can't be read."
            }
        }
    }

    @Published private(set) var rom: ROMInfo?
    @Published private(set) var disks: [Disk] = []
    @Published var lastError: String?
    /// Disks inserted automatically when the Mac starts, in order (the first one boots).
    @Published var startupDisks: [URL] = [] {
        didSet { UserDefaults.standard.set(startupDisks.map(\.lastPathComponent), forKey: Self.startupKey) }
    }

    static let diskExtensions: Set<String> = ["dsk", "img", "image", "hfv", "hda", "disk", "dc42", "diskcopy42", "toast", "iso"]
    static let romExtensions: Set<String> = ["rom", "bin"]
    private static let startupKey = "startupDisks"

    let documents: URL
    let romFolder: URL
    let diskFolder: URL

    init() {
        let fm = FileManager.default
        documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        romFolder = documents.appendingPathComponent("ROM", isDirectory: true)
        diskFolder = documents.appendingPathComponent("Disks", isDirectory: true)
        try? fm.createDirectory(at: romFolder, withIntermediateDirectories: true)
        try? fm.createDirectory(at: diskFolder, withIntermediateDirectories: true)
        refresh()
    }

    /// Picks up files dropped into Documents via the Files app, then rescans.
    func refresh() {
        let fm = FileManager.default
        // Sort loose files from the top of Documents into ROM/ and Disks/.
        if let loose = try? fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isRegularFileKey]) {
            for url in loose where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let ext = url.pathExtension.lowercased()
                if Self.romExtensions.contains(ext) || fileSize(url) == Int64(MV_ROM_SIZE) {
                    adoptROM(url, move: true)
                } else if Self.diskExtensions.contains(ext) {
                    _ = place(url, in: diskFolder, move: true)
                }
            }
        }

        let romFiles = (try? fm.contentsOfDirectory(at: romFolder, includingPropertiesForKeys: nil)) ?? []
        if let url = romFiles.filter({ !$0.lastPathComponent.hasPrefix(".") }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
            var checksum: UInt32 = 0
            let check = MVCoreCheckROM(url.path, &checksum)
            rom = ROMInfo(url: url, check: check, checksum: checksum)
        } else {
            rom = nil
        }

        let diskFiles = (try? fm.contentsOfDirectory(at: diskFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        disks = diskFiles
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { Disk(url: $0, size: fileSize($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let saved = UserDefaults.standard.stringArray(forKey: Self.startupKey) ?? []
        let byName = Dictionary(disks.map { ($0.url.lastPathComponent, $0.url) }, uniquingKeysWith: { a, _ in a })
        let restored = saved.compactMap { byName[$0] }
        if restored != startupDisks { startupDisks = restored }
        // A first disk is chosen for you so Start works straight away.
        if startupDisks.isEmpty, let first = disks.first(where: { !$0.isFloppy }) ?? disks.first {
            startupDisks = [first.url]
        }
    }

    /// Imports files picked in the document picker or shared to the app.
    func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            if Self.romExtensions.contains(ext) || fileSize(url) == Int64(MV_ROM_SIZE) {
                adoptROM(url, move: false)
            } else if let placed = place(url, in: diskFolder, move: false) {
                if !startupDisks.contains(placed) && startupDisks.count < Int(MV_MAX_DISKS) {
                    startupDisks.append(placed)
                }
            }
        }
        refresh()
    }

    func delete(_ disk: Disk) {
        try? FileManager.default.removeItem(at: disk.url)
        startupDisks.removeAll { $0 == disk.url }
        refresh()
    }

    func deleteROM() {
        if let rom { try? FileManager.default.removeItem(at: rom.url) }
        refresh()
    }

    func toggleStartup(_ disk: Disk) {
        if let i = startupDisks.firstIndex(of: disk.url) {
            startupDisks.remove(at: i)
        } else if startupDisks.count < Int(MV_MAX_DISKS) {
            startupDisks.append(disk.url)
        }
    }

    func makeBootDisk(_ disk: Disk) {
        startupDisks.removeAll { $0 == disk.url }
        startupDisks.insert(disk.url, at: 0)
    }

    /// Makes an empty disk the Mac can initialize (it asks to when inserted).
    func createBlankDisk(named name: String, bytes: Int) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        let url = uniqueURL(in: diskFolder, name: (clean.isEmpty ? "Untitled" : clean) + ".dsk")
        if FileManager.default.createFile(atPath: url.path, contents: nil),
           let handle = try? FileHandle(forWritingTo: url) {
            try? handle.truncate(atOffset: UInt64(bytes))
            try? handle.close()
        } else {
            lastError = "Couldn't create the disk."
        }
        refresh()
    }

    // MARK: - Helpers

    private func adoptROM(_ url: URL, move: Bool) {
        let fm = FileManager.default
        // Only one ROM at a time: the newest replaces the old one.
        for old in (try? fm.contentsOfDirectory(at: romFolder, includingPropertiesForKeys: nil)) ?? [] where old.standardizedFileURL != url.standardizedFileURL {
            try? fm.removeItem(at: old)
        }
        _ = place(url, in: romFolder, move: move)
        var checksum: UInt32 = 0
        if let placed = try? fm.contentsOfDirectory(at: romFolder, includingPropertiesForKeys: nil).first {
            let check = MVCoreCheckROM(placed.path, &checksum)
            if check != MVRomOK && check != MVRomUnknown {
                lastError = ROMInfo(url: placed, check: check, checksum: checksum).problem
            }
        }
    }

    private func place(_ url: URL, in folder: URL, move: Bool) -> URL? {
        let fm = FileManager.default
        if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { return url }
        let target = uniqueURL(in: folder, name: url.lastPathComponent)
        do {
            if move { try fm.moveItem(at: url, to: target) } else { try fm.copyItem(at: url, to: target) }
            return target
        } catch {
            lastError = "Couldn't add \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
