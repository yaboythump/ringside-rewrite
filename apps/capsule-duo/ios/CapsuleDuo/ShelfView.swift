import SwiftUI
import UIKit

extension Capsule {
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Message from \(createdAt.formatted(date: .abbreviated, time: .omitted))" : trimmed
    }

    /// How far along the wait is, for the orbit ring. Nil for "Open when…" and opened capsules.
    func progress(at now: Date) -> Double? {
        guard !isOpened, let date = unlockDate else { return nil }
        let total = date.timeIntervalSince(createdAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(createdAt) / total))
    }

    func statusLine(at now: Date) -> String {
        if let openedAt {
            return "Opened \(openedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        switch lock {
        case .openWhen(let text):
            return "Open when \(text)"
        case .date(let date):
            if date <= now { return "Ready to open · sealed \(CapsuleFormat.ago(createdAt, from: now))" }
            return "\(CapsuleFormat.countdown(to: date, from: now)) · \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

/// Home screen: record on one side of the fold, your sealed capsules on the other.
struct ShelfView: View {
    @EnvironmentObject private var store: CapsuleStore
    @State private var composing = false
    @State private var selected: UUID?
    @State private var showingAbout = false
    @State private var startedDemo = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                DuoSplit {
                    primary(now: context.date)
                } secondary: {
                    secondary(now: context.date)
                }
            }
            .background(CosmicBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAbout = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .tint(Palette.ink)
                    .accessibilityLabel("About Capsule Duo")
                }
            }
            .navigationDestination(item: $selected) { id in
                CapsuleView(capsuleID: id)
            }
        }
        .tint(Palette.wax)
        .fullScreenCover(isPresented: $composing) {
            ComposeView()
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .task { startDemoIfAsked() }
    }

    // MARK: Panes

    @ViewBuilder
    private func primary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Capsule Duo")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.85, green: 0.8, blue: 1.0), Palette.nebula],
                                                    startPoint: .leading, endPoint: .trailing))
                    .shadow(color: Palette.wax.opacity(0.7), radius: 14)
                Text("Messages to your future self, sent across time. Once sealed, they stay sealed.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
            }

            Button { composing = true } label: {
                HStack(spacing: 16) {
                    OrbButtonFace(symbol: "mic.fill", size: 46, halo: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Launch a new capsule")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text("Say something to the person you'll be")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .card(glow: Palette.nebula)
            }
            .buttonStyle(.plain)

            let ready = store.capsules.filter { !$0.isOpened && $0.unlockDate != nil && $0.canOpen(at: now) }
            if !ready.isEmpty {
                SectionTitle(text: "Ready to open")
                rows(ready, now: now)
            }

            let openWhen = store.capsules.filter { !$0.isOpened && $0.openWhenText != nil }
            if !openWhen.isEmpty {
                SectionTitle(text: "Open when…")
                rows(openWhen, now: now)
            }
        }
    }

    @ViewBuilder
    private func secondary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            let sealed = store.capsules
                .filter { !$0.isOpened && !$0.canOpen(at: now) }
                .sorted { ($0.unlockDate ?? .distantFuture) < ($1.unlockDate ?? .distantFuture) }
            let opened = store.capsules
                .filter(\.isOpened)
                .sorted { ($0.openedAt ?? .distantPast) > ($1.openedAt ?? .distantPast) }

            if store.capsules.isEmpty {
                emptyState
            } else {
                if !sealed.isEmpty {
                    SectionTitle(text: "In orbit")
                    rows(sealed, now: now)
                }
                if !opened.isEmpty {
                    SectionTitle(text: "Opened")
                    rows(opened, now: now)
                }
                if sealed.isEmpty && opened.isEmpty {
                    Text("Capsules you seal for a date show up here with a countdown.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func rows(_ capsules: [Capsule], now: Date) -> some View {
        VStack(spacing: 12) {
            ForEach(capsules) { capsule in
                Button { selected = capsule.id } label: {
                    CapsuleRow(capsule: capsule, now: now)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            CapsuleOrb(opened: false, size: 120)
                .padding(.top, 20)
            Text("Your sky is empty")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text("Record a message, choose when it comes back to you, and launch it. You won't hear it until it lands.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Simulator checks

    private func startDemoIfAsked() {
        guard !startedDemo else { return }
        startedDemo = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-CapsuleLandscape"),
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
        if args.contains("-CapsuleCompose") {
            composing = true
        } else if args.contains("-CapsuleOpenedDemo") {
            selected = store.capsules.first(where: \.isOpened)?.id
        } else if args.contains("-CapsuleSealedDemo") {
            selected = store.capsules.first(where: { !$0.canOpen(at: Date()) })?.id
        }
    }
}

struct CapsuleRow: View {
    let capsule: Capsule
    let now: Date

    var body: some View {
        let ready = !capsule.isOpened && capsule.unlockDate != nil && capsule.canOpen(at: now)
        HStack(spacing: 14) {
            CapsuleOrb(opened: capsule.isOpened, ready: ready, size: 56, progress: capsule.progress(at: now))
            VStack(alignment: .leading, spacing: 4) {
                Text(capsule.displayTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(capsule.statusLine(at: now))
                    .font(.system(size: 13))
                    .foregroundStyle(ready ? Palette.gold : Palette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.muted)
        }
        .card(glow: ready ? Palette.gold : nil)
        .accessibilityElement(children: .combine)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Capsule Duo").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Record a voice message for your future self, seal it, and open it when the day comes. Made for iPhone Duo: on the open phone, recording sits on one side of the fold and your notes on the other.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("How it works") {
                    Label("Seal a capsule until a date, and you'll get a notification when it unlocks", systemImage: "calendar")
                    Label("Or seal it as “Open when…” and open it when that moment comes", systemImage: "envelope")
                    Label("Sealed means sealed: there's no listening early", systemImage: "lock.fill")
                    Label("Add a written note and photos that appear when you open it", systemImage: "photo.on.rectangle")
                }
                Section("Privacy") {
                    Text("Everything stays on this iPhone. There's no account, no server and no upload. Deleting the app deletes your capsules, so keep it installed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
