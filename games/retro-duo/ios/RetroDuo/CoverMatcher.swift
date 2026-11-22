// AVYDRIX Play - finds a game's box art among the libretro-thumbnails names.
// Copyright 2026 CT Network Studios. GPL v3 or later.
import Foundation

/// Picks the libretro-thumbnails box art for a game, whatever naming style its file uses.
///
/// Box art is named after No-Intro ("Donkey Kong Country (USA) (Rev 2)"), but people's files
/// often use GoodTools tags ("Donkey Kong Country (U) (V1.2) [!]") or no tags at all. Titles are
/// compared without punctuation, case, accents, "the" or "and"/"&" (stored as "_" in the box art
/// names), then the region and revision the file asks for pick between releases. Betas, demos,
/// prototypes and re-releases are only chosen when the file asks for them.
enum CoverMatcher {
    static func bestMatch(for fileName: String, in names: [String]) -> String? {
        var name = fileName.replacingOccurrences(
            of: #"\.(sfc|smc|nes|gb|gbc|gba|agb|nds|md|gen|smd|sms|gg|bin|zip)$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: #"^\d{4}\s*-\s*"#, with: "", options: .regularExpression)
        let (title, tags) = split(name)
        let wanted = key(title)
        guard !wanted.isEmpty else { return nil }
        let wantedRegions = regions(tags)
        let wantedRevision = revision(tags)
        let userText = tags.joined(separator: " ")
        let titleBase = title.components(separatedBy: " - ").first ?? title

        // Tier 0: same title. Tier 1: the box art adds a subtitle ("Donkey Kong Country 2" ->
        // "... 2 - Diddy's Kong Quest"). Tier 2: the file adds one the box art lacks.
        var pool: [(name: String, tier: Int)] = []
        for candidate in names {
            let candidateTitle = split(candidate).title
            let candidateKey = key(candidateTitle)
            if candidateKey == wanted {
                pool.append((candidate, 0))
            } else if candidateTitle.contains(" - "),
                      key(candidateTitle.components(separatedBy: " - ")[0]) == wanted {
                pool.append((candidate, 1))
            } else if title.contains(" - "), key(titleBase) == candidateKey {
                pool.append((candidate, 2))
            }
        }

        func score(_ item: (name: String, tier: Int)) -> Int {
            let candidateTags = split(item.name).tags
            let candidateRegions = regions(Array(candidateTags.prefix(1)))
            var s = item.tier > 0 ? -12 : 0
            let preferred = wantedRegions.isEmpty ? ["usa", "world", "europe", "japan"] : wantedRegions
            let shared = preferred.filter {
                candidateRegions.contains($0) || ($0 != "world" && candidateRegions.contains("world"))
            }
            if !shared.isEmpty {
                s += 20 - (shared.map { regionRank[$0] ?? 4 }.min() ?? 4)
            }
            let candidateRevision = revision(candidateTags) ?? 0
            if let wantedRevision {
                s += candidateRevision == wantedRevision ? 5 : -abs(candidateRevision - wantedRevision)
            } else if candidateRevision == 0 {
                s += 3
            }
            let candidateText = candidateTags.joined(separator: " ")
            for word in unwanted where contains(word, in: candidateText) && !contains(word, in: userText) {
                s -= 30
            }
            if candidateText.range(of: #"\d{4}-\d{2}"#, options: .regularExpression) != nil { s -= 30 }
            return s
        }

        // Highest score wins; on a tie the shorter (plainer) name, then the first listed.
        var best: (name: String, score: Int)?
        for item in pool {
            let s = score(item)
            if let current = best,
               s < current.score || (s == current.score && item.name.count >= current.name.count) {
                continue
            }
            best = (item.name, s)
        }
        return best?.name
    }

    // MARK: - Pieces (internal for tests)

    /// "Title (tag) [tag]" -> ("Title", ["tag", "tag"]), tags lowercased.
    static func split(_ name: String) -> (title: String, tags: [String]) {
        var title = name
        if let bracket = name.range(of: #"\s*[(\[]"#, options: .regularExpression) {
            title = String(name[..<bracket.lowerBound])
        }
        var tags: [String] = []
        var rest = name[...]
        while let open = rest.firstIndex(where: { $0 == "(" || $0 == "[" }) {
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(where: { $0 == ")" || $0 == "]" }) else { break }
            tags.append(rest[after..<close].trimmingCharacters(in: .whitespaces).lowercased())
            rest = rest[rest.index(after: close)...]
        }
        return (title.trimmingCharacters(in: .whitespaces), tags)
    }

    /// Title reduced to letters and digits, ignoring case, accents, "the" and "and"/"&"/"_".
    static func key(_ title: String) -> String {
        var t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        t = t.replacingOccurrences(of: "&", with: " ").replacingOccurrences(of: "_", with: " ")
        t = t.replacingOccurrences(of: #"\band\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #",\s*the$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^the\s+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #",\s*the\s+-"#, with: " -", options: .regularExpression)
        return String(t.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
            .map(Character.init))
    }

    static func regions(_ tags: [String]) -> [String] {
        var out: [String] = []
        for tag in tags {
            for part in tag.components(separatedBy: ",") {
                out += regionCodes[part.trimmingCharacters(in: .whitespaces)] ?? []
            }
        }
        return out
    }

    /// GoodTools "V1.2", "PRG1", "REV01" and No-Intro "Rev 2" / "Rev A" -> 2, 1, 1, 2, 1.
    static func revision(_ tags: [String]) -> Int? {
        for tag in tags {
            for pattern in [#"^v\s*1\.(\d)$"#, #"^rev\s*(\d+)$"#, #"^prg\s*(\d)$"#] {
                if let number = firstGroup(pattern, in: tag), let value = Int(number) { return value }
            }
            if let letter = firstGroup(#"^rev\s*([a-e])$"#, in: tag), let scalar = letter.unicodeScalars.first {
                return Int(scalar.value) - 96
            }
        }
        return nil
    }

    private static let regionRank = ["usa": 0, "world": 1, "europe": 2, "japan": 3]

    private static let regionCodes: [String: [String]] = [
        "u": ["usa"], "us": ["usa"], "usa": ["usa"], "america": ["usa"], "4": ["usa"],
        "e": ["europe"], "eu": ["europe"], "eur": ["europe"], "europe": ["europe"],
        "j": ["japan"], "jp": ["japan"], "jpn": ["japan"], "japan": ["japan"],
        "w": ["world"], "world": ["world"],
        "ue": ["usa", "europe"], "uj": ["usa", "japan"], "ju": ["japan", "usa"], "jue": ["japan", "usa", "europe"],
        "f": ["france"], "france": ["france"], "g": ["germany"], "germany": ["germany"],
        "s": ["spain"], "spain": ["spain"], "i": ["italy"], "italy": ["italy"],
        "k": ["korea"], "korea": ["korea"], "a": ["australia"], "australia": ["australia"],
        "b": ["brazil"], "brazil": ["brazil"], "c": ["china"], "china": ["china"],
    ]

    private static let unwanted = [
        "virtual console", "switch online", "classic mini", "beta", "proto", "demo", "sample", "kiosk",
        "pirate", "unl", "aftermarket", "evercade", "collection", "gamecube", "wii", "nso", "e-reader",
        "alt", "possible proto", "sega channel", "program", "debug",
    ]

    private static func contains(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return text.range(of: "\\b\(escaped)\\b", options: .regularExpression) != nil
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
