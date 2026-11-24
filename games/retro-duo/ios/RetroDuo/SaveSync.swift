import Combine
import Foundation

/// Keeps in-game saves and save states in the app's private iCloud folder, so they follow
/// the player to another iPhone (or come back after reinstalling).
///
/// Two-way and file by file: whichever copy is newer wins. Nothing is ever deleted: a save
/// removed on one device stays in iCloud and on the others.
enum SaveSyncPlan {
    /// Copies needed so both sides end up with the newest version of every file. Dates within
    /// `tolerance` count as the same (iCloud rounds them).
    static func plan(local: [String: Date], cloud: [String: Date], tolerance: TimeInterval = 2)
        -> (upload: [String], download: [String]) {
        var upload: [String] = []
        var download: [String] = []
        for (name, localDate) in local {
            if let cloudDate = cloud[name] {
                if localDate.timeIntervalSince(cloudDate) > tolerance { upload.append(name) }
                else if cloudDate.timeIntervalSince(localDate) > tolerance { download.append(name) }
            } else {
                upload.append(name)
            }
        }
        for name in cloud.keys where local[name] == nil { download.append(name) }
        return (upload.sorted(), download.sorted())
    }

    /// Files worth syncing: saves, states and their previews, not hidden or temporary files.
    static func syncable(_ name: String) -> Bool {
        guard !name.hasPrefix("."), !name.hasSuffix(".tmp") else { return false }
        return name.hasSuffix(".sav") || name.hasSuffix(".state") || name.hasSuffix(".png") || name.hasSuffix(".srm")
    }
}

/// The file work, off the main thread. `folders` pairs each local folder with its name in iCloud.
final class SaveSyncEngine {
    static let containerID = "iCloud.com.ctnetworkstudios.retroduo"

    struct Result {
        var uploaded = 0
        var downloaded = 0
        /// Files iCloud hasn't brought to this device yet (picked up next time).
        var waiting = 0
    }

    enum Failure: Error { case unavailable }

    let folders: [(local: URL, cloudName: String)]
    private let files = FileManager()

    init(folders: [(local: URL, cloudName: String)]) {
        self.folders = folders
    }

    /// Call off the main thread: finding the iCloud folder can take a moment.
    func run() throws -> Result {
        guard let container = files.url(forUbiquityContainerIdentifier: Self.containerID) else { throw Failure.unavailable }
        return run(container: container)
    }

    /// The sync itself, against any folder standing in for the iCloud container (tests use one).
    func run(container: URL) -> Result {
        var result = Result()
        for folder in folders {
            let cloud = container.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folder.cloudName, isDirectory: true)
            try? files.createDirectory(at: cloud, withIntermediateDirectories: true)
            try? files.createDirectory(at: folder.local, withIntermediateDirectories: true)
            let localDates = dates(in: folder.local)
            var cloudDates: [String: Date] = [:]
            for item in (try? files.contentsOfDirectory(at: cloud, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let name = item.lastPathComponent
                // Not downloaded yet: iCloud keeps a ".name.icloud" stand-in.
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    let real = String(name.dropFirst().dropLast(".icloud".count))
                    if SaveSyncPlan.syncable(real) {
                        try? files.startDownloadingUbiquitousItem(at: cloud.appendingPathComponent(real))
                        result.waiting += 1
                    }
                    continue
                }
                guard SaveSyncPlan.syncable(name),
                      let date = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                cloudDates[name] = date
            }
            let plan = SaveSyncPlan.plan(local: localDates, cloud: cloudDates)
            for name in plan.upload where copy(folder.local.appendingPathComponent(name), to: cloud.appendingPathComponent(name),
                                                date: localDates[name]) {
                result.uploaded += 1
            }
            for name in plan.download where copy(cloud.appendingPathComponent(name), to: folder.local.appendingPathComponent(name),
                                                  date: cloudDates[name]) {
                result.downloaded += 1
            }
        }
        return result
    }

    private func dates(in folder: URL) -> [String: Date] {
        var dates: [String: Date] = [:]
        for item in (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let name = item.lastPathComponent
            guard SaveSyncPlan.syncable(name),
                  let date = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            dates[name] = date
        }
        return dates
    }

    /// Copies through a file coordinator (iCloud may be using the file) and keeps the source's
    /// date, so the next sync sees both copies as the same.
    private func copy(_ source: URL, to target: URL, date: Date?) -> Bool {
        var copied = false
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: target,
                                       options: .forReplacing, error: &error) { reading, writing in
            guard let data = try? Data(contentsOf: reading) else { return }
            do {
                try data.write(to: writing, options: .atomic)
                if let date { try? files.setAttributes([.modificationDate: date], ofItemAtPath: writing.path) }
                copied = true
            } catch {}
        }
        return copied && error == nil
    }
}

/// The app's side of save sync: whether it's on, what happened last, and when to run.
@MainActor
final class SaveSync: ObservableObject {
    static let shared = SaveSync()
    static let enabledKey = "avydrix.icloud.enabled"

    @Published private(set) var status = "Not synced yet"
    @Published private(set) var syncing = false
    private var folders: [(local: URL, cloudName: String)] = []
    private var again = false

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
            if newValue { sync() } else { status = "Off" }
        }
    }

    func configure(saves: URL, states: URL) {
        folders = [(saves, "Saves"), (states, "States")]
    }

    /// Runs a sync in the background (a request while one runs is queued once).
    func sync() {
        guard enabled, !folders.isEmpty else { return }
        // UI tests run without iCloud; don't let them touch it.
        guard !ProcessInfo.processInfo.arguments.contains("-RetroDuoUITests") else { status = "Off during tests"; return }
        guard !syncing else { again = true; return }
        syncing = true
        status = "Syncing…"
        let engine = SaveSyncEngine(folders: folders)
        Task.detached(priority: .utility) {
            let outcome = Result { try engine.run() }
            await MainActor.run {
                self.finish(outcome)
            }
        }
    }

    private func finish(_ outcome: Swift.Result<SaveSyncEngine.Result, Error>) {
        syncing = false
        switch outcome {
        case .success(let result):
            let time = Date().formatted(date: .omitted, time: .shortened)
            var parts: [String] = []
            if result.uploaded > 0 { parts.append("\(result.uploaded) up") }
            if result.downloaded > 0 { parts.append("\(result.downloaded) down") }
            if result.waiting > 0 { parts.append("\(result.waiting) still downloading") }
            status = "Synced at \(time)" + (parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")")
        case .failure:
            status = "iCloud isn't available: sign in to iCloud with iCloud Drive on in Settings."
        }
        if again {
            again = false
            sync()
        }
    }
}
