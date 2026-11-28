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
    @State private var replying = false
    @State private var transcribing = false
    @State private var transcriptFailed = false
    @State private var fold = FoldGesture()
    @State private var onDuo = false

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
        .background(CosmicBackground())
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
        .fullScreenCover(isPresented: $replying) {
            ComposeView(replyTo: capsuleID, initialPrompt: Prompts.reply)
        }
        .onHinge { degrees in
            onDuo = true
            var gesture = fold
            let event = gesture.update(degrees)
            fold = gesture
            // Unfolding the phone opens a capsule that's ready.
            guard event == .unfolded, !breaking, let capsule = store.capsule(id: capsuleID),
                  !capsule.isOpened, capsule.canOpen(at: Date()) else { return }
            if capsule.openWhenText != nil { confirmingOpenWhen = true } else { breakSeal(capsule) }
        }
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
            ZStack {
                CapsuleOrb(opened: false, ready: openable && capsule.unlockDate != nil, size: 200,
                           progress: capsule.progress(at: now))
                    .scaleEffect(breaking ? 1.6 : 1)
                    .opacity(breaking ? 0 : 1)
                if breaking { Supernova() }
            }
            .padding(.top, 12)
            Text(capsule.displayTitle)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink)
            if let date = capsule.unlockDate {
                if openable {
                    Text("It has landed. The day has come.")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.gold)
                        .shadow(color: Palette.gold.opacity(0.7), radius: 10)
                } else {
                    Text(CapsuleFormat.countdown(to: date, from: now))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.glow)
                        .shadow(color: Palette.wax.opacity(0.8), radius: 12)
                        .multilineTextAlignment(.center)
                    Text(date.formatted(date: .complete, time: .shortened))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
            } else if let text = capsule.openWhenText {
                Text("Open when \(text)")
                    .font(.system(size: 18, design: .rounded))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.glow)
            }

            if openable {
                Button {
                    if capsule.openWhenText != nil { confirmingOpenWhen = true } else { breakSeal(capsule) }
                } label: {
                    Label("Open the capsule", systemImage: "sparkles")
                }
                .buttonStyle(GlowButtonStyle(colors: [Palette.gold, Color(red: 1.0, green: 0.55, blue: 0.3), Palette.nebula]))
                .disabled(breaking)
                if onDuo {
                    Text("Or fold your iPhone Duo closed, then open it.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
            } else {
                Label("In orbit. No listening early.", systemImage: "lock.fill")
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
                if capsule.replyToID != nil {
                    Label("A reply to your past self", systemImage: "arrowshape.turn.up.left")
                }
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

            SectionTitle(text: "Launched")
            VStack(alignment: .leading, spacing: 6) {
                Text(capsule.createdAt.formatted(date: .long, time: .shortened))
                    .font(.system(size: 16, design: .rounded))
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
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                Text("You recorded this \(CapsuleFormat.ago(capsule.createdAt, from: now)), on \(capsule.createdAt.formatted(date: .long, time: .omitted)).")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.muted)
                if let prompt = capsule.prompt {
                    Text("You were answering: \(prompt)")
                        .font(.system(size: 15, design: .serif).italic())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.gold)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 16)

            if player.missing {
                Label("The recording couldn't be found on this iPhone.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .card()
            } else {
                Button { player.toggle() } label: {
                    OrbButtonFace(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 110,
                                  active: player.isPlaying, colors: [Palette.cyan, Palette.wax])
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play your message")

                VStack(spacing: 4) {
                    Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 0.1))
                        .tint(Palette.cyan)
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

            Button {
                player.stop()
                replying = true
            } label: {
                Label("Reply to your past self", systemImage: "arrowshape.turn.up.left.fill")
            }
            .buttonStyle(GlowButtonStyle(colors: [Palette.gold, Palette.wax, Palette.nebula]))
        }
        .frame(maxWidth: .infinity)
        .onAppear { player.load(store.audioURL(for: capsule)) }
    }

    private func notePane(_ capsule: Capsule) -> some View {
        let note = capsule.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = store.photoURLs(for: capsule).compactMap { UIImage(contentsOfFile: $0.path) }
        let thread = store.thread(for: capsule)
        return VStack(alignment: .leading, spacing: 16) {
            transcriptSection(capsule)

            if !note.isEmpty {
                SectionTitle(text: "Your note")
                Text(note)
                    .font(.system(size: 18, design: .rounded))
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
            if thread.count > 1 {
                SectionTitle(text: "Conversation with yourself")
                VStack(spacing: 10) {
                    ForEach(thread) { item in
                        if item.id == capsule.id {
                            Label("This message · \(item.createdAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.gold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        } else {
                            NavigationLink(value: item.id) {
                                CapsuleRow(capsule: item, now: Date())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transcriptSection(_ capsule: Capsule) -> some View {
        if let transcript = capsule.transcript {
            SectionTitle(text: "What you said")
            Text(transcript)
                .font(.system(size: 17, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        } else if !player.missing {
            Button {
                transcribing = true
                transcriptFailed = false
                Task {
                    let ok = await store.transcribe(capsule, askPermission: true)
                    transcribing = false
                    transcriptFailed = !ok
                }
            } label: {
                HStack(spacing: 10) {
                    if transcribing { ProgressView().tint(Palette.gold) } else { Image(systemName: "text.quote") }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transcribing ? "Writing it out…" : "Read it as text")
                            .font(.system(size: 15, weight: .semibold))
                        Text(transcriptFailed
                             ? "Couldn't write this one out. Speech recognition may be off in Settings, or your language isn't supported on this iPhone."
                             : "Turns your voice message into text, right on this iPhone.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .buttonStyle(.plain)
            .disabled(transcribing)
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


/// The burst of light when a capsule is opened.
struct Supernova: View {
    @State private var go = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white, Palette.gold, Palette.nebula.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: 120))
                .frame(width: 240, height: 240)
                .scaleEffect(go ? 1.8 : 0.2)
                .opacity(go ? 0 : 1)
            Circle()
                .stroke(Palette.gold, lineWidth: 3)
                .frame(width: 200, height: 200)
                .scaleEffect(go ? 2.2 : 0.3)
                .opacity(go ? 0 : 0.9)
            ForEach(0..<14) { i in
                Circle()
                    .fill(i.isMultiple(of: 2) ? Palette.gold : Palette.cyan)
                    .frame(width: 6, height: 6)
                    .offset(x: go ? 150 : 10)
                    .rotationEffect(.degrees(Double(i) / 14 * 360))
                    .opacity(go ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.75)) { go = true } }
    }
}
