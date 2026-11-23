// Checks HingeTracker (the hinge as a game control) with simulated hinge movements.
// Build on macOS: swiftc ios/RetroDuo/HingeGesture.swift tests/hinge/main.swift
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print(condition ? "ok   \(message)" : "FAIL \(message)")
    if !condition { failures += 1 }
}

/// Feeds `angle` every 1/60 s for `seconds` and returns the last fold.
func hold(_ tracker: inout HingeTracker, _ angle: Double?, open: Bool = true,
          for seconds: Double, from time: inout Double) -> HingeTracker.Fold {
    var fold = HingeTracker.Fold.none
    let end = time + seconds
    while time < end {
        fold = tracker.update(angle: angle, partiallyOpen: open, at: time)
        time += 1.0 / 60
    }
    return fold
}

var t = 0.0
var tracker = HingeTracker()

check(hold(&tracker, nil, open: false, for: 1, from: &t) == .none, "no hinge (other iPhones): nothing pressed")
check(tracker.rest == nil, "no hinge: nothing learned")

// Opening the phone sweeps through angles: no rest is learned while it moves.
var angle = 20.0
while angle < 100 {
    _ = tracker.update(angle: angle, partiallyOpen: true, at: t)
    angle += 1.5; t += 1.0 / 60
}
check(tracker.rest == nil, "no resting angle while the hinge is moving")
check(hold(&tracker, 100, for: 0.5, from: &t) == .none && tracker.rest == nil, "not learned before it settles")
_ = hold(&tracker, 101, for: 0.5, from: &t)
let rest = tracker.rest ?? -1
check((97...101).contains(rest), "rest learned after holding still (small wobble allowed): \(rest)")

check(hold(&tracker, 95, for: 0.2, from: &t) == .none, "inside the dead zone: nothing")
check(hold(&tracker, 80, for: 0.2, from: &t) == .closer, "folded ~20° shut: closer (squeeze / left)")
check(hold(&tracker, 100, for: 0.2, from: &t) == .none, "back to rest: released")
check(hold(&tracker, 118, for: 0.2, from: &t) == .wider, "opened ~18° wider: wider (right)")
check(hold(&tracker, 80, for: 3, from: &t) == .closer, "a squeeze can be held (the rest doesn't drift)")
check(tracker.rest == rest, "rest unchanged after a long squeeze")

check(hold(&tracker, 170, open: false, for: 0.3, from: &t) == .none, "fully opened (not laptop pose): nothing")
check(tracker.rest == nil, "leaving the laptop pose forgets the rest")
_ = hold(&tracker, 120, for: 1, from: &t)
check(tracker.rest == 120, "the next pose learns a new rest")
check(hold(&tracker, 104, for: 0.2, from: &t) == .closer, "squeeze measured from the new rest")

tracker.recenter()
check(tracker.rest == nil, "recenter (game resumed) learns again")
check(hold(&tracker, 90, for: 1, from: &t) == .none && tracker.rest == 90, "relearned where the phone is now")

print(failures == 0 ? "\nall hinge checks passed" : "\n\(failures) hinge check(s) failed")
exit(failures == 0 ? 0 : 1)
