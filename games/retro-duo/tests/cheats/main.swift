// Checks cheat-code parsing (ios/RetroDuo/CheatCodes.swift).
//   swiftc CheatCodes.swift tests/cheats/main.swift -o cheats_test && ./cheats_test
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print((condition ? "ok   " : "FAIL ") + message)
    if !condition { failures += 1 }
}
func cheat(_ code: String) -> Cheat { Cheat(name: "test", code: code) }

check(CheatCodes.lines("  015001c0 \n\n  82003cd0   0063 \r\n") == ["015001C0", "82003CD0 0063"], "lines are trimmed, upper-cased and blank lines dropped")
check(CheatCodes.entry(cheat("aaa-bbb-ccc\nddd-eee-fff")) == "AAA-BBB-CCC\nDDD-EEE-FFF", "a cheat's entry keeps one code per line")

// SNES (bsnes wants lower case)
check(CheatCodes.snesCodes(cheat("7E0DBE09")) == ["7e0dbe09"], "SNES Pro Action Replay")
check(CheatCodes.snesCodes(cheat("DD6B-6F00\nC2A4-6D0F")) == ["dd6b-6f00", "c2a4-6d0f"], "SNES Game Genie, two lines")
check(CheatCodes.snesCodes(cheat("7e0dbe=09")) == ["7e0dbe=09"], "SNES address=value")
check(CheatCodes.snesCodes(cheat("7E0DBE0")) == nil, "a short SNES code is refused")
check(CheatCodes.snesCodes(cheat("GGGG-HHHH")) == nil, "letters that aren't hex are refused")

// Sega RAM codes
check(CheatCodes.segaRAMWrites(cheat("FFFE12:0009"), genesis: true) == [.init(address: 0xFFFE12, bytes: [0x00, 0x09])], "Genesis 16-bit Action Replay")
check(CheatCodes.segaRAMWrites(cheat("fffe20:99"), genesis: true) == [.init(address: 0xFFFE20, bytes: [0x99])], "Genesis 8-bit write")
check(CheatCodes.segaRAMWrites(cheat("FFFE120009\nFFFE2000FF"), genesis: true)?.count == 2, "Genesis codes without colons, two lines")
check(CheatCodes.segaRAMWrites(cheat("AB12-CD34"), genesis: true) == nil, "a Genesis Game Genie code is refused (not supported yet)")
check(CheatCodes.segaRAMWrites(cheat("00C010:09"), genesis: false) == [.init(address: 0xC010, bytes: [0x09])], "Master System Action Replay")
check(CheatCodes.segaRAMWrites(cheat("C010:09"), genesis: false) == [.init(address: 0xC010, bytes: [0x09])], "short Master System form")
check(CheatCodes.segaRAMWrites(cheat("00C01009"), genesis: false) == [.init(address: 0xC010, bytes: [0x09])], "Master System without a colon")
check(CheatCodes.segaRAMWrites(cheat("008000:09"), genesis: false) == nil, "a Master System write outside RAM is refused")

for system in ["gameBoy", "gameBoyColor", "nes", "snes", "gameBoyAdvance", "nintendoDS", "genesis", "masterSystem", "gameGear"] {
    check(!CheatCodes.help(system: system).contains("doesn't take"), "\(system) explains which codes it takes")
}

// Storage round trip
let id = "test-\(UUID().uuidString)"
let saved = [Cheat(name: "Lives", code: "015001C0"), Cheat(name: "Off", code: "SXIOPO", enabled: false)]
CheatStore.save(saved, for: id)
check(CheatStore.load(id) == saved, "cheats are saved per game")
CheatStore.save([], for: id)
check(CheatStore.load(id).isEmpty, "deleting the last cheat clears the game's list")

withCStrings(["a", "bc"]) { pointers in
    check(pointers.count == 2 && String(cString: pointers[1]!) == "bc", "strings are handed to C intact")
}

print(failures == 0 ? "\nall cheat checks passed" : "\n\(failures) cheat check(s) failed")
exit(failures == 0 ? 0 : 1)
