import AVFoundation
import Photos
import Security
import SwiftUI

/// Streaming services with a known server address (Kick's differs per account, so it stays editable).
enum LiveService: String, CaseIterable, Identifiable {
    case twitch, youtube, kick, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twitch: return "Twitch"
        case .youtube: return "YouTube"
        case .kick: return "Kick"
        case .custom: return "Other"
        }
    }

    var defaultServer: String {
        switch self {
        case .twitch: return "rtmp://ingest.global-contribute.live-video.net/app"
        case .youtube: return "rtmps://a.rtmps.youtube.com:443/live2"
        case .kick: return "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app"
        case .custom: return ""
        }
    }

    /// Whether the lower screen can show this service's chat.
    var hasChat: Bool { self != .custom }

    var chatHelp: String {
        switch self {
        case .youtube: return "Your channel handle (like @name). Or paste the live video's link."
        default: return "Your \(title) channel name."
        }
    }

    var keyHelp: String {
        switch self {
        case .twitch: return "Twitch: Creator Dashboard › Settings › Stream › Primary Stream key."
        case .youtube: return "YouTube: Studio › Create › Go live › Stream › Stream key."
        case .kick: return "Kick: Creator Dashboard › Settings › Stream URL & Key. Paste both: Kick's server address can differ per account."
        case .custom: return "Paste the server address (rtmp:// or rtmps://) and stream key from your service."
        }
    }
}

enum LiveQuality: String, CaseIterable, Identifiable {
    case low, standard, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return "Data saver · 1.5 Mbps"
        case .standard: return "Standard · 3 Mbps"
        case .high: return "High · 4.5 Mbps"
        }
    }
    var bitrate: Int {
        switch self {
        case .low: return 1_500_000
        case .standard: return 3_000_000
        case .high: return 4_500_000
        }
    }
}

/// Stream keys live in the Keychain, one per service, on this device only.
enum StreamKeyStore {
    private static let service = "com.ctnetworkstudios.retroduo.streamkey"

    static func key(for liveService: LiveService) -> String {
        var query = base(liveService)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ key: String, for liveService: LiveService) {
        SecItemDelete(base(liveService) as CFDictionary)
        guard !key.isEmpty else { return }
        var item = base(liveService)
        item[kSecValueData] = Data(key.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func base(_ liveService: LiveService) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: liveService.rawValue]
    }
}

/// Runs the live stream for whichever game is open: wires the game's picture and sound and the
/// microphone into a LiveStreamCore and publishes its state for the UI.
@MainActor
final class LiveStreamer: ObservableObject {
    static let shared = LiveStreamer()

    enum Status: Equatable {
        case off
        case connecting
        case live(since: Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var stats = LiveStreamCore.Stats()
    @Published private(set) var micLive = false
    /// The service being streamed to (while active).
    @Published private(set) var service: LiveService?
    /// That channel's chat, for the lower screen (YouTube's appears once the video is live).
    @Published private(set) var chatURL: URL?
    @Published private(set) var savingClip = false
    /// "Clip saved to Photos" and the like, shown briefly in the game.
    @Published var clipMessage: String?

    static let overlayKey = "avydrix.live.overlay"
    static func chatKey(_ service: LiveService) -> String { "avydrix.live.chat.\(service.rawValue)" }
    /// The open game's tracker card for the stream, and its toasts (set by its session).
    var overlaySource: (@MainActor () -> StreamOverlay?)?
    var announce: ((String) -> Void)?
    private var overlayTimer: Timer?
    private var chatLookup: Task<Void, Never>?

    private var core: LiveStreamCore?
    private var micEngine: AVAudioEngine?
    private var restartAudio: (() -> Void)?
    private var statsTimer: Timer?
    private var wantsMicrophone = false

    var isActive: Bool { core != nil }
    var isLive: Bool { if case .live = status { return true }; return false }

    func frame(pixels: UnsafePointer<UInt32>, width: Int, height: Int, slot: Int) {
        core?.pushVideo(pixels: pixels, width: width, height: height, screen: slot)
    }

    /// Connects and goes live. `screens`: 2 for the DS. `restartAudio` re-opens the game's
    /// sound so a change to the audio session (the microphone) takes effect.
    func start(service: LiveService, server: String, key: String, quality: LiveQuality,
               microphone: Bool, screens: Int, restartAudio: @escaping () -> Void) {
        guard core == nil else { return }
        guard let destination = RTMPDestination(server: server, key: key) else {
            status = .failed(key.trimmingCharacters(in: .whitespaces).isEmpty
                             ? "Paste your \(service.title) stream key first."
                             : "The server address should look like rtmps://server/app.")
            return
        }
        var config = LiveStreamCore.Config(destination: destination)
        config.videoBitrate = quality.bitrate
        config.screens = screens
        let core = LiveStreamCore(config: config)
        core.onState = { [weak self] state in
            Task { @MainActor in self?.coreChanged(state) }
        }
        self.core = core
        self.restartAudio = restartAudio
        self.service = service
        startChat(service)
        status = .connecting
        stats = .init()
        AudioOutput.setStreamSink { [weak core] buffer in core?.pushGameAudio(buffer) }
        wantsMicrophone = microphone
        core.start()
    }

    func stop() {
        guard let core else { return }
        core.stop()
        tearDown()
        status = .off
    }

    /// iOS suspends a backgrounded app, which would drop the connection anyway.
    func stopForBackground() {
        guard core != nil else { return }
        stop()
        status = .failed("The stream ended when AVYDRIX Play left the screen. Go live again when you're back.")
    }

    func dismissError() {
        if case .failed = status { status = .off }
    }

    func setMicrophone(_ on: Bool) {
        guard core != nil else { return }
        if on { Task { await startMicrophone() } } else { stopMicrophone() }
    }

    private func coreChanged(_ state: LiveStreamCore.State) {
        guard core != nil else { return }
        switch state {
        case .connecting:
            status = .connecting
        case .live:
            status = .live(since: Date())
            // Ask for the microphone only once the stream is really on.
            if wantsMicrophone { Task { await startMicrophone() } }
            statsTimer?.invalidate()
            statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let core = self.core else { return }
                    self.stats = core.currentStats
                }
            }
            overlayTimer?.invalidate()
            updateOverlay()
            overlayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateOverlay() }
            }
        case .failed(let message):
            tearDown()
            status = .failed(message)
        case .ended:
            tearDown()
            status = .off
        }
    }

    private func tearDown() {
        statsTimer?.invalidate()
        statsTimer = nil
        overlayTimer?.invalidate()
        overlayTimer = nil
        chatLookup?.cancel()
        chatLookup = nil
        chatURL = nil
        service = nil
        AudioOutput.setStreamSink(nil)
        stopMicrophone()
        core = nil
        restartAudio = nil
    }

    // MARK: Tracker card

    var overlayEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.overlayKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.overlayKey)
            objectWillChange.send()
            updateOverlay()
        }
    }

    private func updateOverlay() {
        core?.setOverlay(overlayEnabled ? overlaySource?() : nil)
    }

    // MARK: Chat

    private func startChat(_ service: LiveService) {
        chatURL = nil
        chatLookup?.cancel()
        let saved = UserDefaults.standard.string(forKey: Self.chatKey(service)) ?? ""
        switch service {
        case .twitch: chatURL = LiveChatLinks.twitch(saved)
        case .kick: chatURL = LiveChatLinks.kick(saved)
        case .custom: break
        case .youtube:
            if let id = LiveChatLinks.youTubeVideoID(saved) {
                chatURL = LiveChatLinks.youTube(videoID: id)
            } else if let page = LiveChatLinks.youTubeLivePage(saved) {
                // YouTube makes the live video a little after the stream starts: look a few times.
                chatLookup = Task { [weak self] in
                    for _ in 0..<12 {
                        try? await Task.sleep(for: .seconds(10))
                        guard !Task.isCancelled else { return }
                        var request = URLRequest(url: page)
                        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
                        if let (data, _) = try? await URLSession.shared.data(for: request),
                           let id = LiveChatLinks.youTubeVideoID(inLivePage: String(decoding: data, as: UTF8.self)) {
                            await MainActor.run { self?.chatURL = LiveChatLinks.youTube(videoID: id) }
                            return
                        }
                    }
                }
            }
        }
    }

    // MARK: Clips

    /// Saves the last 30 seconds of the stream to Photos.
    func saveClip() {
        guard let core, isLive, !savingClip else { return }
        savingClip = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AVYDRIX clip \(UUID().uuidString.prefix(8)).mp4")
        core.saveClip(seconds: 30, to: url) { result in
            Task { @MainActor in
                switch result {
                case .success(let seconds):
                    let saved = await Self.saveToPhotos(url)
                    self.clipMessage = saved ? "🎬 Saved a \(Int(seconds.rounded()))-second clip to Photos"
                                             : "Couldn't save the clip: allow AVYDRIX Play to add to Photos in Settings."
                case .failure:
                    self.clipMessage = "There's nothing to clip yet."
                }
                try? FileManager.default.removeItem(at: url)
                self.savingClip = false
                if let message = self.clipMessage { self.announce?(message) }
                try? await Task.sleep(for: .seconds(3))
                self.clipMessage = nil
            }
        }
    }

    private static func saveToPhotos(_ url: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Microphone

    private func startMicrophone() async {
        guard micEngine == nil else { return }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed, let core else {
            if !allowed { micLive = false }
            return
        }
        AudioOutput.recordsMicrophone = true
        restartAudio?() // switch the session to play-and-record
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { stopMicrophone(); return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak core] buffer, _ in
            core?.pushMicrophone(buffer)
        }
        do {
            try engine.start()
            micEngine = engine
            micLive = true
        } catch {
            input.removeTap(onBus: 0)
            stopMicrophone()
        }
    }

    private func stopMicrophone() {
        if let micEngine {
            micEngine.inputNode.removeTap(onBus: 0)
            micEngine.stop()
        }
        micEngine = nil
        micLive = false
        if AudioOutput.recordsMicrophone {
            AudioOutput.recordsMicrophone = false
            restartAudio?() // back to playback only
        }
    }
}

/// Go-live setup while off; status, timer and controls while streaming.
struct LiveStreamSheet: View {
    @ObservedObject var streamer = LiveStreamer.shared
    let screens: Int
    let restartAudio: () -> Void

    @AppStorage("avydrix.live.service") private var serviceName = LiveService.twitch.rawValue
    @AppStorage("avydrix.live.quality") private var qualityName = LiveQuality.standard.rawValue
    @AppStorage("avydrix.live.microphone") private var microphone = true
    @State private var server = ""
    @State private var key = ""
    @State private var chatChannel = ""
    @Environment(\.dismiss) private var dismiss

    private var service: LiveService { LiveService(rawValue: serviceName) ?? .twitch }
    private var serverKey: String { "avydrix.live.server.\(service.rawValue)" }

    var body: some View {
        NavigationStack {
            Form {
                switch streamer.status {
                case .live(let since):
                    liveSection(since)
                case .connecting:
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Connecting to \(service.title)…")
                        }
                        Button("Cancel", role: .destructive) { streamer.stop() }
                    }
                case .off, .failed:
                    setup
                }
            }
            .navigationTitle("Live stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: load)
            .onChange(of: serviceName) { _, _ in load() }
        }
    }

    @ViewBuilder
    private var setup: some View {
        if case .failed(let message) = streamer.status {
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("live-error")
            }
        }
        Section {
            Picker("Stream to", selection: $serviceName) {
                ForEach(LiveService.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("live-service")
            TextField("Server address", text: $server)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 13, design: .monospaced))
                .accessibilityIdentifier("live-server")
            SecureField("Stream key", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("live-key")
        } footer: {
            Text(service.keyHelp + " Your key stays on this iPhone.")
        }
        if service.hasChat {
            Section {
                TextField(service == .youtube ? "@handle or live video link" : "Channel name", text: $chatChannel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("live-chat-channel")
            } header: {
                Text("Chat")
            } footer: {
                Text(service.chatHelp + " While you're live, the chat button in the game's top bar shows it on the lower screen.")
            }
        }
        Section {
            Toggle("Include my microphone", isOn: $microphone)
            Toggle("Show the tracker on stream", isOn: Binding(get: { streamer.overlayEnabled },
                                                               set: { streamer.overlayEnabled = $0 }))
                .accessibilityIdentifier("live-overlay")
            Picker("Quality", selection: $qualityName) {
                ForEach(LiveQuality.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } footer: {
            Text("Viewers see the game picture in 720p and hear the game, even if you mute it here. Wear headphones so the game sound doesn't echo through your mic.")
        }
        Section {
            Button {
                UserDefaults.standard.set(server, forKey: serverKey)
                UserDefaults.standard.set(chatChannel, forKey: LiveStreamer.chatKey(service))
                StreamKeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: service)
                streamer.start(service: service, server: server, key: key,
                               quality: LiveQuality(rawValue: qualityName) ?? .standard,
                               microphone: microphone, screens: screens, restartAudio: restartAudio)
            } label: {
                Label("Go live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
            .accessibilityIdentifier("live-go")
        }
    }

    private func liveSection(_ since: Date) -> some View {
        Section {
            HStack {
                Label("LIVE", systemImage: "circle.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.red)
                Spacer()
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(LiveBadge.elapsed(context.date.timeIntervalSince(since)))
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            LabeledContent("Upload", value: streamer.stats.kilobitsPerSecond > 0 ? "\(streamer.stats.kilobitsPerSecond) kbps" : "—")
            if streamer.stats.droppedFrames > 0 {
                LabeledContent("Frames skipped (slow connection)", value: "\(streamer.stats.droppedFrames)")
            }
            Toggle("Microphone", isOn: Binding(get: { streamer.micLive }, set: { streamer.setMicrophone($0) }))
            Toggle("Tracker on stream", isOn: Binding(get: { streamer.overlayEnabled }, set: { streamer.overlayEnabled = $0 }))
            Button {
                streamer.saveClip()
            } label: {
                Label(streamer.savingClip ? "Saving clip…" : "Save the last 30 seconds", systemImage: "film.stack")
            }
            .disabled(streamer.savingClip)
            Button("End stream", role: .destructive) { streamer.stop() }
                .accessibilityIdentifier("live-end")
        }
    }

    private func load() {
        server = UserDefaults.standard.string(forKey: serverKey) ?? service.defaultServer
        if server.isEmpty { server = service.defaultServer }
        key = StreamKeyStore.key(for: service)
        chatChannel = UserDefaults.standard.string(forKey: LiveStreamer.chatKey(service)) ?? ""
    }
}

/// The red LIVE pill in a game's top bar while streaming, with buttons to clip the last
/// 30 seconds and (where the lower screen can show it) open the chat.
struct LiveBadge: View {
    @ObservedObject var streamer = LiveStreamer.shared
    var chatOpen: Binding<Bool>? = nil
    let action: () -> Void

    var body: some View {
        switch streamer.status {
        case .live(let since):
            HStack(spacing: 2) {
                pill(since)
                Button { streamer.saveClip() } label: {
                    Image(systemName: streamer.savingClip ? "hourglass" : "film.stack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 40)
                }
                .disabled(streamer.savingClip)
                .accessibilityLabel("Clip the last 30 seconds")
                .accessibilityIdentifier("live-clip")
                if let chatOpen, streamer.chatURL != nil {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { chatOpen.wrappedValue.toggle() } } label: {
                        Image(systemName: chatOpen.wrappedValue ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(chatOpen.wrappedValue ? Theme.accent : .white.opacity(0.8))
                            .frame(width: 34, height: 40)
                    }
                    .accessibilityLabel(chatOpen.wrappedValue ? "Hide chat" : "Show chat")
                    .accessibilityIdentifier("live-chat-toggle")
                }
            }
        case .connecting:
            Button(action: action) {
                Text("CONNECTING")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            .accessibilityIdentifier("live-badge")
        default:
            EmptyView()
        }
    }

    private func pill(_ since: Date) -> some View {
        Button(action: action) {
            TimelineView(.periodic(from: since, by: 1)) { context in
                HStack(spacing: 5) {
                    Circle().fill(.white).frame(width: 6, height: 6)
                    Text("LIVE " + Self.elapsed(context.date.timeIntervalSince(since)))
                        .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(.red))
            }
        }
        .accessibilityLabel("Live stream")
        .accessibilityIdentifier("live-badge")
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
