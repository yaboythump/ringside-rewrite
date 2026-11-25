import SwiftUI
import WebKit

/// The stream's chat on the lower screen (the platform's own pop-out chat page, so you can read
/// and, once signed in there, reply). Touch controls are hidden meanwhile, as with the tracker;
/// a Bluetooth controller and the hinge still play.
struct LiveChatPanel: View {
    @ObservedObject var streamer = LiveStreamer.shared

    var body: some View {
        ZStack {
            Color.black
            if let url = streamer.chatURL {
                ChatWebView(url: url)
                    .accessibilityIdentifier("live-chat")
            } else {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Waiting for the chat…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

private struct ChatWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // keeps you signed in to chat
        configuration.allowsInlineMediaPlayback = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.overrideUserInterfaceStyle = .dark
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loaded: URL?
    }
}
