import Foundation
import SwiftUI
import WidgetKit

/// Keeps a copy of every capsule in the app's private iCloud Drive folder, so capsules
/// survive deleting the app or moving to a new iPhone. The folder isn't shown in the
/// Files app, and capsules still can't be opened early.
@MainActor
final class CloudBackup: ObservableObject {
    static let shared = CloudBackup()
    static let containerID = "iCloud.com.ctnetworkstudios.capsuleduo"
    static let enabledKey = "iCloudBackup"

    enum Status: Equatable {
        case off, checking, unavailable, upToDate, working(String)
    }

    @Published private(set) var status: Status = .checking
    @Published private(set) var lastBackup: Date? = UserDefaults.standard.object(forKey: "iCloudLastBackup") as? Date

    private weak var store: CapsuleStore?
    private var root: URL?
    private var started = false

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Connects the store, restores anything missing from iCloud, then backs everything up.
    func start(with store: CapsuleStore) {
        self.store = store
        store.onChange = { [weak self] id, deleted in
            guard let self else { return }
            Task { await self.changed(id: id, deleted: deleted) }
        }
        refreshWidgets()
        guard !started else { return }
        started = true
        Task { await connect(restoring: true) }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            Task { await connect(restoring: true) }
        } else {
            status = .off
        }
    }

    /// Restores capsules found in iCloud that aren't on this iPhone. Returns how many came back.
    @discardableResult
    func restoreNow() async -> Int {
        guard await prepare(), let root, let store else { return 0 }
        status = .working("Looking in iCloud…")
        let localRoot = store.root
        let local = Set(store.capsules.map(\.id.uuidString))
        let restored = await Task.detached(priority: .utility) {
            Self.restore(from: root, into: localRoot, skipping: local)
        }.value
        if restored > 0 { store.load() }
        status = .upToDate
        refreshWidgets()
        return restored
    }

    func backUpNow() async {
        guard await prepare(), let root, let store else { return }
        status = .working("Backing up…")
        let folders = store.capsules.map { store.folder(for: $0.id) }
        await Task.detached(priority: .utility) {
            for folder in folders { Self.copy(folder: folder, into: root) }
        }.value
        markBackedUp()
    }

    // MARK: Private

    private func connect(restoring: Bool) async {
        guard enabled else { status = .off; return }
        if restoring { await restoreNow() }
        await backUpNow()
    }

    private func changed(id: UUID, deleted: Bool) async {
        refreshWidgets()
        guard await prepare(), let root, let store else { return }
        let folder = store.folder(for: id)
        await Task.detached(priority: .utility) {
            let target = root.appendingPathComponent(id.uuidString, isDirectory: true)
            if deleted {
                Self.coordinatedRemove(target)
            } else {
                Self.copy(folder: folder, into: root)
            }
        }.value
        markBackedUp()
    }

    /// Finds the iCloud folder. False when backup is off, iCloud is signed out, or this is a test build.
    private func prepare() async -> Bool {
        guard enabled else { status = .off; return false }
        #if targetEnvironment(simulator)
        status = .unavailable
        return false
        #else
        if ProcessInfo.processInfo.arguments.contains("-CapsuleDemo") { status = .unavailable; return false }
        if let root { return FileManager.default.fileExists(atPath: root.path) }
        guard FileManager.default.ubiquityIdentityToken != nil else { status = .unavailable; return false }
        let id = Self.containerID
        let found = await Task.detached(priority: .utility) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: id) else { return nil }
            let folder = container.appendingPathComponent("Capsules", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }.value
        root = found
        if found == nil { status = .unavailable }
        return found != nil
        #endif
    }

    private func markBackedUp() {
        let now = Date()
        lastBackup = now
        UserDefaults.standard.set(now, forKey: "iCloudLastBackup")
        status = .upToDate
    }

    /// Updates the home and lock screen widgets.
    func refreshWidgets() {
        guard let store else { return }
        let now = Date()
        let sealed = store.capsules.filter { !$0.isOpened && !$0.canOpen(at: now) }
        let next = sealed.filter { $0.unlockDate != nil }.min { ($0.unlockDate ?? .distantFuture) < ($1.unlockDate ?? .distantFuture) }
        let ready = store.capsules.filter { !$0.isOpened && $0.unlockDate != nil && $0.canOpen(at: now) }.count
        let summary = WidgetSummary(nextTitle: next?.displayTitle, nextDate: next?.unlockDate, nextFrom: next?.sender,
                                    readyCount: ready, sealedCount: sealed.count)
        if summary.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: File work (off the main thread)

    /// Copies a capsule folder into iCloud, skipping files that are already there unchanged.
    nonisolated private static func copy(folder: URL, into root: URL) {
        let fm = FileManager.default
        let target = root.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in files {
            let destination = target.appendingPathComponent(file.lastPathComponent)
            if let a = try? fm.attributesOfItem(atPath: file.path), let b = try? fm.attributesOfItem(atPath: destination.path),
               (a[.size] as? Int) == (b[.size] as? Int),
               let changedA = a[.modificationDate] as? Date, let changedB = b[.modificationDate] as? Date, changedB >= changedA {
                continue
            }
            var coordinatorError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinatorError) { url in
                try? fm.removeItem(at: url)
                try? fm.copyItem(at: file, to: url)
            }
        }
    }

    nonisolated private static func coordinatedRemove(_ url: URL) {
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Downloads capsules from iCloud (waiting up to a minute) and copies them into the app.
    nonisolated private static func restore(from root: URL, into localRoot: URL, skipping local: Set<String>) -> Int {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return 0 }
        let missing = folders.filter { UUID(uuidString: $0.lastPathComponent) != nil && !local.contains($0.lastPathComponent) }
        guard !missing.isEmpty else { return 0 }

        func realFiles(in folder: URL) -> [URL] {
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.map { name -> URL in
                // Files that haven't downloaded yet show up as ".name.icloud".
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    return folder.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                }
                return folder.appendingPathComponent(name)
            }
        }

        for folder in missing {
            for file in realFiles(in: folder) { try? fm.startDownloadingUbiquitousItem(at: file) }
        }
        var restored = 0
        var pending = missing
        let deadline = Date().addingTimeInterval(60)
        while !pending.isEmpty && Date() < deadline {
            pending = pending.filter { folder in
                let files = realFiles(in: folder)
                let ready = !files.isEmpty && files.allSatisfy { fm.fileExists(atPath: $0.path) }
                    && files.contains { $0.lastPathComponent == "capsule.json" }
                guard ready else { return true }
                let destination = localRoot.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
                var coordinatorError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinatorError) { url in
                    if (try? fm.copyItem(at: url, to: destination)) != nil { restored += 1 }
                }
                return false
            }
            if !pending.isEmpty { Thread.sleep(forTimeInterval: 1) }
        }
        return restored
    }
}

struct BackupSettings: View {
    @ObservedObject private var backup = CloudBackup.shared
    @AppStorage(CloudBackup.enabledKey) private var enabled = true
    @State private var restoredMessage: String?

    var body: some View {
        Section {
            Toggle("Back up to iCloud", isOn: Binding(get: { enabled }, set: { backup.setEnabled($0) }))
            if enabled {
                LabeledContent("Status", value: statusText)
                Button("Back up now") { Task { await backup.backUpNow() } }
                Button("Restore from iCloud") {
                    Task {
                        let count = await backup.restoreNow()
                        restoredMessage = count == 0
                            ? "Everything in iCloud is already on this iPhone."
                            : "Brought back \(count) capsule\(count == 1 ? "" : "s")."
                    }
                }
            }
        } header: {
            Text("iCloud backup")
        } footer: {
            Text("Keeps a private copy of your capsules in your iCloud, so they come back if you delete the app or get a new iPhone. They still stay sealed.")
        }
        .alert("iCloud", isPresented: Binding(get: { restoredMessage != nil }, set: { if !$0 { restoredMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoredMessage ?? "")
        }
    }

    private var statusText: String {
        switch backup.status {
        case .off: return "Off"
        case .checking: return "Checking…"
        case .unavailable: return "Sign in to iCloud in Settings"
        case .working(let text): return text
        case .upToDate:
            if let date = backup.lastBackup { return "Backed up \(date.formatted(.relative(presentation: .named)))" }
            return "Up to date"
        }
    }
}
