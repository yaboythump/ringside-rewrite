import LocalAuthentication
import Speech
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Transcripts

/// Turns a voice message into text, on this iPhone only. Nothing is sent to a server.
enum Transcriber {
    static func transcribe(_ url: URL, askPermission: Bool) async -> String? {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined && askPermission {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized,
              let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let box = ResumeOnce(continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    box.resume(text.isEmpty ? nil : text)
                } else if error != nil {
                    box.resume(nil)
                }
            }
            box.task = task
        }
    }

    /// Makes sure the continuation is resumed exactly once.
    private final class ResumeOnce: @unchecked Sendable {
        private var continuation: CheckedContinuation<String?, Never>?
        private let lock = NSLock()
        var task: SFSpeechRecognitionTask?

        init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }

        func resume(_ value: String?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}

// MARK: - Prompts

enum Prompts {
    static let all = [
        "What are you worried about right now?",
        "What do you hope has changed by the time you hear this?",
        "What's something you're proud of this week?",
        "Who are the people you can't stop thinking about lately?",
        "What does a normal day look like for you right now?",
        "What's a promise you want to keep?",
        "What would you tell yourself on a hard day?",
        "What are you excited about?",
        "What's a small thing that made you smile today?",
        "What do you want to stop doing?",
        "What's the best advice you've heard recently?",
        "Where do you see yourself when this opens?",
        "What's a song, show or meal you love right now?",
        "What are you afraid you'll forget?",
        "What would make you proud when you hear this?",
        "What do you want to say thank you for?",
        "What's a risk you're thinking about taking?",
        "What's going really well right now?",
        "What do you hope you've let go of?",
        "Describe where you're sitting, right now, in detail.",
    ]

    static let reply = "What would you tell the person who recorded this?"
    static let ritual = "What do you want to remember about this year?"

    static func random(excluding current: String? = nil) -> String {
        all.filter { $0 != current }.randomElement() ?? all[0]
    }
}

/// "Need an idea?" A question to answer, with a button for a different one.
struct PromptCard: View {
    @Binding var prompt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(prompt == nil ? "Need an idea?" : "Your prompt", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.gold)
                Spacer()
                if prompt != nil {
                    Button { prompt = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Palette.muted)
                        .accessibilityLabel("Remove prompt")
                }
            }
            if let prompt {
                Text(prompt)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { prompt = Prompts.random(excluding: prompt) }
            } label: {
                Label(prompt == nil ? "Give me a question" : "Another question", systemImage: "shuffle")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Palette.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Yearly ritual

extension Notification.Name {
    /// Posted when the yearly ritual reminder is tapped, to open a new capsule.
    static let dearTomorrowRitual = Notification.Name("dearTomorrowRitual")
}

enum Ritual {
    static let enabledKey = "ritualEnabled"
    static let occasionKey = "ritualOccasion"   // "birthday" or "newYear"
    static let monthKey = "ritualMonth"
    static let dayKey = "ritualDay"
    static let identifier = "dear-tomorrow-yearly-ritual"

    /// Schedules (or removes) the yearly reminder from the saved settings.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return }
        let birthday = defaults.string(forKey: occasionKey) != "newYear"
        let month = birthday ? max(1, defaults.integer(forKey: monthKey)) : 1
        let day = birthday ? max(1, defaults.integer(forKey: dayKey)) : 1

        let content = UNMutableNotificationContent()
        content.title = birthday ? "Happy birthday. Time for this year's capsule." : "New year, new capsule."
        content.body = "Take two minutes to tell next year's you how this one went."
        content.sound = .default
        content.userInfo = ["ritual": true]
        var parts = DateComponents()
        parts.month = month
        parts.day = day
        parts.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}

struct RitualSettings: View {
    @AppStorage(Ritual.enabledKey) private var enabled = false
    @AppStorage(Ritual.occasionKey) private var occasion = "birthday"
    @AppStorage(Ritual.monthKey) private var month = 1
    @AppStorage(Ritual.dayKey) private var day = 1

    private var birthday: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(year: 2000, month: max(1, month), day: max(1, day))) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.month, .day], from: $0)
                month = parts.month ?? 1
                day = parts.day ?? 1
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Remind me every year", isOn: $enabled)
            if enabled {
                Picker("When", selection: $occasion) {
                    Text("My birthday").tag("birthday")
                    Text("New Year's Day").tag("newYear")
                }
                if occasion == "birthday" {
                    DatePicker("Birthday", selection: birthday, displayedComponents: .date)
                }
            }
        } header: {
            Text("Yearly ritual")
        } footer: {
            Text("Once a year, at 10 AM, you'll get a nudge to record this year's capsule.")
        }
        .onChange(of: enabled) { _, on in
            if on {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    Ritual.reschedule()
                }
            } else {
                Ritual.reschedule()
            }
        }
        .onChange(of: occasion) { _, _ in Ritual.reschedule() }
        .onChange(of: month) { _, _ in Ritual.reschedule() }
        .onChange(of: day) { _, _ in Ritual.reschedule() }
    }
}

// MARK: - Face ID lock

enum AppLock {
    static let enabledKey = "faceIDLock"

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Covers the app with a lock screen whenever it comes back from the background.
struct AppLockGate: ViewModifier {
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
    @State private var checking = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if lockEnabled && locked {
                    LockScreen(checking: checking) { Task { await unlock() } }
                        .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && lockEnabled { locked = true }
                if phase == .active && lockEnabled && locked { Task { await unlock() } }
            }
            .task { if lockEnabled && locked { await unlock() } }
    }

    @MainActor
    private func unlock() async {
        guard !checking else { return }
        checking = true
        let ok = await AppLock.authenticate(reason: "Unlock your capsules")
        checking = false
        if ok { withAnimation(.easeOut(duration: 0.25)) { locked = false } }
    }
}

struct LockScreen: View {
    let checking: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            CosmicBackground()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Palette.gold)
                    .shadow(color: Palette.gold.opacity(0.6), radius: 16)
                Text("Dear Tomorrow is locked")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink)
                Button(action: unlock) {
                    Label("Unlock with \(AppLock.biometryName)", systemImage: "faceid")
                }
                .buttonStyle(GlowButtonStyle(colors: [Palette.gold, Palette.wax, Palette.nebula]))
                .disabled(checking)
            }
        }
    }
}

struct LockSettings: View {
    @AppStorage(AppLock.enabledKey) private var enabled = false
    @State private var failed = false

    var body: some View {
        Section {
            Toggle("Lock with \(AppLock.biometryName)", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    Task {
                        // Confirm it's really you before turning the lock on or off.
                        if await AppLock.authenticate(reason: newValue ? "Turn on the lock" : "Turn off the lock") {
                            enabled = newValue
                        } else {
                            failed = true
                        }
                    }
                }
            ))
        } header: {
            Text("Privacy")
        } footer: {
            Text("Ask for \(AppLock.biometryName) every time you open Dear Tomorrow.")
        }
        .alert("Couldn't confirm it's you", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Make sure a passcode is set up in the Settings app.")
        }
    }
}

// MARK: - Hinge (iPhone Duo)

/// Reports the iPhone Duo hinge angle in degrees (180 = flat open). Other iPhones never report.
struct HingeWatcher: ViewModifier {
    let onChange: (Double) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                if let degrees = context.hinge?.angle.degrees { onChange(degrees) }
            }
        } else {
            content
        }
    }
}

/// Spots a fold-closed (open, then folded past ~75°) or an unfold (closed, then opened past ~140°).
struct FoldGesture {
    enum Event { case folded, unfolded }
    private var wasOpen: Bool?

    mutating func update(_ degrees: Double) -> Event? {
        if degrees >= 140 {
            defer { wasOpen = true }
            return wasOpen == false ? .unfolded : nil
        }
        if degrees <= 75 {
            defer { wasOpen = false }
            return wasOpen == true ? .folded : nil
        }
        return nil
    }
}

extension View {
    func onHinge(_ perform: @escaping (Double) -> Void) -> some View { modifier(HingeWatcher(onChange: perform)) }
}
