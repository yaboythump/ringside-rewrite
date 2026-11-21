import SwiftUI
import WebKit
import UniformTypeIdentifiers
import GameController
import AVFoundation

@main
struct CTArcadeApp: App {
    var body: some Scene {
        WindowGroup { ArcadeRoot().preferredColorScheme(.dark) }
    }
}

struct ArcadeRoot: View {
    @StateObject private var bridge = ArcadeBridge()

    var body: some View {
        ArcadeWebView(bridge: bridge)
            .ignoresSafeArea()
            .background(Color(red: 0.035, green: 0.045, blue: 0.085))
            .fileImporter(isPresented: $bridge.showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "nes") ?? .data, .data]) { result in
                switch result {
                case .success(let url): bridge.importROM(url)
                case .failure(let error): bridge.error(error.localizedDescription)
                }
            }
    }
}

struct ArcadeWebView: UIViewRepresentable {
    @ObservedObject var bridge: ArcadeBridge
    func makeUIView(context: Context) -> WKWebView {
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .default()
        settings.allowsInlineMediaPlayback = true
        settings.mediaTypesRequiringUserActionForPlayback = []
        settings.userContentController.add(bridge, name: "ctArcade")
        let view = WKWebView(frame: .zero, configuration: settings)
        view.navigationDelegate = bridge
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.035, green: 0.045, blue: 0.085, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.isScrollEnabled = false
        view.allowsLinkPreview = false
        bridge.webView = view
        bridge.connectControllers()
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<body style='background:#090d17;color:white'>CT ARCADE assets missing</body>", baseURL: nil)
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ctArcade")
    }
}

struct Cartridge: Codable {
    let id: String
    let name: String
    let file: String
}

@MainActor
final class ArcadeBridge: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var showImporter = false
    weak var webView: WKWebView?
    private var connected = false
    private var controllerObservers: [NSObjectProtocol] = []
    private var registeredControllers = Set<ObjectIdentifier>()
    private var cartridges: [Cartridge] {
        get { guard let bytes = try? Data(contentsOf: libraryURL),
                  let list = try? JSONDecoder().decode([Cartridge].self, from: bytes) else { return [] }
            return list }
        set { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let bytes = try? JSONEncoder().encode(newValue) { try? bytes.write(to: libraryURL, options: .atomic) } }
    }
    private var folder: URL {
        URL.applicationSupportDirectory.appending(path: "CTArcade", directoryHint: .isDirectory)
    }
    private var libraryURL: URL { folder.appending(path: "library.json") }
    private var savesFolder: URL { folder.appending(path: "Saves", directoryHint: .isDirectory) }
    private var gameURL: URL? { Bundle.main.url(forResource: "index", withExtension: "html") }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        list()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url, target.isFileURL,
              target.lastPathComponent == "index.html",
              target.deletingLastPathComponent() == gameURL?.deletingLastPathComponent() else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func userContentController(_ content: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ctArcade", message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.standardizedFileURL == gameURL?.standardizedFileURL,
              let msg = message.body as? [String: Any],
              let action = msg["action"] as? String else { return }
        switch action {
        case "list": list()
        case "import": showImporter = true
        case "open":
            if let id = msg["id"] as? String { open(id: id) }
        case "save":
            if let id = msg["id"] as? String, let value = msg["value"] as? String {
                save(id: id, value: value)
            }
        case "load":
            if let id = msg["id"] as? String { load(id: id) }
        default: break
        }
    }

    private func json(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let bytes = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: bytes, encoding: .utf8) else { return nil }
        return string
    }
    private func call(_ name: String, _ object: [String: Any]) {
        guard let data = json(object) else { return }
        webView?.evaluateJavaScript("window.CTArcadeNative && window.CTArcadeNative.\(name)(\(data))", completionHandler: nil)
    }
    func error(_ message: String) { call("error", ["message":message]) }
    private func list() {
        let items: [[String: String]] = cartridges.map { ["id":$0.id, "name":$0.name] }
        // Library is an array, not a dictionary.
        guard let bytes = try? JSONSerialization.data(withJSONObject: items),
              let jsonText = String(data: bytes, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.CTArcadeNative && window.CTArcadeNative.onLibrary(\(jsonText))")
    }
    func importROM(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let magic = Data([0x4e, 0x45, 0x53, 0x1a])
            guard data.count >= 16, data.count <= 4 * 1024 * 1024,
                  data.prefix(4) == magic else {
                error("Choose a valid .nes cartridge under 4 MB")
                return
            }
            let id = UUID().uuidString
            let file = id + ".nes"
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appending(path: file), options: .atomic)
            let name = url.deletingPathExtension().lastPathComponent
            cartridges.append(Cartridge(id: id, name: name, file: file))
            list()
            open(id: id)
        } catch {
            self.error("Could not import game: \(error.localizedDescription)")
        }
    }
    private func open(id: String) {
        guard let cartridge = cartridges.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: folder.appending(path: cartridge.file)),
              data.count <= 4 * 1024 * 1024 else {
            error("Game file is missing or could not be read"); return
        }
        call("rom", ["id":id, "name":cartridge.name, "base64":data.base64EncodedString()])
    }
    private func save(id: String, value: String) {
        guard cartridges.contains(where: { $0.id == id }),
              value.utf8.count < 8 * 1024 * 1024 else { return }
        do {
            try FileManager.default.createDirectory(at: savesFolder, withIntermediateDirectories: true)
            try Data(value.utf8).write(to: savesFolder.appending(path: id + ".json"), options: .atomic)
        } catch { self.error("Could not save state") }
    }
    private func load(id: String) {
        guard cartridges.contains(where: { $0.id == id }),
              let bytes = try? Data(contentsOf: savesFolder.appending(path: id + ".json")),
              let string = String(data: bytes, encoding: .utf8) else {
            error("No save for this game yet"); return
        }
        call("state", ["id":id, "value":string])
    }

    func connectControllers() {
        guard !connected else { return }
        connected = true
        for controller in GCController.controllers() { register(controller) }
        controllerObservers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] notification in
                if let controller = notification.object as? GCController {
                    Task { @MainActor in self?.register(controller) }
                }
            })
        controllerObservers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sendPad([]) }
            })
    }
    private func register(_ controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        guard !registeredControllers.contains(identifier), let pad = controller.extendedGamepad else { return }
        registeredControllers.insert(identifier)
        pad.valueChangedHandler = { [weak self] pad, _ in
            var active: [String] = []
            if pad.buttonA.isPressed { active.append("A") }
            if pad.buttonB.isPressed { active.append("B") }
            if pad.buttonMenu.isPressed { active.append("START") }
            if pad.buttonOptions?.isPressed == true { active.append("SELECT") }
            if pad.dpad.up.isPressed || pad.leftThumbstick.up.isPressed { active.append("UP") }
            if pad.dpad.down.isPressed || pad.leftThumbstick.down.isPressed { active.append("DOWN") }
            if pad.dpad.left.isPressed || pad.leftThumbstick.left.isPressed { active.append("LEFT") }
            if pad.dpad.right.isPressed || pad.leftThumbstick.right.isPressed { active.append("RIGHT") }
            Task { @MainActor in self?.sendPad(active) }
        }
    }
    private func sendPad(_ active: [String]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: active),
              let array = String(data: bytes, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.CTArcadeNative && window.CTArcadeNative.pad(\(array))")
    }
}
