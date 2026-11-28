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
    @State private var composeFocus = "Record"
    @State private var destination = "Home"
    @AppStorage("dearTomorrowName") private var displayName = ""
    @State private var profile = false
    @State private var selected: UUID?
    @State private var showingAbout = false
    @State private var startedDemo = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                DuoSplit {
                    if destination == "Home" { primary(now: context.date) }
                    else { collection(now: context.date) }
                } secondary: {
                    if destination == "Home" { secondary(now: context.date) }
                }
            }
            .background(CosmicBackground())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar.background(Palette.paper) }
            .sheet(isPresented: $profile) {
                NavigationStack {
                    Form { TextField("Your first name", text: $displayName) }
                        .navigationTitle("Your profile")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { profile = false } } }
                }
            }
            .navigationDestination(item: $selected) { id in
                CapsuleView(capsuleID: id)
            }
        }
        .tint(Palette.wax)
        .fullScreenCover(isPresented: $composing) {
            ComposeView(initialFocus: composeFocus)
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .task { startDemoIfAsked() }
    }

    // MARK: Panes

    @ViewBuilder
    private func primary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                HStack {
                    Button { profile = true } label: { Image(systemName: "person.crop.circle").font(.title) }
                    Spacer()
                    Button { destination = "Scheduled" } label: { Image(systemName: "bell").font(.title2) }
                    Button { showingAbout = true } label: { Image(systemName: "gearshape").font(.title2) }
                }.foregroundStyle(Palette.gold)
                ZStack(alignment: .bottom) {
                    Image(systemName: "envelope").font(.system(size: 58, weight: .ultraLight))
                    Image(systemName: "clock.fill").font(.system(size: 25)).padding(5)
                        .background(Circle().fill(Palette.paper)).offset(y: 6)
                }
                    .foregroundStyle(Palette.gold)
                    .shadow(color: Palette.gold.opacity(0.65), radius: 18)
                Text("Dear Tomorrow")
                    .font(.system(size: 34, weight: .medium, design: .serif).italic())
                    .foregroundStyle(Palette.gold)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("MESSAGES TO YOUR FUTURE SELF")
                    .font(.caption2.weight(.medium)).tracking(2)
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting(now))
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.ink)
                Text("Leave a thought, a plan, a promise or a reminder for the person you’ll become.")
                    .foregroundStyle(Palette.muted)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                actionTile("Record", "Voice Message", "mic", highlighted: true) { openComposer("Record") }
                actionTile("Write", "A Note", "pencil") { openComposer("Write") }
                actionTile("Seal & Send", "Choose a Date", "calendar") { openComposer("Schedule") }
                actionTile("My Vault", "All Capsules", "lock.square") { destination = "Vault" }
            }

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

            HStack {
                Text("Upcoming Deliveries").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Button("See All ›") { destination = "Scheduled" }.font(.subheadline).foregroundStyle(Palette.gold)
            }
            if sealed.isEmpty {
                Text("No upcoming deliveries").font(.subheadline).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).card()
            } else {
                rows(Array(sealed.prefix(1)), now: now)
            }
            HStack(spacing: 8) {
                statistic("envelope", "Total Capsules", store.capsules.count)
                statistic("lock", "Sealed", store.capsules.filter { !$0.isOpened }.count)
                statistic("envelope.open", "Delivered", opened.count)
            }
            Text("“One day, your past will call.”")
                .font(.system(size: 20, design: .serif).italic())
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(LinearGradient(colors: [Palette.nebula.opacity(0.6), Palette.paper], startPoint: .bottomLeading, endPoint: .topTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 18))

        }
    }

    private func greeting(_ now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let greeting = hour < 12 ? "Good Morning" : hour < 18 ? "Good Afternoon" : "Good Evening"
        return displayName.isEmpty ? greeting : greeting + ", " + displayName
    }

    private func openComposer(_ focus: String) {
        composeFocus = focus
        composing = true
    }

    private func actionTile(_ title: String, _ subtitle: String, _ symbol: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 27, weight: .medium))
                    .foregroundStyle(highlighted ? Color.purple.opacity(0.85) : Palette.gold)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity).frame(height: 82)
            .background(RoundedRectangle(cornerRadius: 17).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(highlighted ? Color.purple : Palette.line, lineWidth: highlighted ? 2 : 1))
            .shadow(color: highlighted ? .purple.opacity(0.65) : .clear, radius: 8)
        }.buttonStyle(.plain)
    }

    private var navigationBar: some View {
        HStack {
            ForEach(["Home", "Record", "Write", "Scheduled", "Vault"], id: \.self) { item in
                Button {
                    if item == "Record" || item == "Write" { openComposer(item) }
                    else { destination = item }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: ["Home":"house", "Record":"mic", "Write":"pencil", "Scheduled":"calendar", "Vault":"lock.square"][item] ?? "house")
                            .font(.system(size: 23))
                        Text(item).font(.caption2)
                    }.foregroundStyle(destination == item ? Palette.gold : Palette.muted)
                    .frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 28).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.line))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func collection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(destination == "Vault" ? "My Vault" : "Upcoming Deliveries")
                .font(.system(size: 32, design: .serif)).foregroundStyle(Palette.gold)
            let items = destination == "Vault" ? store.capsules : store.capsules.filter { !$0.isOpened }
            if items.isEmpty { Text("No messages yet").foregroundStyle(Palette.muted) }
            rows(items, now: now)
        }
    }

    private func statistic(_ symbol: String, _ label: String, _ count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(Palette.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(count.formatted()).font(.headline).foregroundStyle(Palette.ink)
                Text(label).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
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
            Text("Your story starts here")
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
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Palette.gold.opacity(0.10))
                Image(systemName: capsule.isOpened ? "envelope.open" : ready ? "envelope.badge" : "lock.envelope")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(Palette.gold)
            }
            .frame(width: 56, height: 56)
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
            if !capsule.isOpened, let date = capsule.unlockDate, date > now {
                let seconds = Int(ceil(date.timeIntervalSince(now)))
                Text(String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink).padding(7)
                    .background(SwiftUI.Capsule().fill(Color.purple.opacity(0.4)))
            }
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
                        Text("Dear Tomorrow").font(.system(size: 28, weight: .bold, design: .rounded))
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
