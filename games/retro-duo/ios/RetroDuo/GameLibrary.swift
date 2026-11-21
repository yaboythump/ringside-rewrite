import Foundation
import UniformTypeIdentifiers

struct Game: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isBuiltIn: Bool
    let isColor: Bool

    var systemName: String { isColor ? "Game Boy Color" : "Game Boy" }
}

extension UTType {
    static let gameBoyROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gb")
    static let gameBoyColorROM = UTType(importedAs: "com.ctnetworkstudios.retroduo.gbc")
}

/// Games live in Documents/Games, which the Files app shows under
/// On My iPhone › Retro Duo. In-game saves sit next to them in Documents/Saves
/// so players can back them up; save states stay private in Application Support.
@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var message: String?

    static let romExtensions: Set<String> = ["gb", "gbc", "cgb"]
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
                             isBuiltIn: true, isColor: true))
        }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: gamesFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        list += urls
            .filter { Self.romExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                Game(id: url.lastPathComponent, url: url,
                     name: url.deletingPathExtension().lastPathComponent,
                     isBuiltIn: false,
                     isColor: ["gbc", "cgb"].contains(url.pathExtension.lowercased()))
            }
        games = list
    }

    /// Copies picked or shared files into the library. Files that are not Game Boy cartridges are skipped.
    func importFiles(_ urls: [URL]) {
        var added: [String] = []
        var skipped: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard Self.romExtensions.contains(url.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: url),
                  Self.looksLikeROM(data) else {
                skipped.append(name)
                continue
            }
            let destination = gamesFolder.appendingPathComponent(name)
            if destination.standardizedFileURL != url.standardizedFileURL {
                do {
                    try data.write(to: destination, options: .atomic)
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
            message = "Couldn't add \(skipped.joined(separator: ", ")). Retro Duo plays .gb and .gbc Game Boy files."
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

    /// A real cartridge has a valid header checksum; the console refuses to boot one without it.
    static func looksLikeROM(_ data: Data) -> Bool {
        guard data.count >= 0x150, data.count <= maximumROMSize else { return false }
        let bytes = [UInt8](data.prefix(0x150))
        var checksum: UInt8 = 0
        for index in 0x134...0x14C {
            checksum = checksum &- bytes[index] &- 1
        }
        return checksum == bytes[0x14D]
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
