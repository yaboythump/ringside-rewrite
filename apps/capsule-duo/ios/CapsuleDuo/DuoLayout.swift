import SwiftUI
import UIKit

enum Palette {
    /// Deep space behind everything.
    static let paper = Color(red: 0.035, green: 0.031, blue: 0.098)
    static let card = Color.white.opacity(0.06)
    static let ink = Color(red: 0.95, green: 0.94, blue: 1.0)
    static let muted = Color(red: 0.80, green: 0.78, blue: 0.95).opacity(0.62)
    /// The main glow: nebula violet-pink.
    static let wax = Color(red: 0.66, green: 0.42, blue: 1.0)
    static let nebula = Color(red: 0.98, green: 0.36, blue: 0.75)
    static let cyan = Color(red: 0.36, green: 0.86, blue: 1.0)
    /// Ready to open: starlight gold.
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.40)
    static let line = Color.white.opacity(0.12)
    static let glow = LinearGradient(colors: [cyan, wax, nebula], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Deep space: a slow nebula, two layers of twinkling stars and the odd shooting star.
struct CosmicBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star { let x, y, size, phase, speed: Double; let tint: Int }
    private static let stars: [Star] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<170).map { _ in
            Star(x: next(), y: next(), size: 0.4 + pow(next(), 3) * 2.4, phase: next() * .pi * 2,
                 speed: 0.6 + next() * 1.8, tint: Int(next() * 10))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.07),
                                      Color(red: 0.07, green: 0.04, blue: 0.17),
                                      Color(red: 0.03, green: 0.03, blue: 0.10)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))

                // Nebula clouds drifting very slowly.
                let clouds: [(Color, Double, Double, Double)] = [
                    (Palette.wax, 0.18, 0.22, 0.55), (Palette.nebula, 0.85, 0.35, 0.45),
                    (Palette.cyan, 0.65, 0.88, 0.40), (Palette.wax, 0.10, 0.80, 0.35),
                ]
                for (i, cloud) in clouds.enumerated() {
                    let drift = sin(t / 18 + Double(i) * 1.7) * 0.04
                    let center = CGPoint(x: size.width * (cloud.1 + drift), y: size.height * (cloud.2 - drift))
                    let radius = max(size.width, size.height) * cloud.3
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                             with: .radialGradient(Gradient(colors: [cloud.0.opacity(0.20), cloud.0.opacity(0)]),
                                                   center: center, startRadius: 0, endRadius: radius))
                }

                for star in Self.stars {
                    let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * star.speed + star.phase))
                    let point = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    let r = star.size
                    let color: Color = star.tint == 0 ? Palette.cyan : star.tint == 1 ? Palette.gold : .white
                    if r > 1.6 {
                        ctx.fill(Path(ellipseIn: CGRect(x: point.x - r * 3, y: point.y - r * 3, width: r * 6, height: r * 6)),
                                 with: .radialGradient(Gradient(colors: [color.opacity(0.35 * twinkle), .clear]),
                                                       center: point, startRadius: 0, endRadius: r * 3))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: point.x - r / 2, y: point.y - r / 2, width: r, height: r)),
                             with: .color(color.opacity(twinkle)))
                }

                // A shooting star every 9 seconds.
                let cycle = t.truncatingRemainder(dividingBy: 9) / 9
                if !reduceMotion, cycle < 0.09 {
                    let p = cycle / 0.09
                    let lane = (floor(t / 9) * 0.37).truncatingRemainder(dividingBy: 1)
                    let start = CGPoint(x: size.width * (0.2 + lane * 0.6), y: size.height * 0.08)
                    let head = CGPoint(x: start.x + size.width * 0.35 * p, y: start.y + size.height * 0.18 * p)
                    let tail = CGPoint(x: head.x - size.width * 0.12, y: head.y - size.height * 0.06)
                    var path = Path(); path.move(to: tail); path.addLine(to: head)
                    ctx.stroke(path, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * (1 - p))]),
                                                           startPoint: tail, endPoint: head), lineWidth: 1.6)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
                    VStack(spacing: 28) {
                        primary
                        secondary
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
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
    /// 0...1 progress toward unlocking, drawn as an orbit around the planet.
    var progress: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    private var core: [Color] {
        if opened { return [Color(red: 0.75, green: 0.95, blue: 1.0), Palette.cyan, Color(red: 0.1, green: 0.25, blue: 0.5)] }
        if ready { return [Color(red: 1.0, green: 0.97, blue: 0.8), Palette.gold, Color(red: 0.85, green: 0.35, blue: 0.15)] }
        return [Color(red: 0.95, green: 0.8, blue: 1.0), Palette.wax, Color(red: 0.2, green: 0.08, blue: 0.45)]
    }

    private var accent: Color { opened ? Palette.cyan : ready ? Palette.gold : Palette.wax }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.55), accent.opacity(0)], center: .center,
                                     startRadius: size * 0.2, endRadius: size * 0.75))
                .scaleEffect(pulse ? 1.12 : 0.92)

            if let progress {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: max(2, size * 0.025))
                    .frame(width: size * 0.98, height: size * 0.98)
                Circle()
                    .trim(from: 0, to: max(0.02, min(progress, 1)))
                    .stroke(Palette.glow, style: StrokeStyle(lineWidth: max(2, size * 0.025), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size * 0.98, height: size * 0.98)
                    .shadow(color: accent.opacity(0.8), radius: 6)
            }

            Circle()
                .fill(RadialGradient(colors: core, center: UnitPoint(x: 0.32, y: 0.28),
                                     startRadius: 0, endRadius: size * 0.42))
                .frame(width: size * 0.56, height: size * 0.56)
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.6))
                .shadow(color: accent.opacity(0.9), radius: size * 0.14)

            if !opened {
                Ellipse()
                    .stroke(LinearGradient(colors: [.white.opacity(0.85), accent.opacity(0.2), .white.opacity(0.7)],
                                           startPoint: .leading, endPoint: .trailing),
                            lineWidth: max(1.2, size * 0.035))
                    .frame(width: size * 0.92, height: size * 0.26)
                    .rotationEffect(.degrees(-18))
                Image(systemName: ready ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: size * 0.17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.3), radius: 2)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }

            // A small moon orbiting sealed capsules.
            if !opened {
                Circle()
                    .fill(.white)
                    .frame(width: max(3, size * 0.07), height: max(3, size * 0.07))
                    .shadow(color: accent, radius: 3)
                    .offset(x: size * 0.42)
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: ready ? 4 : 9).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: ready ? 1.1 : 2.6).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
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
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04), (glow ?? Palette.wax).opacity(0.35)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: (glow ?? .clear).opacity(0.35), radius: 16)
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
