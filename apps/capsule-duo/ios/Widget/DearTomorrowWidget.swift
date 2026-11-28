import SwiftUI
import WidgetKit

struct CountdownEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

struct CountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: Date(), summary: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntry(date: Date(), summary: WidgetSummary.load() ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let now = Date()
        let summary = WidgetSummary.load()
        // One entry per day so the day count stays right; refresh right when the next capsule lands.
        var entries: [CountdownEntry] = []
        let start = Calendar.current.startOfDay(for: now)
        for day in 0..<7 {
            let date = day == 0 ? now : Calendar.current.date(byAdding: .day, value: day, to: start) ?? now
            entries.append(CountdownEntry(date: date, summary: summary))
        }
        var refresh = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? now.addingTimeInterval(86_400)
        if let next = summary?.nextDate, next > now, next < refresh { refresh = next }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

private enum Look {
    static let gold = Color(red: 0.90, green: 0.79, blue: 0.59)
    static let ink = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let muted = Color(red: 0.83, green: 0.79, blue: 0.85)
    static let background = LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.28),
                                                     Color(red: 0.07, green: 0.05, blue: 0.13)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct CountdownView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    private var days: Int? {
        guard let date = entry.summary?.nextDate else { return nil }
        return WidgetSummary.daysUntil(date, from: entry.date)
    }

    private var dayLine: String {
        guard let days else { return "" }
        switch days {
        case 0: return "Lands today"
        case 1: return "Lands tomorrow"
        default: return "\(days) days to go"
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let days {
                Text("Dear Tomorrow · \(days == 0 ? "a capsule lands today" : "\(days)d to go")")
            } else {
                Text("Dear Tomorrow")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "envelope.fill").font(.system(size: 10))
                    Text(days.map(String.init) ?? "–")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                    Text("days").font(.system(size: 9))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Dear Tomorrow", systemImage: "envelope.fill")
                    .font(.system(size: 12, weight: .semibold))
                if let summary = entry.summary, summary.readyCount > 0 {
                    Text("\(summary.readyCount) ready to open").font(.system(size: 15, weight: .bold))
                } else if let title = entry.summary?.nextTitle {
                    Text(title).font(.system(size: 13)).lineLimit(1)
                    Text(dayLine).font(.system(size: 15, weight: .bold))
                } else {
                    Text("Nothing in orbit").font(.system(size: 13))
                }
            }
        default:
            home
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                Text("DEAR TOMORROW").font(.system(size: 10, weight: .semibold)).tracking(1.2)
            }
            .foregroundStyle(Look.gold)

            Spacer(minLength: 0)

            if let summary = entry.summary, summary.readyCount > 0 {
                Text("\(summary.readyCount)")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(Look.gold)
                Text(summary.readyCount == 1 ? "capsule is ready to open" : "capsules are ready to open")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Look.ink)
            } else if let summary = entry.summary, let title = summary.nextTitle, let days {
                Text(days == 0 ? "Today" : "\(days)")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(Look.gold)
                    .minimumScaleFactor(0.6)
                Text(days == 0 ? "a capsule lands" : days == 1 ? "day to go" : "days to go")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Look.muted)
                Text(summary.nextFrom.map { "From \($0): \(title)" } ?? title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Look.ink)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                if family != .systemSmall, summary.sealedCount > 1 {
                    Text("\(summary.sealedCount) capsules in orbit")
                        .font(.system(size: 11))
                        .foregroundStyle(Look.muted)
                }
            } else {
                Text("Nothing in orbit")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Look.ink)
                Text("Record a message for future you.")
                    .font(.system(size: 12))
                    .foregroundStyle(Look.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DearTomorrowCountdown: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DearTomorrowCountdown", provider: CountdownProvider()) { entry in
            CountdownView(entry: entry)
                .containerBackground(for: .widget) { Look.background }
        }
        .configurationDisplayName("Next capsule")
        .description("Counts down to the next capsule that lands.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct DearTomorrowWidgets: WidgetBundle {
    var body: some Widget {
        DearTomorrowCountdown()
    }
}
