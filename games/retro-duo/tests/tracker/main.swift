// Checks the second-screen tracker (ios/RetroDuo/Tracker.swift) against Trackers.json with
// memory laid out the way each game keeps it. Build with:
//   swiftc Tracker.swift CoverMatcher.swift tests/tracker/main.swift -o tracker_test
//   tracker_test ios/RetroDuo/Resources/Trackers.json
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print((condition ? "ok   " : "FAIL ") + message)
    if !condition { failures += 1 }
}
func expect<T: Equatable>(_ value: T?, _ wanted: T, _ message: String) {
    check(value == wanted, value == wanted ? message : "\(message): got \(value.map { "\($0)" } ?? "nil"), wanted \(wanted)")
}

guard CommandLine.arguments.count > 1, let data = FileManager.default.contents(atPath: CommandLine.arguments[1]) else {
    print("usage: tracker_test Trackers.json"); exit(2)
}
let library: TrackerLibrary
do { library = try TrackerLibrary.load(data) } catch { print("FAIL Trackers.json doesn't load: \(error)"); exit(1) }
check(library.games.count >= 10, "every game definition loads (\(library.games.count))")
check(Set(library.games.map(\.id)).count == library.games.count, "game ids are unique")
expect(library.tables["pokemonGen1"]?.count, 190, "Gen 1 species table has 190 internal ids")
expect(library.tables["pokemonGen2"]?.count, 253, "Gen 2 species table runs to the egg")
let systems: Set<String> = ["nes", "snes", "gameBoy", "gameBoyColor", "gameBoyAdvance", "genesis", "masterSystem", "gameGear"]
check(library.games.allSatisfy { !$0.systems.isEmpty && Set($0.systems).isSubset(of: systems) }, "every definition names real systems")

// MARK: Matching file names to definitions

func match(_ name: String, _ system: String) -> String? { library.game(titles: [name], system: system)?.id }
expect(match("Pokemon - Red Version (USA, Europe) (SGB Enhanced)", "gameBoy"), "pokemon-red-blue", "No-Intro Pokémon Red")
expect(match("Pokemon Blue (UE) [S][!]", "gameBoy"), "pokemon-red-blue", "GoodTools Pokémon Blue")
expect(match("Pokémon Yellow", "gameBoyColor"), "pokemon-yellow", "accented Pokémon Yellow on the Game Boy Color")
expect(match("Pokemon - Crystal Version (USA, Europe) (Rev 1)", "gameBoyColor"), "pokemon-crystal", "Pokémon Crystal Rev 1")
expect(match("Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible)", "gameBoyColor"), "pokemon-gold-silver", "Pokémon Silver")
expect(match("Super Mario Bros. (World)", "nes"), "super-mario-bros", "Super Mario Bros.")
check(match("Super Mario Bros. 3 (USA)", "nes") == nil, "Super Mario Bros. 3 isn't taken for the first game")
expect(match("Super Mario World (USA)", "snes"), "super-mario-world", "Super Mario World")
expect(match("Sonic The Hedgehog (USA, Europe)", "genesis"), "sonic-the-hedgehog", "Sonic the Hedgehog")
check(match("Sonic The Hedgehog (USA, Europe)", "masterSystem") == nil, "the Master System Sonic isn't the Genesis one")
check(match("Sonic The Hedgehog 2 (World)", "genesis") == nil, "Sonic 2 isn't Sonic 1")
expect(match("Retro Duo Test Cart", "gameBoyColor"), "retro-duo-test-cart", "built-in Game Boy test cart")
expect(match("Retro Duo Game Gear Test Cart", "gameGear"), "retro-duo-sega-8bit-test-cart", "built-in Game Gear test cart")
check(match("Tetris (World)", "gameBoy") == nil, "games without a definition get none")
expect(library.game(titles: ["My Rom", "Pokemon Red (U)"], system: "gameBoy")?.id, "pokemon-red-blue",
       "any of a game's names can match (display name or file name)")

// MARK: Where each core keeps work RAM

expect(ConsoleRAM.snes.offset(of: 0x7E0577), 0x577, "SNES $7E0577")
expect(ConsoleRAM.snes.offset(of: 0x7F0000), 0x10000, "SNES $7F0000 (second bank)")
expect(ConsoleRAM.snes.offset(of: 0x0015), 0x15, "SNES low-RAM mirror")
check(ConsoleRAM.snes.offset(of: 0x808000) == nil, "SNES ROM isn't work RAM")
expect(ConsoleRAM.genesis.offset(of: 0xFF0000), 1, "Genesis $FF0000 is the high byte of the first word")
expect(ConsoleRAM.genesis.offset(of: 0xFF0001), 0, "Genesis $FF0001 is the low byte")
expect(ConsoleRAM.genesis.offset(of: 0xFFFE12), 0xFE13, "Genesis $FFFE12")
expect(ConsoleRAM.genesis.offset(of: 0xE0FE12), 0xFE13, "Genesis RAM mirror")
check(ConsoleRAM.genesis.offset(of: 0x000200) == nil, "Genesis ROM isn't work RAM")
expect(ConsoleRAM.masterSystem.offset(of: 0xC003), 3, "Master System $C003")
expect(ConsoleRAM.masterSystem.offset(of: 0xE003), 3, "Master System mirror")
check(ConsoleRAM.masterSystem.offset(of: 0x8000) == nil, "Master System ROM isn't work RAM")

// MARK: Reading games

/// A flat 64KB address space (Game Boy, NES), all zero unless set.
struct Memory {
    var bytes = [UInt8](repeating: 0, count: 0x10000)
    subscript(address: Int) -> UInt8 { get { bytes[address] } set { bytes[address] = newValue } }
    mutating func put(_ address: Int, _ values: [UInt8]) { for (i, v) in values.enumerated() { bytes[address + i] = v } }
    var reader: TrackerMemory { { [bytes] in $0 <= 0xFFFF ? bytes[Int($0)] : nil } }
}
func stats(_ snapshot: TrackerSnapshot) -> [String: String] {
    Dictionary(uniqueKeysWithValues: snapshot.stats.map { ($0.label, $0.value) })
}
func pokemonText(_ text: String) -> [UInt8] {
    text.map { c -> UInt8 in
        if let a = c.asciiValue, (65...90).contains(a) { return 0x80 + a - 65 }
        if let a = c.asciiValue, (97...122).contains(a) { return 0xA0 + a - 97 }
        return 0x7F
    } + [0x50]
}

// Pokémon Red: two in the party, three badges, $12,345, 12:05:09.
do {
    let game = library.games.first { $0.id == "pokemon-red-blue" }!
    var ram = Memory()
    ram[0xD163] = 2
    ram.put(0xD16B, [0x99, 0x00, 0x14])          // Bulbasaur (internal id $99), 20 HP
    ram[0xD16B + 0x21] = 12                      // level 12
    ram.put(0xD16B + 0x22, [0x00, 0x21])         // max HP 33
    ram.put(0xD197, [0x54, 0x00, 0x00])          // Pikachu, fainted
    ram[0xD197 + 0x21] = 9
    ram.put(0xD197 + 0x22, [0x00, 0x1A])
    ram.put(0xD2B5, pokemonText("BULBY"))
    ram.put(0xD2B5 + 11, pokemonText("PIKACHU"))
    ram[0xD356] = 0b0000_0111
    ram.put(0xD2F7, [0xFF, 0x01])                // 9 caught
    ram.put(0xD30A, [0xFF, 0x0F])                // 12 seen
    ram.put(0xD347, [0x01, 0x23, 0x45])
    ram[0xDA41] = 12; ram[0xDA43] = 5; ram[0xDA44] = 9
    let snapshot = library.snapshot(of: game, memory: ram.reader)
    let s = stats(snapshot)
    expect(s["Badges"], "3 / 8", "Red: badges")
    expect(s["Pokédex"], "9 caught", "Red: Pokédex")
    expect(s["Seen"], "12", "Red: seen")
    expect(s["Money"], "$12,345", "Red: money (BCD)")
    expect(s["Play time"], "12:05:09", "Red: play time")
    expect(snapshot.party.count, 2, "Red: party size")
    expect(snapshot.party.first?.name, "BULBY", "Red: nickname")
    expect(snapshot.party.first?.species, "Bulbasaur", "Red: species from the internal id")
    expect(snapshot.party.first?.level, 12, "Red: level")
    expect(snapshot.party.first?.hp, 20, "Red: HP")
    expect(snapshot.party.first?.maxHP, 33, "Red: max HP")
    expect(snapshot.party.last?.species, "Pikachu", "Red: second member")
    expect(snapshot.party.last?.hp, 0, "Red: a fainted member reads 0 HP")

    ram[0xD163] = 0xFF                           // before a save is loaded RAM is noise
    ram[0xD347] = 0xAB                           // not BCD
    let noise = library.snapshot(of: game, memory: ram.reader)
    check(noise.party.isEmpty, "Red: an impossible party size shows no party")
    check(stats(noise)["Money"] == nil, "Red: money that isn't BCD is left out")
}

// Pokémon Crystal: binary money, Johto + Kanto badges, two-byte hours.
do {
    let game = library.games.first { $0.id == "pokemon-crystal" }!
    var ram = Memory()
    ram[0xDCD7] = 1
    ram[0xDCDF] = 155                             // Cyndaquil (dex number)
    ram[0xDCDF + 0x1F] = 7
    ram.put(0xDCDF + 0x22, [0x00, 0x16])          // 22 HP
    ram.put(0xDCDF + 0x24, [0x00, 0x18])          // of 24
    ram.put(0xDE41, pokemonText("Ember"))
    ram.put(0xD84E, [0x00, 0x0B, 0xB8])           // 3000
    ram[0xD857] = 0xFF; ram[0xD858] = 0x01        // 8 Johto + 1 Kanto
    ram.put(0xD4C4, [0x01, 0x2C]); ram[0xD4C6] = 0; ram[0xD4C7] = 7
    let snapshot = library.snapshot(of: game, memory: ram.reader)
    let s = stats(snapshot)
    expect(s["Money"], "$3,000", "Crystal: money")
    expect(s["Badges"], "9 / 16", "Crystal: badges from both regions")
    expect(s["Play time"], "300:00:07", "Crystal: play time past 255 hours")
    expect(snapshot.party.first?.species, "Cyndaquil", "Crystal: species by dex number")
    expect(snapshot.party.first?.name, "Ember", "Crystal: lower-case nickname")
    expect(snapshot.party.first?.level, 7, "Crystal: level")
    expect(snapshot.party.first?.hp, 22, "Crystal: HP")
    expect(snapshot.party.first?.maxHP, 24, "Crystal: max HP")
}

// Super Mario Bros.: lives and world are stored minus one, score and time as digits.
do {
    let game = library.games.first { $0.id == "super-mario-bros" }!
    var ram = Memory()
    ram[0x075F] = 3; ram[0x075C] = 1               // 4-2
    ram[0x075A] = 2
    ram[0x075E] = 17
    ram.put(0x07DD, [0, 0, 1, 2, 3, 0])
    ram.put(0x07F8, [3, 5, 9])
    ram[0x0756] = 2
    let s = stats(library.snapshot(of: game, memory: ram.reader))
    expect(s["World"], "4-2", "SMB: world")
    expect(s["Lives"], "3", "SMB: lives")
    expect(s["Coins"], "17", "SMB: coins")
    expect(s["Score"], "1,230", "SMB: score digits")
    expect(s["Time"], "359", "SMB: time")
    expect(s["Power"], "Fire", "SMB: power-up")
    ram[0x0756] = 9
    expect(stats(library.snapshot(of: game, memory: ram.reader))["Power"], "—", "SMB: an unknown value shows a dash")
}

// Super Mario World: little-endian 24-bit score kept divided by 10.
do {
    let game = library.games.first { $0.id == "super-mario-world" }!
    var wram = [UInt8](repeating: 0, count: 0x20000)
    wram[0x0DBE] = 4
    wram[0x0F34] = 0x39; wram[0x0F35] = 0x30; wram[0x0F36] = 0x00   // 12345
    wram[0x0019] = 2
    let reader: TrackerMemory = { address in ConsoleRAM.snes.offset(of: address).map { wram[$0] } }
    let s = stats(library.snapshot(of: game, memory: reader))
    expect(s["Lives"], "5", "SMW: lives")
    expect(s["Score"], "123,450", "SMW: score")
    expect(s["Power"], "Cape", "SMW: power-up")
}

// Sonic the Hedgehog: RAM as BlastEm holds it (16-bit words in little-endian order).
do {
    let game = library.games.first { $0.id == "sonic-the-hedgehog" }!
    var logical = [UInt8](repeating: 0, count: 0x10000)   // the 68000's view, big-endian
    logical[0xFE10] = 2; logical[0xFE11] = 1                // Marble Zone act 2
    logical[0xFE12] = 4
    logical[0xFE20] = 0x01; logical[0xFE21] = 0x23          // 291 rings
    logical[0xFE23] = 1; logical[0xFE24] = 5
    logical[0xFE26 ..< 0xFE2A] = [0x00, 0x00, 0x04, 0xD2]   // 1234 -> 12,340
    var words = [UInt16](repeating: 0, count: 0x8000)
    for i in 0..<0x8000 { words[i] = UInt16(logical[2 * i]) << 8 | UInt16(logical[2 * i + 1]) }
    let stored: [UInt8] = words.withUnsafeBytes { Array($0) }  // host (little-endian) order
    let reader: TrackerMemory = { address in ConsoleRAM.genesis.offset(of: address).map { stored[$0] } }
    let s = stats(library.snapshot(of: game, memory: reader))
    expect(s["Zone"], "Marble 2", "Sonic: zone and act")
    expect(s["Rings"], "291", "Sonic: rings (big-endian word)")
    expect(s["Lives"], "4", "Sonic: lives")
    expect(s["Time"], "1:05", "Sonic: time")
    expect(s["Score"], "12,340", "Sonic: score")
}

// Memory that can't be read leaves stats out instead of showing zeros.
do {
    let game = library.games.first { $0.id == "super-mario-bros" }!
    check(library.snapshot(of: game, memory: { _ in nil }).stats.isEmpty, "unreadable memory shows nothing")
}

print(failures == 0 ? "\nall tracker checks passed" : "\n\(failures) tracker check(s) failed")
exit(failures == 0 ? 0 : 1)
