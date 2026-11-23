import SwiftUI
import UIKit

/// One capsule. Sealed: an envelope and a countdown, nothing else. Opened: your voice on
/// one side of the fold, your note and photos on the other.
struct CapsuleView: View {
    let capsuleID: UUID

    @EnvironmentObject private var store: CapsuleStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = VoicePlayer()
    @State private var confirmingDelete = false
    @State private var confirmingOpenWhen = false
    @State private var breaking = false

    var body: some View {
        Group {
            if let capsule = store.capsule(id: capsuleID) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(capsule, now: context.date)
                }
                .confirmationDialog("Is it time?", isPresented: $confirmingOpenWhen, titleVisibility: .visible) {
                    Button("Yes, open it") { breakSeal(capsule) }
                    Button("Not yet", role: .cancel) {}
                } message: {
                    Text("You sealed this to open when \(capsule.openWhenText ?? "the moment came").")
                }
                .confirmationDialog("Delete this capsule?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete forever", role: .destructive) {
                        player.stop()
                        store.delete(capsule)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(capsule.isOpened ? "The recording, note and photos will be gone." : "It will be deleted without ever being opened.")
                }
            } else {
                Text("This capsule is gone.")
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete capsule", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(Palette.ink)
            }
        }
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private func content(_ capsule: Capsule, now: Date) -> some View {
        if capsule.isOpened {
            DuoSplit {
                listenPane(capsule, now: now)
            } secondary: {
                notePane(capsule)
            }
        } else {
            DuoSplit {
                sealedPane(capsule, now: now)
            } secondary: {
                insidePane(capsule, now: now)
            }
        }
    }

    // MARK: Sealed

    private func sealedPane(_ capsule: Capsule, now: Date) -> some View {
        let openable = capsule.canOpen(at: now)
        return VStack(spacing: 20) {
            EnvelopeMark(opened: false, ready: openable && capsule.unlockDate != nil, size: 140)
                .scaleEffect(breaking ? 1.25 : 1)
                .rotationEffect(.degrees(breaking ? -6 : 0))
                .opacity(breaking ? 0 : 1)
                .padding(.top, 24)
            Text(capsule.displayTitle)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink)
            if let date = capsule.unlockDate {
                if openable {
                    Text("The day has come.")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.wax)
                } else {
                    Text(CapsuleFormat.countdown(to: date, from: now))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.wax)
                    Text(date.formatted(date: .complete, time: .shortened))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
            } else if let text = capsule.openWhenText {
                Text("Open when \(text)")
                    .font(.system(size: 18, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.wax)
            }

            if openable {
                Button {
                    if capsule.openWhenText != nil { confirmingOpenWhen = true } else { breakSeal(capsule) }
                } label: {
                    Label("Break the seal", systemImage: "seal")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(breaking)
            } else {
                Label("Sealed. No listening early.", systemImage: "lock.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func insidePane(_ capsule: Capsule, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Inside")
            VStack(alignment: .leading, spacing: 12) {
                Label("A \(CapsuleFormat.duration(capsule.duration)) voice message", systemImage: "waveform")
                if !capsule.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("A written note", systemImage: "text.alignleft")
                }
                if capsule.photoCount > 0 {
                    Label("\(capsule.photoCount) photo\(capsule.photoCount == 1 ? "" : "s")", systemImage: "photo")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            SectionTitle(text: "Sealed")
            VStack(alignment: .leading, spacing: 6) {
                Text(capsule.createdAt.formatted(date: .long, time: .shortened))
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(Palette.ink)
                Text("by you, \(CapsuleFormat.ago(capsule.createdAt, from: now))")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            if capsule.unlockDate != nil && !capsule.canOpen(at: now) {
                Text("You'll get a notification the moment it unseals, if notifications are on.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    // MARK: Opened

    private func listenPane(_ capsule: Capsule, now: Date) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(capsule.displayTitle)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                Text("You recorded this \(CapsuleFormat.ago(capsule.createdAt, from: now)), on \(capsule.createdAt.formatted(date: .long, time: .omitted)).")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 16)

            if player.missing {
                Label("The recording couldn't be found on this iPhone.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .card()
            } else {
                Button { player.toggle() } label: {
                    ZStack {
                        Circle().fill(Palette.wax).frame(width: 104, height: 104)
                            .shadow(color: Palette.wax.opacity(0.3), radius: 14, y: 6)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.white)
                            .offset(x: player.isPlaying ? 0 : 3)
                    }
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play your message")

                VStack(spacing: 4) {
                    Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 0.1))
                    HStack {
                        Text(CapsuleFormat.duration(player.currentTime))
                        Spacer()
                        Text(CapsuleFormat.duration(player.duration))
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.muted)
                }
            }

            if let openedAt = capsule.openedAt {
                Text("Opened \(openedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { player.load(store.audioURL(for: capsule)) }
    }

    private func notePane(_ capsule: Capsule) -> some View {
        let note = capsule.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = store.photoURLs(for: capsule).compactMap { UIImage(contentsOfFile: $0.path) }
        return VStack(alignment: .leading, spacing: 16) {
            if !note.isEmpty {
                SectionTitle(text: "Your note")
                Text(note)
                    .font(.system(size: 18, design: .serif))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }
            if !photos.isEmpty {
                SectionTitle(text: "Photos")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { item in
                        Image(uiImage: item.element)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            if note.isEmpty && photos.isEmpty {
                VStack(spacing: 10) {
                    EnvelopeMark(opened: true, size: 60)
                    Text("No note with this one. Just your voice.")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            }
        }
    }

    // MARK: Actions

    private func breakSeal(_ capsule: Capsule) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeIn(duration: 0.6)) { breaking = true }
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeOut(duration: 0.4)) {
                store.open(capsule)
                breaking = false
            }
        }
    }
}
