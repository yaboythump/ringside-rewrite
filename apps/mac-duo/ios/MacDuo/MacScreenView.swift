import SwiftUI
import UIKit

/// How touches on the Mac's screen move the pointer.
enum ScreenTouchMode: String, CaseIterable, Identifiable {
    /// Touch where you want to click; drag to drag.
    case direct
    /// The screen works like the trackpad (handy in landscape).
    case trackpad
    var id: String { rawValue }
    var label: String { self == .direct ? "Touch to click" : "Screen is a trackpad" }
}

/// Shows the emulated Mac's 640×480 screen and turns touches into mouse input.
struct MacScreen: UIViewRepresentable {
    var touchMode: ScreenTouchMode
    var smooth: Bool

    func makeUIView(context: Context) -> MacScreenUIView {
        let view = MacScreenUIView()
        view.touchMode = touchMode
        view.smooth = smooth
        return view
    }

    func updateUIView(_ view: MacScreenUIView, context: Context) {
        view.touchMode = touchMode
        view.smooth = smooth
    }
}

final class MacScreenUIView: UIView {
    static let macSize = CGSize(width: CGFloat(MV_SCREEN_WIDTH), height: CGFloat(MV_SCREEN_HEIGHT))

    var touchMode: ScreenTouchMode = .direct
    var smooth = true {
        didSet { picture.magnificationFilter = smooth ? .linear : .nearest; picture.minificationFilter = smooth ? .trilinear : .nearest }
    }

    private let picture = CALayer()
    private var pixels = [UInt32](repeating: 0xFF000000, count: Int(MV_SCREEN_WIDTH * MV_SCREEN_HEIGHT))
    private var frameNumber: UInt64 = 0
    private var link: CADisplayLink?
    private let trackpad = PointerTracker()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        picture.contentsGravity = .resizeAspect
        picture.magnificationFilter = .linear
        picture.minificationFilter = .trilinear
        picture.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(picture)
        accessibilityLabel = "Macintosh screen"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = screenRect
        CATransaction.commit()
    }

    /// Where the Mac picture sits inside the view (aspect fit, 4:3).
    var screenRect: CGRect {
        let scale = min(bounds.width / Self.macSize.width, bounds.height / Self.macSize.height)
        let size = CGSize(width: Self.macSize.width * scale, height: Self.macSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height).integral
    }

    fileprivate func refresh() {
        let latest = pixels.withUnsafeMutableBufferPointer { MVCoreCopyFrame($0.baseAddress, frameNumber) }
        guard latest != frameNumber else { return }
        frameNumber = latest
        let width = Int(MV_SCREEN_WIDTH), height = Int(MV_SCREEN_HEIGHT)
        let image: CGImage? = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
            else { return nil }
            return context.makeImage()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = image
        CATransaction.commit()
    }

    // MARK: - Touch

    private func macPoint(_ point: CGPoint) -> (Int32, Int32) {
        let rect = screenRect
        let x = (point.x - rect.minX) / rect.width * Self.macSize.width
        let y = (point.y - rect.minY) / rect.height * Self.macSize.height
        return (Int32(x.rounded(.down)), Int32(y.rounded(.down)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        switch touchMode {
        case .direct:
            let (x, y) = macPoint(touch.location(in: self))
            MVCoreMouseSet(x, y)
            MVCoreMouseButton(1)
            Haptics.tap()
        case .trackpad:
            trackpad.began(touch, in: self, scale: Self.macSize.width / max(1, screenRect.width))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        switch touchMode {
        case .direct:
            let (x, y) = macPoint(touch.location(in: self))
            MVCoreMouseSet(x, y)
        case .trackpad:
            trackpad.moved(touch, in: self)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch touchMode {
        case .direct: MVCoreMouseButton(0)
        case .trackpad: if let touch = touches.first { trackpad.ended(touch, in: self) }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch touchMode {
        case .direct: MVCoreMouseButton(0)
        case .trackpad: trackpad.cancelled()
        }
    }
}

/// CADisplayLink keeps a strong reference to its target; this breaks the cycle.
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var view: MacScreenUIView?
    init(_ view: MacScreenUIView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.refresh()
    }
}

/// Trackpad behaviour shared by the trackpad pad and the screen in trackpad mode:
/// slide to move, tap to click, tap-then-slide to drag, double-tap to double-click.
@MainActor
final class PointerTracker {
    private var last: CGPoint = .zero
    private var start: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var lastTapEnd: TimeInterval = 0
    private var dragging = false
    private var travelled: CGFloat = 0
    private var position: CGPoint = .zero
    private var scale: CGFloat = 1
    /// Extra speed multiplier from Settings (1 = default).
    var sensitivity: CGFloat = 1

    func began(_ touch: UITouch, in view: UIView, scale: CGFloat) {
        self.scale = scale
        last = touch.location(in: view)
        start = last
        startTime = touch.timestamp
        travelled = 0
        var x: Int32 = 0, y: Int32 = 0
        MVCoreMousePosition(&x, &y)
        position = CGPoint(x: CGFloat(x), y: CGFloat(y))
        if touch.timestamp - lastTapEnd < 0.28 {
            dragging = true
            MVCoreMouseButton(1)
        }
    }

    func moved(_ touch: UITouch, in view: UIView) {
        let point = touch.location(in: view)
        let dx = point.x - last.x, dy = point.y - last.y
        last = point
        let distance = hypot(dx, dy)
        travelled += distance
        // Gentle acceleration: slow moves stay precise, quick flicks cross the screen.
        let gain = scale * sensitivity * (1.0 + min(distance, 30) / 12)
        position.x = min(max(position.x + dx * gain, 0), CGFloat(MV_SCREEN_WIDTH - 1))
        position.y = min(max(position.y + dy * gain, 0), CGFloat(MV_SCREEN_HEIGHT - 1))
        MVCoreMouseSet(Int32(position.x), Int32(position.y))
    }

    func ended(_ touch: UITouch, in view: UIView) {
        if dragging {
            dragging = false
            MVCoreMouseButton(0)
            lastTapEnd = 0
            return
        }
        if travelled < 8 && touch.timestamp - startTime < 0.3 {
            click()
            lastTapEnd = touch.timestamp
        }
    }

    func cancelled() {
        if dragging { MVCoreMouseButton(0) }
        dragging = false
    }

    func click() {
        MVCoreMouseButton(1)
        Haptics.tap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MVCoreMouseButton(0) }
    }
}

/// The trackpad: one finger moves the pointer. Tap to click, tap then slide to
/// drag. The bar along the bottom is the mouse button: hold it and slide on the
/// pad to drag, like a PowerBook.
struct Trackpad: UIViewRepresentable {
    var sensitivity: Double

    func makeUIView(context: Context) -> TrackpadUIView {
        let view = TrackpadUIView()
        view.tracker.sensitivity = sensitivity
        return view
    }

    func updateUIView(_ view: TrackpadUIView, context: Context) {
        view.tracker.sensitivity = sensitivity
    }
}

final class TrackpadUIView: UIView {
    let tracker = PointerTracker()
    private var padTouch: UITouch?
    private var buttonTouch: UITouch?
    private let buttonHeight: CGFloat = 54
    private let buttonLayer = CALayer()
    private let padLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        padLayer.backgroundColor = UIColor.secondarySystemFill.cgColor
        padLayer.cornerRadius = 18
        padLayer.cornerCurve = .continuous
        buttonLayer.backgroundColor = UIColor.tertiarySystemFill.cgColor
        buttonLayer.cornerRadius = 14
        buttonLayer.cornerCurve = .continuous
        layer.addSublayer(padLayer)
        layer.addSublayer(buttonLayer)
        isAccessibilityElement = true
        accessibilityLabel = "Trackpad"
        accessibilityHint = "Slide to move the pointer. Tap to click."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var buttonRect: CGRect {
        CGRect(x: 0, y: bounds.height - buttonHeight, width: bounds.width, height: buttonHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        padLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - buttonHeight - 8))
        buttonLayer.frame = buttonRect
        padLayer.backgroundColor = UIColor.secondarySystemFill.resolvedColor(with: traitCollection).cgColor
        buttonLayer.backgroundColor = UIColor.tertiarySystemFill.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if buttonRect.contains(touch.location(in: self)) {
                guard buttonTouch == nil else { continue }
                buttonTouch = touch
                MVCoreMouseButton(1)
                Haptics.tap()
                buttonLayer.opacity = 0.5
            } else if padTouch == nil {
                padTouch = touch
                // About 1.6 Mac pixels per point by default.
                tracker.began(touch, in: self, scale: 1.6)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let padTouch, touches.contains(padTouch) { tracker.moved(padTouch, in: self) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == buttonTouch {
                buttonTouch = nil
                MVCoreMouseButton(0)
                buttonLayer.opacity = 1
            } else if touch == padTouch {
                padTouch = nil
                if buttonTouch == nil { tracker.ended(touch, in: self) }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == buttonTouch {
                buttonTouch = nil
                MVCoreMouseButton(0)
                buttonLayer.opacity = 1
            } else if touch == padTouch {
                padTouch = nil
                tracker.cancelled()
            }
        }
    }
}

@MainActor
enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)
    static func tap() { generator.impactOccurred(intensity: 0.6) }
}
