import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibrary
    @State private var importing = false
    @State private var playing: Game?
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CTINTERACTIVE").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(3)
                            Spacer()
                            Image(systemName: "waveform.path").foregroundStyle(Theme.buttonB)
                        }.foregroundStyle(Theme.accent)
                        Text("YOUR POCKET.\nANOTHER WORLD.")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        HStack(spacing: 8) {
                            Text("GAME BOY + COLOR")
                            Circle().fill(Theme.accent).frame(width: 4, height: 4)
                            Text("DUO READY")
                        }
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
                        .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Theme.panel, Theme.bezel], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.25)))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section {

                    ForEach(library.games) { game in
                        Button {
                            playing = game
                        } label: {
                            GameRow(game: game)
                        }
                        .swipeActions {
                            if !game.isBuiltIn {
                                Button(role: .destructive) {
                                    library.delete(game)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } footer: {
                    if library.games.count <= 1 {
                        emptyHelp
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ConsoleBackdrop())
            .navigationTitle("Retro Duo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About Retro Duo")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importing = true
                    } label: {
                        Label("Add Games", systemImage: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.gameBoyROM, .gameBoyColorROM, .data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    library.importFiles(urls)
                }
            }
            .refreshable { library.refresh() }
            .alert(library.message ?? "", isPresented: Binding(
                get: { library.message != nil },
                set: { if !$0 { library.message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .fullScreenCover(item: $playing) { game in
            GameView(session: EmulatorSession(game: game, library: library))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            library.refresh()
        }
        .task {
            // Launch argument used for screenshots: opens the Test Cart straight away.
            if ProcessInfo.processInfo.arguments.contains("-RetroDuoDemo") {
                playing = library.games.first
            }
        }
    }

    private var emptyHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add your games")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            Text("Tap + to pick .gb or .gbc files from Files, or drop them into Files › On My iPhone › Retro Duo. Only add games you own or that are free to share.")
            Text("Try the built-in Test Cart to check your controls and sound.")
        }
        .font(.footnote)
        .padding(.top, 12)
    }
}

private struct GameRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(game.isColor
                          ? LinearGradient(colors: [Theme.buttonA, Theme.buttonB], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color(red: 0.55, green: 0.67, blue: 0.25), Color(red: 0.2, green: 0.32, blue: 0.12)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initials)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(game.isBuiltIn ? "Built in · Controls and sound check" : game.systemName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.fill")
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 10)
    }

    private var initials: String {
        let words = game.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "GB" : String(letters).uppercased()
    }
}
