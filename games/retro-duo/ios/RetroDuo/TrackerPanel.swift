import SwiftUI

/// Loads the bundled tracker definitions once.
@MainActor
enum TrackerCatalog {
    static let library: TrackerLibrary? = {
        guard let url = Bundle.main.url(forResource: "Trackers", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? TrackerLibrary.load(data)
    }()

    static func definition(for game: Game) -> TrackerGame? {
        let fileName = game.url.deletingPathExtension().lastPathComponent
        return library?.game(titles: [game.name, fileName], system: game.system.rawValue)
    }
}

/// The lower screen as a live tracker: the game's stats and party, read from its memory a few
/// times a second, or the session's basics for a game without a definition. Touch controls are
/// hidden meanwhile; a Bluetooth controller and the hinge still play.
struct TrackerPanel: View {
    @ObservedObject var session: EmulatorSession
    @State private var snapshot = TrackerSnapshot()
    @State private var now = Date()
    private let definition: TrackerGame?
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(session: EmulatorSession) {
        self.session = session
        definition = TrackerCatalog.definition(for: session.game)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if definition != nil, snapshot.stats.isEmpty && snapshot.party.isEmpty {
                    Text("Waiting for the game to start…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if !snapshot.stats.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(snapshot.stats) { stat in tile(stat.label, stat.value) }
                    }
                }
                if !snapshot.party.isEmpty {
                    Text("PARTY")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Theme.accent.opacity(0.8))
                        .padding(.top, 2)
                    ForEach(snapshot.party) { member in partyRow(member) }
                }
                if definition == nil { sessionBasics }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
        .accessibilityElement(children: .contain)
    }

    private func refresh() {
        now = Date()
        guard let definition, let library = TrackerCatalog.library else { return }
        let next = library.snapshot(of: definition, memory: { session.peek($0) })
        if next != snapshot { snapshot = next }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(definition == nil ? Color.white.opacity(0.3) : Color.green).frame(width: 7, height: 7)
            Text(definition == nil ? "SESSION" : "LIVE TRACKER")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            Text(definition?.title ?? session.game.system.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private var sessionBasics: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tile("This session", Self.duration(now.timeIntervalSince(session.openedAt)))
                tile("System", session.game.system.displayName)
            }
            Text("No live stats for this game yet. Pokémon, Super Mario and Sonic games show their party, lives, coins and more here.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier("tracker-stat-\(label)")
    }

    private func partyRow(_ member: TrackerSnapshot.Member) -> some View {
        let fraction = member.maxHP > 0 ? min(1, Double(member.hp) / Double(member.maxHP)) : 0
        let colour: Color = fraction > 0.5 ? .green : fraction > 0.2 ? .yellow : .red
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(member.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if member.name.caseInsensitiveCompare(member.species) != .orderedSame {
                    Text(member.species)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 4)
                Text("Lv \(member.level)")
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(colour).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 6)
                Text("\(member.hp)/\(member.maxHP)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel.opacity(0.85)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(member.name), \(member.species), level \(member.level)")
        .accessibilityValue("\(member.hp) of \(member.maxHP) HP")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
