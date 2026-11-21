import Foundation
import UniformTypeIdentifiers

enum GameSystem: String, Hashable {
    case nes, gameBoy, gameBoyColor, nintendoDS

    var displayName: String {
        switch self {
        case .nes: return "NES"
        case .gameBoy: return "Game Boy"
        case .gameBoyColor: return "Game Boy Color"
        case .nintendoDS: return "Nintendo DS"
        }
    }

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "gb": self = .gameBoy
        case "gbc", "cgb": self = .gameBoyColor
        case "nds": self = .nintendoDS
        case "nes": self = .nes
        default: return nil
        }
    }

    var maximumROMSize: Int {
        switch self {
        case .nintendoDS: return 512 * 1024 * 1024
        case .nes: return 16 * 1024 * 1024
        default: return 8 * 1024 * 1024
        }
    }
}

struct Game: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isBuiltIn: Bool
    let system: GameSystem
    /// A free game that ships with the app: listed with the player's games, not the test carts.
    var isBundledGame = false
    /// Cover art bundled with the app (PNG resource name).
    var coverResource: String? = nil

    var isColor: Bool { system != .gameBoy && system != .nes }
    var systemName: String { system.displayName }
}

extension UTType {
    static let gameBoyROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gb")
    static let gameBoyColorROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gbc")
    static let nintendoDSROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.nds")
    static let nesROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.nes")
}

/// Games live in Documents/Games, which the Files app shows under
/// On My iPhone › Retro Duo. In-game saves sit next to them in Documents/Saves
/// so players can back them up; save states stay private in Application Support.
@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var message: String?

    static let romExtensions: Set<String> = ["nes", "gb", "gbc", "cgb", "nds"]
    static let maximumROMSize = 8 * 1024 * 1024

    let documentsFolder: URL
    let gamesFolder: URL
    let savesFolder: URL
    let statesFolder: URL

    init() {
        let files = FileManager.default
        documentsFolder = files.urls(for: .documentDirectory, in: .userDomainMask)[0]
        gamesFolder = documentsFolder.appendingPathComponent("Games", isDirectory: true)
        savesFolder = documentsFolder.appendingPathComponent("Saves", isDirectory: true)
        statesFolder = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroDuo/States", isDirectory: true)
        for folder in [gamesFolder, savesFolder, statesFolder] {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        refresh()
    }

    func refresh() {
        collectLooseFiles()
        var list: [Game] = []
        if let cart = Bundle.main.url(forResource: "RetroDuoTestCart", withExtension: "gbc") {
            list.append(Game(id: "builtin.testcart", url: cart, name: "Retro Duo Test Cart",
                             isBuiltIn: true, system: .gameBoyColor))
        }
        if let cart = Bundle.main.url(forResource: "RetroDuoNESTestCart", withExtension: "nes") {
            list.append(Game(id: "builtin.nestestcart", url: cart, name: "Retro Duo NES Test Cart",
                             isBuiltIn: true, system: .nes))
        }
        if let cart = Bundle.main.url(forResource: "RetroDuoDSTestCart", withExtension: "nds") {
            list.append(Game(id: "builtin.dstestcart", url: cart, name: "Retro Duo DS Test Cart",
                             isBuiltIn: true, system: .nintendoDS))
        }
        // Free original game made for Retro Duo (games/funeral-home-ds).
        if let cart = Bundle.main.url(forResource: "GraveMistakes", withExtension: "nds") {
            list.append(Game(id: "builtin.gravemistakes", url: cart, name: "Grave Mistakes",
                             isBuiltIn: true, system: .nintendoDS,
                             isBundledGame: true, coverResource: "GraveMistakesPremiumCover"))
        }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: gamesFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        list += urls
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let system = GameSystem(fileExtension: url.pathExtension) else { return nil }
                return Game(id: url.lastPathComponent, url: url,
                            name: url.deletingPathExtension().lastPathComponent,
                            isBuiltIn: false, system: system)
            }
        games = list
    }

    /// Copies picked or shared files into the library. Files that aren't games Retro Duo can play are skipped.
    func importFiles(_ urls: [URL]) {
        var added: [String] = []
        var skipped: [String] = []
        let files = FileManager.default
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard let system = GameSystem(fileExtension: url.pathExtension),
                  Self.isPlayable(url, system: system) else {
                skipped.append(name)
                continue
            }
            let destination = gamesFolder.appendingPathComponent(name)
            if destination.standardizedFileURL != url.standardizedFileURL {
                do {
                    if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
                    try files.copyItem(at: url, to: destination)
                } catch {
                    skipped.append(name)
                    continue
                }
            }
            added.append(url.deletingPathExtension().lastPathComponent)
            removeInboxCopy(url)
        }
        refresh()
        if !skipped.isEmpty {
            message = "Couldn't add \(skipped.joined(separator: ", ")). Retro Duo plays NES (.nes), Game Boy (.gb, .gbc) and Nintendo DS (.nds) files."
        } else if added.count == 1 {
            message = "Added \(added[0])."
        } else if added.count > 1 {
            message = "Added \(added.count) games."
        }
    }

    func delete(_ game: Game) {
        guard !game.isBuiltIn else { return }
        try? FileManager.default.removeItem(at: game.url)
        try? FileManager.default.removeItem(at: stateURL(for: game, slot: "resume"))
        try? FileManager.default.removeItem(at: stateURL(for: game, slot: "quick"))
        // In-game saves are kept, so re-adding the game brings its progress back.
        refresh()
    }

    func batteryURL(for game: Game) -> URL {
        savesFolder.appendingPathComponent(game.name).appendingPathExtension("sav")
    }

    func stateURL(for game: Game, slot: String) -> URL {
        statesFolder.appendingPathComponent("\(game.name).\(slot).state")
    }

    /// Optional artwork beside a save state; never changes the legacy .state format.
    func statePreviewURL(for game: Game, slot: String) -> URL {
        statesFolder.appendingPathComponent("\(game.name).\(slot).preview.png")
    }

    /// Checks size and header without reading a whole (possibly huge) DS file into memory.
    static func isPlayable(_ url: URL, system: GameSystem) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.intValue <= system.maximumROMSize,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 0x200) else { return false }
        switch system {
        case .nintendoDS: return looksLikeDSROM(header)
        case .nes: return header.count >= 16 && header.prefix(4) == Data([0x4E, 0x45, 0x53, 0x1A])
        default: return looksLikeROM(header)
        }
    }

    /// A real Game Boy cartridge has a valid header checksum; the console refuses to boot one without it.
    static func looksLikeROM(_ data: Data) -> Bool {
        guard data.count >= 0x150, data.count <= maximumROMSize else { return false }
        let bytes = [UInt8](data.prefix(0x150))
        var checksum: UInt8 = 0
        for index in 0x134...0x14C {
            checksum = checksum &- bytes[index] &- 1
        }
        return checksum == bytes[0x14D]
    }

    /// A DS cartridge header carries a CRC-16 of its first 0x15E bytes.
    static func looksLikeDSROM(_ data: Data) -> Bool {
        guard data.count >= 0x160 else { return false }
        let bytes = [UInt8](data.prefix(0x160))
        var crc: UInt16 = 0xFFFF
        for byte in bytes[0..<0x15E] {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc == UInt16(bytes[0x15E]) | (UInt16(bytes[0x15F]) << 8)
    }

    /// Games dropped straight into the app's top folder in Files are moved into Games.
    private func collectLooseFiles() {
        let files = FileManager.default
        let loose = (try? files.contentsOfDirectory(at: documentsFolder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? []
        for url in loose where Self.romExtensions.contains(url.pathExtension.lowercased()) {
            let destination = gamesFolder.appendingPathComponent(url.lastPathComponent)
            try? files.removeItem(at: destination)
            try? files.moveItem(at: url, to: destination)
        }
    }

    private func removeInboxCopy(_ url: URL) {
        let inbox = documentsFolder.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(inbox) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
