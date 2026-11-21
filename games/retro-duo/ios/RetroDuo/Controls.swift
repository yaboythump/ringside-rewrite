import SwiftUI
import UIKit

@MainActor private let haptics = UIImpactFeedbackGenerator(style: .light)

/// Raw UIKit touches avoid competing SwiftUI drag recognizers. Each surface owns
/// its fingers, so direction + A/B work together and cancellations always release.
private struct TouchSurface: UIViewRepresentable {
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

private final class TouchView: UIView {
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

struct DPad: View {
    let session: EmulatorSession
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
}

struct ActionButton: View {
    let label: String
    let key: Int
    let color: Color
    let diameter: CGFloat
    let session: EmulatorSession
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
    let session: EmulatorSession
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

struct FaceButtons: View {
    let session: EmulatorSession
    let diameter: CGFloat
    var body: some View {
        HStack(spacing: diameter * 0.16) {
            ActionButton(label: "B", key: Int(RD_KEY_B), color: Theme.buttonB, diameter: diameter, session: session)
                .offset(y: diameter * 0.24)
            ActionButton(label: "A", key: Int(RD_KEY_A), color: Theme.buttonA, diameter: diameter, session: session)
                .offset(y: -diameter * 0.24)
        }
    }
}

struct MenuButtons: View {
    let session: EmulatorSession
    var body: some View {
        HStack(spacing: 12) {
            PillButton(label: "SELECT", key: Int(RD_KEY_SELECT), session: session)
            PillButton(label: "START", key: Int(RD_KEY_START), session: session)
        }
    }
}
