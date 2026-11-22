// Checks CoverMatcher (the app's box art name matching) against real libretro-thumbnails names.
// Build on macOS: swiftc ios/RetroDuo/CoverMatcher.swift tests/cover_matcher/main.swift
// Usage: cover_matcher_test names.tsv expected.tsv
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let namesText = try? String(contentsOfFile: arguments[1], encoding: .utf8),
      let expectedText = try? String(contentsOfFile: arguments[2], encoding: .utf8) else {
    print("usage: cover_matcher_test names.tsv expected.tsv")
    exit(2)
}
var names: [String: [String]] = [:]
for line in namesText.split(separator: "\n") {
    let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
    if parts.count == 2 { names[parts[0], default: []].append(parts[1]) }
}
var failures = 0
for line in expectedText.split(separator: "\n") {
    let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 3 else { continue }
    let found = CoverMatcher.bestMatch(for: parts[1], in: names[parts[0]] ?? []) ?? ""
    if found == parts[2] {
        print("ok   \(parts[1]) -> \(found.isEmpty ? "(none)" : found)")
    } else {
        print("FAIL \(parts[1]) -> \(found.isEmpty ? "(none)" : found), expected \(parts[2].isEmpty ? "(none)" : parts[2])")
        failures += 1
    }
}
print(failures == 0 ? "\nall cover matching checks passed" : "\n\(failures) cover matching check(s) failed")
exit(failures == 0 ? 0 : 1)
