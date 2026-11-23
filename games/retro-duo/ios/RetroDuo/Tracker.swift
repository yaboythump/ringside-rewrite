import Foundation

// The second-screen tracker: reads a running game's work RAM and turns it into stats and a
// party list, from per-game definitions in Trackers.json. Pure Foundation so the test in
// tests/tracker can build it on its own.

/// Where a libretro core's work RAM sits in the console's own address space.
enum ConsoleRAM {
    /// $7E0000-$7FFFFF, and the $0000-$1FFF mirror.
    case snes
    /// $FF0000-$FFFFFF (mirrored from $E00000), kept as 16-bit words in the host's
    /// little-endian order, so each byte pair is swapped.
    case genesis
    /// $C000-$FFFF: 8KB, mirrored.
    case masterSystem

    /// Offset into the core's RAM buffer for a console address, or nil outside work RAM.
    func offset(of address: UInt32) -> Int? {
        switch self {
        case .snes:
            if (0x7E_0000...0x7F_FFFF).contains(address) { return Int(address - 0x7E_0000) }
            return address < 0x2000 ? Int(address) : nil
        case .genesis:
            guard (0xE0_0000...0xFF_FFFF).contains(address) else { return nil }
            return Int(address & 0xFFFF) ^ 1
        case .masterSystem:
            guard (0xC000...0xFFFF).contains(address) else { return nil }
            return Int(address & 0x1FFF)
        }
    }
}

/// Reads one byte at a console address; nil where nothing can be read.
typealias TrackerMemory = (UInt32) -> UInt8?

struct TrackerLibrary: Decodable {
    /// Named lists of names, such as the Pokémon species in a game's internal order.
    var tables: [String: [String]] = [:]
    var games: [TrackerGame]

    static func load(_ data: Data) throws -> TrackerLibrary {
        try JSONDecoder().decode(TrackerLibrary.self, from: data)
    }

    /// The definition for a game, matched on its title (ignoring region and revision tags,
    /// case, accents and punctuation) and system.
    func game(titles: [String], system: String) -> TrackerGame? {
        let keys = Set(titles.map { CoverMatcher.key(CoverMatcher.split($0).title) })
        return games.first { game in
            game.systems.contains(system) && game.titles.contains { keys.contains(CoverMatcher.key($0)) }
        }
    }

    func snapshot(of game: TrackerGame, memory: TrackerMemory) -> TrackerSnapshot {
        var snapshot = TrackerSnapshot()
        for stat in game.stats {
            if let value = stat.text(memory: memory) { snapshot.stats.append(.init(label: stat.label, value: value)) }
        }
        if let party = game.party { snapshot.party = party.members(memory: memory, tables: tables) }
        return snapshot
    }
}

struct TrackerSnapshot: Equatable {
    struct Stat: Equatable, Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    struct Member: Equatable, Identifiable {
        var slot: Int
        var name: String
        var species: String
        var level: Int
        var hp: Int
        var maxHP: Int
        var id: Int { slot }
    }

    var stats: [Stat] = []
    var party: [Member] = []
}

struct TrackerGame: Decodable {
    var id: String
    var title: String
    var systems: [String]
    /// Titles this definition is for, as they appear in file names.
    var titles: [String]
    var stats: [TrackerStat] = []
    var party: TrackerParty?
}

/// One number read from memory.
struct TrackerRead: Decodable {
    enum Kind: String, Decodable {
        /// Unsigned binary, `length` bytes (default 1).
        case le, be
        /// Packed BCD, two digits a byte, most significant first.
        case bcd
        /// One decimal digit a byte, most significant first.
        case digits
        /// How many bits are set across `length` bytes (badges, Pokédex).
        case bits
    }

    var address: String
    var type: Kind = .le
    var length: Int = 1
    /// Added to the raw number (a game that stores lives minus one).
    var add: Int = 0
    /// Multiplies after adding (a score kept divided by 10).
    var multiply: Int = 1
    /// Minimum digits, zero-padded (the seconds of a clock).
    var pad: Int = 0
    /// Labels for particular values ("0": "Small").
    var names: [String: String]?

    private enum CodingKeys: String, CodingKey { case address, type, length, add, multiply, pad, names }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        type = try c.decodeIfPresent(Kind.self, forKey: .type) ?? .le
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 1
        add = try c.decodeIfPresent(Int.self, forKey: .add) ?? 0
        multiply = try c.decodeIfPresent(Int.self, forKey: .multiply) ?? 1
        pad = try c.decodeIfPresent(Int.self, forKey: .pad) ?? 0
        names = try c.decodeIfPresent([String: String].self, forKey: .names)
        guard TrackerRead.parse(address) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .address, in: c, debugDescription: "not a hex address: \(address)")
        }
        guard (1...8).contains(length) || (type == .bits && (1...64).contains(length)) else {
            throw DecodingError.dataCorruptedError(forKey: .length, in: c, debugDescription: "bad length \(length)")
        }
    }

    static func parse(_ hex: String) -> UInt32? {
        let digits = hex.hasPrefix("$") ? String(hex.dropFirst()) : hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return UInt32(digits, radix: 16)
    }

    /// The number, or nil if any byte can't be read or a BCD / digit byte isn't decimal.
    func value(memory: TrackerMemory, offset: Int = 0) -> Int? {
        guard let base = TrackerRead.parse(address) else { return nil }
        var bytes: [UInt8] = []
        for i in 0..<length {
            guard let byte = memory(UInt32(Int(base) + offset + i)) else { return nil }
            bytes.append(byte)
        }
        var raw = 0
        switch type {
        case .le: for byte in bytes.reversed() { raw = raw << 8 | Int(byte) }
        case .be: for byte in bytes { raw = raw << 8 | Int(byte) }
        case .bcd:
            for byte in bytes {
                let high = Int(byte >> 4), low = Int(byte & 0xF)
                guard high < 10, low < 10 else { return nil }
                raw = raw * 100 + high * 10 + low
            }
        case .digits:
            for byte in bytes {
                guard byte < 10 else { return nil }
                raw = raw * 10 + Int(byte)
            }
        case .bits: raw = bytes.reduce(0) { $0 + $1.nonzeroBitCount }
        }
        return (raw + add) * multiply
    }

    func text(memory: TrackerMemory) -> String? {
        guard let value = value(memory: memory) else { return nil }
        if let names {
            return names[String(value)] ?? "—"
        }
        if pad > 0 {
            let digits = String(value)
            return String(repeating: "0", count: max(0, pad - digits.count)) + digits
        }
        return TrackerRead.grouped(value)
    }

    /// 1234567 -> "1,234,567" (fixed separators, the same on every device and in tests).
    static func grouped(_ value: Int) -> String {
        let digits = Array(String(abs(value)))
        var out = ""
        for (i, digit) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return (value < 0 ? "-" : "") + out
    }
}

/// One line on the tracker: a single read, or several joined ("1-2", "12:05:09").
struct TrackerStat: Decodable {
    var label: String
    var read: TrackerRead?
    var parts: [TrackerRead]?
    var separator: String?
    /// Shown as "value / max".
    var max: Int?
    var prefix: String?
    var suffix: String?

    func text(memory: TrackerMemory) -> String? {
        var body: String
        if let parts, !parts.isEmpty {
            var pieces: [String] = []
            for part in parts {
                guard let piece = part.text(memory: memory) else { return nil }
                pieces.append(piece)
            }
            body = pieces.joined(separator: separator ?? " ")
        } else if let read, let value = read.text(memory: memory) {
            body = value
        } else {
            return nil
        }
        if let max { body += " / \(max)" }
        return (prefix ?? "") + body + (suffix ?? "")
    }
}

/// A list of party members (a Pokémon team): `count` at one address, then fixed-size records.
struct TrackerParty: Decodable {
    struct Field: Decodable {
        var offset: Int
        var type: TrackerRead.Kind?
        var length: Int?
        /// For species: the name table and the value of its first entry.
        var table: String?
        var base: Int?
    }

    struct Names: Decodable {
        var address: String
        var stride: Int
        var length: Int
        var charset: String
    }

    var count: String
    var limit: Int
    var first: String
    var stride: Int
    var species: Field
    var level: Field
    var hp: Field
    var maxHP: Field
    var nickname: Names?

    func members(memory: TrackerMemory, tables: [String: [String]]) -> [TrackerSnapshot.Member] {
        guard let countAddress = TrackerRead.parse(self.count), let size = memory(countAddress),
              Int(size) <= limit, let start = TrackerRead.parse(first) else { return [] }
        var members: [TrackerSnapshot.Member] = []
        for slot in 0..<Int(size) {
            let record = Int(start) + slot * stride
            func number(_ field: Field) -> Int? {
                var bytes: [UInt8] = []
                for i in 0..<(field.length ?? 1) {
                    guard let byte = memory(UInt32(record + field.offset + i)) else { return nil }
                    bytes.append(byte)
                }
                let order: [UInt8] = field.type == .be ? bytes : Array(bytes.reversed())
                return order.reduce(0) { $0 << 8 | Int($1) }
            }
            guard let id = number(self.species), let levelValue = number(self.level),
                  let hpValue = number(self.hp), let maxValue = number(self.maxHP) else { return [] }
            var speciesName = "#\(id)"
            if let table = self.species.table.flatMap({ tables[$0] }) {
                let index = id - (self.species.base ?? 0)
                if table.indices.contains(index) { speciesName = table[index] }
            }
            var name = speciesName
            if let nickname, let nameStart = TrackerRead.parse(nickname.address) {
                var bytes: [UInt8] = []
                for i in 0..<nickname.length {
                    guard let byte = memory(nameStart + UInt32(slot * nickname.stride + i)) else { break }
                    bytes.append(byte)
                }
                let decoded = TrackerText.decode(bytes, charset: nickname.charset)
                if !decoded.isEmpty { name = decoded }
            }
            members.append(.init(slot: slot, name: name, species: speciesName, level: levelValue, hp: hpValue, maxHP: maxValue))
        }
        return members
    }
}

enum TrackerText {
    /// Game text to a string. "pokemon": the Game Boy Pokémon games' character set, ending at $50.
    static func decode(_ bytes: [UInt8], charset: String) -> String {
        guard charset == "pokemon" else { return "" }
        var out = ""
        for byte in bytes {
            if byte == 0x50 { break }
            if let character = pokemon[byte] { out.append(character) }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static let pokemon: [UInt8: String] = {
        var map: [UInt8: String] = [0x7F: " ", 0xE0: "'", 0xE3: "-", 0xE6: "?", 0xE7: "!", 0xE8: ".",
                                    0xEF: "♂", 0xF1: "×", 0xF5: "♀", 0xF4: ",", 0xF3: "/"]
        for (i, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { map[0x80 + UInt8(i)] = String(letter) }
        for (i, letter) in "abcdefghijklmnopqrstuvwxyz".enumerated() { map[0xA0 + UInt8(i)] = String(letter) }
        for digit in 0...9 { map[0xF6 + UInt8(digit)] = String(digit) }
        return map
    }()
}
