// AVYDRIX Play - the iPhone Duo hinge as a game control.
// Copyright 2026 CT Network Studios. GPL v3 or later.
import Foundation

/// What folding the iPhone Duo does in a game (Settings › Hinge control, per system).
enum HingeMode: String, CaseIterable {
    /// The hinge does nothing.
    case off
    /// Squeeze: fold a little shut from where you hold it and a chosen button is pressed.
    case button
    /// Steer: fold shut for left, open further for right.
    case steer

    var title: String {
        switch self {
        case .off: return "Off"
        case .button: return "Squeeze for a button"
        case .steer: return "Steer left / right"
        }
    }
}

/// Turns hinge angles into a fold direction. Pure logic (no UI), checked on CI.
///
/// Where the player naturally holds the Duo differs, so the resting angle is learned: the
/// first time the hinge stays still for `settle` seconds while partly open, that angle
/// becomes the rest. Folding more than `deadZone` degrees shut from it reads as `.closer`,
/// opening more than that reads as `.wider`. Leaving the partly-open pose forgets the rest,
/// so the next time it is learned again.
struct HingeTracker {
    enum Fold: Equatable { case none, closer, wider }

    var deadZone: Double = 12
    var settle: TimeInterval = 0.8
    /// How far the angle may wander and still count as "still".
    var stillness: Double = 3

    private(set) var rest: Double?
    private var stillSince: TimeInterval?
    private var stillAngle: Double?

    /// Feed every hinge update. Returns the fold direction now.
    mutating func update(angle: Double?, partiallyOpen: Bool, at time: TimeInterval) -> Fold {
        guard let angle, partiallyOpen else {
            rest = nil
            stillSince = nil
            stillAngle = nil
            return .none
        }
        if let rest {
            if angle < rest - deadZone { return .closer }
            if angle > rest + deadZone { return .wider }
            return .none
        }
        // Still learning the resting angle.
        if let stillAngle, abs(angle - stillAngle) <= stillness, let since = stillSince {
            if time - since >= settle { rest = angle }
        } else {
            stillAngle = angle
            stillSince = time
        }
        return .none
    }

    /// Forget the rest angle so it's learned again from how the phone is held now.
    mutating func recenter() {
        rest = nil
        stillSince = nil
        stillAngle = nil
    }
}
