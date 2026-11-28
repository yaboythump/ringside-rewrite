import PhotosUI
import SwiftUI
import UIKit

/// Recording sits on one side of the fold; the note, photos and lock on the other.
struct ComposeView: View {
    var initialFocus: String = "Record"
    /// Set when this capsule answers an earlier one.
    var replyTo: UUID? = nil
    /// A question to start with (replies and the yearly ritual).
    var initialPrompt: String? = nil
    @FocusState private var noteFocused: Bool
    enum LockKind: String, CaseIterable, Identifiable {
        case date = "On a date"
        case openWhen = "Open when…"
        var id: String { rawValue }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case month = "1 month", halfYear = "6 months", year = "1 year", fiveYears = "5 years"
        var id: String { rawValue }
        var components: DateComponents {
            switch self {
            case .month: return DateComponents(month: 1)
            case .halfYear: return DateComponents(month: 6)
            case .year: return DateComponents(year: 1)
            case .fiveYears: return DateComponents(year: 5)
            }
        }
    }

    static let openWhenIdeas = [
        "I'm having a hard day",
        "I need a laugh",
        "I reach my goal",
        "I'm stressed about money",
        "it's my birthday",
        "I doubt myself",
    ]

    @EnvironmentObject private var store: CapsuleStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var player = VoicePlayer()

    @State private var title = ""
    @State private var note = ""
    @State private var lockKind: LockKind = .date
    @State private var unlockDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var openWhen = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photos: [Data] = []
    @State private var confirmingSeal = false
    @State private var confirmingDiscard = false
    @State private var sealing = false
    @State private var errorMessage: String?
    @State private var prompt: String?
    @State private var mediaMode: MediaMode = .voice
    @State private var videoURL: URL?
    @State private var videoDuration: TimeInterval = 0
    @State private var showingCamera = false
    @State private var forSomeone = false
    @State private var recipientName = ""
    @State private var shareItem: ShareFile?
    @AppStorage("dearTomorrowName") private var displayName = ""

    enum MediaMode: String, CaseIterable, Identifiable {
        case voice = "Voice", video = "Video"
        var id: String { rawValue }
    }

    private var hasMessage: Bool {
        mediaMode == .video ? videoURL != nil : recorder.hasRecording
    }
    @State private var fold = FoldGesture()
    @State private var onDuo = false

    private var minimumDate: Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    }

    private var canSeal: Bool {
        guard hasMessage, !sealing else { return false }
        if forSomeone && recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if lockKind == .openWhen {
            return !openWhen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return unlockDate > Date()
    }

    private var lockDescription: String {
        switch lockKind {
        case .date:
            return "You won't be able to listen until \(unlockDate.formatted(date: .long, time: .shortened))."
        case .openWhen:
            return "You can open it when \(openWhen.trimmingCharacters(in: .whitespacesAndNewlines)). Try to wait for the real moment."
        }
    }

    var body: some View {
        NavigationStack {
            DuoSplit {
                if initialFocus == "Record" { recordPane } else { detailsPane }
            } secondary: {
                if initialFocus == "Record" { detailsPane } else { recordPane }
            }
            .background(CosmicBackground())
            .navigationTitle("New capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasMessage || !note.isEmpty { confirmingDiscard = true } else { close() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Launch") { confirmingSeal = true }
                        .fontWeight(.semibold)
                        .disabled(!canSeal)
                }
            }
            .confirmationDialog("Throw this capsule away?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard recording", role: .destructive) { close() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Seal this capsule?", isPresented: $confirmingSeal) {
                Button("Seal it") { seal() }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text(lockDescription)
            }
            .alert("Couldn't seal", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if sealing { SealingOverlay() }
            }
        }
        .tint(Palette.wax)
        .interactiveDismissDisabled(hasMessage)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraRecorder { url in
                showingCamera = false
                guard let url else { return }
                if let old = videoURL { try? FileManager.default.removeItem(at: old) }
                videoURL = url
                Task { videoDuration = await VideoInfo.duration(of: url) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $shareItem, onDismiss: { dismiss() }) { item in
            ShareSheet(url: item.url)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .onChange(of: recorder.state) { _, state in
            if state == .recorded, let url = recorder.fileURL { player.load(url) }
        }
        .onDisappear { player.stop() }
        .onAppear {
            if initialFocus == "Write" { noteFocused = true }
            if prompt == nil { prompt = initialPrompt }
            if title.isEmpty, let replyTo, let original = store.capsule(id: replyTo) {
                title = "Reply: \(original.displayTitle)"
            }
        }
        .onHinge { degrees in
            onDuo = true
            var gesture = fold
            let event = gesture.update(degrees)
            fold = gesture
            // Folding the phone closed seals the capsule.
            if event == .folded, canSeal { seal() }
        }
    }

    // MARK: Recording side

    private var recordPane: some View {
        VStack(spacing: 22) {
            SectionTitle(text: "Your message")
            if CameraRecorder.isAvailable && recorder.state != .recording {
                Picker("Message type", selection: $mediaMode) {
                    ForEach(MediaMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if recorder.state != .denied {
                PromptCard(prompt: $prompt)
            }
            if mediaMode == .video {
                videoSection
            } else {
            Waveform(levels: recorder.levels, active: recorder.state == .recording)
                .frame(height: 70)

            Text(CapsuleFormat.duration(recorder.state == .recorded ? (player.duration > 0 ? player.duration : recorder.elapsed) : recorder.elapsed))
                .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)

            switch recorder.state {
            case .idle, .failed:
                recordButton
                Text(recorder.state == .failed ? "Recording didn't start. Try again." : "Tap to start. Up to 10 minutes.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            case .recording:
                Button { recorder.stop() } label: {
                    OrbButtonFace(symbol: "stop.fill", size: 96, active: true)
                }
                .accessibilityLabel("Stop recording")
                Text("Recording… tap to stop")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.nebula)
            case .recorded:
                HStack(spacing: 28) {
                    Button { player.toggle() } label: {
                        OrbButtonFace(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 72,
                                      active: player.isPlaying, colors: [Palette.cyan, Palette.wax])
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Listen back")
                    Button {
                        player.stop()
                        recorder.discard()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Record again").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Palette.ink)
                    }
                }
                Text("Listen back now. After you seal it, you won't hear it again until it opens.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.muted)
            case .denied:
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Palette.muted)
                Text("Dear Tomorrow needs the microphone to record your message.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(GlowButtonStyle())
            }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var videoSection: some View {
        if let videoURL {
            VideoMessage(url: videoURL)
                .id(videoURL)
                .frame(maxHeight: 360)
            Button {
                player.stop()
                showingCamera = true
            } label: {
                Label("Record again", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Palette.ink)
            Text("Watch it back now. After you seal it, it stays hidden until it opens.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.muted)
        } else {
            Button {
                player.stop()
                showingCamera = true
            } label: {
                OrbButtonFace(symbol: "video.fill", size: 96)
            }
            .accessibilityLabel("Record a video")
            Text("Tap to record a video. Up to 10 minutes.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
        }
    }

    private var recordButton: some View {
        Button {
            player.stop()
            Task { await recorder.start() }
        } label: {
            OrbButtonFace(symbol: "mic.fill", size: 96)
        }
        .accessibilityLabel("Start recording")
    }

    // MARK: Details side

    private var detailsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(text: "Label")
            TextField("Give it a name (optional)", text: $title)
                .font(.system(size: 17, design: .rounded))
                .textInputAutocapitalization(.sentences)
                .card()

            SectionTitle(text: "Who is it for?")
            VStack(alignment: .leading, spacing: 12) {
                Picker("For", selection: $forSomeone) {
                    Text("Future me").tag(false)
                    Text("Someone else").tag(true)
                }
                .pickerStyle(.segmented)
                if forSomeone {
                    TextField("Their name", text: $recipientName)
                        .font(.system(size: 16, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
                    TextField("Your name, as they'll see it", text: $displayName)
                        .font(.system(size: 16, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
                    Text("After you seal it, you'll send it by Messages, AirDrop or email. They'll need Dear Tomorrow, and it stays sealed for them until the day comes.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
            }
            .card()

            SectionTitle(text: "When it opens")
            VStack(alignment: .leading, spacing: 14) {
                Picker("Unlocks", selection: $lockKind) {
                    ForEach(LockKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if lockKind == .date {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Preset.allCases) { preset in
                                Chip(text: preset.rawValue) {
                                    unlockDate = Calendar.current.date(byAdding: preset.components, to: Date()) ?? unlockDate
                                }
                            }
                        }
                    }
                    DatePicker("Opens", selection: $unlockDate, in: minimumDate..., displayedComponents: [.date, .hourAndMinute])
                        .foregroundStyle(Palette.ink)
                } else {
                    TextField("Open when…", text: $openWhen)
                        .font(.system(size: 16, design: .rounded))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
                    FlowChips(items: Self.openWhenIdeas) { openWhen = $0 }
                }
            }
            .card()

            SectionTitle(text: "A note to go with it")
            TextField("Write anything you want your future self to read", text: $note, axis: .vertical)
                .focused($noteFocused)
                .lineLimit(4...12)
                .font(.system(size: 16, design: .rounded))
                .card()

            SectionTitle(text: "Photos")
            VStack(alignment: .leading, spacing: 12) {
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { item in
                                if let image = UIImage(data: item.element) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Label(photos.isEmpty ? "Add up to 4 photos" : "Change photos", systemImage: "photo.on.rectangle.angled")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            if onDuo && canSeal {
                Label("Or just fold your iPhone Duo closed to seal it", systemImage: "rectangle.portrait.and.arrow.forward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.gold)
                    .frame(maxWidth: .infinity)
            }

            Button { confirmingSeal = true } label: {
                Label("Seal & launch", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(!canSeal)

            if !hasMessage {
                Text("Record your message first, then seal it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Actions

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let jpeg = PhotoPrep.jpeg(from: data) {
                    loaded.append(jpeg)
                }
            }
            photos = loaded
        }
    }

    private func seal() {
        player.stop()
        let lock: Capsule.Lock = lockKind == .date
            ? .date(unlockDate)
            : .openWhen(openWhen.trimmingCharacters(in: .whitespacesAndNewlines))
        let isVideo = mediaMode == .video
        let duration = isVideo ? videoDuration : (player.duration > 0 ? player.duration : recorder.elapsed)
        let recipient = forSomeone ? recipientName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let taken: URL?
        if isVideo {
            taken = videoURL
            videoURL = nil
        } else {
            taken = recorder.takeFile()
        }
        guard let file = taken else {
            errorMessage = CapsuleError.noRecording.localizedDescription
            return
        }
        do {
            let capsule = try store.seal(title: title, note: note, lock: lock, recording: file, duration: duration,
                                         photos: photos, prompt: prompt, replyTo: replyTo,
                                         isVideo: isVideo, recipient: recipient)
            if recipient != nil {
                let url = try store.exportFile(for: capsule, from: displayName)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    shareItem = ShareFile(url: url)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { sealing = true }
        Task {
            if lockKind == .date { await store.requestNotificationPermission() }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // Capsules for someone else close after the share sheet instead.
            if !forSomeone { dismiss() }
        }
    }

    private func close() {
        player.stop()
        recorder.discard()
        if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        dismiss()
    }
}

/// The capsule launching into the future after you seal it.
struct SealingOverlay: View {
    @State private var appear = false
    @State private var launch = false

    var body: some View {
        ZStack {
            CosmicBackground().opacity(appear ? 1 : 0)
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    // Engine trail.
                    SwiftUI.Capsule()
                        .fill(LinearGradient(colors: [Palette.nebula.opacity(0), Palette.nebula, Palette.gold, .white],
                                             startPoint: .bottom, endPoint: .top))
                        .frame(width: 26, height: launch ? 380 : 0)
                        .blur(radius: 6)
                        .offset(y: launch ? 150 : 40)
                        .opacity(launch ? 0.9 : 0)
                    CapsuleOrb(opened: false, size: 170)
                        .scaleEffect(appear ? (launch ? 0.18 : 1) : 1.8)
                        .offset(y: launch ? -340 : 0)
                        .opacity(appear ? 1 : 0)
                }
                .frame(height: 220)
                VStack(spacing: 8) {
                    Text(launch ? "Launched into the future" : "Sealed")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.glow)
                        .shadow(color: Palette.wax.opacity(0.8), radius: 14)
                        .contentTransition(.opacity)
                    Text("See you on the other side.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Palette.muted)
                        .opacity(launch ? 1 : 0)
                }
                .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { appear = true }
            withAnimation(.easeIn(duration: 0.8).delay(0.45)) { launch = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
        }
        .accessibilityLabel("Capsule sealed and launched")
    }
}

struct Waveform: View {
    let levels: [Float]
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { item in
                SwiftUI.Capsule()
                    .fill(active ? AnyShapeStyle(Palette.glow) : AnyShapeStyle(Palette.ink.opacity(0.2)))
                    .shadow(color: active ? Palette.wax.opacity(0.8) : .clear, radius: 4)
                    .frame(width: 4, height: max(4, CGFloat(item.element) * 70))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

struct Chip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(SwiftUI.Capsule().fill(.white.opacity(0.08)))
                .overlay(SwiftUI.Capsule().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Chips that wrap onto new lines.
struct FlowChips: View {
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Chip(text: item) { pick(item) }
            }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
