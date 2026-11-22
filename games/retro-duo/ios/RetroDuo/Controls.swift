import SwiftUI
import UIKit

@MainActor let haptics = UIImpactFeedbackGenerator(style: .light)

/// What the on-screen controls talk to: a Game Boy or DS session.
/// Directions always use RD_KEY_* bits (right 1, left 2, up 4, down 8); each session maps them.
@MainActor protocol PadInput: AnyObject {
    func setKey(_ key: Int, pressed: Bool)
    func setDirections(_ mask: UInt8)
}

/// Raw UIKit touches avoid competing SwiftUI drag recognizers. Each surface owns
/// its fingers, so direction + A/B work together and cancellations always release.
struct TouchSurface: UIViewRepresentable {
    let label: String
    let changed: (CGPoint?, CGSize) -> Void
    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.isExclusiveTouch = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityTraits = .button
        return view
    }
    func updateUIView(_ view: TouchView, context: Context) {
        view.changed = changed
        view.accessibilityLabel = label
    }
    static func dismantleUIView(_ view: TouchView, coordinator: ()) { view.releaseAll() }
}

final class TouchView: UIView {
    var changed: ((CGPoint?, CGSize) -> Void)?
    private var fingers: [UITouch: CGPoint] = [:]
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    private func update(_ touches: Set<UITouch>) {
        for touch in touches { fingers[touch] = touch.location(in: self) }
        changed?(fingers.values.first, bounds.size)
    }
    private func release(_ touches: Set<UITouch>) {
        for touch in touches { fingers.removeValue(forKey: touch) }
        changed?(fingers.values.first, bounds.size)
    }
    func releaseAll() { fingers.removeAll(); changed?(nil, bounds.size) }
    override func didMoveToWindow() { if window == nil { releaseAll() } }
    override func accessibilityActivate() -> Bool {
        changed?(CGPoint(x: bounds.midX, y: bounds.midY), bounds.size)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.releaseAll() }
        return true
    }
}

/// The direction control: the classic D-pad, or the floating thumbstick when it's
/// turned on in Settings ("Floating thumbstick instead of D-pad").
struct DPad: View {
    let session: any PadInput
    @AppStorage(ThumbStick.settingKey) private var thumbstick = false
    var body: some View {
        if thumbstick {
            ThumbStick(session: session)
        } else {
            ClassicDPad(session: session)
        }
    }
}

struct ClassicDPad: View {
    let session: any PadInput
    @State private var mask: UInt8 = 0
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let arm = size * 0.34
            ZStack {
                Circle().fill(.black.opacity(0.32))
                    .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
                RoundedRectangle(cornerRadius: 10).fill(Theme.pad.gradient)
                    .frame(width: arm, height: size * 0.88)
                RoundedRectangle(cornerRadius: 10).fill(Theme.pad.gradient)
                    .frame(width: size * 0.88, height: arm)
                arrow("chevron.up", lit: mask & 4 != 0).offset(y: -size * 0.30)
                arrow("chevron.down", lit: mask & 8 != 0).offset(y: size * 0.30)
                arrow("chevron.left", lit: mask & 2 != 0).offset(x: -size * 0.30)
                arrow("chevron.right", lit: mask & 1 != 0).offset(x: size * 0.30)
                Circle().fill(.black.opacity(0.25)).frame(width: arm * 0.50)
                    .overlay(Circle().stroke(.white.opacity(0.05)))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 4)
            .overlay(TouchSurface(label: "Direction pad") { point, bounds in
                let next = point.map { direction(at: $0, size: bounds.width) } ?? 0
                if next != mask {
                    if next != 0 { haptics.impactOccurred(intensity: 0.45) }
                    mask = next
                    session.setDirections(next)
                }
            })
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
    private func arrow(_ name: String, lit: Bool) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .black))
            .foregroundStyle(lit ? Theme.accent : .white.opacity(0.5))
            .shadow(color: lit ? Theme.accent : .clear, radius: 7)
    }
    private func direction(at point: CGPoint, size: CGFloat) -> UInt8 {
        let dx = point.x - size / 2, dy = point.y - size / 2
        guard hypot(dx, dy) > size * 0.12 else { return 0 }
        return directionMask(dx: dx, dy: dy)
    }
}

/// Eight directions as RD_KEY_* bits (right 1, left 2, up 4, down 8) from a screen-space offset.
func directionMask(dx: CGFloat, dy: CGFloat) -> UInt8 {
        switch Int((atan2(dy, dx) / (.pi / 4)).rounded()) {
        case 0: return 1
        case 1: return 9
        case 2: return 8
        case 3: return 10
        case 4, -4: return 2
        case -3: return 6
        case -2: return 4
        default: return 5
        }
}

/// A thumbstick that appears wherever your thumb lands in the direction area and follows
/// it if you slide past the edge, so you never have to find the D-pad by feel. Slide to
/// move in eight directions; let go and it fades back to a faint ring.
struct ThumbStick: View {
    static let settingKey = "avydrix.thumbstick"

    let session: any PadInput
    @State private var mask: UInt8 = 0
    /// Where the stick's base sits while a thumb is down; nil when idle.
    @State private var origin: CGPoint?
    @State private var knob: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size * 0.34
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let base = origin ?? center
            ZStack {
                Circle()
                    .fill(.black.opacity(origin == nil ? 0.18 : 0.32))
                    .overlay(Circle().stroke(.white.opacity(origin == nil ? 0.14 : 0.10),
                                             style: StrokeStyle(lineWidth: 1.5, dash: origin == nil ? [5, 6] : [])))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(base)
                Circle()
                    .fill(Theme.pad.gradient)
                    .overlay(Circle().stroke(mask != 0 ? Theme.accent : .white.opacity(0.22), lineWidth: 2))
                    .frame(width: radius * 0.95, height: radius * 0.95)
                    .shadow(color: mask != 0 ? Theme.accent.opacity(0.55) : .black.opacity(0.5),
                            radius: mask != 0 ? 9 : 4, y: 3)
                    .opacity(origin == nil ? 0.55 : 1)
                    .position(x: base.x + knob.width, y: base.y + knob.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .overlay(TouchSurface(label: "Thumbstick") { point, _ in
                track(point, radius: radius)
            })
            .accessibilityIdentifier("rd-thumbstick")
        }
    }

    private func track(_ point: CGPoint?, radius: CGFloat) {
        guard let point else {
            origin = nil
            knob = .zero
            send(0)
            return
        }
        var base = origin ?? point
        var dx = point.x - base.x, dy = point.y - base.y
        let distance = hypot(dx, dy)
        if distance > radius {
            // Past the rim: drag the base along so reversing direction is instant.
            let over = distance - radius
            base.x += dx / distance * over
            base.y += dy / distance * over
            dx = dx / distance * radius
            dy = dy / distance * radius
        }
        origin = base
        knob = CGSize(width: dx, height: dy)
        send(hypot(dx, dy) > radius * 0.28 ? directionMask(dx: dx, dy: dy) : 0)
    }

    private func send(_ next: UInt8) {
        guard next != mask else { return }
        if next != 0 { haptics.impactOccurred(intensity: 0.4) }
        mask = next
        session.setDirections(next)
    }
}

struct ActionButton: View {
    let label: String
    let key: Int
    let color: Color
    let diameter: CGFloat
    let session: any PadInput
    @State private var pressed = false
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [color.opacity(pressed ? 0.65 : 1), color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().stroke(.white.opacity(pressed ? 0.6 : 0.25), lineWidth: 2))
            .overlay(Text(label).font(.system(size: diameter * 0.36, weight: .black, design: .rounded)).foregroundStyle(.white))
            .padding(5)
            .background(Circle().fill(.black.opacity(0.45)).overlay(Circle().stroke(color.opacity(0.3), lineWidth: 1)))
            .frame(width: diameter, height: diameter)
            .shadow(color: color.opacity(pressed ? 0.5 : 0.1), radius: pressed ? 12 : 4)
            .scaleEffect(pressed ? 0.94 : 1)
            .overlay(TouchSurface(label: "\(label) button") { point, _ in
                let down = point != nil
                guard pressed != down else { return }
                pressed = down
                if down { haptics.impactOccurred() }
                session.setKey(key, pressed: down)
            })
    }
}

struct PillButton: View {
    let label: String
    let key: Int
    let session: any PadInput
    @State private var pressed = false
    var body: some View {
        VStack(spacing: 7) {
            Capsule().fill(pressed ? Theme.accent : Theme.pad)
                .frame(width: 62, height: 17)
                .overlay(Capsule().stroke(.white.opacity(0.18)))
                .shadow(color: .black.opacity(0.7), radius: 2, y: 3)
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(2).foregroundStyle(.white.opacity(0.65))
        }
        .frame(width: 86, height: 52)
        .overlay(TouchSurface(label: label) { point, _ in
            let down = point != nil
            guard pressed != down else { return }
            pressed = down
            if down { haptics.impactOccurred(intensity: 0.5) }
            session.setKey(key, pressed: down)
        })
    }
}

/// The face buttons for a system: a slanted pair (Game Boy, NES), an arc of three
/// (Genesis) or a diamond of four (SNES). Keys are PadKey bits.
struct FaceButtons: View {
    let session: any PadInput
    let diameter: CGFloat
    var keys: [FaceKey] = GameSystem.gameBoy.faceKeys

    var body: some View {
        switch keys.count {
        case 4:
            // Diamond: keys are [left, top, bottom, right], like Y X B A on a SNES pad.
            let reach = diameter * 0.78
            ZStack {
                button(keys[0]).offset(x: -reach)
                button(keys[1]).offset(y: -reach)
                button(keys[2]).offset(y: reach)
                button(keys[3]).offset(x: reach)
            }
            .frame(width: diameter + reach * 2, height: diameter + reach * 2)
        case 3:
            HStack(spacing: diameter * 0.12) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    button(key).offset(y: CGFloat(1 - index) * diameter * 0.22)
                }
            }
        default:
            HStack(spacing: diameter * 0.16) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    button(key).offset(y: index == 0 ? diameter * 0.24 : -diameter * 0.24)
                }
            }
        }
    }

    private func button(_ key: FaceKey) -> some View {
        ActionButton(label: key.label, key: key.key, color: key.color, diameter: diameter, session: session)
    }
}

struct MenuButtons: View {
    let session: any PadInput
    var selectKey = Int(RD_KEY_SELECT)
    var startKey = Int(RD_KEY_START)
    /// When set, these replace SELECT/START (for example RUN on PC Engine, or just START on Sega).
    var keys: [(label: String, key: Int)]? = nil
    var body: some View {
        HStack(spacing: 12) {
            if let keys {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, item in
                    PillButton(label: item.label, key: item.key, session: session)
                }
            } else {
                PillButton(label: "SELECT", key: selectKey, session: session)
                PillButton(label: "START", key: startKey, session: session)
            }
        }
    }
}
