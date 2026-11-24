import GameController
import SwiftUI
import UIKit

/// Device-local metadata only. Existing ROM files and legacy save-state paths are never changed.
@MainActor
final class AVPlayerProfile: ObservableObject {
    struct Snapshot: Codable {
        var favorites: [String] = []
        var recent: [String] = []
        var seconds: [String: Double] = [:]
        var launches: [String: Int] = [:]
    }

    @Published private(set) var data = Snapshot()
    private var activeGame: String?
    private var beganAt: Date?

    init() {
        if let saved = UserDefaults.standard.data(forKey: "avydrix.profile.v1"),
           let loaded = try? JSONDecoder().decode(Snapshot.self, from: saved) {
            data = loaded
        }
    }

    func isFavorite(_ game: Game) -> Bool { data.favorites.contains(game.id) }

    func toggleFavorite(_ game: Game) {
        if let index = data.favorites.firstIndex(of: game.id) {
            data.favorites.remove(at: index)
        } else {
            data.favorites.insert(game.id, at: 0)
        }
        persist()
    }

    func start(_ game: Game) {
        finish()
        guard !game.isBuiltIn || game.isBundledGame else { return }
        activeGame = game.id
        beganAt = Date()
        data.recent.removeAll { $0 == game.id }
        data.recent.insert(game.id, at: 0)
        data.recent = Array(data.recent.prefix(50))
        data.launches[game.id, default: 0] += 1
        persist()
    }

    func finish() {
        if let game = activeGame, let started = beganAt {
            data.seconds[game, default: 0] += max(0, Date().timeIntervalSince(started))
            persist()
        }
        activeGame = nil
        beganAt = nil
    }

    func seconds(for game: Game) -> Double {
        let accumulated = data.seconds[game.id] ?? 0
        if activeGame == game.id, let beganAt {
            return accumulated + max(0, Date().timeIntervalSince(beganAt))
        }
        return accumulated
    }

    var totalSeconds: Double { data.seconds.values.reduce(0, +) }
    var totalLaunches: Int { data.launches.values.reduce(0, +) }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "avydrix.profile.v1")
        }
    }
}

/// Per-console size, position and opacity controls, leaving touch hit areas intact.
@MainActor
final class AVControlTuning: ObservableObject {
    let system: GameSystem
    @Published var size: Double { didSet { save() } }
    @Published var opacity: Double { didSet { save() } }
    @Published var mirrored: Bool { didSet { save() } }
    @Published var directionOffset: Double { didSet { save() } }
    @Published var actionOffset: Double { didSet { save() } }

    init(system: GameSystem) {
        self.system = system
        let defaults = UserDefaults.standard
        let key = "avydrix.controls.\(system.rawValue)."
        size = defaults.object(forKey: key + "size") as? Double ?? 1.0
        opacity = defaults.object(forKey: key + "opacity") as? Double ?? 1.0
        mirrored = defaults.bool(forKey: key + "mirrored")
        directionOffset = defaults.object(forKey: key + "directionOffset") as? Double ?? 0
        actionOffset = defaults.object(forKey: key + "actionOffset") as? Double ?? 0
    }

    func reset() {
        size = 1.0
        opacity = 1.0
        mirrored = false
        directionOffset = 0
        actionOffset = 0
    }

    private func save() {
        let key = "avydrix.controls.\(system.rawValue)."
        let defaults = UserDefaults.standard
        defaults.set(size, forKey: key + "size")
        defaults.set(opacity, forKey: key + "opacity")
        defaults.set(mirrored, forKey: key + "mirrored")
        defaults.set(directionOffset, forKey: key + "directionOffset")
        defaults.set(actionOffset, forKey: key + "actionOffset")
    }
}

/// Map each virtual input to a configurable physical face-button position.
enum AVControllerMapping {
    static let physical = ["A", "B", "X", "Y"]
    static func selected(_ logical: String, system: GameSystem) -> String? {
        let key = "avydrix.controller.\(system.rawValue).\(logical)"
        return UserDefaults.standard.string(forKey: key)
    }

    static func set(_ physical: String, for logical: String, system: GameSystem) {
        UserDefaults.standard.set(physical, forKey: "avydrix.controller.\(system.rawValue).\(logical)")
    }

    static func pressed(_ logical: String, pad: GCExtendedGamepad, system: GameSystem) -> Bool {
        if let name = selected(logical, system: system) {
            switch name {
            case "A": return pad.buttonA.isPressed
            case "B": return pad.buttonB.isPressed
            case "X": return pad.buttonX.isPressed
            case "Y": return pad.buttonY.isPressed
            default: return false
            }
        }
        // Keep the pre-upgrade mapping until a player explicitly changes it.
        switch logical {
        // Two-button systems also accept the other face buttons; four-button pads use each one.
        case "A": return pad.buttonB.isPressed || (system.faceKeys.count <= 2 && system != .nintendoDS && pad.buttonY.isPressed)
        case "B": return pad.buttonA.isPressed || (system.faceKeys.count <= 2 && system != .nintendoDS && pad.buttonX.isPressed)
        case "X": return pad.buttonY.isPressed
        case "Y": return pad.buttonX.isPressed
        default: return false
        }
    }
}

struct AVGameSettings: View {
    @ObservedObject var tuning: AVControlTuning
    @Environment(\.dismiss) private var dismiss
    @AppStorage("avydrix.duo.mode") private var duoMode = "auto"
    @AppStorage("avydrix.gba.landscapeControls") private var gbaLandscapeControls = true
    @AppStorage(ThumbStick.settingKey) private var thumbstick = false
    @AppStorage("retroDuoOriginalProportions") private var originalAspect = false
    @AppStorage("avydrix.displayFilter") private var displayFilter = "off"
    @AppStorage("avydrix.dsSwapScreens") private var swapDS = false
    @AppStorage("avydrix.dsTouchScale") private var dsTouchScale = 1.0

    private var logical: [String] { tuning.system == .nintendoDS ? ["A", "B", "X", "Y"] : ["A", "B"] }
    @State private var hingeRefresh = 0

    private var hingeHelp: String {
        switch HingeControl.mode(for: tuning.system) {
        case .off:
            return "Use the iPhone Duo's hinge as a control while it's partly folded (laptop style)."
        case .button:
            return "Hold the Duo partly folded as you like to play. A moment later that angle is remembered; fold it a little shut (about 12°) to press \(HingeControl.button(for: tuning.system)), let it open again to release."
        case .steer:
            return "Hold the Duo partly folded as you like to play. A moment later that angle is remembered; fold it a little shut to press left, open it a little wider to press right. Great for racing games."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("On-screen controls • \(tuning.system.displayName)") {
                    HStack {
                        Text("Button size")
                        Slider(value: $tuning.size, in: 0.75...1.15, step: 0.05)
                        Text("\(Int(tuning.size * 100))%").monospacedDigit().font(.caption)
                    }
                    HStack {
                        Text("Opacity")
                        Slider(value: $tuning.opacity, in: 0.5...1, step: 0.05)
                        Text("\(Int(tuning.opacity * 100))%").monospacedDigit().font(.caption)
                    }
                    Toggle("Floating thumbstick instead of D-pad", isOn: $thumbstick)
                        .accessibilityIdentifier("avydrix-thumbstick-toggle")
                    Toggle("Swap D-pad and action buttons", isOn: $tuning.mirrored)
                    HStack {
                        Text("D-pad position")
                        Slider(value: $tuning.directionOffset, in: -28...28, step: 4)
                    }
                    HStack {
                        Text("Action buttons position")
                        Slider(value: $tuning.actionOffset, in: -28...28, step: 4)
                    }
                    Button("Reset this console's controls") { tuning.reset() }
                }

                Section("Duo display") {
                    Picker("Screen layout", selection: $duoMode) {
                        Text("Automatic").tag("auto")
                        Text("Upper gameplay + lower controls").tag("stacked")
                        Text("Side controls when unfolded").tag("side")
                    }
                    Toggle("Original picture proportions", isOn: $originalAspect)
                    if tuning.system == .gameBoyAdvance {
                        Toggle("Use AVYDRIX GBA console shell in landscape", isOn: $gbaLandscapeControls)
                        Text("The dedicated GBA console shell puts controls beside the game instead of covering it. Turn it off to use the standard Duo layout.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if tuning.system == .nintendoDS {
                        Toggle("Swap DS screens", isOn: $swapDS)
                        HStack {
                            Text("Lower screen size")
                            Slider(value: $dsTouchScale, in: 0.8...1.2, step: 0.05)
                            Text("\(Int(dsTouchScale * 100))%").font(.caption).monospacedDigit()
                        }
                    }
                    Text("A partially folded Duo always keeps gameplay on the upper panel, regardless of your selected layout.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Game display") {
                    Picker("Picture filter", selection: $displayFilter) {
                        Text("Sharp pixels").tag("off")
                        Text("Smooth").tag("smooth")
                        Text("Soft").tag("soft")
                        Text("LCD pixel grid").tag("lcd")
                        Text("CRT scanlines").tag("crt")
                    }
                    Text("Filters change only the presentation, never your game data.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Rewind & fast-forward") {
                    Toggle("Rewind", isOn: Binding(
                        get: { TimeControls.rewindEnabled },
                        set: { UserDefaults.standard.set($0, forKey: TimeControls.rewindKey); hingeRefresh += 1 }
                    ))
                    .accessibilityIdentifier("avydrix-rewind-enabled")
                    Picker("Fast-forward speed", selection: Binding(
                        get: { TimeControls.fastForwardSpeed },
                        set: { UserDefaults.standard.set($0, forKey: TimeControls.speedKey); hingeRefresh += 1 }
                    )) {
                        ForEach(TimeControls.speeds, id: \.self) { Text("\($0)×").tag($0) }
                    }
                    Text("Hold ⏪ in the top bar to go back up to about 10 seconds; tap ⏩ to speed up. Sound is muted while rewinding or fast-forwarding.")
                        .font(.caption).foregroundStyle(.secondary)
                        .id(hingeRefresh)
                }

                Section("Hinge control • \(tuning.system.displayName)") {
                    Picker("Folding the Duo", selection: Binding(
                        get: { HingeControl.mode(for: tuning.system) },
                        set: { UserDefaults.standard.set($0.rawValue, forKey: HingeControl.modeKey(tuning.system)); hingeRefresh += 1 }
                    )) {
                        ForEach(HingeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("avydrix-hinge-mode")
                    if HingeControl.mode(for: tuning.system) == .button {
                        Picker("Squeeze presses", selection: Binding(
                            get: { HingeControl.button(for: tuning.system) },
                            set: { UserDefaults.standard.set($0, forKey: HingeControl.buttonKey(tuning.system)); hingeRefresh += 1 }
                        )) {
                            ForEach(HingeControl.buttonChoices(for: tuning.system), id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Text(hingeHelp)
                        .font(.caption).foregroundStyle(.secondary)
                        .id(hingeRefresh)
                }

                Section("Bluetooth controller • \(tuning.system.displayName)") {
                    ForEach(logical, id: \.self) { button in
                        Picker("Game \(button)", selection: Binding(
                            get: { AVControllerMapping.selected(button, system: tuning.system) ?? defaultButton(for: button) },
                            set: { AVControllerMapping.set($0, for: button, system: tuning.system) }
                        )) {
                            ForEach(AVControllerMapping.physical, id: \.self) { physical in
                                Text("Controller \(physical)").tag(physical)
                            }
                        }
                    }
                    Text("Connect a gamepad through iOS Bluetooth settings. D-pad, analog direction, shoulders and Menu retain their native controls.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AVYDRIX Game Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func defaultButton(for logical: String) -> String {
        switch logical {
        case "A": return "B"
        case "B": return "A"
        case "X": return "Y"
        default: return "X"
        }
    }
}

/// Lightweight pixel-overlay filters, keeping native emulator rendering untouched.
struct AVDisplayFilter: View {
    @AppStorage("avydrix.displayFilter") private var style = "off"

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard style == "lcd" || style == "crt" else { return }
                var lines = Path()
                let pitch: CGFloat = style == "crt" ? 4 : 5
                for y in stride(from: CGFloat(0), through: size.height, by: pitch) {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                if style == "lcd" {
                    for x in stride(from: CGFloat(0), through: size.width, by: pitch) {
                        lines.move(to: CGPoint(x: x, y: 0))
                        lines.addLine(to: CGPoint(x: x, y: size.height))
                    }
                }
                context.stroke(lines, with: .color(.black.opacity(style == "crt" ? 0.22 : 0.12)),
                               lineWidth: style == "crt" ? 1.1 : 0.6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AVSaveManager: View {
    let game: Game
    let save: (String) -> Bool
    let load: (String) -> Bool
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var refreshing = 0
    @State private var overwriting: String?
    @State private var message: String?

    private let slots: [(name: String, id: String)] = [
        ("Quick Slot", "quick"), ("Slot 1", "slot1"), ("Slot 2", "slot2"), ("Slot 3", "slot3")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(game.name).font(.headline).padding(.bottom, 3)
                    ForEach(slots.indices, id: \.self) { index in
                        let slot = slots[index]
                        let exists = FileManager.default.fileExists(atPath: library.stateURL(for: game, slot: slot.id).path)
                        HStack(spacing: 12) {
                            if let cover = UIImage(contentsOfFile: library.statePreviewURL(for: game, slot: slot.id).path) {
                                Image(uiImage: cover).resizable().scaledToFill()
                                    .frame(width: 82, height: 66).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "square.stack.3d.up")
                                    .frame(width: 82, height: 66)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(slot.name).font(.headline)
                                Text(exists ? modifiedText(slot.id) : "Empty")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    Button("Save") {
                                        if exists { overwriting = slot.id }
                                        else { saveSlot(slot.id) }
                                    }
                                    Button("Load") {
                                        message = load(slot.id) ? "Save loaded" : "Unable to load save"
                                        if message == "Save loaded" { dismiss() }
                                    }
                                    .disabled(!exists)
                                }
                                .buttonStyle(.bordered)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                    }
                    Text("Existing Quick Save and Resume files are preserved. Saved screenshots are optional previews.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 5)
                    if let message { Text(message).font(.caption).foregroundStyle(.orange) }
                }
                .padding(18)
                .id(refreshing)
            }
            .background(Color(red: 0.025, green: 0.035, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Visual Save Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Overwrite this save?", isPresented: Binding(
                get: { overwriting != nil }, set: { if !$0 { overwriting = nil } }
            )) {
                Button("Overwrite Save", role: .destructive) {
                    if let slot = overwriting { saveSlot(slot) }
                    overwriting = nil
                }
                Button("Cancel", role: .cancel) { overwriting = nil }
            } message: { Text("The previous save in this slot will be replaced.") }
        }
        .preferredColorScheme(.dark)
    }

    private func modifiedText(_ slot: String) -> String {
        let url = library.stateURL(for: game, slot: slot)
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return "Saved game"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func saveSlot(_ slot: String) {
        message = save(slot) ? "Saved successfully" : "Could not save this slot"
        refreshing += 1
    }
}

struct AVPlayerProfileView: View {
    @ObservedObject var player: AVPlayerProfile
    let games: [Game]
    @Environment(\.dismiss) private var dismiss

    private var favorites: [Game] { games.filter { player.isFavorite($0) } }
    private var recent: [Game] {
        player.data.recent.compactMap { id in games.first(where: { $0.id == id }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("YOUR AVYDRIX PLAYER CARD", systemImage: "person.crop.circle.fill")
                            .foregroundStyle(Color(red: 0.51, green: 0.84, blue: 1))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text("PLAY WITHOUT LIMITS")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Color(red: 0.15, green: 0.17, blue: 0.36), Color(red: 0.08, green: 0.05, blue: 0.20)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 17))
                    HStack(spacing: 10) {
                        stat("GAMES", "\(games.count)", icon: "gamecontroller")
                        stat("SESSIONS", "\(player.totalLaunches)", icon: "play.circle")
                        stat("HOURS", String(format: "%.1f", player.totalSeconds / 3600), icon: "clock")
                    }
                    Text("FAVORITES").font(.system(size: 17, weight: .heavy, design: .rounded))
                    if favorites.isEmpty {
                        Text("Long-press a game in your library to add it to Favorites.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites) { game in
                            HStack {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                Text(game.name)
                                Spacer()
                                Text(game.systemName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("RECENTLY PLAYED").font(.system(size: 17, weight: .heavy, design: .rounded))
                    if recent.isEmpty { Text("Your next game session will appear here.").foregroundStyle(.secondary) }
                    ForEach(recent.prefix(10)) { game in
                        HStack {
                            Text(game.name).lineLimit(1)
                            Spacer()
                            Text(format(player.seconds(for: game))).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    Text("Your play history stays on this device. No account or tracking is required.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(red: 0.02, green: 0.03, blue: 0.07).ignoresSafeArea())
            .navigationTitle("Player Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func stat(_ heading: String, _ value: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(value).font(.system(size: 19, weight: .black, design: .rounded))
            Text(heading).font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func format(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}


/// Built-in emulator test cartridges live behind Settings > Advanced,
/// never in the player-facing home game library.
private struct AVSystemToolsView: View {
    let diagnosticGames: [Game]
    let launchDiagnostic: (Game) -> Void

    var body: some View {
        List {
            Section {
                ForEach(diagnosticGames) { game in
                    Button {
                        launchDiagnostic(game)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: game.system == .nintendoDS
                                  ? "rectangle.split.2x1" : "gamecontroller")
                                .font(.system(size: 21))
                                .frame(width: 40, height: 40)
                                .foregroundStyle(Color(red: 0.36, green: 0.75, blue: 1))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(game.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Built-in controls and sound test")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(Color(red: 0.36, green: 0.75, blue: 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("avydrix-diagnostic-\(game.id)")
                }
            } header: {
                Text("Diagnostic cartridges")
            } footer: {
                Text("These test cartridges help verify controllers, audio, and emulator output. Your imported games remain in the main library.")
            }
        }
        .navigationTitle("System Tools")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if diagnosticGames.isEmpty {
                ContentUnavailableView("No diagnostic cartridges",
                                       systemImage: "wrench.and.screwdriver",
                                       description: Text("The built-in system tests are unavailable."))
            }
        }
        .accessibilityIdentifier("avydrix-system-tools")
    }
}

struct AVSettingsHome: View {
    let diagnosticGames: [Game]
    let launchDiagnostic: (Game) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("avydrix.bootSoundEnabled") private var bootSound = true
    @AppStorage("avydrix.taglineVoiceEnabled") private var femaleTagline = true
    @AppStorage("muted") private var muted = false
    @AppStorage("avydrix.duo.mode") private var duoMode = "auto"
    @AppStorage("avydrix.gba.landscapeControls") private var gbaLandscapeControls = true
    @AppStorage(ThumbStick.settingKey) private var thumbstick = false
    @AppStorage("retroDuoOriginalProportions") private var proportions = false
    @AppStorage("avydrix.displayFilter") private var filter = "off"
    @AppStorage("avydrix.ambientMotionEnabled") private var ambientMotionEnabled = true
    @AppStorage("avydrix.launchAnimationEnabled") private var launchAnimationEnabled = true
    @AppStorage("avydrix.skin") private var selectedSkin = "obsidian"
    @AppStorage("avydrix.dsSwapScreens") private var swapDS = false
    @AppStorage("avydrix.dsTouchScale") private var lowerScale = 1.0

    @State private var system: GameSystem = .nintendoDS
    @State private var showControls = false
    @State private var showAbout = false

    @StateObject private var nes = AVControlTuning(system: .nes)
    @StateObject private var ds = AVControlTuning(system: .nintendoDS)
    @StateObject private var gb = AVControlTuning(system: .gameBoy)
    @StateObject private var gbc = AVControlTuning(system: .gameBoyColor)
    @StateObject private var gba = AVControlTuning(system: .gameBoyAdvance)
    @StateObject private var snes = AVControlTuning(system: .snes)
    @StateObject private var genesis = AVControlTuning(system: .genesis)
    @StateObject private var sms = AVControlTuning(system: .masterSystem)
    @StateObject private var gameGear = AVControlTuning(system: .gameGear)

    private var tuning: AVControlTuning {
        switch system {
        case .nes: return nes
        case .nintendoDS: return ds
        case .gameBoy: return gb
        case .gameBoyColor: return gbc
        case .gameBoyAdvance: return gba
        case .snes: return snes
        case .genesis: return genesis
        case .masterSystem: return sms
        case .gameGear: return gameGear
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(
                                LinearGradient(colors: [
                                    Color(red: 0.08, green: 0.59, blue: 1),
                                    Color(red: 0.43, green: 0.24, blue: 0.95)
                                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("AVYDRIX PLAY")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                            Text("Make every screen yours.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 7)
                }
                Section("Console Skins") {
                    AVConsoleSkinPicker(selectedSkin: $selectedSkin)
                    Text("Your finish changes the dashboard accents and console shell without modifying games, covers or audio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Audio") {
                    Toggle("Startup sound", isOn: $bootSound)
                    Toggle("Female “Play without limits” whisper", isOn: $femaleTagline)
                        .disabled(!bootSound)
                        .accessibilityIdentifier("avydrix-female-tagline-toggle")
                    Toggle("Mute game audio", isOn: $muted)
                }
                Section("Duo Display") {
                    Picker("Screen layout", selection: $duoMode) {
                        Text("Automatic").tag("auto")
                        Text("Upper game, lower controls").tag("stacked")
                        Text("Side controls when unfolded").tag("side")
                    }
                    Toggle("Floating thumbstick instead of D-pad", isOn: $thumbstick)
                    Toggle("Original screen proportions", isOn: $proportions)
                    Toggle("Use GBA console shell in landscape", isOn: $gbaLandscapeControls)
                        .accessibilityIdentifier("avydrix-gba-landscape-controls-toggle")
                    Toggle("Swap Nintendo DS screens", isOn: $swapDS)
                    HStack {
                        Text("Lower DS screen size")
                        Slider(value: $lowerScale, in: 0.8...1.2, step: 0.05)
                        Text("\(Int(lowerScale * 100))%").font(.caption).monospacedDigit()
                    }
                }
                Section("Display") {
                    Picker("Picture filter", selection: $filter) {
                        Text("Sharp pixels").tag("off")
                        Text("Smooth").tag("smooth")
                        Text("Soft").tag("soft")
                        Text("LCD pixel grid").tag("lcd")
                        Text("CRT scanlines").tag("crt")
                    }
                }
                Section("Motion & Transitions") {
                    Toggle("Animated dashboard", isOn: $ambientMotionEnabled)
                        .accessibilityIdentifier("avydrix-ambient-motion-toggle")
                    Toggle("Cartridge insertion on game launch", isOn: $launchAnimationEnabled)
                        .accessibilityIdentifier("avydrix-cartridge-motion-toggle")
                    Text("A subtle moving background and an optional cartridge loading sequence. System Reduce Motion disables both animations automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Controls & Bluetooth") {
                    Picker("Console", selection: $system) {
                        Text("Nintendo DS").tag(GameSystem.nintendoDS)
                        Text("NES").tag(GameSystem.nes)
                        Text("Super Nintendo").tag(GameSystem.snes)
                        Text("Sega Genesis").tag(GameSystem.genesis)
                        Text("Master System").tag(GameSystem.masterSystem)
                        Text("Game Gear").tag(GameSystem.gameGear)
                        Text("Game Boy Color").tag(GameSystem.gameBoyColor)
                        Text("Game Boy Advance").tag(GameSystem.gameBoyAdvance)
                        Text("Game Boy").tag(GameSystem.gameBoy)
                    }
                    Button {
                        showControls = true
                    } label: {
                        Label("Customize buttons & controller mapping", systemImage: "slider.horizontal.3")
                    }
                    Text("Adjust button size, opacity, position, layout, and Bluetooth button mappings for each console.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Advanced") {
                    NavigationLink {
                        AVSystemToolsView(diagnosticGames: diagnosticGames,
                                          launchDiagnostic: launchDiagnostic)
                    } label: {
                        Label("System Tools", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityIdentifier("avydrix-system-tools-link")
                }
                Section("Information") {
                    Button {
                        showAbout = true
                    } label: {
                        Label("About & open-source licenses", systemImage: "info.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.018, green: 0.028, blue: 0.065).ignoresSafeArea())
            .navigationTitle("AVYDRIX Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showControls) {
                AVGameSettings(tuning: tuning)
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
        }
        .tint(Color(red: 0.36, green: 0.75, blue: 1))
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("avydrix-settings")
    }
}

 
// MARK: - AVYDRIX Play 2.0 console identity

enum AVConsoleSkin: String, CaseIterable, Identifiable {
    case obsidian, titanium, ultraviolet, afterburn

    var id: String { rawValue }
    var name: String {
        switch self {
        case .obsidian: return "Obsidian"
        case .titanium: return "Titanium"
        case .ultraviolet: return "Ultraviolet"
        case .afterburn: return "Afterburn"
        }
    }
    var detail: String {
        switch self {
        case .obsidian: return "Midnight metal"
        case .titanium: return "Frosted silver"
        case .ultraviolet: return "Electric violet"
        case .afterburn: return "Arcade neon"
        }
    }
    var accent: Color {
        switch self {
        case .obsidian: return Color(red: 0.17, green: 0.65, blue: 1)
        case .titanium: return Color(red: 0.73, green: 0.85, blue: 0.96)
        case .ultraviolet: return Color(red: 0.67, green: 0.42, blue: 1)
        case .afterburn: return Color(red: 0.20, green: 0.98, blue: 0.76)
        }
    }
    var secondary: Color {
        switch self {
        case .obsidian: return Color(red: 0.45, green: 0.22, blue: 0.93)
        case .titanium: return Color(red: 0.29, green: 0.48, blue: 0.68)
        case .ultraviolet: return Color(red: 0.18, green: 0.42, blue: 1)
        case .afterburn: return Color(red: 0.06, green: 0.48, blue: 0.91)
        }
    }
    var shell: Color {
        switch self {
        case .obsidian: return Color(red: 0.025, green: 0.039, blue: 0.088)
        case .titanium: return Color(red: 0.11, green: 0.15, blue: 0.21)
        case .ultraviolet: return Color(red: 0.068, green: 0.026, blue: 0.14)
        case .afterburn: return Color(red: 0.01, green: 0.09, blue: 0.11)
        }
    }
    static func selected(_ raw: String) -> AVConsoleSkin { AVConsoleSkin(rawValue: raw) ?? .obsidian }
}

struct AVConsoleSkinPicker: View {
    @Binding var selectedSkin: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(AVConsoleSkin.allCases) { skin in
                    let chosen = selectedSkin == skin.rawValue
                    Button {
                        selectedSkin = skin.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(LinearGradient(colors: [skin.secondary, skin.shell, skin.accent.opacity(0.35)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.55), lineWidth: 2)
                                    .padding(14)
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(skin.accent)
                            }
                            .frame(height: 86)
                            Text(skin.name).font(.system(size: 13, weight: .bold))
                            Text(skin.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 129)
                        .padding(9)
                        .background(.white.opacity(chosen ? 0.10 : 0.035),
                                    in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17)
                            .stroke(chosen ? skin.accent : .white.opacity(0.10), lineWidth: chosen ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(skin.name) console skin")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("avydrix-skin-\(skin.rawValue)")
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }
}

// One command surface for GB/NES/GBA/SNES and DS, without altering emulator input.
// Nested tool sheets leave the game paused until the command center is dismissed.
struct AVInGameCommandCenter: View {
    let game: Game
    let muted: Bool
    let quickAvailable: Bool
    @ObservedObject var tuning: AVControlTuning
    @Binding var originalProportions: Bool
    @Binding var useTwoPanels: Bool
    let save: (String) -> Bool
    let load: (String) -> Bool
    let quickSave: () -> Void
    let quickLoad: () -> Void
    let toggleMute: () -> Void
    let restart: () -> Void
    let exit: () -> Void
    /// Closes the menu and lets the player drag and resize the on-screen controls.
    var editControls: (() -> Void)? = nil
    /// Closes the menu and opens live streaming (Twitch, YouTube, Kick).
    var goLive: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("avydrix.skin") private var skinName = "obsidian"
    @State private var showingSettings = false
    @State private var showingSaves = false
    @State private var confirmRestart = false

    private var skin: AVConsoleSkin { .selected(skinName) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28, weight: .bold))
                            .frame(width: 60, height: 60)
                            .foregroundStyle(skin.accent)
                            .background(skin.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("COMMAND CENTER")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .tracking(2.0)
                                .foregroundStyle(skin.accent)
                            Text(game.name)
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .lineLimit(2)
                            Text(game.systemName.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }
                    .padding(.vertical, 5)

                    HStack(spacing: 10) {
                        command("QUICK SAVE", subtitle: "Capture progress", icon: "square.and.arrow.down.fill") {
                            quickSave()
                        }
                        command("QUICK LOAD", subtitle: "Return to save", icon: "arrow.counterclockwise",
                                disabled: !quickAvailable) {
                            quickLoad()
                        }
                    }
                    HStack(spacing: 10) {
                        command("SAVE VAULT", subtitle: "Manage slots", icon: "square.stack.3d.up.fill") {
                            showingSaves = true
                        }
                        command("CONTROLS", subtitle: "Layouts & filters", icon: "slider.horizontal.3") {
                            showingSettings = true
                        }
                    }
                    if let editControls {
                        command("MOVE CONTROLS", subtitle: "Drag & resize buttons", icon: "hand.draw.fill") {
                            editControls()
                        }
                        .accessibilityIdentifier("avydrix-move-controls")
                    }
                    if let goLive {
                        command(LiveStreamer.shared.isActive ? "LIVE NOW" : "GO LIVE",
                                subtitle: "Twitch · YouTube · Kick", icon: "dot.radiowaves.left.and.right") {
                            goLive()
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("CONSOLE OPTIONS")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(skin.accent)
                        Toggle("Fill upper screen", isOn: Binding(
                            get: { !originalProportions },
                            set: { originalProportions = !$0 }
                        ))
                        Toggle("Two-panel Duo layout", isOn: $useTwoPanels)
                        Button {
                            toggleMute()
                        } label: {
                            Label(muted ? "Turn game audio on" : "Mute game audio",
                                  systemImage: muted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(17)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))

                    HStack {
                        Button {
                            confirmRestart = true
                        } label: {
                            Label("Restart game", systemImage: "arrow.clockwise")
                        }
                        Spacer()
                        Button(action: exit) {
                            Label("Exit to library", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 3)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(LinearGradient(colors: [skin.shell, Color(red: 0.012, green: 0.016, blue: 0.041)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea())
            .navigationTitle("AVYDRIX PLAY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("RESUME") { dismiss() }
                        .fontWeight(.bold)
                        .accessibilityIdentifier("avydrix-resume-game")
                }
            }
            .sheet(isPresented: $showingSettings) {
                AVGameSettings(tuning: tuning)
            }
            .sheet(isPresented: $showingSaves) {
                AVSaveManager(game: game, save: save, load: load)
            }
            .confirmationDialog("Restart \(game.name)?", isPresented: $confirmRestart,
                                titleVisibility: .visible) {
                Button("Restart Game", role: .destructive) {
                    restart()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This resets the active game and its automatic resume. Manual save slots stay intact.")
            }
        }
        .tint(skin.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("avydrix-command-center")
    }

    private func command(_ title: String, subtitle: String, icon: String,
                         disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(skin.accent)
                    .frame(height: 29)
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity, minHeight: 97, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(skin.accent.opacity(0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }
}
