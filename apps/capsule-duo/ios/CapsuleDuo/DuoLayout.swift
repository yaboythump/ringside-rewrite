import SwiftUI
import UIKit

enum Palette {
    static let paper = Color(red: 0.976, green: 0.949, blue: 0.894)
    static let card = Color(red: 1.0, green: 0.984, blue: 0.953)
    static let ink = Color(red: 0.204, green: 0.153, blue: 0.122)
    static let muted = Color(red: 0.204, green: 0.153, blue: 0.122).opacity(0.58)
    static let wax = Color(red: 0.706, green: 0.165, blue: 0.145)
    static let gold = Color(red: 0.788, green: 0.584, blue: 0.247)
    static let line = Color(red: 0.204, green: 0.153, blue: 0.122).opacity(0.12)
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

/// A sealed or opened envelope with a wax seal.
struct EnvelopeMark: View {
    var opened: Bool
    var ready: Bool = false
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Image(systemName: opened ? "envelope.open.fill" : "envelope.fill")
                .font(.system(size: size * 0.78))
                .foregroundStyle(opened ? Palette.gold.opacity(0.85) : Palette.ink.opacity(0.82))
            if !opened {
                Circle()
                    .fill(ready ? Palette.gold : Palette.wax)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                    .offset(y: size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
