import AVFAudio
import SwiftUI
import UIKit
import WebKit

@main
struct RingsideComboApp: App {
    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        } catch {
            NSLog("Ringside Combo audio session could not be configured: %@", error.localizedDescription)
        }
    }

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
        configuration.allowsInlineMediaPlayback = true
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
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: GameController.bridgeName)
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }
}

@MainActor
final class GameController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let bridgeName = "ringsideGame"
    private static let keys: Set<String> = [
        "ringcombo-muted"
    ]
    private static let maximumSaveBytes = 512 * 1024
    let gameURL = Bundle.main.url(forResource: "index", withExtension: "html")

    private var saveURL: URL {
        URL.applicationSupportDirectory.appending(path: "RingsideCombo/game-saves.json")
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
        default:
            return
        }
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
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: bootstrap(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let gameURL { webView.loadFileURL(gameURL, allowingReadAccessTo: gameURL) }
    }
}
