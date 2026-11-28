import SwiftUI
import UIKit
import UserNotifications

@main
struct CapsuleDuoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: CapsuleStore
    @State private var starting = !ProcessInfo.processInfo.arguments.contains("-CapsuleSnapshot")

    init() {
        if ProcessInfo.processInfo.arguments.contains("-CapsuleDemo") {
            // A throwaway store so simulator checks never touch real capsules.
            let demo = FileManager.default.temporaryDirectory.appendingPathComponent("DemoCapsules", isDirectory: true)
            try? FileManager.default.removeItem(at: demo)
            let store = CapsuleStore(root: demo)
            store.seedDemo()
            _store = StateObject(wrappedValue: store)
        } else {
            _store = StateObject(wrappedValue: CapsuleStore())
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ShelfView()
                if starting { StartupView().transition(.opacity).zIndex(1) }
            }
                .task {
                    guard starting else { return }
                    try? await Task.sleep(nanoseconds:1_800_000_000)
                    withAnimation(.easeOut(duration:0.35)) { starting=false }
                }
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await DebugSnapshot.runIfAsked() }
        }
    }
}

/// Shows the "capsule unsealed" notification even while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// `-CapsuleSnapshot` saves pictures of the app into its tmp folder, for checking
/// builds on simulators that can't take screenshots themselves.
enum DebugSnapshot {
    @MainActor
    static func runIfAsked() async {
        guard ProcessInfo.processInfo.arguments.contains("-CapsuleSnapshot") else { return }
        #if DEBUG
        CapsuleVerification.runIfAsked()
        #endif
        for (index, delay) in [5.0, 4.0].enumerated() {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            save(name: "snapshot-\(index + 1)")
        }
    }

    @MainActor
    static func save(name: String) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            for window in windows.sorted(by: { $0.windowLevel < $1.windowLevel }) where !window.isHidden {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try? image.pngData()?.write(to: url)
        print("CapsuleDuo snapshot \(name) \(window.bounds.size)")
    }
}
