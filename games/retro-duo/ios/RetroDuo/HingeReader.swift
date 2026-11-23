import SwiftUI

struct HingeState: Equatable {
    var isHalfOpen = false
}

/// Watches the iPhone Duo hinge (iOS 27.1 and later). On other iPhones the
/// state simply stays "not half-open" and the normal layouts are used.
struct HingeReader: ViewModifier {
    @Binding var state: HingeState

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                let halfOpen = context.hinge?.status == .partiallyOpen
                // The angle also drives Hinge control (folding as a game button).
                HingeControl.shared.update(angleDegrees: context.hinge?.angle.degrees, partiallyOpen: halfOpen)
                if state.isHalfOpen != halfOpen {
                    withAnimation(.spring(duration: 0.35)) { state.isHalfOpen = halfOpen }
                }
            }
        } else {
            content
        }
    }
}
