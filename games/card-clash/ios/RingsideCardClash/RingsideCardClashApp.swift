import AVFAudio
import SwiftUI
import UIKit
import WebKit

@main
struct RingsideCardClashApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .background(Color.black.ignoresSafeArea())
                .preferredColorScheme(.dark)
        }
    }
}

struct GameView: UIViewRepresentable {
    func makeCoordinator() -> GameController { GameController() }

    func makeUIView(context: Context) -> WKWebView {
        let controller = context.coordinator
        let configuration = WKWebViewConfiguration()
        // Save files are owned by the app, including on devices where WebKit
        // treats storage for local file origins as ephemeral.
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(controller, name: GameController.bridgeName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: controller.bootstrap(), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = controller
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false

        if let gameURL = controller.gameURL {
            webView.loadFileURL(gameURL, allowingReadAccessTo: gameURL)
        } else {
            webView.loadHTMLString("<body style='background:#000;color:#fff'><h1>Game files could not load.</h1></body>", baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: GameController) {
        coordinator.stopAudio()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: GameController.bridgeName)
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }
}

@MainActor
final class GameController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let bridgeName = "ringsideGame"
    private static let keys: Set<String> = [
        "rcc-career", "rcc-best", "rcc-cup", "rcc-tag", "rcc-mute", "rcc-low-motion", "rcc-music-off"
    ]
    private static let maximumSaveBytes = 512 * 1024
    private static let soundEffects: Set<String> = [
        "tag", "entrance", "card", "hit", "big", "block", "hype", "heal", "count", "bell", "crowd", "boo",
        "ref-1", "ref-2", "ref-3"
    ]
    private static let musicClips: Set<String> = ["menu-loop", "arena-loop"]
    private var musicClip: String?
    private var audioInterrupted = false
    private var players: [String: AVAudioPlayer] = [:]
    let gameURL = Bundle.main.url(forResource: "index", withExtension: "html")

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(audioInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(pauseForBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeForForeground),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private var saveURL: URL {
        URL.applicationSupportDirectory.appending(path: "RingsideCardClash/game-saves.json")
    }

    private lazy var saves: [String: String] = {
        guard let contents = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: contents) else { return [:] }
        return decoded.filter { Self.keys.contains($0.key) }
    }()

    func bootstrap() -> String {
        // The base64 string cannot terminate the injected JavaScript literal.
        let encoded = ((try? JSONEncoder().encode(saves)) ?? Data("{}".utf8)).base64EncodedString()
        return """
        (() => {
            const seed = Uint8Array.from(atob("\(encoded)"), letter => letter.charCodeAt(0));
            const saves = JSON.parse(new TextDecoder().decode(seed));
            const send = message => window.webkit.messageHandlers["\(Self.bridgeName)"].postMessage(message);
            Object.defineProperty(window, "RingsideNative", {value: Object.freeze({
                getItem(key) {
                    return Object.hasOwn(saves, key) ? saves[key] : null;
                },
                setItem(key, value) {
                    send({action:"save", key:key, value:value});
                    saves[key] = value;
                },
                impact(strength) { send({action:"impact", strength:strength}); },
                audio(cue) { send({action:"audio", cue:cue}); }
            })});
        })();
        """
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.bridgeName,
              message.frameInfo.isMainFrame,
              let origin = message.frameInfo.request.url?.standardizedFileURL,
              origin == gameURL?.standardizedFileURL,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        switch action {
        case "save":
            guard let key = body["key"] as? String, Self.keys.contains(key),
                  let value = body["value"] as? String, value.utf8.count <= Self.maximumSaveBytes else { return }
            var updated = saves
            updated[key] = value
            do {
                try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(updated).write(to: saveURL, options: .atomic)
                saves = updated
            } catch {
                message.webView?.evaluateJavaScript("document.dispatchEvent(new Event('ringside-save-error'))")
            }
        case "impact":
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            let heavy = body["strength"] as? String == "heavy"
            UIImpactFeedbackGenerator(style: heavy ? .heavy : .light).impactOccurred()
        case "audio":
            guard let cue = body["cue"] as? String else { return }
            switch cue {
            case "stop-all": stopAudio()
            case "music-stop": setMusic(nil)
            case "music-menu": setMusic("menu-loop")
            case "music-arena": setMusic("arena-loop")
            case "effects-stop":
                for clip in Self.soundEffects { players[clip]?.stop() }
            case "test-bell":
                let started = playAudio("bell")
                let event = started ? "ringside-audio-started" : "ringside-audio-failed"
                message.webView?.evaluateJavaScript("document.dispatchEvent(new Event('\(event)'))")
            default:
                if Self.soundEffects.contains(cue) { playAudio(cue) }
            }
        default:
            return
        }
    }

    private func setMusic(_ clip: String?) {
        if let previous = musicClip, previous != clip { players[previous]?.stop() }
        musicClip = clip
        if let clip { playAudio(clip, looping: Self.musicClips.contains(clip)) }
    }

    @objc private func pauseForBackground() {
        stopAudio()
    }

    @objc private func resumeForForeground() {
        if let musicClip { setMusic(musicClip) }
    }

    @objc private func audioInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        audioInterrupted = type == .began
        if audioInterrupted {
            stopAudio()
        } else {
            let flags = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: flags).contains(.shouldResume) {
                resumeForForeground()
            }
        }
    }

    @discardableResult
    private func playAudio(_ clip: String, looping: Bool = false) -> Bool {
        guard !audioInterrupted, UIApplication.shared.applicationState != .background else { return false }
        do {
            let player: AVAudioPlayer
            if let cached = players[clip] {
                player = cached
            } else {
                guard let resource = Bundle.main.url(forResource: clip, withExtension: "mp3", subdirectory: "sound") else { return false }
                player = try AVAudioPlayer(contentsOf: resource)
                player.numberOfLoops = looping ? -1 : 0
                player.volume = looping ? 0.65 : 1
                players[clip] = player
            }
            if (looping || clip == "crowd") && player.isPlaying { return true }
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback || !session.categoryOptions.contains(.mixWithOthers) {
                try session.setCategory(.playback, options: .mixWithOthers)
            }
            try session.setActive(true)
            player.currentTime = 0
            return player.play()
        } catch {
            NSLog("Ringside audio could not play %@: %@", clip, error.localizedDescription)
            return false
        }
    }

    func stopAudio() {
        for player in players.values { player.stop() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let destination = navigationAction.request.url?.standardizedFileURL,
              destination == gameURL?.standardizedFileURL else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        stopAudio()
        // Refresh the injection from the last successful save after iOS reclaims WebKit.
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: bootstrap(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let gameURL { webView.loadFileURL(gameURL, allowingReadAccessTo: gameURL) }
    }
}
