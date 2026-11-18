import AVFoundation
import Security
import SwiftUI
import UIKit
import WebKit

@main
struct WorstRoommatesApp: App {
    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        } catch {
            NSLog("Worst Roommates audio session could not be configured: %@", error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Screen

struct RootView: View {
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.078, green: 0.067, blue: 0.11).ignoresSafeArea()
            GameView().ignoresSafeArea()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding(.trailing, 12)
            .padding(.top, 6)
            .accessibilityLabel("Settings")
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

struct GameView: UIViewRepresentable {
    func makeCoordinator() -> GameController { GameController() }

    func makeUIView(context: Context) -> WKWebView {
        let controller = context.coordinator
        let configuration = WKWebViewConfiguration()
        // Saves are owned by the app (see GameController), so WebKit storage can stay ephemeral.
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(controller, name: GameController.bridgeName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: controller.bootstrap(), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let background = UIColor(red: 0.078, green: 0.067, blue: 0.11, alpha: 1)
        webView.navigationDelegate = controller
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        controller.webView = webView

        if let gameURL = controller.gameURL {
            webView.loadFileURL(gameURL, allowingReadAccessTo: gameURL)
        } else {
            webView.loadHTMLString("<body style='background:#000;color:#fff'><h1>Game files could not load.</h1></body>", baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: GameController) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: GameController.bridgeName)
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }
}

// MARK: - Bridge between the game page and the app

@MainActor
final class GameController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let bridgeName = "worstRoommates"
    private static let keys: Set<String> = ["wre_save"]
    private static let maximumSaveBytes = 512 * 1024
    let gameURL = Bundle.main.url(forResource: "index", withExtension: "html")
    weak var webView: WKWebView?
    private let speech = Speech()
    private var resetObserver: NSObjectProtocol?

    override init() {
        super.init()
        resetObserver = NotificationCenter.default.addObserver(forName: .resetSeason, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resetSeason() }
        }
    }

    private var saveURL: URL {
        URL.applicationSupportDirectory.appending(path: "WorstRoommates/game-saves.json")
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
            Object.defineProperty(window, "WorstNative", {value: Object.freeze({
                getItem(key) {
                    return Object.hasOwn(saves, key) ? saves[key] : null;
                },
                setItem(key, value) {
                    send({action:"save", key:key, value:String(value)});
                    saves[key] = String(value);
                },
                post(message) {
                    send(message);
                },
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
            store(key: key, value: value)
        case "write":
            let id = body["id"] as? String ?? ""
            let prompt = body["prompt"] as? String ?? ""
            Task {
                do {
                    let text = try await ClaudeClient.complete(prompt: prompt)
                    self.reply(id: id, ok: true, text: text)
                } catch {
                    self.reply(id: id, ok: false, text: error.localizedDescription)
                }
            }
        case "haptic":
            Haptics.play(body["style"] as? String ?? "light")
        case "speak":
            speech.speak(body["text"] as? String ?? "", voice: body["voice"] as? [String: Any] ?? [:])
        case "stopSpeaking":
            speech.stop()
        default:
            return
        }
    }

    private func store(key: String, value: String) {
        var updated = saves
        updated[key] = value
        do {
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: saveURL, options: .atomic)
            saves = updated
        } catch {
            NSLog("Worst Roommates could not save: %@", error.localizedDescription)
        }
    }

    private func reply(id: String, ok: Bool, text: String) {
        let payload: [String: Any] = ["id": id, "ok": ok, "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__nativeReply && window.__nativeReply(\(json))")
    }

    private func resetSeason() {
        store(key: "wre_save", value: "")
        guard let webView else { return }
        reloadWithFreshSaves(webView)
    }

    private func reloadWithFreshSaves(_ webView: WKWebView) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: bootstrap(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let gameURL { webView.loadFileURL(gameURL, allowingReadAccessTo: gameURL) }
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
        // Refresh the injection from the last successful save after iOS reclaims WebKit.
        reloadWithFreshSaves(webView)
    }
}

extension Notification.Name {
    static let resetSeason = Notification.Name("WorstRoommates.resetSeason")
}

// MARK: - Claude episode writer

enum ClaudeClient {
    static let keyAccount = "anthropic_api_key"
    static let modelKey = "claude_model"
    static let defaultModel = "claude-sonnet-5-5"

    enum ClientError: LocalizedError {
        case noKey
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noKey: return "No API key set"
            case .http(let code, let message): return "Claude API error \(code): \(message)"
            case .badResponse: return "Unexpected response from Claude"
            }
        }
    }

    static func complete(prompt: String) async throws -> String {
        guard let key = Keychain.get(keyAccount), !key.isEmpty else { throw ClientError.noKey }
        let model = UserDefaults.standard.string(forKey: modelKey) ?? defaultModel

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 4000,
            "messages": [["role": "user", "content": prompt]]
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ClientError.http(status, String(String(data: data, encoding: .utf8)?.prefix(300) ?? ""))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else { throw ClientError.badResponse }
        return content.compactMap { block in
            (block["type"] as? String) == "text" ? block["text"] as? String : nil
        }.joined()
    }
}

enum Keychain {
    private static let service = "WorstRoommates"

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = Keychain.get(ClaudeClient.keyAccount) ?? ""
    @State private var confirmReset = false
    @AppStorage(ClaudeClient.modelKey) private var model = ClaudeClient.defaultModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Claude API key")
                } footer: {
                    Text("Claude writes the episodes. The key is stored only in this phone's Keychain. Without one, the built-in gag writer is used.")
                }

                Section("Writer") {
                    Picker("Model", selection: $model) {
                        Text("Claude Sonnet 5.5").tag("claude-sonnet-5-5")
                        Text("Claude Opus 5.5").tag("claude-opus-5-5")
                        Text("Claude Haiku 5.5 (fastest)").tag("claude-haiku-5-5")
                    }
                }

                Section {
                    Button("Reset episodes & grudges", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: ClaudeClient.keyAccount)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Start the season over?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    NotificationCenter.default.post(name: .resetSeason, object: nil)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Haptics and voices

enum Haptics {
    static func play(_ style: String) {
        switch style {
        case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

final class Speech {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, voice: [String: Any]) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        let rate = (voice["rate"] as? Double) ?? 1
        let pitch = (voice["pitch"] as? Double) ?? 1
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             max(AVSpeechUtteranceMinimumSpeechRate, Float(rate) * AVSpeechUtteranceDefaultSpeechRate))
        utterance.pitchMultiplier = min(2, max(0.5, Float(pitch)))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
