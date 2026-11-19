import SwiftUI
import UIKit
import WebKit
import AVFAudio

@main
struct DetectiveDuoApp: App {
    var body: some Scene {
        WindowGroup {
            DetectiveWebView()
                .background(Color(red: 0.03, green: 0.05, blue: 0.09))
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
    }
}

struct DetectiveWebView: UIViewRepresentable {
    func makeCoordinator() -> DetectiveController {
        DetectiveController()
    }

    func makeUIView(context: Context) -> WKWebView {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        let controller = context.coordinator
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(controller, name: DetectiveController.messageName)
        config.userContentController.addUserScript(
            WKUserScript(source: controller.bootstrap(), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let web = WKWebView(frame: .zero, configuration: config)
        let color = UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)
        web.navigationDelegate = controller
        web.isOpaque = false
        web.backgroundColor = color
        web.scrollView.backgroundColor = color
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        web.scrollView.contentInset = .zero
        if let fileURL = controller.gameURL {
            web.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            web.loadHTMLString("<p style='color:white'>Missing bundled game.</p>", baseURL: nil)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: DetectiveController) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: DetectiveController.messageName)
        web.navigationDelegate = nil
        web.stopLoading()
    }
}

@MainActor
final class DetectiveController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let messageName = "detectiveDuo"
    private static let saveKey = "detective_duo_v1"
    private static let maximumSaveBytes = 256 * 1024
    let gameURL = Bundle.main.url(forResource: "index", withExtension: "html")

    func bootstrap() -> String {
        let seed = (UserDefaults.standard.string(forKey: Self.saveKey) ?? "").data(using: .utf8)!.base64EncodedString()
        return """
        (() => {
          const encoded = "\(seed)";
          const data = Uint8Array.from(atob(encoded), character => character.charCodeAt(0));
          const initialSave = new TextDecoder().decode(data);
          const bridge = window.webkit.messageHandlers["\(Self.messageName)"];
          Object.defineProperty(window, "DetectiveNative", {value: Object.freeze({
            read() { return initialSave; },
            save(value) { bridge.postMessage({action:"save", value: String(value)}); },
            haptic(style) { bridge.postMessage({action:"haptic", style: String(style)}); }
          })});
        })();
        """
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageName,
              message.frameInfo.isMainFrame,
              let requested = message.frameInfo.request.url?.standardizedFileURL,
              requested == gameURL?.standardizedFileURL,
              let payload = message.body as? [String: Any],
              let action = payload["action"] as? String else { return }

        switch action {
        case "save":
            guard let value = payload["value"] as? String,
                  value.utf8.count <= Self.maximumSaveBytes else { return }
            UserDefaults.standard.set(value, forKey: Self.saveKey)
        case "haptic":
            let style = payload["style"] as? String ?? "light"
            switch style {
            case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
            default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(url.isFileURL && url.standardizedFileURL == gameURL?.standardizedFileURL ? .allow : .cancel)
    }
}

