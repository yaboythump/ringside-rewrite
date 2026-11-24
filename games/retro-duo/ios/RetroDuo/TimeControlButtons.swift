import SwiftUI

/// What the rewind / fast-forward buttons drive (both game sessions).
@MainActor
protocol TimeControllable: ObservableObject {
    var fastForward: Bool { get }
    var rewinding: Bool { get }
    func toggleFastForward()
    func setRewinding(_ on: Bool)
}

extension EmulatorSession: TimeControllable {}
extension DSSession: TimeControllable {}

/// Hold-to-rewind and a fast-forward toggle, for the top bar of every layout.
struct TimeControlButtons<Session: TimeControllable>: View {
    @ObservedObject var session: Session
    @State private var holding = false
    @AppStorage(TimeControls.speedKey) private var speed = 2

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "backward.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(session.rewinding ? Color.black : .white.opacity(0.75))
                .frame(width: 38, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(session.rewinding ? Theme.accent : .white.opacity(0.05)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding else { return }
                        holding = true
                        session.setRewinding(true)
                    }
                    .onEnded { _ in
                        holding = false
                        session.setRewinding(false)
                    })
                .accessibilityElement()
                .accessibilityLabel("Rewind (hold)")
                .accessibilityIdentifier("avydrix-rewind")
                .accessibilityAddTraits(.isButton)
            Button { session.toggleFastForward() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "forward.fill").font(.system(size: 13, weight: .bold))
                    if session.fastForward {
                        Text("\(TimeControls.speeds.contains(speed) ? speed : 2)×")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                }
                .foregroundStyle(session.fastForward ? Color.black : .white.opacity(0.75))
                .frame(minWidth: 38, minHeight: 34)
                .padding(.horizontal, session.fastForward ? 4 : 0)
                .background(RoundedRectangle(cornerRadius: 10).fill(session.fastForward ? Theme.accent : .white.opacity(0.05)))
            }
            .accessibilityLabel(session.fastForward ? "Normal speed" : "Fast-forward")
            .accessibilityIdentifier("avydrix-fast-forward")
        }
    }
}
