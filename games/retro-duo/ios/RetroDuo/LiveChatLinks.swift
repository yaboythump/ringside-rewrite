import Foundation

/// Where each platform's chat for a channel can be opened as a page of its own (the "pop-out"
/// chat), which the lower screen shows while streaming.
enum LiveChatLinks {
    /// A channel name as people type or paste it: "@name", "twitch.tv/name", a full link...
    static func channelName(_ text: String) -> String? {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: name), let host = url.host, !host.isEmpty {
            name = url.path.split(separator: "/").first.map(String.init) ?? ""
        } else if let slash = name.firstIndex(of: "/"), name[..<slash].contains(".") {
            name = name[name.index(after: slash)...].split(separator: "/").first.map(String.init) ?? ""
        }
        if name.hasPrefix("@") { name.removeFirst() }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return name
    }

    static func twitch(_ channel: String) -> URL? {
        channelName(channel).flatMap { URL(string: "https://www.twitch.tv/popout/\($0.lowercased())/chat?darkpopout") }
    }

    static func kick(_ channel: String) -> URL? {
        channelName(channel).flatMap { URL(string: "https://kick.com/popout/\($0.lowercased())/chat") }
    }

    static func youTube(videoID: String) -> URL? {
        URL(string: "https://www.youtube.com/live_chat?is_popout=1&dark_theme=1&v=\(videoID)")
    }

    /// A YouTube video ID from a pasted watch, live or youtu.be link (or the ID itself).
    static func youTubeVideoID(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVideoID(trimmed) { return trimmed }
        guard let components = URLComponents(string: trimmed), let host = components.host?.lowercased() else { return nil }
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, isVideoID(v) { return v }
        let parts = components.path.split(separator: "/").map(String.init)
        if host.hasSuffix("youtu.be"), let first = parts.first, isVideoID(first) { return first }
        if let index = parts.firstIndex(where: { $0 == "live" || $0 == "shorts" || $0 == "embed" }),
           index + 1 < parts.count, isVideoID(parts[index + 1]) { return parts[index + 1] }
        return nil
    }

    /// The page that redirects to a YouTube channel's current live video.
    static func youTubeLivePage(_ channel: String) -> URL? {
        guard let name = channelName(channel) else { return nil }
        if name.hasPrefix("UC"), name.count == 24 { return URL(string: "https://www.youtube.com/channel/\(name)/live") }
        return URL(string: "https://www.youtube.com/@\(name)/live")
    }

    /// The live video's ID in that page's HTML (its canonical link points at the video while live).
    static func youTubeVideoID(inLivePage html: String) -> String? {
        for marker in ["<link rel=\"canonical\" href=\"https://www.youtube.com/watch?v=", "\"videoDetails\":{\"videoId\":\""] {
            guard let range = html.range(of: marker) else { continue }
            let id = String(html[range.upperBound...].prefix(11))
            if isVideoID(id) { return id }
        }
        return nil
    }

    static func isVideoID(_ text: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return text.count == 11 && text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
