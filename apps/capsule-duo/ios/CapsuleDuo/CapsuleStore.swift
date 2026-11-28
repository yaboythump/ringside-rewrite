import Foundation
import UIKit
import UserNotifications

/// One sealed voice message to your future self.
struct Capsule: Codable, Identifiable, Hashable {
    enum Lock: Codable, Hashable {
        /// Stays sealed until this moment.
        case date(Date)
        /// "Open when…": you decide when the moment has come.
        case openWhen(String)
    }

    var id: UUID
    var title: String
    var note: String
    var createdAt: Date
    var lock: Lock
    var openedAt: Date?
    var duration: TimeInterval
    var photoCount: Int

    var isOpened: Bool { openedAt != nil }

    var unlockDate: Date? {
        if case .date(let date) = lock { return date }
        return nil
    }

    var openWhenText: String? {
        if case .openWhen(let text) = lock { return text }
        return nil
    }

    /// Whether the seal may be broken right now.
    func canOpen(at now: Date) -> Bool {
        if isOpened { return true }
        switch lock {
        case .date(let date): return date <= now
        case .openWhen: return true
        }
    }
}

enum CapsuleError: LocalizedError {
    case noRecording
    var errorDescription: String? { "Record a message before sealing the capsule." }
}

/// Keeps every capsule on this iPhone, in Application Support. Nothing is uploaded.
@MainActor
final class CapsuleStore: ObservableObject {
    @Published private(set) var capsules: [Capsule] = []

    let root: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(root: URL? = nil) {
        let fm = FileManager.default
        if let root {
            self.root = root
        } else {
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("Capsules", isDirectory: true)
        }
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
        load()
    }

    // MARK: Files

    func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func audioURL(for capsule: Capsule) -> URL {
        folder(for: capsule.id).appendingPathComponent("voice.m4a")
    }

    func photoURLs(for capsule: Capsule) -> [URL] {
        (0..<capsule.photoCount).map { folder(for: capsule.id).appendingPathComponent("photo-\($0).jpg") }
    }

    private func manifestURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("capsule.json")
    }

    func load() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        capsules = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("capsule.json")) else { return nil }
            return try? decoder.decode(Capsule.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func write(_ capsule: Capsule) throws {
        try FileManager.default.createDirectory(at: folder(for: capsule.id), withIntermediateDirectories: true)
        let data = try encoder.encode(capsule)
        try data.write(to: manifestURL(for: capsule.id), options: [.atomic, .completeFileProtection])
        if let index = capsules.firstIndex(where: { $0.id == capsule.id }) {
            capsules[index] = capsule
        } else {
            capsules.insert(capsule, at: 0)
        }
    }

    // MARK: Actions

    /// Moves the draft recording and photos into a new capsule folder and seals it.
    @discardableResult
    func seal(title: String, note: String, lock: Capsule.Lock,
              recording: URL?, duration: TimeInterval, photos: [Data]) throws -> Capsule {
        let fm = FileManager.default
        var capsule = Capsule(id: UUID(), title: title, note: note, createdAt: Date(), lock: lock,
                              openedAt: nil, duration: duration, photoCount: photos.count)
        try fm.createDirectory(at: folder(for: capsule.id), withIntermediateDirectories: true)
        if let recording {
            guard fm.fileExists(atPath: recording.path) else { throw CapsuleError.noRecording }
            try fm.moveItem(at: recording, to: audioURL(for: capsule))
        }
        for (index, data) in photos.enumerated() {
            try data.write(to: folder(for: capsule.id).appendingPathComponent("photo-\(index).jpg"),
                           options: [.atomic, .completeFileProtection])
        }
        capsule.photoCount = photos.count
        try write(capsule)
        scheduleReminder(for: capsule)
        return capsule
    }

    func open(_ capsule: Capsule) {
        guard var current = capsules.first(where: { $0.id == capsule.id }),
              !current.isOpened, current.canOpen(at: Date()) else { return }
        current.openedAt = Date()
        try? write(current)
    }

    func delete(_ capsule: Capsule) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [capsule.id.uuidString])
        try? FileManager.default.removeItem(at: folder(for: capsule.id))
        capsules.removeAll { $0.id == capsule.id }
    }

    func capsule(id: UUID) -> Capsule? {
        capsules.first { $0.id == id }
    }

    // MARK: Reminders

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func scheduleReminder(for capsule: Capsule) {
        guard let date = capsule.unlockDate, date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "A capsule just unsealed"
        content.body = capsule.title.isEmpty
            ? "You left yourself a message on \(capsule.createdAt.formatted(date: .long, time: .omitted)). It's ready."
            : "“\(capsule.title)” from \(capsule.createdAt.formatted(date: .long, time: .omitted)) is ready to open."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: capsule.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Demo data for simulator checks

    /// `-CapsuleDemo` fills a throwaway store with example capsules.
    func seedDemo() {
        guard capsules.isEmpty else { return }
        let day: TimeInterval = 86_400
        let now = Date()
        let examples: [Capsule] = [
            Capsule(id: UUID(), title: "First week at the new place", note: "The boxes are still everywhere. Remember how scared you were? Look how far you've come.",
                    createdAt: now.addingTimeInterval(-380 * day), lock: .date(now.addingTimeInterval(-2 * day)),
                    openedAt: nil, duration: 94, photoCount: 0),
            Capsule(id: UUID(), title: "Read this on a hard day", note: "",
                    createdAt: now.addingTimeInterval(-40 * day), lock: .openWhen("I'm stressed about money"),
                    openedAt: nil, duration: 61, photoCount: 0),
            Capsule(id: UUID(), title: "Birthday, one year out", note: "",
                    createdAt: now.addingTimeInterval(-5 * day), lock: .date(now.addingTimeInterval(212 * day)),
                    openedAt: nil, duration: 133, photoCount: 0),
            Capsule(id: UUID(), title: "Before the channel launch", note: "Whatever the numbers say, you shipped it. That was the hard part.\n\nGo get a good dinner.",
                    createdAt: now.addingTimeInterval(-200 * day), lock: .date(now.addingTimeInterval(-20 * day)),
                    openedAt: now.addingTimeInterval(-19 * day), duration: 48, photoCount: 0),
        ]
        for capsule in examples { try? write(capsule) }
        capsules.sort { $0.createdAt > $1.createdAt }
    }
}

enum CapsuleFormat {
    /// "Opens in 212 days", "Opens in 5 hours", "Ready to open".
    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "Ready to open" }
        let days = Int(seconds / 86_400)
        if days >= 365 {
            let years = Double(days) / 365
            return years >= 2 ? "Opens in \(Int(years)) years" : "Opens in over a year"
        }
        if days >= 2 { return "Opens in \(days) days" }
        if days == 1 { return "Opens tomorrow" }
        let hours = Int(seconds / 3600)
        if hours >= 1 { return "Opens in \(hours) hour\(hours == 1 ? "" : "s")" }
        let minutes = max(1, Int(seconds / 60))
        return "Opens in \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "2 years ago", "40 days ago".
    static func ago(_ date: Date, from now: Date) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        if days >= 730 { return "\(days / 365) years ago" }
        if days >= 365 { return "a year ago" }
        if days >= 2 { return "\(days) days ago" }
        if days == 1 { return "yesterday" }
        return "today"
    }
}

enum PhotoPrep {
    /// Shrinks a picked photo to at most 2048 points on its long side and stores it as JPEG.
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}
