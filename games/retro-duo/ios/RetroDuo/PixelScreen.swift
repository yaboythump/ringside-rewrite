import SwiftUI
import UIKit

/// Shows the console's 160x144 picture with sharp, unblurred pixels.
final class PixelScreenView: UIView {
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    // UIKit can clear a UIView's backing contents when its geometry changes.
    // Keep the game picture in a dedicated child layer throughout rotation.
    private let pictureLayer = CALayer()

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

    func show(_ core: OpaquePointer) {
        guard let pixels = RDCorePixels(core) else { return }
        show(pixels: pixels, width: Int(RDCoreScreenWidth(core)), height: Int(RDCoreScreenHeight(core)))
    }

    /// Shows RGBX pixels (red byte first).
    func show(pixels: UnsafePointer<UInt32>, width: Int, height: Int) {
        let data = Data(bytes: pixels, count: width * height * 4)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: Self.colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureLayer.contents = image
        CATransaction.commit()
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
