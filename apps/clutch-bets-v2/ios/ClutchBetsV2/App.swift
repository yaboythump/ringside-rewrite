import SwiftUI

@main
struct ClutchBetsV2App: App {
    @StateObject private var store = ClutchStore()
    var body: some Scene {
        WindowGroup {
            ClutchRootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum ClutchStyle {
    static let background = Color(hex: 0x080B12)
    static let panel = Color(hex: 0x131822)
    static let panelLight = Color(hex: 0x1C2330)
    static let gold = Color(hex: 0xF1C76C)
    static let silver = Color(hex: 0xCFD7E2)
    static let muted = Color(hex: 0x8E99AA)
    static let green = Color(hex: 0x58D7A0)
    static let border = Color(hex: 0x29303D)
    static let goldFade = LinearGradient(colors: [.init(hex: 0xFFE7A6), gold, .init(hex: 0xAC7737)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum ClutchArea: String, CaseIterable, Identifiable {
    case home = "Home"
    case builder = "Slip Builder"
    case wagers = "My Bets"
    case tools = "Edge Tools"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .builder: "plus.rectangle.on.rectangle"
        case .wagers: "ticket.fill"
        case .tools: "chart.xyaxis.line"
        }
    }
}

struct ClutchRootView: View {
    @State private var active: ClutchArea = .home

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 680
            HStack(spacing: 0) {
                if wide { sideRail }
                VStack(spacing: 0) {
                    if !wide { compactHeader }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            switch active {
                            case .home: ClutchHomeView(onBuild: { active = .builder })
                            case .builder: SlipBuilderView()
                            case .wagers: TicketsView()
                            case .tools: EdgeToolsView()
                            }
                        }
                        .padding(.horizontal, wide ? 30 : 18)
                        .padding(.vertical, wide ? 30 : 20)
                        .frame(maxWidth: 1050)
                        .frame(maxWidth: .infinity)
                    }
                    if !wide { bottomBar }
                }
            }
            .background(ClutchStyle.background.ignoresSafeArea())
        }
        .tint(ClutchStyle.gold)
    }

    private var sideRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            brand
                .padding(.bottom, 20)
            ForEach(ClutchArea.allCases) { area in
                Button { active = area } label: {
                    HStack(spacing: 15) {
                        Image(systemName: area.symbol).frame(width: 23)
                        Text(area.rawValue).font(.system(size: 15, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(active == area ? ClutchStyle.gold : ClutchStyle.silver)
                    .padding(14)
                    .background(active == area ? ClutchStyle.panelLight : .clear, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active == area ? .isSelected : [])
            }
            Spacer()
            Text("VERSION 2.0  •  PRIVATE BETA")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(ClutchStyle.muted)
            Text("Research and tracking only. No wagers are placed in this app.")
                .font(.system(size: 11))
                .foregroundStyle(ClutchStyle.muted)
        }
        .padding(21)
        .frame(width: 238)
        .background(ClutchStyle.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(ClutchStyle.border).frame(width: 1) }
    }

    private var compactHeader: some View {
        HStack {
            brand
            Spacer()
            Text("V2")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(ClutchStyle.background)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(ClutchStyle.goldFade, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(ClutchStyle.panel)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(ClutchStyle.goldFade)
                .frame(width: 38, height: 38)
                .background(ClutchStyle.background, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 0) {
                Text("CLUTCH").foregroundStyle(ClutchStyle.gold)
                Text("BETS").foregroundStyle(ClutchStyle.silver)
            }
            .font(.system(size: 15, weight: .black, design: .rounded))
            .tracking(2.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clutch Bets V2")
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(ClutchArea.allCases) { area in
                Button { active = area } label: {
                    VStack(spacing: 6) {
                        Image(systemName: area.symbol).font(.system(size: 20, weight: .semibold))
                        Text(area.rawValue).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(active == area ? ClutchStyle.gold : ClutchStyle.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(ClutchStyle.panel)
        .overlay(alignment: .top) { Rectangle().fill(ClutchStyle.border).frame(height: 1) }
    }
}

struct PremiumPanel<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(ClutchStyle.silver)
            content
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClutchStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(ClutchStyle.border, lineWidth: 1))
    }
}

struct GoldenButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                Text(title).fontWeight(.heavy)
            }
            .font(.system(size: 14))
            .foregroundStyle(ClutchStyle.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(ClutchStyle.goldFade, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}

struct SectionIntro: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(2.2)
                .foregroundStyle(ClutchStyle.gold)
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(ClutchStyle.muted)
        }
    }
}

struct ClutchHomeView: View {
    @EnvironmentObject var store: ClutchStore
    let onBuild: () -> Void

    var body: some View {
        SectionIntro(eyebrow: "CTINTERACTIVE  /  PERFORMANCE DESK", title: "Own Your Edge.", subtitle: "A new home for disciplined research, tickets and results.")
        hero
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { metrics }
            VStack(spacing: 12) { metrics }
        }
        PremiumPanel("Verified Pick Feed") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 26)).foregroundStyle(ClutchStyle.gold)
                VStack(alignment: .leading, spacing: 7) {
                    Text("No verified picks loaded")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text("V2 never invents picks, live odds or confidence percentages. Verified feeds can be connected in a later release.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClutchStyle.muted)
                }
            }
        }
        PremiumPanel("Clutch Research Standard") {
            VStack(spacing: 13) {
                researchRow("Last 10 games & minutes / role", "chart.bar.xaxis")
                researchRow("Opponent tendencies & injury news", "person.crop.rectangle.stack")
                researchRow("Line movement, splits & price", "arrow.left.arrow.right")
                researchRow("Green Score with explainable reasons", "checkmark.seal")
            }
            Text("A Green label is a research classification, never a win guarantee.")
                .font(.system(size: 11))
                .foregroundStyle(ClutchStyle.muted)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("CLUTCH BETS  /  V2", systemImage: "crown.fill")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.6)
                Spacer()
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 26))
            }
            .foregroundStyle(ClutchStyle.gold)
            Text("THE EDGE IS\nEARNED.")
                .font(.system(size: 39, weight: .black, design: .rounded))
                .tracking(-1.3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Build your own slips. Know the numbers. Track every result.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClutchStyle.silver)
            GoldenButton(title: "BUILD A NEW SLIP", symbol: "plus.circle.fill", action: onBuild)
                .frame(maxWidth: 300)
        }
        .padding(23)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.init(hex: 0x273246), .init(hex: 0x151C29), .init(hex: 0x11141A)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(ClutchStyle.gold.opacity(0.35), lineWidth: 1))
    }

    private var metrics: some View {
        Group {
            metric("Current P/L", store.realizedProfit.signedMoney, "dollarsign.circle", store.realizedProfit >= 0 ? ClutchStyle.green : .red)
            metric("Open tickets", "\(store.openTickets.count)", "ticket", ClutchStyle.gold)
            metric("Win rate", String(format: "%.1f%%", store.winRate), "chart.line.uptrend.xyaxis", ClutchStyle.silver)
        }
    }

    private func metric(_ name: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(name.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(ClutchStyle.muted)
                Spacer()
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("From your recorded tickets")
                .font(.system(size: 10))
                .foregroundStyle(ClutchStyle.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClutchStyle.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func researchRow(_ label: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(ClutchStyle.gold).frame(width: 20)
            Text(label).foregroundStyle(ClutchStyle.silver).font(.system(size: 13))
            Spacer(minLength: 0)
            Image(systemName: "circle.dotted").foregroundStyle(ClutchStyle.muted)
        }
    }
}
