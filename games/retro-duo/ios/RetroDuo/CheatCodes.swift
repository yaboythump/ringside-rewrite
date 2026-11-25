import Foundation

/// One cheat as the player typed it: a name and one or more codes, one per line.
struct Cheat: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var code: String
    var enabled = true
}

/// Parsing and per-console rules for cheat codes. Pure Foundation (tests/cheats builds it alone).
enum CheatCodes {
    /// The code's lines: trimmed, upper-cased, inner runs of spaces collapsed, blanks dropped.
    static func lines(_ code: String) -> [String] {
        code.split(whereSeparator: \.isNewline).compactMap { raw in
            let words = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
            let line = words.joined(separator: " ").uppercased()
            return line.isEmpty ? nil : line
        }
    }

    /// The text a core's cheat engine gets for one cheat: its lines joined with newlines.
    static func entry(_ cheat: Cheat) -> String { lines(cheat.code).joined(separator: "\n") }

    /// SNES (bsnes) codes, lower-case: Game Genie "xxxx-xxxx", Pro Action Replay "aaaaaavv",
    /// or "aaaaaa=vv". nil when any line is something else.
    static func snesCodes(_ cheat: Cheat) -> [String]? {
        let result = lines(cheat.code).map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
        guard !result.isEmpty else { return nil }
        for line in result {
            let hex = line.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "=", with: "")
            guard hex.count == 8, hex.allSatisfy(\.isHexDigit) else { return nil }
            let gameGenie = line.count == 9 && Array(line)[4] == "-"
            let raw = line.count == 9 && Array(line)[6] == "="
            guard line.count == 8 || gameGenie || raw else { return nil }
        }
        return result
    }

    /// A RAM write a Sega Action Replay code makes every frame.
    struct RAMWrite: Equatable {
        var address: UInt32
        var bytes: [UInt8]
    }

    /// Genesis "FFxxxx:yyyy" (16-bit) or "FFxxxx:yy"; Master System / Game Gear "00Cxxx:yy",
    /// "Cxxx:yy" or "00Cxxxyy". The colon is optional. nil when any line is something else.
    static func segaRAMWrites(_ cheat: Cheat, genesis: Bool) -> [RAMWrite]? {
        var writes: [RAMWrite] = []
        for line in lines(cheat.code) {
            let hex = line.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
            guard hex.allSatisfy(\.isHexDigit) else { return nil }
            if genesis {
                guard hex.count == 10 || hex.count == 8, hex.hasPrefix("FF"),
                      let address = UInt32(hex.prefix(6), radix: 16),
                      let value = UInt32(hex.dropFirst(6), radix: 16) else { return nil }
                let bytes: [UInt8] = hex.count == 10 ? [UInt8(value >> 8), UInt8(value & 0xFF)] : [UInt8(value)]
                writes.append(RAMWrite(address: address, bytes: bytes))
            } else {
                let body: Substring
                switch hex.count {
                case 8 where hex.hasPrefix("00"): body = hex.dropFirst(2)
                case 6: body = Substring(hex)
                default: return nil
                }
                guard let address = UInt32(body.prefix(4), radix: 16), (0xC000...0xDFFF).contains(address),
                      let value = UInt8(body.dropFirst(4), radix: 16) else { return nil }
                writes.append(RAMWrite(address: address, bytes: [value]))
            }
        }
        return writes.isEmpty ? nil : writes
    }

    /// What codes a console takes, for the cheats screen.
    static func help(system: String) -> String {
        switch system {
        case "gameBoy", "gameBoyColor": return "Game Genie (XXX-YYY-ZZZ) or GameShark (01VVAAAA) codes."
        case "nes": return "Game Genie (6 or 8 letters), Pro Action Rocky, or RAM codes like 0075:09."
        case "snes": return "Game Genie (XXXX-XXXX) or Pro Action Replay (7E0DBE09) codes."
        case "gameBoyAdvance": return "GameShark, Action Replay or CodeBreaker codes. Put multi-line codes in one cheat."
        case "nintendoDS": return "Action Replay DS codes: lines of two 8-digit words, like 02000100 00000063."
        case "genesis": return "Action Replay RAM codes like FFFE12:0009. Game Genie codes aren't supported yet."
        case "masterSystem", "gameGear": return "Action Replay RAM codes like 00C010:09. Game Genie codes aren't supported yet."
        default: return "This console doesn't take cheat codes yet."
        }
    }
}

/// Each game's cheats, kept on this device.
enum CheatStore {
    static func key(_ gameID: String) -> String { "avydrix.cheats.\(gameID)" }

    static func load(_ gameID: String) -> [Cheat] {
        guard let data = UserDefaults.standard.data(forKey: key(gameID)),
              let cheats = try? JSONDecoder().decode([Cheat].self, from: data) else { return [] }
        return cheats
    }

    static func save(_ cheats: [Cheat], for gameID: String) {
        if cheats.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(gameID))
        } else if let data = try? JSONEncoder().encode(cheats) {
            UserDefaults.standard.set(data, forKey: key(gameID))
        }
    }
}

/// Calls `body` with the strings as an array of C strings (valid only during the call).
func withCStrings<R>(_ strings: [String], _ body: ([UnsafePointer<CChar>?]) -> R) -> R {
    let pointers = strings.map { strdup($0) }
    defer { pointers.forEach { free($0) } }
    return body(pointers.map { UnsafePointer($0) })
}
