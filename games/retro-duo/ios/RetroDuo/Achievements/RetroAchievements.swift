import Foundation
import Security

/// RetroAchievements (retroachievements.org): sign in once, and games the site knows award
/// achievements as you play. Built on rcheevos through RDAchievements.c; this class does the
/// web requests, keeps the sign-in in the Keychain and tells the open game what happened.
///
/// Casual ("softcore") mode, so rewind, cheats and save states all keep working.
@MainActor
final class RetroAchievements: ObservableObject {
    static let shared = RetroAchievements()

    struct GameProgress: Equatable {
        var title: String
        var earned: Int
        var total: Int
        var points: Int
        var totalPoints: Int
    }

    struct Achievement: Identifiable, Equatable {
        let id: UInt32
        let title: String
        let detail: String
        let points: Int
        let badge: URL?
        let progress: String
        let unlocked: Bool
    }

    /// Display name of the signed-in player, or nil.
    @Published private(set) var player: String?
    @Published private(set) var score = 0
    @Published private(set) var signingIn = false
    @Published private(set) var signInError: String?
    /// The open game's achievements, if RetroAchievements knows it.
    @Published private(set) var progress: GameProgress?
    @Published private(set) var achievements: [Achievement] = []
    /// What happened with the open game ("No achievements for this game yet", ...).
    @Published private(set) var gameStatus: String?

    /// Shows a short message in the open game (set by the game's session).
    var announce: ((String) -> Void)?

    private var ach: OpaquePointer?
    private var memory: ((UInt32) -> UInt8?)?
    private var loading: Game?
    private var scopedURL: URL?
    private var lastFrame = Date.distantPast
    private var idleTimer: Timer?
    private var userAgent = "AVYDRIX-Play"
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    private init() {
        // UI tests run without a network account.
        guard !ProcessInfo.processInfo.arguments.contains("-RetroDuoUITests") else { return }
        var callbacks = RDAchCallbacks()
        callbacks.context = nil
        callbacks.read = { _, address in
            MainActor.assumeIsolated { RetroAchievements.shared.read(address) }
        }
        callbacks.request = { _, url, post, contentType, request in
            let url = url.map { String(cString: $0) } ?? ""
            let post = post.map { String(cString: $0) }
            let contentType = contentType.map { String(cString: $0) }
            MainActor.assumeIsolated {
                RetroAchievements.shared.send(url: url, post: post, contentType: contentType, request: request)
            }
        }
        callbacks.finished = { _, what, ok, message in
            let message = message.map { String(cString: $0) } ?? ""
            MainActor.assumeIsolated { RetroAchievements.shared.finished(what: what, ok: ok != 0, message: message) }
        }
        callbacks.event = { _, type, item in
            guard let item else { return }
            let achievement = Achievement(item.pointee)
            MainActor.assumeIsolated { RetroAchievements.shared.handle(event: type, achievement) }
        }
        ach = RDAchCreate(callbacks)
        var clause = [CChar](repeating: 0, count: 64)
        RDAchUserAgentClause(ach, &clause, clause.count)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        userAgent = "AVYDRIX-Play/\(version) (iOS) " + String(cString: clause)

        if let saved = AchievementsLogin.load() {
            signingIn = true
            RDAchLoginWithToken(ach, saved.username, saved.token)
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let achievements = RetroAchievements.shared
                // rcheevos needs a regular call while no frames run (pings, retried unlocks).
                if let ach = achievements.ach, Date().timeIntervalSince(achievements.lastFrame) > 1 { RDAchIdle(ach) }
            }
        }
    }

    var available: Bool { ach != nil }

    // MARK: Account

    func signIn(username: String, password: String) {
        guard let ach, !username.isEmpty, !password.isEmpty else { return }
        signingIn = true
        signInError = nil
        RDAchLoginWithPassword(ach, username, password)
    }

    func signOut() {
        guard let ach else { return }
        RDAchLogout(ach)
        AchievementsLogin.clear()
        player = nil
        score = 0
        progress = nil
        achievements = []
        gameStatus = nil
    }

    // MARK: The open game

    /// Starts tracking a game. `memory` reads a byte at a console address (ConsoleBackend.peek).
    func start(game: Game, memory: @escaping (UInt32) -> UInt8?) {
        guard let ach else { return }
        stop()
        self.memory = memory
        guard !game.isBuiltIn, !game.isBundledGame else { return }
        let console = RDAchConsoleID(game.url.pathExtension)
        guard console != 0 else { return }
        guard player != nil || signingIn else {
            gameStatus = "Sign in to RetroAchievements in Settings to earn achievements."
            return
        }
        loading = game
        gameStatus = "Looking up achievements…"
        if game.url.startAccessingSecurityScopedResource() { scopedURL = game.url }
        RDAchLoadGame(ach, console, game.url.path)
    }

    func stop() {
        releaseFile()
        loading = nil
        memory = nil
        progress = nil
        achievements = []
        gameStatus = nil
        if let ach { RDAchUnloadGame(ach) }
    }

    /// After each emulated frame.
    func frame() {
        guard let ach, progress != nil else { return }
        lastFrame = Date()
        RDAchDoFrame(ach)
    }

    /// After loading a save state: progress toward achievements starts over from there.
    func stateLoaded() {
        guard let ach, progress != nil else { return }
        RDAchReset(ach)
    }

    func refreshList() {
        guard let ach, progress != nil else { achievements = []; return }
        let count = RDAchListBuild(ach)
        var list: [Achievement] = []
        var item = RDAchItem()
        for index in 0..<count where RDAchListItem(ach, index, &item) != 0 {
            list.append(Achievement(item))
        }
        achievements = list
    }

    // MARK: rcheevos callbacks

    private func read(_ address: UInt32) -> UInt32 {
        guard let byte = memory?(address) else { return 0x100 }
        return UInt32(byte)
    }

    private func send(url: String, post: String?, contentType: String?, request: OpaquePointer?) {
        guard let target = URL(string: url) else {
            RDAchRequestDone(request, 0, nil, 0)
            return
        }
        var urlRequest = URLRequest(url: target)
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let post {
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = Data(post.utf8)
            urlRequest.setValue(contentType ?? "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let pending = UInt(bitPattern: request)
        session.dataTask(with: urlRequest) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                let request = OpaquePointer(bitPattern: pending)
                if let data {
                    data.withUnsafeBytes { bytes in
                        RDAchRequestDone(request, Int32(status), bytes.bindMemory(to: CChar.self).baseAddress, data.count)
                    }
                } else {
                    RDAchRequestDone(request, 0, nil, 0)
                }
            }
        }.resume()
    }

    private func finished(what: Int32, ok: Bool, message: String) {
        guard let ach else { return }
        switch Int(what) {
        case Int(RD_ACH_LOGIN):
            signingIn = false
            if ok, let name = RDAchUserName(ach), let token = RDAchUserToken(ach) {
                player = String(cString: name)
                score = Int(RDAchUserScore(ach))
                signInError = nil
                AchievementsLogin.save(username: String(cString: name), token: String(cString: token))
            } else {
                player = nil
                signInError = message.isEmpty ? "Couldn't sign in." : message
                // A rejected saved token means signing in again; a network problem keeps it.
                if message.localizedCaseInsensitiveContains("token") || message.localizedCaseInsensitiveContains("password") {
                    AchievementsLogin.clear()
                }
                if loading != nil {
                    gameStatus = "Sign in to RetroAchievements in Settings to earn achievements."
                }
            }
        case Int(RD_ACH_GAME):
            releaseFile()
            guard loading != nil else { return }
            loading = nil
            if ok, let title = RDAchGameTitle(ach) {
                updateProgress(title: String(cString: title))
                refreshList()
                if let progress {
                    gameStatus = nil
                    if progress.total == 0 {
                        gameStatus = "\(progress.title) has no achievements yet."
                    } else {
                        announce?("🏆 \(progress.earned) of \(progress.total) achievements")
                    }
                }
            } else {
                progress = nil
                gameStatus = message.localizedCaseInsensitiveContains("unknown")
                    ? "RetroAchievements doesn't know this version of the game."
                    : "Achievements aren't available: \(message)"
            }
        default:
            break
        }
    }

    private func handle(event: Int32, _ achievement: Achievement) {
        switch Int(event) {
        case Int(RD_ACH_EVENT_UNLOCKED):
            if let ach, let title = RDAchGameTitle(ach) { updateProgress(title: String(cString: title)) }
            score += achievement.points
            refreshList()
            announce?("🏆 \(achievement.title) (+\(achievement.points))")
        case Int(RD_ACH_EVENT_COMPLETED):
            announce?("🏆 Every achievement earned!")
        case Int(RD_ACH_EVENT_OFFLINE):
            announce?("Achievement saved: it'll be sent when you're back online")
        case Int(RD_ACH_EVENT_ERROR):
            if !achievement.title.isEmpty { announce?("RetroAchievements: \(achievement.title)") }
        default:
            break
        }
    }

    private func updateProgress(title: String) {
        guard let ach else { return }
        var earned: UInt32 = 0, total: UInt32 = 0, points: UInt32 = 0, totalPoints: UInt32 = 0
        RDAchGameSummary(ach, &earned, &total, &points, &totalPoints)
        progress = GameProgress(title: title, earned: Int(earned), total: Int(total),
                                points: Int(points), totalPoints: Int(totalPoints))
    }

    private func releaseFile() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}

private extension RetroAchievements.Achievement {
    init(_ item: RDAchItem) {
        id = item.id
        title = item.title.map { String(cString: $0) } ?? ""
        detail = item.description.map { String(cString: $0) } ?? ""
        points = Int(item.points)
        badge = item.badgeURL.flatMap { URL(string: String(cString: $0)) }
        progress = item.progress.map { String(cString: $0) } ?? ""
        unlocked = item.unlocked != 0
    }
}

/// The RetroAchievements sign-in (user name and API token, never the password), on this device only.
enum AchievementsLogin {
    private static let service = "com.ctnetworkstudios.retroduo.retroachievements"

    static func load() -> (username: String, token: String)? {
        var query = base
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [CFString: Any],
              let username = item[kSecAttrAccount] as? String,
              let data = item[kSecValueData] as? Data else { return nil }
        let token = String(decoding: data, as: UTF8.self)
        return token.isEmpty ? nil : (username, token)
    }

    static func save(username: String, token: String) {
        clear()
        var item = base
        item[kSecAttrAccount] = username
        item[kSecValueData] = Data(token.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }

    private static var base: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
    }
}
