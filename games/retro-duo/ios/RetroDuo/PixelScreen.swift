import SwiftUI
import UIKit

/// Shows the console's 160x144 picture with sharp, unblurred pixels.
final class PixelScreenView: UIView {
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ core: OpaquePointer) {
        guard let pixels = RDCorePixels(core) else { return }
        let width = Int(RDCoreScreenWidth(core))
        let height = Int(RDCoreScreenHeight(core))
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
        layer.contents = image
        CATransaction.commit()
    }
}

struct PixelScreen: UIViewRepresentable {
    let session: EmulatorSession

    func makeUIView(context: Context) -> PixelScreenView {
        let view = PixelScreenView(frame: .zero)
        session.screen = view
        return view
    }

    func updateUIView(_ view: PixelScreenView, context: Context) {
        session.screen = view
    }
}
