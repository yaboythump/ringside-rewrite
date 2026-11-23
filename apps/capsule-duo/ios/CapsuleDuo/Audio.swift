import AVFoundation
import Foundation

/// Records one draft message into a temporary file.
@MainActor
final class VoiceRecorder: ObservableObject {
    enum State: Equatable { case idle, recording, recorded, denied, failed }

    static let maxLength: TimeInterval = 10 * 60

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// Recent input levels, 0…1, newest last. Drives the live waveform.
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 32)

    private(set) var fileURL: URL?
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?

    var hasRecording: Bool { state == .recorded && fileURL != nil }

    func start() async {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { state = .denied; return }
        discard()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("draft-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maxLength) else { state = .failed; return }
            self.recorder = recorder
            fileURL = url
            elapsed = 0
            state = .recording
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    self?.tick()
                }
            }
        } catch {
            state = .failed
        }
    }

    private func tick() {
        guard let recorder else { return }
        if !recorder.isRecording {
            stop()
            return
        }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0) // -160…0 dB
        let level = max(0, min(1, (power + 50) / 50))
        levels.removeFirst()
        levels.append(level)
        elapsed = recorder.currentTime
    }

    func stop() {
        meterTask?.cancel()
        meterTask = nil
        if let recorder {
            if recorder.isRecording { elapsed = recorder.currentTime }
            recorder.stop()
        }
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = (fileURL != nil && elapsed >= 0.5) ? .recorded : .idle
        if state == .idle { discard() }
    }

    /// Throws the draft away.
    func discard() {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        elapsed = 0
        levels = Array(repeating: 0, count: levels.count)
        if state != .denied { state = .idle }
    }

    /// Hands the draft file over (for sealing) without deleting it.
    func takeFile() -> URL? {
        let url = fileURL
        fileURL = nil
        state = .idle
        return url
    }
}

/// Plays back a draft or an opened capsule.
@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var missing = false

    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var progressTask: Task<Void, Never>?

    func load(_ url: URL) {
        guard url != loadedURL else { return }
        stop()
        loadedURL = url
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            self.player = nil
            missing = true
            duration = 0
            return
        }
        missing = false
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        duration = player.duration
        currentTime = 0
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTask?.cancel()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = max(0, min(time, duration))
        currentTime = player?.currentTime ?? 0
    }

    func stop() {
        player?.stop()
        player = nil
        loadedURL = nil
        isPlaying = false
        currentTime = 0
        progressTask?.cancel()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progressTask?.cancel()
            self.currentTime = 0
            self.player?.currentTime = 0
        }
    }
}
