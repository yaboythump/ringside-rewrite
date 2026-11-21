import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper, sepia, dusk, night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .dusk: return "Dusk"
        case .night: return "Night"
        }
    }

    var background: String {
        switch self {
        case .paper: return "#FBF8F1"
        case .sepia: return "#F2E7CF"
        case .dusk: return "#2C2925"
        case .night: return "#101214"
        }
    }

    var text: String {
        switch self {
        case .paper: return "#1E1B16"
        case .sepia: return "#4A3A28"
        case .dusk: return "#E4DCCD"
        case .night: return "#C7C2B6"
        }
    }

    var link: String {
        switch self {
        case .paper: return "#8A5A1F"
        case .sepia: return "#8C4A1C"
        case .dusk: return "#E8B266"
        case .night: return "#D9A14E"
        }
    }

    var isDark: Bool { self == .dusk || self == .night }
    var backgroundColor: Color { Color(hex: background) }
    var textColor: Color { Color(hex: text) }
    var accentColor: Color { Color(hex: link) }
}

enum ReaderFont: String, CaseIterable, Identifiable {
    case publisher, serif, sans, rounded

    var id: String { rawValue }

    var name: String {
        switch self {
        case .publisher: return "Original"
        case .serif: return "Serif"
        case .sans: return "Sans"
        case .rounded: return "Rounded"
        }
    }

    var sample: Font {
        switch self {
        case .publisher, .serif: return .system(size: 17, design: .serif)
        case .sans: return .system(size: 17)
        case .rounded: return .system(size: 17, design: .rounded)
        }
    }
}

enum SpreadMode: String, CaseIterable, Identifiable {
    case auto, single

    var id: String { rawValue }
    var name: String { self == .auto ? "Two pages" : "One page" }
}

/// Appearance choices, shared by every book and kept between launches.
@MainActor
final class ReaderSettings: ObservableObject {
    @Published var theme: ReaderTheme { didSet { store(theme.rawValue, "theme") } }
    @Published var font: ReaderFont { didSet { store(font.rawValue, "font") } }
    @Published var scale: Double { didSet { store(scale, "scale") } }
    @Published var lineHeight: Double { didSet { store(lineHeight, "lineHeight") } }
    @Published var margin: Double { didSet { store(margin, "margin") } }
    @Published var justify: Bool { didSet { store(justify, "justify") } }
    @Published var spread: SpreadMode { didSet { store(spread.rawValue, "spread") } }

    static let scales: [Double] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5, 1.7, 1.9, 2.2]

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        theme = ReaderTheme(rawValue: d.string(forKey: "BookDuo.theme") ?? "") ?? .paper
        font = ReaderFont(rawValue: d.string(forKey: "BookDuo.font") ?? "") ?? .serif
        scale = d.object(forKey: "BookDuo.scale") as? Double ?? 1.0
        lineHeight = d.object(forKey: "BookDuo.lineHeight") as? Double ?? 1.5
        margin = d.object(forKey: "BookDuo.margin") as? Double ?? 1.0
        justify = d.object(forKey: "BookDuo.justify") as? Bool ?? true
        spread = SpreadMode(rawValue: d.string(forKey: "BookDuo.spread") ?? "") ?? .auto
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: "BookDuo." + key)
    }

    func smaller() {
        if let index = Self.scales.lastIndex(where: { $0 < scale - 0.001 }) { scale = Self.scales[index] }
    }

    func larger() {
        if let index = Self.scales.firstIndex(where: { $0 > scale + 0.001 }) { scale = Self.scales[index] }
    }

    /// The settings object handed to reader.js for a pane of this size.
    func json(for pane: CGSize) -> String {
        let marginX = max(16, min(48, pane.width * 0.07)) * margin
        let marginY = max(18, min(44, pane.height * 0.05))
        let object: [String: Any] = [
            "scale": scale,
            "lineHeight": lineHeight,
            "marginX": marginX.rounded(),
            "marginY": marginY.rounded(),
            "font": font.rawValue,
            "justify": justify,
            "themeColors": theme != .paper,
            "dimImages": theme.isDark,
            "background": theme.background,
            "text": theme.text,
            "link": theme.link,
            "rule": theme.isDark ? "rgba(255,255,255,0.18)" : "rgba(0,0,0,0.15)",
            "selection": theme.isDark ? "rgba(217,161,78,0.35)" : "rgba(200,140,40,0.28)",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
