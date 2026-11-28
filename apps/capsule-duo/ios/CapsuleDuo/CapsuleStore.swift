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
    case noRecording, emptyContent
    var errorDescription: String? {
        switch self {
        case .noRecording: return "The recording could not be found. Please record it again."
        case .emptyContent: return "Add a written note, recording or photo before sealing."
        }
    }
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
        guard recording != nil || !note.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !photos.isEmpty else {throw CapsuleError.emptyContent}
        var capsule = Capsule(id: UUID(), title: title, note: note, createdAt: Date(), lock: lock,
                              openedAt: nil, duration: duration, photoCount: photos.count)
        try fm.createDirectory(at: folder(for: capsule.id), withIntermediateDirectories: true)
        var saved = false
        defer { if !saved {try? fm.removeItem(at:folder(for:capsule.id))} }
        if let recording {
            guard fm.fileExists(atPath: recording.path) else { throw CapsuleError.noRecording }
            try fm.copyItem(at: recording, to: audioURL(for: capsule))
            try fm.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:audioURL(for:capsule).path)
        }
        for (index, data) in photos.enumerated() {
            try data.write(to: folder(for: capsule.id).appendingPathComponent("photo-\(index).jpg"),
                           options: [.atomic, .completeFileProtection])
        }
        capsule.photoCount = photos.count
        try write(capsule)
        saved = true
        if let recording {try? fm.removeItem(at:recording)}
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

    func rescheduleReminders() {
        for capsule in capsules where !capsule.isOpened { scheduleReminder(for:capsule) }
    }

    private func scheduleReminder(for capsule: Capsule) {
        guard let date = capsule.unlockDate, date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "A capsule just unsealed"
        content.body = capsule.title.isEmpty
            ? "You left yourself a message on \(capsule.createdAt.formatted(date: .long, time: .omitted)). It's ready."
            : "“\(capsule.title)” from \(capsule.createdAt.formatted(date: .long, time: .omitted)) is ready to open."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
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
    static func clock(to date:Date,from now:Date) -> String {
        let seconds=max(0,Int(ceil(date.timeIntervalSince(now))))
        return String(format:"%02d:%02d:%02d",seconds/3600,(seconds/60)%60,seconds%60)
    }

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

#if DEBUG
/// Runs only in an isolated simulator directory; never touches the user's store.
enum CapsuleVerification {
    private static func sameManifest(_ actual:Capsule?,_ expected:Capsule) -> Bool {
        guard let actual, actual.id == expected.id, actual.title == expected.title,
              actual.note == expected.note, actual.duration == expected.duration,
              actual.photoCount == expected.photoCount,
              abs(actual.createdAt.timeIntervalSince(expected.createdAt)) < 1 else {return false}
        switch (actual.lock,expected.lock) {
        case let (.date(a),.date(b)): guard abs(a.timeIntervalSince(b)) < 1 else {return false}
        case let (.openWhen(a),.openWhen(b)): guard a == b else {return false}
        default: return false
        }
        switch (actual.openedAt,expected.openedAt) {
        case (nil,nil): return true
        case let (a?,b?): return abs(a.timeIntervalSince(b)) < 1
        default: return false
        }
    }
    @MainActor static func runIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("-CapsuleVerify") else {return}
        let fm=FileManager.default
        let root=fm.temporaryDirectory.appendingPathComponent("Verification-\(UUID().uuidString)")
        var results:[String:Bool]=[:]
        defer {try? fm.removeItem(at:root)}
        do {
            let store=CapsuleStore(root:root)
            let future=Date().addingTimeInterval(3600)
            let letter=try store.seal(title:"Letter",note:"Only a written message.",lock:.date(future),recording:nil,duration:0,photos:[])
            results["standalone_written_message"]=letter.duration == 0 && letter.note == "Only a written message."
            store.open(letter)
            results["future_capsule_cannot_open"]=store.capsule(id:letter.id)?.openedAt == nil
            let bytes=Data([0,1,2,3,255,128])
            let audio=root.appendingPathComponent("legacy-recording.m4a")
            try bytes.write(to:audio)
            let voice=try store.seal(title:"Legacy voice",note:"Original note",lock:.date(Date().addingTimeInterval(-2)),recording:audio,duration:12,photos:[bytes])
            let reloaded=CapsuleStore(root:root)
            // Existing ISO-8601 manifests have whole-second date precision.
            results["legacy_manifest_round_trip"]=sameManifest(reloaded.capsule(id:voice.id),voice) && sameManifest(reloaded.capsule(id:letter.id),letter)
            results["audio_bytes_preserved"]=(try Data(contentsOf:reloaded.audioURL(for:voice))) == bytes
            results["photo_bytes_preserved"]=(try Data(contentsOf:reloaded.photoURLs(for:voice)[0])) == bytes
            reloaded.open(voice)
            results["due_capsule_can_open"]=reloaded.capsule(id:voice.id)?.isOpened == true
            let openWhen=try reloaded.seal(title:"When",note:"A promise",lock:.openWhen("I reach my goal"),recording:nil,duration:0,photos:[])
            results["open_when_compatibility"]=openWhen.canOpen(at:Date()) && openWhen.openWhenText == "I reach my goal"
            do {_ = try reloaded.seal(title:"Empty",note:"  ",lock:.date(future),recording:nil,duration:0,photos:[]);results["empty_capsule_rejected"]=false} catch {results["empty_capsule_rejected"]=true}
            let bad=root.appendingPathComponent("missing.m4a")
            let before=reloaded.capsules.count
            do {_ = try reloaded.seal(title:"Missing",note:"note",lock:.date(future),recording:bad,duration:2,photos:[]);results["failed_seal_is_atomic"]=false} catch {results["failed_seal_is_atomic"]=reloaded.capsules.count == before}
            let loadedAgain=CapsuleStore(root:root)
            results["opening_persists"]=loadedAgain.capsule(id:voice.id)?.isOpened == true
            let now=Date()
            results["countdown_seconds_tick"]=CapsuleFormat.clock(to:now.addingTimeInterval(3661),from:now) == "01:01:01" && CapsuleFormat.clock(to:now.addingTimeInterval(3661),from:now.addingTimeInterval(1)) == "01:01:00"
            for asset in ["EnvelopeEmblem","OpenedEnvelope","MountainSunrise","SunsetSkyline","PurpleGlass"] {results["compiled_asset_\(asset)"]=UIImage(named:asset) != nil}
        } catch {results["unexpected_error"]=false;print("Verification error: \(error)")}
        let output:[String:Any]=["passed":!results.isEmpty && results.values.allSatisfy{$0},"checks":results]
        if let data=try? JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:fm.temporaryDirectory.appendingPathComponent("verification.json"))}
    }
}
#endif
