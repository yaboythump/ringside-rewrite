import CoreGraphics
import CoreText
import Foundation

/// The tracker card shown on the stream: the game's stats and party (or the session's basics),
/// drawn into the 720p picture beside the game, or over its corner when there's no room.
/// Platform-neutral (CoreGraphics + CoreText) so tests/live can draw it on a Mac.
struct StreamOverlay: Equatable {
    struct Row: Equatable {
        var label: String
        var value: String
    }

    var title: String
    var subtitle: String = ""
    var rows: [Row] = []
    /// Party members, one line each ("Pikachu  Lv 32  HP 80/95").
    var party: [String] = []

    /// Where the card goes in a `width` x `height` frame whose game picture leaves
    /// `side` pixels free left and right and `below` pixels free under it.
    static func placement(width: Int, height: Int, side: Int, below: Int) -> CGRect {
        let margin = max(12, width / 80)
        if side >= width * 3 / 20 {
            // Beside the game, in the right-hand margin.
            return CGRect(x: width - side + margin, y: margin, width: side - margin * 2, height: height - margin * 2)
        }
        if below >= height / 6 {
            // Under the game (the DS's two screens).
            return CGRect(x: margin, y: height - below + margin / 2, width: width - margin * 2, height: below - margin)
        }
        // Over the game's bottom-right corner.
        let cardWidth = width / 4
        return CGRect(x: width - cardWidth - margin, y: height / 2, width: cardWidth, height: height / 2 - margin)
    }

    /// The card as an image fitting `size` (its height trimmed to the content).
    func render(width: Int, height: Int) -> CGImage? {
        guard width > 40, height > 30 else { return nil }
        let wide = width > height * 2 // a strip under the game: rows flow in columns
        let fontSize = CGFloat(max(11, min(26, wide ? height / 6 : width / 13)))
        let pad = fontSize * 0.7
        let titleFont = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize * 1.05, nil)!
        let labelFont = CTFontCreateUIFontForLanguage(.system, fontSize * 0.72, nil)!
        let valueFont = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)!
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        // Draw top-down.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let accent = CGColor(srgbRed: 0.32, green: 0.86, blue: 0.62, alpha: 1)
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let dim = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6)

        var y = pad
        var items: [(CGFloat) -> Void] = [] // drawn after the background is sized
        let inner = CGFloat(width) - pad * 2
        func line(_ text: String, _ font: CTFont, _ color: CGColor, x: CGFloat, top: CGFloat, maxWidth: CGFloat,
                  alignRight: Bool = false) {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
            var ctLine = CTLineCreateWithAttributedString(attributed)
            if CTLineGetTypographicBounds(ctLine, nil, nil, nil) > Double(maxWidth),
               let ellipsis = Optional(CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [
                   NSAttributedString.Key(kCTFontAttributeName as String): font,
                   NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]))),
               let truncated = CTLineCreateTruncatedLine(ctLine, Double(maxWidth), .end, ellipsis) {
                ctLine = truncated
            }
            let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            let ascent = CTFontGetAscent(font)
            items.append { _ in
                context.saveGState()
                // CoreText draws upward: flip back locally around the baseline.
                context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                context.textPosition = CGPoint(x: alignRight ? x + maxWidth - lineWidth : x, y: top + ascent)
                CTLineDraw(ctLine, context)
                context.restoreGState()
            }
        }
        func lineHeight(_ font: CTFont) -> CGFloat { CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font) }

        line(title.uppercased(), titleFont, accent, x: pad, top: y, maxWidth: inner)
        y += lineHeight(titleFont)
        if !subtitle.isEmpty {
            line(subtitle, labelFont, dim, x: pad, top: y, maxWidth: inner)
            y += lineHeight(labelFont)
        }
        y += pad * 0.4
        let columns = wide ? max(1, min(rows.count, Int(inner / (fontSize * 8)))) : 1
        let columnWidth = inner / CGFloat(max(columns, 1))
        let rowHeight = lineHeight(labelFont) + lineHeight(valueFont) + pad * 0.3
        for (index, row) in rows.enumerated() {
            let column = index % columns
            let rowTop = y + CGFloat(index / columns) * rowHeight
            guard rowTop + rowHeight <= CGFloat(height) - pad else { break }
            let x = pad + CGFloat(column) * columnWidth
            line(row.label.uppercased(), labelFont, dim, x: x, top: rowTop, maxWidth: columnWidth - pad * 0.5)
            line(row.value, valueFont, white, x: x, top: rowTop + lineHeight(labelFont), maxWidth: columnWidth - pad * 0.5)
        }
        if !rows.isEmpty { y += CGFloat((rows.count + columns - 1) / columns) * rowHeight }
        if !party.isEmpty, y + lineHeight(labelFont) * 2 <= CGFloat(height) - pad {
            line("PARTY", labelFont, accent, x: pad, top: y, maxWidth: inner)
            y += lineHeight(labelFont) * 1.2
            for member in party {
                guard y + lineHeight(labelFont) <= CGFloat(height) - pad else { break }
                line(member, valueFont.withSize(fontSize * 0.8), white, x: pad, top: y, maxWidth: inner)
                y += lineHeight(valueFont) * 0.85
            }
        }
        let used = min(CGFloat(height), y + pad * 0.6)
        let card = CGPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(width), height: used),
                          cornerWidth: pad, cornerHeight: pad, transform: nil)
        context.addPath(card)
        context.setFillColor(CGColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 0.78))
        context.fillPath()
        context.setFillColor(accent)
        context.fill(CGRect(x: 0, y: pad, width: max(3, pad * 0.25), height: max(0, used - pad * 2)))
        for item in items { item(0) }
        guard let full = context.makeImage() else { return nil }
        // Trim to what was drawn.
        return full.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(width), height: ceil(used)))
    }
}

private extension CTFont {
    func withSize(_ size: CGFloat) -> CTFont { CTFontCreateCopyWithAttributes(self, size, nil, nil) }
}
