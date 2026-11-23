import SwiftUI
import WidgetKit

// AVYDRIX Play's home screen and lock screen widget: jump back into the last game played.

struct ShelfEntry: TimelineEntry {
    let date: Date
    let games: [ShelfGame]
}

struct ShelfProvider: TimelineProvider {
    static let sample = [
        ShelfGame(id: "sample", name: "Grave Mistakes", system: "Nintendo DS", playedAt: Date().addingTimeInterval(-3600), cover: nil),
        ShelfGame(id: "sample2", name: "Super Mario World", system: "Super Nintendo", playedAt: Date().addingTimeInterval(-86_400), cover: nil),
    ]

    func placeholder(in context: Context) -> ShelfEntry { ShelfEntry(date: Date(), games: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (ShelfEntry) -> Void) {
        let games = WidgetShelf.load()
        completion(ShelfEntry(date: Date(), games: games.isEmpty && context.isPreview ? Self.sample : games))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShelfEntry>) -> Void) {
        // The app reloads the widget whenever a game is opened; "played … ago" updates itself.
        completion(Timeline(entries: [ShelfEntry(date: Date(), games: WidgetShelf.load())], policy: .never))
    }
}

private enum Palette {
    static let background = Color(red: 0.03, green: 0.04, blue: 0.08)
    static let accent = Color(red: 1.0, green: 0.78, blue: 0.22)
}

struct CoverArt: View {
    let game: ShelfGame?
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let data = game?.cover, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Palette.accent.opacity(0.55), Color.purple.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct PlayPill: View {
    var title = "Continue"
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill").font(.system(size: 9, weight: .black))
            Text(title).font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.accent))
    }
}

struct EmptyShelf: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVYDRIX")
                .font(.system(size: 11, weight: .black, design: .rounded)).tracking(1.5)
                .foregroundStyle(Palette.accent)
            Spacer(minLength: 0)
            Text("Play a game and it shows up here.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            PlayPill(title: "Open")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SmallShelfView: View {
    let game: ShelfGame

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AVYDRIX")
                .font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.5)
                .foregroundStyle(Palette.accent)
            Spacer(minLength: 0)
            Text(game.name)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .shadow(color: .black.opacity(0.6), radius: 4)
            PlayPill()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MediumShelfView: View {
    let games: [ShelfGame]

    var body: some View {
        let first = games[0]
        HStack(spacing: 12) {
            CoverArt(game: first, corner: 14)
                .frame(width: 112)
            VStack(alignment: .leading, spacing: 3) {
                Text("CONTINUE")
                    .font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.5)
                    .foregroundStyle(Palette.accent)
                Text(first.name)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(first.system) · \(first.playedAt, style: .relative) ago")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if games.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(games.dropFirst().prefix(2)) { game in
                            Link(destination: game.playURL) {
                                HStack(spacing: 5) {
                                    CoverArt(game: game, corner: 5).frame(width: 22, height: 22)
                                    Text(game.name)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(1)
                                }
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                            }
                        }
                    }
                } else {
                    PlayPill()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ShelfWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShelfEntry

    var body: some View {
        let first = entry.games.first
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Continue", systemImage: "gamecontroller.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(first?.name ?? "AVYDRIX Play")
                        .font(.system(size: 14, weight: .heavy))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                if entry.games.isEmpty { EmptyShelf() } else { MediumShelfView(games: entry.games) }
            default:
                if let first { SmallShelfView(game: first) } else { EmptyShelf() }
            }
        }
        .padding(family == .accessoryRectangular ? 0 : 14)
        .widgetURL(first?.playURL ?? URL(string: "avydrix://library")!)
        .containerBackground(for: .widget) {
            if family == .systemSmall, let first {
                ZStack {
                    CoverArt(game: first, corner: 0)
                    LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                }
            } else if family == .accessoryRectangular {
                Color.clear
            } else {
                Palette.background
            }
        }
    }
}

struct ContinueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AvydrixContinue", provider: ShelfProvider()) { entry in
            ShelfWidgetView(entry: entry)
        }
        .configurationDisplayName("Continue playing")
        .description("Jump straight back into your last game.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

@main
struct AvydrixWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWidget()
    }
}
