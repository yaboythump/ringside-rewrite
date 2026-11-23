import Foundation
import Security
import UIKit

/// A recently played game, as the home screen widget shows it.
struct ShelfGame: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var system: String
    var playedAt: Date
    /// A small JPEG of the box art, if the game has one.
    var cover: Data?

    /// Opens AVYDRIX Play straight into this game.
    var playURL: URL {
        var components = URLComponents()
        components.scheme = "avydrix"
        components.host = "play"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }
}

/// The last few games played, shared between the app and its widget (built into both).
///
/// They share a Keychain access group: App Groups can't be set up from CI (Apple's API
/// has no way to create one), while every App Store profile already allows the team's
/// Keychain groups.
enum WidgetShelf {
    static let limit = 3
    private static let service = "com.ctnetworkstudios.retroduo.widget"
    private static let account = "recent-games"
    private static let accessGroup = "J4Y8FY6JNZ.com.ctnetworkstudios.retroduo.shared"

    static func load() -> [ShelfGame] {
        for group in [accessGroup, nil] {
            var query = base(group)
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let games = try? JSONDecoder().decode([ShelfGame].self, from: data) {
                return games
            }
        }
        return []
    }

    /// Puts a game at the front of the list (the app calls this when a game opens).
    static func record(id: String, name: String, system: String, cover: UIImage?) {
        var games = load().filter { $0.id != id }
        let thumbnail = cover.flatMap(thumbnailJPEG)
        games.insert(ShelfGame(id: id, name: name, system: system, playedAt: Date(), cover: thumbnail), at: 0)
        save(Array(games.prefix(limit)))
    }

    static func save(_ games: [ShelfGame]) {
        guard let data = try? JSONEncoder().encode(games) else { return }
        // The shared group needs the signed entitlement; a simulator build without a team
        // keeps the list to the app alone.
        for group in [accessGroup, nil] {
            SecItemDelete(base(group) as CFDictionary)
            var item = base(group)
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    private static func base(_ group: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: account]
        if let group { query[kSecAttrAccessGroup] = group }
        return query
    }

    /// At most 240 points on the long side: sharp in a medium widget, ~15 KB.
    private static func thumbnailJPEG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 240 / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.75)
    }
}
