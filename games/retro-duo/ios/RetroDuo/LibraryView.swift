import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI
import Combine

/// AVYDRIX Play's game-first dashboard. The emulator screens remain separate so
/// changing the storefront cannot change the native controls or Duo layout.
struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @AppStorage("avydrix.lastPlayedGameID") private var lastPlayedGameID = ""
    @AppStorage("avydrix.bootSoundEnabled") private var bootSoundEnabled = true
    @AppStorage("avydrix.skin") private var skinName = "obsidian"
    @AppStorage("avydrix.ambientMotionEnabled") private var ambientMotionEnabled = true
    @AppStorage("avydrix.launchAnimationEnabled") private var launchAnimationEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var importing = false
    @State private var playing: Game?
    @State private var pendingLaunch: Game?
    @State private var launchTask: Task<Void, Never>?
    @State private var showingSettings = false
    @State private var diagnosticAfterSettings: Game?
    @State private var settingCoverFor: Game?
    @State private var featuredIndex = 0
    @StateObject private var covers = GameCoverLibrary()
    @StateObject private var profile = AVPlayerProfile()
    @State private var showingProfile = false
    @State private var showingFavoritesOnly = false
    @State private var selectedSystem: GameSystem?
    @State private var search = ""

    private var skin: AVConsoleSkin { .selected(skinName) }

    private var ownedGames: [Game] { library.games.filter { !$0.isBuiltIn || $0.isBundledGame } }
    private var diagnosticGames: [Game] { library.games.filter { $0.isBuiltIn && !$0.isBundledGame } }

    private var showcasedGames: [Game] {
        let order = [lastPlayedGameID] + profile.data.favorites + profile.data.recent
        let sorted = order.compactMap { id in ownedGames.first { $0.id == id } }
        let unique = sorted.reduce(into: [Game]()) { result, game in
            if !result.contains(game) { result.append(game) }
        }
        return Array((unique + ownedGames.filter { !unique.contains($0) }).prefix(12))
    }

    private var visibleGames: [Game] {
        ownedGames.filter { game in
            (selectedSystem == nil || game.system == selectedSystem) &&
            (!showingFavoritesOnly || profile.isFavorite(game)) &&
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
                        featuredCarousel(compact: compact)
                        consoleShelf(compact: compact)
                        recentlyPlayed(compact: compact)
                        collection(compact: compact)
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
                .background(AVBackdrop(animated: ambientMotionEnabled && !reduceMotion &&
                                       playing == nil && pendingLaunch == nil && scenePhase == .active))
                // Keep ROM import reachable on the narrow folded display without
                // squeezing the brand, profile and settings buttons in the header.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if compact {
                        HStack {
                            Spacer(minLength: 0)
                            Button { importing = true } label: {
                                Label("ADD GAMES", systemImage: "plus")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .tracking(0.9)
                                    .padding(.horizontal, 22)
                                    .frame(minHeight: 48)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(colors: [AVPalette.blue, AVPalette.purple],
                                               startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                            .shadow(color: AVPalette.blue.opacity(0.3), radius: 14, y: 5)
                            .accessibilityLabel("Add games")
                            .accessibilityIdentifier("avydrix-add-games-compact")
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color(red: 0.014, green: 0.023, blue: 0.061).opacity(0.95))
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.gameBoyROM, .gameBoyColorROM, .gameBoyAdvanceROM, .snesROM, .genesisROM, .masterSystemROM, .gameGearROM, .nintendoDSROM,
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
            .sheet(isPresented: $showingSettings, onDismiss: {
                // Dismiss Settings before presenting gameplay, avoiding
                // competing modal presentations on compact/folded displays.
                guard let game = diagnosticAfterSettings else { return }
                diagnosticAfterSettings = nil
                launch(game)
            }) {
                AVSettingsHome(diagnosticGames: diagnosticGames) { game in
                    diagnosticAfterSettings = game
                    showingSettings = false
                }
            }
            .sheet(isPresented: $showingProfile) {
                AVPlayerProfileView(player: profile, games: ownedGames)
            }
            .sheet(item: $settingCoverFor) { game in
                AVArtworkPickerSheet(game: game, covers: covers)
                    .presentationDetents([.medium, .large])
            }
        }
        .overlay {
            if let game = pendingLaunch {
                AVCartridgeLaunchView(game: game, artwork: covers.image(for: game))
                    .transition(.opacity)
                    .zIndex(30)
                    .accessibilityIdentifier("avydrix-cartridge-launch")
            }
        }
        .animation(.easeInOut(duration: 0.18), value: pendingLaunch?.id)
        .fullScreenCover(item: $playing, onDismiss: { profile.finish() }) { game in
            if game.system == .nintendoDS {
                DSGameView(session: DSSession(game: game, library: library))
            } else {
                GameView(session: EmulatorSession(game: game, library: library))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            library.refresh()
            covers.discover(ownedGames)
        }
        .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
            guard playing == nil, pendingLaunch == nil, showcasedGames.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                featuredIndex = (featuredIndex + 1) % showcasedGames.count
            }
        }
        .task(id: ownedGames.map(\.id).joined(separator: "|")) {
            covers.discover(ownedGames)
            if featuredIndex >= showcasedGames.count { featuredIndex = 0 }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // An interrupted insert animation should never unexpectedly open a game.
            if newPhase != .active, pendingLaunch != nil {
                launchTask?.cancel()
                launchTask = nil
                pendingLaunch = nil
            }
        }
        .onDisappear {
            launchTask?.cancel()
            launchTask = nil
        }
        .task {
            // UI test launch arguments must continue to jump directly into gameplay.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-RetroDuoDemoDS") {
                playing = library.games.first { $0.system == .nintendoDS }
            } else if arguments.contains("-RetroDuoDemoGBA") {
                playing = library.games.first { $0.system == .gameBoyAdvance }
            } else if arguments.contains("-RetroDuoDemoGenesis") {
                playing = library.games.first { $0.system == .genesis }
            } else if arguments.contains("-RetroDuoDemoSMS") {
                playing = library.games.first { $0.system == .masterSystem }
            } else if arguments.contains("-RetroDuoDemoGG") {
                playing = library.games.first { $0.system == .gameGear }
            } else if arguments.contains("-RetroDuoDemoSNES") {
                playing = library.games.first { $0.system == .snes }
            } else if arguments.contains("-RetroDuoDemoNES") {
                playing = library.games.first { $0.system.rawValue == "nes" }
            } else if arguments.contains("-RetroDuoDemo") {
                playing = library.games.first
            }
        }
    }

    private func launch(_ game: Game) {
        // All library, featured and recently-played actions share this entrypoint.
        // Never queue two ROM launches or re-trigger play while a game is open.
        guard pendingLaunch == nil, playing == nil else { return }
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-RetroDuoUITests")
        guard launchAnimationEnabled && !reduceMotion && !isUITesting && scenePhase == .active else {
            openGame(game)
            return
        }

        pendingLaunch = game
        launchTask?.cancel()
        launchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled, pendingLaunch?.id == game.id else { return }
            pendingLaunch = nil
            launchTask = nil
            openGame(game)
        }
    }

    private func openGame(_ game: Game) {
        if !game.isBuiltIn || game.isBundledGame { lastPlayedGameID = game.id }
        profile.start(game)
        playing = game
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [skin.accent, skin.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "a.circle.fill")
                    .font(.system(size: compact ? 23 : 28, weight: .light))
                    .foregroundStyle(.white)
            }
            .frame(width: compact ? 43 : 51, height: compact ? 43 : 51)
            .shadow(color: skin.accent.opacity(0.32), radius: 13)

            VStack(alignment: .leading, spacing: 1) {
                Text("AVYDRIX")
                    .font(.system(size: compact ? 19 : 23, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(.white)
                Text("PLAY  /  CTINTERACTIVE")
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

            Button { showingProfile = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("AVYDRIX player profile")

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("AVYDRIX settings")

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

    private func featuredCarousel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showcasedGames.isEmpty {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 25)
                        .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.29),
                                                      Color(red: 0.12, green: 0.065, blue: 0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(alignment: .leading, spacing: 14) {
                        Label("AVYDRIX GAME COLLECTION", systemImage: "sparkles")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.3)
                            .foregroundStyle(AVPalette.lightBlue)
                        Text("YOUR NEXT ADVENTURE\nSTARTS HERE.")
                            .font(.system(size: compact ? 31 : 46, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Add a game to create your featured slideshow.")
                            .font(.system(size: compact ? 13 : 15))
                            .foregroundStyle(.white.opacity(0.72))
                        Button { importing = true } label: {
                            Label("ADD GAMES", systemImage: "plus")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 20)
                                .frame(height: 42)
                                .foregroundStyle(.black)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(compact ? 25 : 34)
                }
                .frame(height: compact ? 270 : 315)
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(AVPalette.blue.opacity(0.35)))
                .accessibilityIdentifier("avydrix-empty-spotlight")
            } else {
                TabView(selection: $featuredIndex) {
                    ForEach(showcasedGames.indices, id: \.self) { index in
                        let game = showcasedGames[index]
                        Button { launch(game) } label: {
                            AVFeaturedSpotlight(game: game,
                                                covers: covers,
                                                compact: compact,
                                                isContinue: game.id == lastPlayedGameID && library.hasProtectedResume(for: game))
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                        .accessibilityLabel("Play featured game \(index + 1) of \(showcasedGames.count): \(game.name)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: compact ? 300 : 335)
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(
                    LinearGradient(colors: [AVPalette.blue.opacity(0.50), AVPalette.purple.opacity(0.35), .white.opacity(0.09)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: AVPalette.blue.opacity(0.15), radius: 24, y: 8)
                .accessibilityIdentifier("avydrix-featured-carousel")

                HStack(spacing: 7) {
                    Image(systemName: "rectangle.stack.fill")
                        .foregroundStyle(AVPalette.lightBlue)
                    Text("FEATURED FROM YOUR LIBRARY")
                        .foregroundStyle(AVPalette.muted)
                    Spacer()
                    ForEach(showcasedGames.indices, id: \.self) { index in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { featuredIndex = index }
                        } label: {
                            Capsule()
                                .fill(index == featuredIndex ? AVPalette.blue : Color.white.opacity(0.19))
                                .frame(width: index == featuredIndex ? 22 : 6, height: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show featured game \(index + 1)")
                    }
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
    }

    /// Swipeable perspective shelf is an additional view of the original library.
    /// Artwork, launches, favorites and ROM locations are shared with the grid.
    private func consoleShelf(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(skin.accent)
                Text("CONSOLE SHELF")
                    .font(.system(size: compact ? 16 : 19, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text("SWIPE TO EXPLORE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if !showcasedGames.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: compact ? 11 : 18) {
                        ForEach(showcasedGames) { game in
                            Button {
                                launch(game)
                            } label: {
                                VStack(spacing: 9) {
                                    AVGameCard(game: game, compact: compact, covers: covers,
                                               favorite: profile.isFavorite(game))
                                        .shadow(color: skin.accent.opacity(0.20), radius: 19, y: 9)
                                    HStack(spacing: 5) {
                                        Image(systemName: library.hasProtectedResume(for: game)
                                              ? "checkmark.shield.fill" : "gamecontroller.fill")
                                        Text(library.hasProtectedResume(for: game)
                                             ? "RESUME PROTECTED" : "READY TO PLAY")
                                    }
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(library.hasProtectedResume(for: game)
                                                     ? skin.accent : .white.opacity(0.52))
                                }
                                .frame(width: compact ? 172 : 219)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(game.name) from console shelf")
                            .contextMenu {
                                Button {
                                    profile.toggleFavorite(game)
                                } label: {
                                    Label(profile.isFavorite(game) ? "Remove Favorite" : "Add to Favorites",
                                          systemImage: profile.isFavorite(game) ? "star.slash" : "star")
                                }
                                Button {
                                    settingCoverFor = game
                                } label: {
                                    Label("Change cover", systemImage: "photo")
                                }
                            }
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .rotation3DEffect(.degrees(Double(phase.value) * -26),
                                                      axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.85)
                                    .opacity(phase.isIdentity ? 1.0 : 0.68)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 6)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .background(alignment: .bottom) {
                    Capsule()
                        .fill(skin.accent.opacity(0.12))
                        .blur(radius: 24)
                        .frame(height: 14)
                        .padding(.bottom, 27)
                        .allowsHitTesting(false)
                }
                .accessibilityIdentifier("avydrix-3d-console-shelf")
            }
        }
    }

    private func recentlyPlayed(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("RECENTLY PLAYED", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: compact ? 15 : 18, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                Spacer()
                Button { showingProfile = true } label: {
                    Text("PLAYER PROFILE")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AVPalette.lightBlue)
                }
                .buttonStyle(.plain)
            }
            if profile.data.recent.isEmpty {
                Text("Launch a game to start your play history.")
                    .font(.footnote)
                    .foregroundStyle(AVPalette.muted)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(profile.data.recent.prefix(7)), id: \.self) { id in
                            if let game = ownedGames.first(where: { $0.id == id }) {
                                Button { launch(game) } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(AVPalette.lightBlue)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(game.name).lineLimit(1)
                                            Text(game.systemName.uppercased())
                                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(AVPalette.muted)
                                        }
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: 220)
                                    .padding(13)
                                    .background(AVPalette.card, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.09)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
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
                Spacer(minLength: 0)
                if !ownedGames.isEmpty && ownedGames.contains(where: { !$0.isBuiltIn && covers.image(for: $0) == nil }) {
                    Button { covers.retryMissing(ownedGames) } label: {
                        Label("FIND COVERS", systemImage: "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AVPalette.lightBlue)
                    .accessibilityIdentifier("avydrix-retry-covers")
                }
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
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showingFavoritesOnly.toggle() }
                    } label: {
                        Label("FAVORITES", systemImage: "star.fill")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(showingFavoritesOnly ? .white : AVPalette.muted)
                            .padding(.horizontal, 14)
                            .frame(height: 35)
                            .background(showingFavoritesOnly ? AVPalette.blue.opacity(0.23) : .white.opacity(0.04), in: Capsule())
                            .overlay(Capsule().stroke(showingFavoritesOnly ? AVPalette.blue : .white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    ForEach(GameSystem.allCases, id: \.self) { system in
                        filterChip(system.filterName, system: system, count: ownedGames.filter { $0.system == system }.count)
                    }
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
                            AVGameCard(game: game, compact: compact, covers: covers,
                                       favorite: profile.isFavorite(game))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(game.name), \(game.systemName)")
                        .contextMenu {
                            Button { profile.toggleFavorite(game) } label: {
                                Label(profile.isFavorite(game) ? "Remove Favorite" : "Add to Favorites",
                                      systemImage: profile.isFavorite(game) ? "star.slash" : "star")
                            }
                            Button { settingCoverFor = game } label: {
                                Label("Set or change cover", systemImage: "photo")
                            }
                            Button { covers.reload(game) } label: {
                                Label("Find artwork online", systemImage: "arrow.clockwise")
                            }
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
    @ObservedObject var covers: GameCoverLibrary
    let favorite: Bool

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
            GeometryReader { geo in
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let cover = covers.image(for: game) {
                        // Keep the *entire* box art visible, including the top and title.
                        // A blurred copy fills the unused side space without stretching art.
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 18)
                            .overlay(.black.opacity(0.36))
                            .accessibilityHidden(true)
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .accessibilityHidden(true)
                    } else {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 2)
                            .frame(width: 170, height: 170)
                            .offset(x: 45, y: -23)
                        VStack(spacing: 9) {
                            Image(systemName: game.system == .nintendoDS ? "rectangle.split.2x1.fill" : "gamecontroller.fill")
                                .font(.system(size: compact ? 42 : 55, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.28))
                            Text(initials.isEmpty ? "PLAY" : initials)
                                .font(.system(size: compact ? 27 : 33, weight: .black, design: .rounded))
                                .tracking(3)
                                .foregroundStyle(.white.opacity(0.91))
                        }
                    }
                    VStack {
                        HStack {
                            Text(game.system.shortName)
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .tracking(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                            Spacer()
                            if favorite {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.system(size: 12))
                                    .padding(.trailing, 4)
                            }
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .padding(7)
                                .background(.black.opacity(0.42), in: Circle())
                        }
                        Spacer()
                    }
                    .padding(11)
                    .foregroundStyle(.white)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            .frame(height: compact ? 170 : 228)

            HStack(alignment: .center, spacing: 7) {
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

private struct AVFeaturedSpotlight: View {
    let game: Game
    @ObservedObject var covers: GameCoverLibrary
    let compact: Bool
    let isContinue: Bool

    private var title: String {
        let first = game.name.components(separatedBy: " (").first ?? game.name
        return first.isEmpty ? game.name : first
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(colors: [
                    Color(red: 0.09, green: 0.16, blue: 0.37),
                    Color(red: 0.13, green: 0.075, blue: 0.30),
                    Color(red: 0.025, green: 0.04, blue: 0.12)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)

                if let cover = covers.image(for: game) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ZStack {
                            Image(uiImage: cover)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width * (compact ? 0.70 : 0.58),
                                       height: geo.size.height)
                                .clipped()
                                .blur(radius: 20)
                                .overlay(.black.opacity(0.24))
                            Image(uiImage: cover)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width * (compact ? 0.70 : 0.58),
                                       height: geo.size.height)
                        }
                        .frame(width: geo.size.width * (compact ? 0.70 : 0.58),
                               height: geo.size.height)
                        .clipped()
                    }
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: game.system == .nintendoDS ? "rectangle.split.2x1.fill" : "gamecontroller.fill")
                        .font(.system(size: compact ? 115 : 175, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.12))
                        .rotationEffect(.degrees(-12))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 15)
                }

                LinearGradient(stops: [
                    .init(color: Color(red: 0.015, green: 0.025, blue: 0.07).opacity(0.97), location: 0),
                    .init(color: Color(red: 0.035, green: 0.045, blue: 0.14).opacity(0.94), location: 0.30),
                    .init(color: Color(red: 0.05, green: 0.045, blue: 0.13).opacity(0.65), location: 0.57),
                    .init(color: .black.opacity(0.04), location: 1.0)
                ], startPoint: .leading, endPoint: .trailing)

                VStack(alignment: .leading, spacing: compact ? 13 : 17) {
                    HStack(spacing: 8) {
                        Circle().fill(AVPalette.blue).frame(width: 7, height: 7)
                            .shadow(color: AVPalette.blue, radius: 8)
                        Text("FEATURED GAME")
                            .font(.system(size: compact ? 10 : 11, weight: .heavy, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(AVPalette.lightBlue)
                    }
                    Spacer(minLength: 2)
                    Text(title.uppercased())
                        .font(.system(size: compact ? 31 : 51, weight: .black, design: .rounded))
                        .tracking(-1)
                        .lineLimit(3)
                        .minimumScaleFactor(0.63)
                        .foregroundStyle(.white)
                        .frame(maxWidth: geo.size.width * (compact ? 0.79 : 0.60), alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.55), radius: 8)

                    Text(game.systemName.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.7)
                        .foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                        Text(isContinue ? "CONTINUE PLAYING" : "PLAY NOW")
                    }
                    .font(.system(size: compact ? 11 : 13, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(Color(red: 0.03, green: 0.035, blue: 0.07))
                    .padding(.horizontal, compact ? 17 : 23)
                    .frame(height: compact ? 39 : 46)
                    .background(.white, in: Capsule())
                    Spacer(minLength: 3)
                }
                .padding(compact ? 24 : 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .contentShape(Rectangle())
    }
}

private enum AVPalette {
    static let blue = Color(red: 0.08, green: 0.60, blue: 1)
    static let purple = Color(red: 0.45, green: 0.23, blue: 0.96)
    static let lightBlue = Color(red: 0.50, green: 0.84, blue: 1)
    static let muted = Color(red: 0.55, green: 0.60, blue: 0.72)
    static let card = Color(red: 0.055, green: 0.068, blue: 0.12)
}

/// Cinematic but lightweight game handoff: cartridge visibly slides into a system
/// slot before the existing emulator view is opened. No emulator code is touched.
private struct AVCartridgeLaunchView: View {
    let game: Game
    let artwork: UIImage?

    @State private var inserted = false
    @State private var powered = false

    private var systemCode: String {
        switch game.system.rawValue {
        case "nes": return "NES"
        case "snes": return "SNES"
        case "genesis": return "GENESIS"
        case "masterSystem": return "SMS"
        case "gameGear": return "GG"
        case "gameBoy": return "GB"
        case "gameBoyColor": return "GBC"
        case "nintendoDS": return "DS"
        default: return game.systemName.uppercased()
        }
    }

    private var cartWidth: CGFloat {
        switch game.system.rawValue {
        case "nes": return 142
        case "nintendoDS": return 104
        default: return 124
        }
    }

    private var cartHeight: CGFloat {
        game.system.rawValue == "nintendoDS" ? 133 : 164
    }

    var body: some View {
        GeometryReader { screen in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.007, green: 0.020, blue: 0.058),
                        Color(red: 0.047, green: 0.034, blue: 0.13),
                        Color(red: 0.009, green: 0.013, blue: 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.05, green: 0.62, blue: 1).opacity(powered ? 0.27 : 0.10),
                        .clear
                    ],
                    center: .center, startRadius: 20, endRadius: 360
                )

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(red: 0.12, green: 0.70, blue: 1))
                            .frame(width: 7, height: 7)
                            .shadow(color: .cyan.opacity(0.85), radius: 8)
                        Text("AVYDRIX PLAY")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .tracking(2.5)
                        Spacer()
                        Text("GAME LOAD")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 42)

                    Spacer(minLength: 12)

                    ZStack {
                        Circle()
                            .stroke(Color(red: 0.20, green: 0.59, blue: 1).opacity(powered ? 0.30 : 0.12),
                                    lineWidth: 1)
                            .frame(width: 265, height: 265)
                            .scaleEffect(powered ? 1.08 : 0.93)
                        Circle()
                            .stroke(Color(red: 0.55, green: 0.33, blue: 1).opacity(0.17),
                                    lineWidth: 1.2)
                            .frame(width: 216, height: 216)
                            .scaleEffect(powered ? 1.12 : 1)

                        // The cartridge is behind the system's front plate.
                        cartridge
                            .frame(width: cartWidth, height: cartHeight)
                            .offset(y: inserted ? 49 : -121)
                            .shadow(color: Color(red: 0.16, green: 0.55, blue: 1).opacity(0.34),
                                    radius: 22, y: 2)

                        systemHousing
                            .offset(y: 99)

                        Capsule()
                            .fill(Color.black.opacity(0.91))
                            .frame(width: systemCode == "NES" ? 174 : 147, height: 11)
                            .overlay(
                                Capsule().stroke(
                                    Color(red: 0.40, green: 0.78, blue: 1).opacity(powered ? 0.95 : 0.23),
                                    lineWidth: 1
                                )
                            )
                            .shadow(color: .cyan.opacity(powered ? 0.65 : 0), radius: 12)
                            .offset(y: 36)
                    }
                    .frame(width: 320, height: 335)
                    .animation(.easeInOut(duration: 0.24), value: powered)

                    Spacer(minLength: 14)

                    VStack(spacing: 10) {
                        Text(game.name.uppercased())
                            .font(.system(size: screen.size.width < 520 ? 22 : 29,
                                          weight: .black, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Text(game.systemName.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Color(red: 0.60, green: 0.81, blue: 1))
                        HStack(spacing: 8) {
                            Image(systemName: powered ? "checkmark.circle.fill" : "arrow.down.to.line.compact")
                                .foregroundStyle(powered ? .green : .cyan)
                            Text(powered ? "CARTRIDGE LOADED" : "INSERTING CARTRIDGE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1.25)
                        }
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.top, 8)

                        Capsule()
                            .fill(.white.opacity(0.10))
                            .frame(width: 192, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(
                                        LinearGradient(colors: [
                                            Color(red: 0.08, green: 0.69, blue: 1),
                                            Color(red: 0.49, green: 0.30, blue: 1)
                                        ], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .frame(width: inserted ? (powered ? 192 : 140) : 14, height: 4)
                            }
                            .animation(.easeInOut(duration: 0.48), value: inserted)
                            .animation(.easeInOut(duration: 0.17), value: powered)
                            .padding(.top, 10)
                    }
                    .frame(maxWidth: 355)
                    .padding(.bottom, 44)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 29)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: screen.size.width, height: screen.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Inserting \(game.name) cartridge for \(game.systemName)")
        .task {
            try? await Task.sleep(nanoseconds: 95_000_000)
            guard !Task.isCancelled else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.48, dampingFraction: 0.83)) {
                inserted = true
            }
            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.17)) {
                powered = true
            }
        }
    }

    private var cartridge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: systemCode == "DS" ? 10 : 15)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.32, blue: 0.48),
                        Color(red: 0.09, green: 0.11, blue: 0.22)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: systemCode == "DS" ? 10 : 15)
                .stroke(.white.opacity(0.22), lineWidth: 1.4)

            VStack(spacing: 7) {
                HStack {
                    Text(systemCode)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1)
                    Spacer()
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.78))

                GeometryReader { label in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 0.10, green: 0.42, blue: 0.87),
                                    Color(red: 0.38, green: 0.16, blue: 0.66)
                                ], startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        if let artwork {
                            Image(uiImage: artwork)
                                .resizable()
                                .scaledToFill()
                                .frame(width: label.size.width, height: label.size.height)
                                .clipped()
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 18))
                                Text(game.name.uppercased())
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.65)
                            }
                            .foregroundStyle(.white)
                            .padding(4)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("CTINTERACTIVE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.59))
            }
            .padding(9)
        }
        .accessibilityHidden(true)
    }

    private var systemHousing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.21, green: 0.25, blue: 0.39),
                        Color(red: 0.07, green: 0.09, blue: 0.19),
                        Color(red: 0.035, green: 0.045, blue: 0.11)
                    ], startPoint: .top, endPoint: .bottom
                ))
            RoundedRectangle(cornerRadius: 23)
                .stroke(.white.opacity(0.18), lineWidth: 1)
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("AVYDRIX")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.90))
                    Text("\(systemCode)  /  PLAY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: systemCode == "DS" ? "rectangle.split.2x1" : "gamecontroller")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(.white.opacity(0.39))
                    Circle()
                        .fill(powered ? Color.green : Color(red: 0.21, green: 0.28, blue: 0.34))
                        .frame(width: 9, height: 9)
                        .shadow(color: powered ? .green : .clear, radius: 9)
                }
            }
            .padding(.horizontal, 21)
            .padding(.top, 29)
        }
        .frame(width: 284, height: 128)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}

/// A visibly living, but low-power, AVYDRIX dashboard background.
/// The artwork and text remain above the backdrop; all motion respects
/// the in-app toggle, system Reduce Motion, scene visibility and gameplay.
private struct AVBackdrop: View {
    let animated: Bool
    @AppStorage("avydrix.skin") private var skinName = "obsidian"

    var body: some View {
        let skin = AVConsoleSkin.selected(skinName)
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animated)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas(opaque: true) { context, size in
                let width = max(size.width, 1)
                let height = max(size.height, 1)
                let frame = Path(CGRect(origin: .zero, size: size))
                context.fill(frame, with: .linearGradient(
                    Gradient(colors: [skin.shell, skin.secondary.opacity(0.26), skin.shell]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: width, y: height)
                ))

                // Two luminous auroras cross the open areas of the library.
                // Rendering as gradients in one Canvas avoids GPU-heavy blurs.
                let palette: [Color] = [skin.accent, skin.secondary, skin.accent.opacity(0.75)]
                for index in 0..<3 {
                    let shift = CGFloat(sin(time * (0.23 + Double(index) * 0.045)
                                             + Double(index) * 1.3))
                    let sway = CGFloat(cos(time * 0.19 + Double(index)))
                    let baseX = width * (0.14 + CGFloat(index) * 0.33)
                    var ribbon = Path()
                    ribbon.move(to: CGPoint(x: baseX - 85 + shift * 96, y: -height * 0.15))
                    ribbon.addCurve(
                        to: CGPoint(x: baseX + sway * 95, y: height * 1.15),
                        control1: CGPoint(x: baseX + 170 + shift * 65, y: height * 0.25),
                        control2: CGPoint(x: baseX - 150 + sway * 70, y: height * 0.72)
                    )
                    let glow = palette[index]
                    context.stroke(
                        ribbon,
                        with: .linearGradient(
                            Gradient(colors: [
                                glow.opacity(0.005),
                                glow.opacity(index == 0 ? 0.18 : 0.115),
                                glow.opacity(0.055),
                                glow.opacity(0.0)
                            ]),
                            startPoint: CGPoint(x: baseX - 180, y: 0),
                            endPoint: CGPoint(x: baseX + 180, y: height)
                        ),
                        style: StrokeStyle(lineWidth: 155, lineCap: .round)
                    )
                    context.stroke(ribbon,
                                   with: .color(glow.opacity(0.035)),
                                   style: StrokeStyle(lineWidth: 26, lineCap: .round))
                }

                let lights: [(CGPoint, CGFloat, Color)] = [
                    (CGPoint(x: width * (0.07 + 0.24 * sin(time * 0.21)),
                             y: height * (0.13 + 0.10 * cos(time * 0.14))),
                     max(width, height) * 0.52,
                     skin.accent),
                    (CGPoint(x: width * (0.84 + 0.12 * cos(time * 0.13)),
                             y: height * (0.73 + 0.11 * sin(time * 0.17))),
                     max(width, height) * 0.63,
                     skin.secondary),
                    (CGPoint(x: width * (0.75 + 0.17 * sin(time * 0.17)),
                             y: height * (0.28 + 0.12 * cos(time * 0.11))),
                     max(width, height) * 0.39,
                     skin.accent.opacity(0.75))
                ]
                for (center, radius, color) in lights {
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                              width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            Gradient(colors: [
                                color.opacity(0.29),
                                color.opacity(0.09),
                                color.opacity(0)
                            ]),
                            center: center, startRadius: 0, endRadius: radius
                        )
                    )
                }

                // A restrained constellation and slow shifting technical rings.
                let orbit = CGPoint(x: width * 0.70, y: height * 0.43)
                for index in 0..<3 {
                    let radius = CGFloat(165 + index * 130) +
                                 CGFloat(sin(time * 0.22 + Double(index))) * 24
                    context.stroke(
                        Path(ellipseIn: CGRect(x: orbit.x - radius, y: orbit.y - radius,
                                              width: radius * 2, height: radius * 2)),
                        with: .color(.cyan.opacity(index == 0 ? 0.095 : 0.055)),
                        lineWidth: 1.1
                    )
                }

                var scanlines = Path()
                for y in stride(from: CGFloat(0), through: height, by: CGFloat(36)) {
                    scanlines.move(to: CGPoint(x: 0, y: y))
                    scanlines.addLine(to: CGPoint(x: width, y: y))
                }
                context.stroke(scanlines, with: .color(.white.opacity(0.018)),
                               lineWidth: 0.5)

                for index in 0..<34 {
                    let seed = Double(index)
                    let x = width * CGFloat(
                        (seed * 0.6180339887 + time * 0.0013 *
                         (index.isMultiple(of: 2) ? 1 : -1))
                            .truncatingRemainder(dividingBy: 1).magnitude
                    )
                    let y = height * CGFloat(
                        (seed * 0.371 + time * (0.010 + seed * 0.00037))
                            .truncatingRemainder(dividingBy: 1).magnitude
                    )
                    let radius: CGFloat = index.isMultiple(of: 5) ? 2.8 : 1.3
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y,
                                              width: radius, height: radius)),
                        with: .color(Color(red: 0.64, green: 0.89, blue: 1)
                            .opacity(index.isMultiple(of: 5) ? 0.44 : 0.21))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("avydrix-animated-aurora")
    }
}

// Cover art lives in Documents/Covers and never touches ROM contents or save games.
// Exact filename matching gets existing Libretro box art; users can override any image.
@MainActor
private final class GameCoverLibrary: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]

    private let directory: URL
    private var attempted = Set<String>()
    private var inFlight = Set<String>()
    private var lastAttempt: [String: Date] = [:]

    init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for game: Game) -> UIImage? {
        images[game.id] ?? game.coverResource.flatMap { resource in
            if let url = Bundle.main.url(forResource: resource, withExtension: "jpg"),
               let cover = UIImage(contentsOfFile: url.path) {
                return cover
            }
            return UIImage(named: resource)
        }
    }

    func discover(_ games: [Game], force: Bool = false) {
        for game in games where !game.isBuiltIn && images[game.id] == nil {
            guard !inFlight.contains(game.id) else { continue }
            if !force, let previous = lastAttempt[game.id],
               Date().timeIntervalSince(previous) < 90 { continue }
            lastAttempt[game.id] = Date()
            attempted.insert(game.id)
            inFlight.insert(game.id)
            Task {
                await retrieve(game)
                inFlight.remove(game.id)
            }
        }
    }

    func retryMissing(_ games: [Game]) {
        discover(games, force: true)
    }

    func reload(_ game: Game) {
        images.removeValue(forKey: game.id)
        for name in [game.id, game.name] {
            for ext in ["jpg", "jpeg", "png"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name).appendingPathExtension(ext))
            }
        }
        attempted.remove(game.id)
        lastAttempt.removeValue(forKey: game.id)
        discover([game], force: true)
    }

    func save(_ data: Data, for game: Game) throws {
        guard !data.isEmpty, data.count <= 15_000_000,
              let input = UIImage(data: data),
              let imageData = Self.optimizedJPEG(input) else {
            throw CoverError.invalidImage
        }
        try imageData.write(to: destination(for: game), options: .atomic)
        images[game.id] = UIImage(data: imageData)
        attempted.insert(game.id)
        lastAttempt.removeValue(forKey: game.id)
    }

    private func destination(for game: Game) -> URL {
        directory.appendingPathComponent(game.id).appendingPathExtension("jpg")
    }

    private func retrieve(_ game: Game) async {
        let candidates = [game.id, game.name]
        for name in candidates {
            for ext in ["jpg", "jpeg", "png"] {
                let file = directory.appendingPathComponent(name).appendingPathExtension(ext)
                if let data = try? Data(contentsOf: file),
                   let image = UIImage(data: data) {
                    images[game.id] = image
                    return
                }
            }
        }

        // Download covers only, never game data. Fallback cards remain functional offline.
        guard let system = Self.artworkFolder(for: game) else { return }
        let normalized = game.name
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "#", with: "_")
        var names = [normalized]
        let noRevision = normalized.replacingOccurrences(
            of: #"\s+\(Rev [^)]+\)"#, with: "", options: .regularExpression)
        if noRevision != normalized { names.append(noRevision) }

        // Some DS No-Intro sets label these releases with combined regions or languages.
        // Try the exact filename first so different revisions never steal artwork.
        if game.system == .nintendoDS, normalized.hasSuffix(" (USA)") {
            let base = String(normalized.dropLast(" (USA)".count))
            names.append(base + " (USA, Australia)")
            names.append(base + " (USA) (En,Fr,Es)")
            names.append(base + " (USA) (En,Fr,De,Es,It)")
        }

        for name in names {
            // Try upstream GitHub box art first, with libretro CDN as a fallback.
            // Some thumbnail mirrors intermittently reject requests; do not leave
            // a permanent no-cover state after one failed attempt.
            let repo = system.replacingOccurrences(of: " ", with: "_")
            let hostsAndPaths: [(String, String)] = [
                ("raw.githubusercontent.com", "/libretro-thumbnails/\(repo)/master/Named_Boxarts/\(name).png"),
                ("thumbnails.libretro.com", "/\(system)/Named_Boxarts/\(name).png")
            ]
            for (host, path) in hostsAndPaths {
                var components = URLComponents()
                components.scheme = "https"
                components.host = host
                components.path = path
                guard let url = components.url else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 7
                request.cachePolicy = .reloadIgnoringLocalCacheData
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200,
                          !data.isEmpty, data.count <= 4_000_000,
                          let downloaded = UIImage(data: data),
                          let compressed = Self.optimizedJPEG(downloaded) else { continue }
                    // Do not overwrite a manually selected cover mid-download.
                    if images[game.id] != nil { return }
                    try? compressed.write(to: destination(for: game), options: .atomic)
                    images[game.id] = UIImage(data: compressed) ?? downloaded
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private static func artworkFolder(for game: Game) -> String? {
        game.system.artworkFolder
    }

    private static func optimizedJPEG(_ original: UIImage) -> Data? {
        let maximum: CGFloat = 960
        let factor = min(1, maximum / max(max(original.size.width, original.size.height), 1))
        let target = CGSize(width: max(1, original.size.width * factor),
                            height: max(1, original.size.height * factor))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            original.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    private enum CoverError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Choose a PNG or JPEG cover image smaller than 15 MB." }
    }
}

private struct AVArtworkPickerSheet: View {
    let game: Game
    @ObservedObject var covers: GameCoverLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var pickingFile = false
    @State private var errorMessage: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 19) {
                Text(game.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("Add your own game cover. It will appear in the library and in the featured slideshow.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("CHOOSE FROM PHOTOS", systemImage: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(AVPalette.blue, in: RoundedRectangle(cornerRadius: 13))

                Button { pickingFile = true } label: {
                    Label("CHOOSE FROM FILES", systemImage: "folder")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                if saving { ProgressView("Saving artwork").tint(AVPalette.blue) }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.orange)
                }
                Text("Covers are stored on your iPhone in Retro Duo / Covers. Matching cover art is also found automatically when available online.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                Spacer(minLength: 0)
            }
            .padding(22)
            .background(Color(red: 0.02, green: 0.03, blue: 0.075).ignoresSafeArea())
            .navigationTitle("Set Game Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: photo) { _, newPhoto in
                guard let newPhoto else { return }
                saving = true
                Task {
                    do {
                        guard let data = try await newPhoto.loadTransferable(type: Data.self) else {
                            throw PickerError.missingData
                        }
                        try covers.save(data, for: game)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    saving = false
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try covers.save(Data(contentsOf: url), for: game)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private enum PickerError: LocalizedError {
        case missingData
        var errorDescription: String? { "Could not read that photo. Try another image." }
    }
}
