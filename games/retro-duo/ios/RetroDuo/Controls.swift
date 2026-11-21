import SwiftUI
import UIKit

@MainActor private let haptics = UIImpactFeedbackGenerator(style: .light)

/// Eight-way D-pad. Sliding a thumb across it changes direction without lifting.
struct DPad: View {
    let session: EmulatorSession
    @State private var mask: UInt8 = 0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let arm = size * 0.34
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.22))
                RoundedRectangle(cornerRadius: arm * 0.18)
                    .fill(Theme.pad)
                    .frame(width: arm, height: size * 0.86)
                RoundedRectangle(cornerRadius: arm * 0.18)
                    .fill(Theme.pad)
                    .frame(width: size * 0.86, height: arm)
                arrow("arrowtriangle.up.fill", lit: mask & up != 0).offset(y: -size * 0.3)
                arrow("arrowtriangle.down.fill", lit: mask & down != 0).offset(y: size * 0.3)
                arrow("arrowtriangle.left.fill", lit: mask & left != 0).offset(x: -size * 0.3)
                arrow("arrowtriangle.right.fill", lit: mask & right != 0).offset(x: size * 0.3)
                Circle()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: arm * 0.5)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in update(direction(at: value.location, size: size)) }
                    .onEnded { _ in update(0) }
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement()
        .accessibilityLabel("Direction pad")
    }

    private var up: UInt8 { UInt8(RD_KEY_UP) }
    private var down: UInt8 { UInt8(RD_KEY_DOWN) }
    private var left: UInt8 { UInt8(RD_KEY_LEFT) }
    private var right: UInt8 { UInt8(RD_KEY_RIGHT) }

    private func arrow(_ name: String, lit: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(lit ? Theme.accent : Color.white.opacity(0.35))
    }

    private func direction(at point: CGPoint, size: CGFloat) -> UInt8 {
        let dx = point.x - size / 2
        let dy = point.y - size / 2
        guard hypot(dx, dy) > size * 0.1 else { return 0 }
        // Eight 45° slices, starting with "right" and going clockwise (y points down).
        let slice = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        switch slice {
        case 0: return right
        case 1: return right | down
        case 2: return down
        case 3: return left | down
        case 4, -4: return left
        case -3: return left | up
        case -2: return up
        default: return right | up
        }
    }

    private func update(_ newMask: UInt8) {
        guard newMask != mask else { return }
        if newMask & ~mask != 0 { haptics.impactOccurred(intensity: 0.6) }
        mask = newMask
        session.setDirections(newMask)
    }
}

/// A round action button (A or B).
struct ActionButton: View {
    let label: String
    let key: Int
    let color: Color
    let diameter: CGFloat
    let session: EmulatorSession
    @State private var pressed = false

    var body: some View {
        Circle()
            .fill(color.opacity(pressed ? 0.75 : 1))
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 2))
            .overlay(
                Text(label)
                    .font(.system(size: diameter * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(pressed ? 0.92 : 1)
            .shadow(color: .black.opacity(0.4), radius: pressed ? 1 : 4, y: pressed ? 1 : 3)
            .contentShape(Circle().inset(by: -diameter * 0.12))
            .gesture(pressGesture)
            .accessibilityLabel("\(label) button")
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                haptics.impactOccurred()
                session.setKey(key, pressed: true)
            }
            .onEnded { _ in
                pressed = false
                session.setKey(key, pressed: false)
            }
    }
}

/// SELECT / START.
struct PillButton: View {
    let label: String
    let key: Int
    let session: EmulatorSession
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Theme.pad.opacity(pressed ? 0.6 : 1))
                .frame(width: 58, height: 18)
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    haptics.impactOccurred(intensity: 0.5)
                    session.setKey(key, pressed: true)
                }
                .onEnded { _ in
                    pressed = false
                    session.setKey(key, pressed: false)
                }
        )
        .accessibilityLabel(label)
    }
}

/// B and A on a slant, like the original handheld.
struct FaceButtons: View {
    let session: EmulatorSession
    let diameter: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: diameter * 0.3) {
            ActionButton(label: "B", key: Int(RD_KEY_B), color: Theme.buttonB, diameter: diameter, session: session)
                .offset(y: diameter * 0.3)
            ActionButton(label: "A", key: Int(RD_KEY_A), color: Theme.buttonA, diameter: diameter, session: session)
                .offset(y: -diameter * 0.3)
        }
    }
}

struct MenuButtons: View {
    let session: EmulatorSession

    var body: some View {
        HStack(spacing: 18) {
            PillButton(label: "SELECT", key: Int(RD_KEY_SELECT), session: session)
            PillButton(label: "START", key: Int(RD_KEY_START), session: session)
        }
    }
}
