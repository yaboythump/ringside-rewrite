import SwiftUI
import WebKit

enum ReaderScript {
    static let source: String = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()
}

/// One page of the book: a WebKit view showing a chapter laid out in page-wide columns.
struct PageWebView: UIViewRepresentable {
    let request: PaneRequest
    let onEvent: (PaneEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: ReaderScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.add(WeakMessageHandler(context.coordinator), name: "bookduo")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.dataDetectorTypes = []
        configuration.allowsInlineMediaPlayback = true
        configuration.suppressesIncrementalRendering = true

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.showsHorizontalScrollIndicator = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.allowsLinkPreview = false
        web.navigationDelegate = context.coordinator
        web.alpha = 0
        if #available(iOS 16.4, *) { web.isInspectable = true }
        context.coordinator.webView = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.apply(request)
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "bookduo")
        web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onEvent: (PaneEvent) -> Void = { _ in }

        private var current: PaneRequest?
        private var loadedToken = -1
        private var laidOut = false
        private var shownPage = -1
        private var appliedSettings = ""
        private var handledAnchor = -1

        func apply(_ request: PaneRequest) {
            guard let web = webView else { return }
            let previous = current
            current = request
            if previous?.loadToken != request.loadToken || previous?.chapterURL != request.chapterURL {
                load(request, in: web)
                return
            }
            guard laidOut, loadedToken == request.loadToken else { return }
            if request.settingsJSON != appliedSettings {
                appliedSettings = request.settingsJSON
                web.evaluateJavaScript("BookDuo.configure(\(request.settingsJSON))", completionHandler: nil)
            }
            if request.page != shownPage {
                let animated = shownPage >= 0 && web.alpha > 0.5 && request.revealed
                shownPage = request.page
                web.evaluateJavaScript("BookDuo.goTo(\(request.page), \(animated))", completionHandler: nil)
            }
            resolveAnchor()
            updateVisibility()
        }

        private func load(_ request: PaneRequest, in web: WKWebView) {
            loadedToken = -1
            laidOut = false
            shownPage = -1
            web.layer.removeAllAnimations()
            web.alpha = 0
            web.loadFileURL(request.chapterURL, allowingReadAccessTo: request.bookFolder)
        }

        private func resolveAnchor() {
            guard laidOut, let web = webView, let anchor = current?.anchor,
                  anchor.token != handledAnchor, anchor.loadToken == loadedToken else { return }
            handledAnchor = anchor.token
            let encoded = (try? JSONEncoder().encode(anchor.id)).flatMap { String(data: $0, encoding: .utf8) }
            web.evaluateJavaScript("BookDuo.pageOf(\(encoded ?? "\"\""))") { [weak self] result, _ in
                let page = (result as? NSNumber)?.intValue ?? 0
                self?.onEvent(.anchor(page: max(0, page), token: anchor.token))
            }
        }

        private func updateVisibility() {
            guard let web = webView, let request = current else { return }
            let visible = laidOut && request.revealed && loadedToken == request.loadToken
            let alpha: CGFloat = visible ? 1 : 0
            guard web.alpha != alpha else { return }
            if visible {
                UIView.animate(withDuration: 0.18) { web.alpha = 1 }
            } else {
                web.alpha = 0
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let request = current else { return }
            loadedToken = request.loadToken
            appliedSettings = request.settingsJSON
            shownPage = request.page
            webView.evaluateJavaScript("BookDuo.start(\(request.settingsJSON), \(request.page))", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed()
        }

        private func failed() {
            // Show an empty page rather than getting stuck; the reader can still turn past it.
            guard let request = current else { return }
            loadedToken = request.loadToken
            laidOut = true
            onEvent(.layout(pages: 1, token: request.loadToken))
            updateVisibility()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if let request = current { load(request, in: webView) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                decisionHandler(.cancel)
                onEvent(.link(url))
                return
            }
            decisionHandler(.allow)
        }

        // MARK: Messages from reader.js

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "layout":
                guard loadedToken >= 0 else { return }
                laidOut = true
                let pages = (body["pages"] as? NSNumber)?.intValue ?? 1
                onEvent(.layout(pages: pages, token: loadedToken))
                resolveAnchor()
                updateVisibility()
            case "tap":
                let x = (body["x"] as? NSNumber)?.doubleValue ?? 0.5
                let y = (body["y"] as? NSNumber)?.doubleValue ?? 0.5
                onEvent(.tap(x: x, y: y))
            case "swipe":
                onEvent(.swipe(forward: (body["forward"] as? Bool) ?? true))
            default:
                break
            }
        }
    }
}

/// WKUserContentController keeps its handlers alive; this keeps it from keeping the coordinator alive.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
