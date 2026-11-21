import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// AVYDRIX Play's game-first dashboard. The emulator screens remain separate so
/// changing the storefront cannot change the native controls or Duo layout.
struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @AppStorage("avydrix.lastPlayedGameID") private var lastPlayedGameID = ""
    @AppStorage("avydrix.bootSoundEnabled") private var bootSoundEnabled = true

    @State private var importing = false
    @State private var playing: Game?
    @State private var showingAbout = false
    @State private var selectedSystem: GameSystem?
    @State private var search = ""

    private var ownedGames: [Game] { library.games.filter { !$0.isBuiltIn } }
    private var diagnosticGames: [Game] { library.games.filter(\.isBuiltIn) }

    private var featured: Game? {
        ownedGames.first { $0.id == lastPlayedGameID } ?? ownedGames.first
    }

    private var visibleGames: [Game] {
        ownedGames.filter { game in
            (selectedSystem == nil || game.system == selectedSystem) &&
            (search.isEmpty || game.name.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let compact = geometry.size.width < 650
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 25 : 30) {
                        header(compact: compact)
                        hero(compact: compact)
                        collection(compact: compact)
                        diagnostics(compact: compact)
                        footer
                    }
                    .padding(.horizontal, compact ? 18 : 34)
                    .padding(.top, 12)
                    .padding(.bottom, 45)
                    .frame(maxWidth: 1420)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable { library.refresh() }
                .background(AVBackdrop())
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.gameBoyROM, .gameBoyColorROM, .nintendoDSROM,
                                                UTType(importedAs: "com.ctnetworkstudios.retroduo.nes"), .data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .alert(library.message ?? "", isPresented: Binding(
                get: { library.message != nil },
                set: { if !$0 { library.message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .fullScreenCover(item: $playing) { game in
            if game.system == .nintendoDS {
                DSGameView(session: DSSession(game: game, library: library))
            } else {
                GameView(session: EmulatorSession(game: game, library: library))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            library.refresh()
        }
        .task {
            // UI test launch arguments must continue to jump directly into gameplay.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-RetroDuoDemoDS") {
                playing = library.games.first { $0.system == .nintendoDS }
            } else if arguments.contains("-RetroDuoDemoNES") {
                playing = library.games.first { $0.system.rawValue == "nes" }
            } else if arguments.contains("-RetroDuoDemo") {
                playing = library.games.first
            }
        }
    }

    private func launch(_ game: Game) {
        if !game.isBuiltIn { lastPlayedGameID = game.id }
        playing = game
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [AVPalette.blue, AVPalette.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "a.circle.fill")
                    .font(.system(size: compact ? 23 : 28, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(width: compact ? 43 : 51, height: compact ? 43 : 51)
            .shadow(color: AVPalette.blue.opacity(0.32), radius: 13)

            VStack(alignment: .leading, spacing: 1) {
                Text("AVYDRIX")
                    .font(.system(size: compact ? 19 : 23, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(.white)
                Text("PLAY  /  RETRO DUO")
                    .font(.system(size: compact ? 8 : 10, weight: .bold, design: .monospaced))
                    .tracking(1.7)
                    .foregroundStyle(AVPalette.muted)
            }
            Spacer(minLength: 4)
            Button { bootSoundEnabled.toggle() } label: {
                Image(systemName: bootSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(bootSoundEnabled ? AVPalette.blue : AVPalette.muted)
            .accessibilityLabel(bootSoundEnabled ? "Turn startup sound off" : "Turn startup sound on")

            Button { showingAbout = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("About and settings")

            if !compact {
                Button { importing = true } label: {
                    Label("ADD GAMES", systemImage: "plus")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .padding(.horizontal, 18)
                        .frame(height: 41)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(LinearGradient(colors: [AVPalette.blue, AVPalette.purple], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .accessibilityLabel("Add games")
            }
        }
    }

    private func hero(compact: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.25),
                                              Color(red: 0.09, green: 0.07, blue: 0.20),
                                              Color(red: 0.025, green: 0.035, blue: 0.095)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            GeometryReader { geo in
                Circle()
                    .stroke(AVPalette.blue.opacity(0.19), lineWidth: 1)
                    .frame(width: 330, height: 330)
                    .position(x: geo.size.width * 0.83, y: geo.size.height * 0.48)
                Circle()
                    .stroke(AVPalette.purple.opacity(0.28), lineWidth: 35)
                    .frame(width: 230, height: 230)
                    .blur(radius: 30)
                    .position(x: geo.size.width * 0.80, y: geo.size.height * 0.46)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: compact ? 128 : 210, weight: .ultraLight))
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.16),
                                                               AVPalette.blue.opacity(0.20),
                                                               AVPalette.purple.opacity(0.30)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .rotationEffect(.degrees(-13))
                    .position(x: geo.size.width * (compact ? 0.88 : 0.77), y: geo.size.height * 0.58)
            }
            .clipped()

            VStack(alignment: .leading, spacing: compact ? 13 : 18) {
                HStack(spacing: 8) {
                    Circle().fill(AVPalette.blue).frame(width: 6, height: 6)
                        .shadow(color: AVPalette.blue, radius: 7)
                    Text("WELCOME TO YOUR UNIVERSE")
                        .font(.system(size: compact ? 9 : 11, weight: .bold, design: .monospaced))
                        .tracking(compact ? 1.2 : 2)
                        .foregroundStyle(AVPalette.lightBlue)
                }
                Text("THE CLASSICS.\nREIMAGINED.")
                    .font(.system(size: compact ? 35 : 54, weight: .black, design: .rounded))
                    .tracking(-1.6)
                    .lineSpacing(-3)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.3), radius: 10)

                Text("Your games. Your screens. Your world.")
                    .font(.system(size: compact ? 12 : 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))

                HStack(spacing: 11) {
                    Button {
                        if let featured { launch(featured) } else { importing = true }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: featured == nil ? "plus" : "play.fill")
                            Text(featured == nil ? "ADD YOUR FIRST GAME" : "CONTINUE PLAYING")
                        }
                        .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, compact ? 14 : 21)
                        .frame(height: compact ? 40 : 45)
                        .foregroundStyle(Color.black.opacity(0.88))
                        .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if compact {
                        Button { importing = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.white)
                                .background(.white.opacity(0.13), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add games")
                    }
                }
                .padding(.top, compact ? 1 : 6)
            }
            .padding(compact ? 22 : 34)
        }
        .frame(height: compact ? 300 : 295)
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(
            LinearGradient(colors: [AVPalette.blue.opacity(0.38), AVPalette.purple.opacity(0.21), .white.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: AVPalette.blue.opacity(0.13), radius: 35, y: 12)
        .accessibilityElement(children: .contain)
    }

    private func collection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("GAME LIBRARY")
                    .font(.system(size: compact ? 20 : 26, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .id("collection")
                Text("\(ownedGames.count) GAMES")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(AVPalette.lightBlue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(AVPalette.blue.opacity(0.11), in: Capsule())
            }
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(AVPalette.muted)
                TextField("Search your games", text: $search)
                    .font(.system(size: 14))
                    .tint(AVPalette.blue)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Search your games")
            }
            .padding(.horizontal, 16)
            .frame(height: 47)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.09), lineWidth: 1))

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    filterChip("ALL GAMES", system: nil, count: ownedGames.count)
                    if let nes = GameSystem(rawValue: "nes") {
                        filterChip("NES", system: nes, count: ownedGames.filter { $0.system == nes }.count)
                    }
                    filterChip("NINTENDO DS", system: .nintendoDS, count: ownedGames.filter { $0.system == .nintendoDS }.count)
                    filterChip("GAME BOY COLOR", system: .gameBoyColor, count: ownedGames.filter { $0.system == .gameBoyColor }.count)
                    filterChip("GAME BOY", system: .gameBoy, count: ownedGames.filter { $0.system == .gameBoy }.count)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            if visibleGames.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(AVPalette.lightBlue)
                    Text(ownedGames.isEmpty ? "YOUR NEXT ADVENTURE STARTS HERE" : "NO GAMES FOUND")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white)
                    Text(ownedGames.isEmpty ? "Import a compatible game to build your collection." : "Try another system or search.")
                        .font(.system(size: 13))
                        .foregroundStyle(AVPalette.muted)
                        .multilineTextAlignment(.center)
                    if ownedGames.isEmpty {
                        Button("IMPORT GAMES") { importing = true }
                            .font(.system(size: 12, weight: .bold))
                            .buttonStyle(.borderedProminent)
                            .tint(AVPalette.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(35)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 150 : 205), spacing: compact ? 12 : 17)],
                          spacing: compact ? 12 : 17) {
                    ForEach(visibleGames) { game in
                        Button { launch(game) } label: {
                            AVGameCard(game: game, compact: compact)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(game.name), \(game.systemName)")
                        .contextMenu {
                            Button(role: .destructive) { library.delete(game) } label: {
                                Label("Remove from library", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, system: GameSystem?, count: Int) -> some View {
        let active = selectedSystem == system
        return Button { withAnimation(.easeInOut(duration: 0.18)) { selectedSystem = system } } label: {
            HStack(spacing: 7) {
                Text(title).tracking(0.7)
                Text("\(count)").foregroundStyle(active ? .white : AVPalette.muted)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(active ? .white : AVPalette.muted)
            .padding(.horizontal, 14)
            .frame(height: 35)
            .background(active ? AVPalette.blue.opacity(0.23) : .white.opacity(0.04), in: Capsule())
            .overlay(Capsule().stroke(active ? AVPalette.blue.opacity(0.85) : .white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func diagnostics(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver").foregroundStyle(AVPalette.lightBlue)
                Text("SYSTEM TOOLS")
                    .font(.system(size: compact ? 16 : 19, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                Spacer()
                Text("CONTROLS + AUDIO TESTS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(AVPalette.muted)
                    .lineLimit(1)
            }
            ForEach(diagnosticGames) { game in
                Button { launch(game) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: game.system == .nintendoDS ? "rectangle.split.2x1" : "gamecontroller")
                            .font(.system(size: 21))
                            .foregroundStyle(AVPalette.lightBlue)
                            .frame(width: 45, height: 45)
                            .background(AVPalette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("BUILT-IN DIAGNOSTIC")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(AVPalette.muted)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(AVPalette.blue)
                    }
                    .padding(13)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle").foregroundStyle(AVPalette.blue)
            Text("AVYDRIX PLAY")
            Circle().frame(width: 3, height: 3)
            Text("POWERED BY CTINTERACTIVE")
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(1.2)
        .foregroundStyle(AVPalette.muted)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

private struct AVGameCard: View {
    let game: Game
    let compact: Bool

    private var colors: [Color] {
        switch game.system {
        case .nintendoDS: return [Color(red: 0.16, green: 0.25, blue: 0.52), Color(red: 0.08, green: 0.09, blue: 0.24)]
        case .gameBoyColor: return [Color(red: 0.32, green: 0.12, blue: 0.51), Color(red: 0.06, green: 0.15, blue: 0.34)]
        case .gameBoy: return [Color(red: 0.13, green: 0.34, blue: 0.37), Color(red: 0.06, green: 0.13, blue: 0.19)]
        default: return [Color(red: 0.38, green: 0.16, blue: 0.22), Color(red: 0.12, green: 0.08, blue: 0.17)]
        }
    }

    private var initials: String {
        let words = game.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 170, height: 170)
                    .offset(x: 45, y: -23)
                Circle()
                    .stroke(.white.opacity(0.07), lineWidth: 25)
                    .frame(width: 105, height: 105)
                    .blur(radius: 12)
                    .offset(x: -45, y: 40)
                VStack(spacing: 9) {
                    Image(systemName: game.system.rawValue == "nes" ? "gamecontroller.fill" : game.system == .nintendoDS ? "rectangle.split.2x1.fill" : "gamecontroller.fill")
                        .font(.system(size: compact ? 42 : 55, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.28))
                    Text(initials.isEmpty ? "PLAY" : initials)
                        .font(.system(size: compact ? 27 : 33, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.91))
                        .shadow(color: .black.opacity(0.4), radius: 12)
                }
                .offset(y: 3)
                VStack {
                    HStack {
                        Text(game.system.rawValue == "nes" ? "NES" : game.system == .nintendoDS ? "DS" : game.system == .gameBoyColor ? "GBC" : "GB")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.26), in: Capsule())
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                }
                .padding(12)
                .foregroundStyle(.white)
            }
            .frame(height: compact ? 136 : 166)
            .clipped()

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.name)
                        .font(.system(size: compact ? 12 : 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: compact ? 30 : 37, alignment: .topLeading)
                    Text(game.systemName.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(AVPalette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: compact ? 29 : 34, height: compact ? 29 : 34)
                    .background(AVPalette.lightBlue, in: Circle())
            }
            .padding(compact ? 11 : 14)
        }
        .background(AVPalette.card, in: RoundedRectangle(cornerRadius: 17))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

private enum AVPalette {
    static let blue = Color(red: 0.08, green: 0.60, blue: 1)
    static let purple = Color(red: 0.45, green: 0.23, blue: 0.96)
    static let lightBlue = Color(red: 0.50, green: 0.84, blue: 1)
    static let muted = Color(red: 0.55, green: 0.60, blue: 0.72)
    static let card = Color(red: 0.055, green: 0.068, blue: 0.12)
}

private struct AVBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.027, blue: 0.066)
            RadialGradient(colors: [AVPalette.blue.opacity(0.12), .clear],
                           center: .topLeading, startRadius: 30, endRadius: 620)
            RadialGradient(colors: [AVPalette.purple.opacity(0.09), .clear],
                           center: .bottomTrailing, startRadius: 30, endRadius: 570)
            Canvas { context, size in
                var lines = Path()
                for y in stride(from: 0.0, through: size.height, by: 5.0) {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(.white.opacity(0.012)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}
