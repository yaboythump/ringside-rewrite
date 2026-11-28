import Foundation

/// What the home and lock screen widgets show. The app writes it into the shared
/// App Group folder whenever capsules change; the widget only reads it.
/// This file is compiled into both the app and the widget.
struct WidgetSummary: Codable, Equatable {
    var nextTitle: String?
    var nextDate: Date?
    var nextFrom: String?
    var readyCount: Int
    var sealedCount: Int

    static let groupID = "group.com.ctnetworkstudios.capsuleduo"

    static let sample = WidgetSummary(nextTitle: "Birthday, one year out",
                                      nextDate: Date().addingTimeInterval(211 * 86_400),
                                      nextFrom: nil, readyCount: 0, sealedCount: 3)

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSummary? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSummary.self, from: data)
    }

    /// Returns false when there's no shared folder (unsigned simulator builds).
    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Whole days until `date`, rounded up, never below zero.
    static func daysUntil(_ date: Date, from now: Date = Date()) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now) / 86_400)))
    }
}
