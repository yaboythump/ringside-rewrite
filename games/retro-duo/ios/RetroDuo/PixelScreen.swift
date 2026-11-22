import SwiftUI
import UIKit

/// Shows the console's picture. "Picture filter" (avydrix.displayFilter) decides the look:
/// sharp pixels (default), "smooth" or "soft".
///
/// Sharp pixels stretch the picture with nearest-neighbour sampling, which at a non-whole
/// scale (a DS screen is ~9x on a big display) makes some game pixels wider than others and
/// edges stair-stepped. "Smooth" first enlarges the picture by a whole number on the CPU, so
/// every pixel is the same size, and lets the GPU blend only the small remaining stretch:
/// even, soft edges without blur. "Soft" blends the whole stretch.
final class PixelScreenView: UIView {
    static let filterKey = "avydrix.displayFilter"
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var scaledBuffer: [UInt32] = []
    private var currentFilter = ""
    // UIKit can clear a UIView's backing contents when its geometry changes.
    // Keep the game picture in a dedicated child layer throughout rotation.
    private let pictureLayer = CALayer()
    private var lastImage: CGImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        pictureLayer.magnificationFilter = .nearest
        pictureLayer.minificationFilter = .nearest
        pictureLayer.contentsGravity = .resize
        layer.addSublayer(pictureLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureLayer.frame = bounds
        CATransaction.commit()
    }

    /// Captures the last fully rendered frame for the visual save-slot preview.
    func screenshotPNG() -> Data? {
        guard let pixels = lastImage else { return nil }
        return UIImage(cgImage: pixels).pngData()
    }

    func show(_ core: OpaquePointer) {
        guard let pixels = RDCorePixels(core) else { return }
        show(pixels: pixels, width: Int(RDCoreScreenWidth(core)), height: Int(RDCoreScreenHeight(core)))
    }

    /// Shows RGBX pixels (red byte first).
    func show(pixels: UnsafePointer<UInt32>, width: Int, height: Int) {
        let filter = UserDefaults.standard.string(forKey: Self.filterKey) ?? "off"
        if filter != currentFilter {
            currentFilter = filter
            let blend = filter == "smooth" || filter == "soft"
            pictureLayer.magnificationFilter = blend ? .linear : .nearest
            pictureLayer.minificationFilter = blend ? .linear : .nearest
        }
        let factor = filter == "smooth" ? wholeScale(width: width, height: height) : 1
        let data: Data
        if factor > 1 {
            data = enlarged(pixels, width: width, height: height, by: factor)
        } else {
            data = Data(bytes: pixels, count: width * height * 4)
        }
        let imageWidth = width * factor, imageHeight = height * factor
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: imageWidth, height: imageHeight,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: imageWidth * 4,
                                  space: Self.colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureLayer.contents = image
        lastImage = image
        CATransaction.commit()
    }

    /// The whole-number enlargement for "smooth": as big as fits on screen, at most 4x
    /// (enough for even edges, and a 256x192 DS screen at 4x is only 3 MB a frame).
    private func wholeScale(width: Int, height: Int) -> Int {
        let scale = window?.screen.scale ?? contentScaleFactor
        let fit = min(bounds.width * scale / CGFloat(width), bounds.height * scale / CGFloat(height))
        return max(1, min(4, Int(fit.rounded(.down))))
    }

    /// Repeats every pixel factor x factor times.
    private func enlarged(_ pixels: UnsafePointer<UInt32>, width: Int, height: Int, by factor: Int) -> Data {
        let outWidth = width * factor
        let count = outWidth * height * factor
        if scaledBuffer.count != count { scaledBuffer = [UInt32](repeating: 0, count: count) }
        scaledBuffer.withUnsafeMutableBufferPointer { out in
            guard let base = out.baseAddress else { return }
            for y in 0..<height {
                let source = pixels + y * width
                let row = base + y * factor * outWidth
                var x = 0, o = 0
                while x < width {
                    let pixel = source[x]
                    for k in 0..<factor { row[o + k] = pixel }
                    x += 1
                    o += factor
                }
                for copy in 1..<factor {
                    (row + copy * outWidth).update(from: row, count: outWidth)
                }
            }
        }
        return scaledBuffer.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

struct PixelScreen: UIViewRepresentable {
    let session: EmulatorSession

    func makeUIView(context: Context) -> PixelScreenView {
        let view = PixelScreenView(frame: .zero)
        session.attachScreen(view)
        return view
    }

    func updateUIView(_ view: PixelScreenView, context: Context) {
        session.attachScreen(view)
    }

    /// Always take exactly the space SwiftUI offers, so the picture fills its frame.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PixelScreenView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 160, height: proposal.height ?? 144)
    }
}

/// One of the DS's two screens.
struct DSScreen: UIViewRepresentable {
    enum Which { case top, bottom }
    let session: DSSession
    let which: Which

    func makeUIView(context: Context) -> PixelScreenView {
        let view = PixelScreenView(frame: .zero)
        attach(view)
        return view
    }

    func updateUIView(_ view: PixelScreenView, context: Context) {
        attach(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PixelScreenView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 256, height: proposal.height ?? 192)
    }

    private func attach(_ view: PixelScreenView) {
        switch which {
        case .top: session.attachScreen(view, top: true)
        case .bottom: session.attachScreen(view, top: false)
        }
    }
}
