import SwiftUI
import UIKit

enum Palette {
    static let paper = Color(red: 0.035, green: 0.012, blue: 0.075)
    static let card = Color(red: 0.14, green: 0.065, blue: 0.23)
    static let ink = Color(red: 0.99, green: 0.96, blue: 1)
    static let muted = Color(red: 0.77, green: 0.68, blue: 0.87)
    static let wax = Color(red: 0.92, green: 0.72, blue: 0.4)
    static let nebula = Color(red: 0.46, green: 0.14, blue: 0.62)
    static let cyan = Color(red: 0.71, green: 0.48, blue: 0.91)
    static let lavender = Color(red: 0.71, green: 0.49, blue: 0.85)
    static let gold = Color(red: 0.95, green: 0.76, blue: 0.46)
    static let line = lavender.opacity(0.4)
    static let glow = LinearGradient(colors: [Color(red: 1, green: 0.91, blue: 0.68), gold, wax], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct CosmicBackground: View {
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                Palette.paper
                Image("MountainSunrise").resizable().scaledToFill()
                    .frame(width:g.size.width,height:min(g.size.height,400)).clipped()
                    .opacity(0.32)
                    .mask(LinearGradient(colors:[.white,.white,.clear],startPoint:.top,endPoint:.bottom))
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

/// Two panes that sit either side of the iPhone Duo fold. On a wide screen without
/// a fold they share it with a gutter; on a normal phone they stack in one scroll.
struct DuoSplit<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        GeometryReader { proxy in
            let fold = DuoGeometry.fold(in: proxy)
            let frames = DuoGeometry.panes(size: proxy.size, fold: fold)
            let _ = DuoGeometry.logIfAsked(size: proxy.size, fold: fold, split: frames != nil)
            if let frames {
                ZStack(alignment: .topLeading) {
                    pane { primary }
                        .frame(width: frames.0.width, height: frames.0.height)
                        .position(x: frames.0.midX, y: frames.0.midY)
                    pane { secondary }
                        .frame(width: frames.1.width, height: frames.1.height)
                        .position(x: frames.1.midX, y: frames.1.midY)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        primary
                        secondary
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

enum DuoGeometry {
    /// Left/right (or top/bottom) pane rectangles, or nil for a single column.
    static func panes(size: CGSize, fold: CGRect?) -> (CGRect, CGRect)? {
        guard size.width > 200, size.height > 200 else { return nil }
        let full = CGRect(origin: .zero, size: size)
        // The fold can run the full height (or width) of the view, so only require that it crosses it.
        if let fold, full.intersects(fold) {
            if fold.height >= fold.width {
                let left = CGRect(x: 0, y: 0, width: fold.minX, height: size.height)
                let right = CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height)
                if left.width > 200, right.width > 200 { return (left, right) }
            } else {
                let top = CGRect(x: 0, y: 0, width: size.width, height: fold.minY)
                let bottom = CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY)
                if top.height > 220, bottom.height > 220 { return (top, bottom) }
            }
        }
        if size.width >= 600, size.width > size.height * 1.2 {
            let gutter: CGFloat = 24
            let width = (size.width - gutter) / 2
            return (CGRect(x: 0, y: 0, width: width, height: size.height),
                    CGRect(x: width + gutter, y: 0, width: width, height: size.height))
        }
        return nil
    }

    /// `-CapsuleSnapshot` writes the measured layout to tmp/layout.txt for simulator checks.
    static func logIfAsked(size: CGSize, fold: CGRect?, split: Bool) {
        guard ProcessInfo.processInfo.arguments.contains("-CapsuleSnapshot") else { return }
        let line = "size=\(Int(size.width))x\(Int(size.height)) fold=\(fold.map { "\($0.integral)" } ?? "none") split=\(split)\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("layout.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// The fold reported by iPhone Duo (iOS 27.1 and later), if this view crosses it.
    static func fold(in proxy: GeometryProxy) -> CGRect? {
        if ProcessInfo.processInfo.arguments.contains("-CapsuleFakeFold"), proxy.size.width > proxy.size.height {
            return CGRect(x: proxy.size.width / 2 - 8, y: 0, width: 16, height: proxy.size.height)
        }
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).first?.frame
        }
        return nil
    }
}

/// A capsule as a glowing little planet. Sealed ones have a ring and a lock, ready ones
/// burn gold, opened ones are a soft open orb with sparkles.
struct CapsuleOrb: View {
    var opened: Bool
    var ready: Bool = false
    var size: CGFloat = 46
    var progress: Double? = nil
    var body: some View {
        ZStack {
            EnvelopeEmblem(size:size)
            if opened {
                PremiumIcon(name:"Delivered",size:size*0.25,gold:true,glow:true)
                    .padding(size*0.055).background(Circle().fill(Palette.paper))
                    .offset(x:size*0.29,y:size*0.29)
            }
            if let progress {
                Circle().trim(from:0,to:max(0.015,min(progress,1)))
                    .stroke(Palette.glow,style:StrokeStyle(lineWidth:2,lineCap:.round))
                    .rotationEffect(.degrees(-90)).frame(width:size*0.94,height:size*0.94)
            }
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.glow).frame(width: 5, height: 5)
            Text(text.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Frosted glass with a faint starlit edge.
struct CardBackground: ViewModifier {
    var glow: Color? = nil
    func body(content: Content) -> some View {
        content.padding(16).background(GlassSurface(radius:20,illuminated:glow != nil))
    }
}

/// A glowing pill button.
struct GlowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var colors: [Color] = [Palette.cyan, Palette.wax, Palette.nebula]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(
                SwiftUI.Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .opacity(isEnabled ? 1 : 0.25)
            )
            .overlay(SwiftUI.Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: colors[1].opacity(isEnabled ? 0.6 : 0), radius: configuration.isPressed ? 6 : 16)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A glowing round button with rings that ripple outward while `active`.
struct OrbButtonFace: View {
    var symbol: String
    var size: CGFloat = 92
    var active = false
    var colors: [Color] = [Palette.nebula, Palette.wax]
    /// Room around the orb for the rings. Turn off where space is tight.
    var halo = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    let p: Double = active ? (t / 1.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : 0
                    let scale: Double = active ? 1 + p * 0.7 : 1.16 + Double(i) * 0.16
                    let ringOpacity: Double = active ? 0.6 * (1 - p) : 0.22 - Double(i) * 0.06
                    let diameter = size * CGFloat(scale)
                    Circle()
                        .stroke(colors[0].opacity(ringOpacity), lineWidth: 2)
                        .frame(width: diameter, height: diameter)
                }
                Circle()
                    .fill(RadialGradient(colors: [colors[0].opacity(0.9), colors[1], colors[1].opacity(0.6)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: colors[0].opacity(0.8), radius: active ? 26 : 16)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size * (halo ? 1.7 : 1.25), height: size * (halo ? 1.7 : 1.25))
    }
}

extension View {
    func card(glow: Color? = nil) -> some View { modifier(CardBackground(glow: glow)) }
}
