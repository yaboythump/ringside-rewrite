import Foundation
import UniformTypeIdentifiers

enum GameSystem: String, Hashable {
    case nes, snes, gameBoy, gameBoyColor, gameBoyAdvance, nintendoDS, genesis, masterSystem, gameGear

    var displayName: String {
        switch self {
        case .nes: return "NES"
        case .snes: return "Super Nintendo"
        case .genesis: return "Sega Genesis"
        case .masterSystem: return "Master System"
        case .gameGear: return "Game Gear"
        case .gameBoy: return "Game Boy"
        case .gameBoyColor: return "Game Boy Color"
        case .gameBoyAdvance: return "Game Boy Advance"
        case .nintendoDS: return "Nintendo DS"
        }
    }

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "gb": self = .gameBoy
        case "gbc", "cgb": self = .gameBoyColor
        case "nds": self = .nintendoDS
        case "nes": self = .nes
        case "gba", "agb": self = .gameBoyAdvance
        case "sfc", "smc": self = .snes
        case "md", "gen", "smd": self = .genesis
        case "sms": self = .masterSystem
        case "gg": self = .gameGear
        default: return nil
        }
    }

    var maximumROMSize: Int {
        switch self {
        case .nintendoDS: return 512 * 1024 * 1024
        case .nes: return 16 * 1024 * 1024
        case .gameBoyAdvance: return 32 * 1024 * 1024
        case .snes: return 12 * 1024 * 1024
        case .genesis: return 16 * 1024 * 1024
        case .masterSystem, .gameGear: return 4 * 1024 * 1024
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

    var isColor: Bool { system == .gameBoyColor }
    var systemName: String { system.displayName }
}

extension UTType {
    static let gameBoyROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gb")
    static let gameBoyColorROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gbc")
    static let nintendoDSROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.nds")
    static let nesROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.nes")
    static let gameBoyAdvanceROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gba")
    static let snesROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.sfc")
    static let genesisROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.md")
    static let masterSystemROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.sms")
    static let gameGearROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gg")
}

/// Games live in Documents/Games, which the Files app shows under
/// On My iPhone › Retro Duo. In-game saves sit next to them in Documents/Saves
/// so players can back them up; save states stay private in Application Support.
@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var message: String?

    static let romExtensions: Set<String> = ["nes", "gb", "gbc", "cgb", "gba", "agb", "nds", "sfc", "smc", "md", "gen", "smd", "sms", "gg"]
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
        if let cart = Bundle.main.url(forResource: "RetroDuoSNESTestCart", withExtension: "sfc") {
            list.append(Game(id: "builtin.snestestcart", url: cart, name: "Retro Duo SNES Test Cart",
                             isBuiltIn: true, system: .snes))
        }
        for (resource, ext, id, name, system) in [
            ("RetroDuoGenesisTestCart", "md", "builtin.genesistestcart", "Retro Duo Genesis Test Cart", GameSystem.genesis),
            ("RetroDuoMasterSystemTestCart", "sms", "builtin.smstestcart", "Retro Duo Master System Test Cart", .masterSystem),
            ("RetroDuoGameGearTestCart", "gg", "builtin.ggtestcart", "Retro Duo Game Gear Test Cart", .gameGear),
        ] {
            if let cart = Bundle.main.url(forResource: resource, withExtension: ext) {
                list.append(Game(id: id, url: cart, name: name, isBuiltIn: true, system: system))
            }
        }
        if let cart = Bundle.main.url(forResource: "RetroDuoGBATestCart", withExtension: "gba") {
            list.append(Game(id: "builtin.gbatestcart", url: cart, name: "Retro Duo GBA Test Cart",
                             isBuiltIn: true, system: .gameBoyAdvance))
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
            message = "Couldn't add \(skipped.joined(separator: ", ")). AVYDRIX Play plays NES (.nes), Super Nintendo (.sfc, .smc), Sega Genesis (.md, .gen, .smd), Master System (.sms), Game Gear (.gg), Game Boy (.gb, .gbc), Game Boy Advance (.gba) and Nintendo DS (.nds) files."
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

    // AVYDRIX 2.0 keeps the original resume file and serialization format.
    // A second generation is held separately; manual slots and battery RAM are untouched.
    private var verifiedResumeGames = Set<String>()

    func hasProtectedResume(for game: Game) -> Bool {
        let files = FileManager.default
        return ["resume", "resume.backup"].contains {
            files.fileExists(atPath: stateURL(for: game, slot: $0).path)
        }
    }

    func restoreProtectedResume(for game: Game, using load: (Data) -> Bool) -> Bool {
        for slot in ["resume", "resume.backup"] {
            let url = stateURL(for: game, slot: slot)
            guard let data = try? Data(contentsOf: url), data.count >= 32 else { continue }
            guard load(data) else { continue }
            verifiedResumeGames.insert(game.id)
            // Repair the primary checkpoint only after the core confirms it can load the backup.
            if slot == "resume.backup" {
                try? data.write(to: stateURL(for: game, slot: "resume"), options: .atomic)
            }
            return true
        }
        return false
    }

    @discardableResult
    func saveProtectedResume(_ data: Data, for game: Game) -> Bool {
        // Reject empty/truncated core results before touching either generation.
        guard data.count >= 32 else { return false }
        let primary = stateURL(for: game, slot: "resume")
        let backup = stateURL(for: game, slot: "resume.backup")
        let files = FileManager.default
        if files.fileExists(atPath: primary.path) {
            // Preserve an unvalidated legacy checkpoint until the emulator confirms it.
            // Once validated, rotate to the backup before replacing the primary.
            let shouldBackup = verifiedResumeGames.contains(game.id) ||
                               !files.fileExists(atPath: backup.path)
            if shouldBackup {
                guard let older = try? Data(contentsOf: primary), older.count >= 32,
                      (try? older.write(to: backup, options: .atomic)) != nil else { return false }
            }
        }
        let saved = (try? data.write(to: primary, options: .atomic)) != nil
        if saved { verifiedResumeGames.insert(game.id) }
        return saved
    }

    func clearProtectedResume(for game: Game) {
        // Only an explicit in-game Restart removes the auto-resume generations.
        for slot in ["resume", "resume.backup"] {
            try? FileManager.default.removeItem(at: stateURL(for: game, slot: slot))
        }
        verifiedResumeGames.remove(game.id)
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
        case .gameBoyAdvance: return header.count >= 0xC0 && header[header.startIndex + 3] == 0xEA
        case .snes: return size.intValue >= 0x8000  // bsnes works out the layout itself (and strips copier headers)
        case .genesis:
            // Plain dumps say SEGA at 0x100; interleaved .smd files have their own layout.
            return size.intValue >= 0x200 && (url.pathExtension.lowercased() == "smd" ||
                (header.count >= 0x104 && header[header.startIndex + 0x100 ..< header.startIndex + 0x104].elementsEqual("SEGA".utf8)) ||
                (header.count >= 0x104 && header[header.startIndex + 0x101 ..< header.startIndex + 0x104].elementsEqual("SEG".utf8)))
        case .masterSystem, .gameGear: return size.intValue >= 0x2000
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
