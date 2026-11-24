// Checks RewindBuffer (ios/RetroDuo/Rewind.swift): newest-first steps back, limits, compression.
//   swiftc Rewind.swift tests/rewind/main.swift -o rewind_test && ./rewind_test
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print((condition ? "ok   " : "FAIL ") + message)
    if !condition { failures += 1 }
}

/// A console-like save state: mostly unchanged memory with a frame counter.
func state(_ frame: Int, size: Int = 64 * 1024) -> Data {
    var bytes = [UInt8](repeating: 0x11, count: size)
    for i in 0..<64 { bytes[i * 997 % size] = UInt8(truncatingIfNeeded: frame &+ i) }
    withUnsafeBytes(of: UInt32(frame)) { for (i, b) in $0.enumerated() { bytes[i] = b } }
    return Data(bytes)
}

do {
    let buffer = RewindBuffer(maxEntries: 5)
    check(buffer.isEmpty && buffer.pop() == nil, "starts empty")
    for frame in 1...8 { buffer.push(state(frame)) }
    check(buffer.count == 5, "keeps only the newest 5 of 8")
    check(buffer.pop() == state(8), "steps back to the newest first")
    check(buffer.pop() == state(7), "then the one before")
    check(buffer.count == 3, "each step back removes a snapshot")
    _ = buffer.pop(); _ = buffer.pop()
    check(buffer.pop() == state(4), "the oldest kept is frame 4")
    check(buffer.pop() == nil, "and then there's nothing left")
}

do {
    let buffer = RewindBuffer(maxEntries: 1000, maxBytes: 200_000)
    for frame in 1...200 { buffer.push(state(frame)) }
    check(buffer.storedBytes <= 200_000, "stays under its memory limit (\(buffer.storedBytes) bytes)")
    check(buffer.count > 10, "save states compress well (\(buffer.count) kept in 200 KB, 64 KB each)")
    check(buffer.pop() == state(200), "the newest survives trimming")
    buffer.clear()
    check(buffer.isEmpty && buffer.storedBytes == 0, "clear empties it")
}

do {
    // The DS pushes from a background queue while the main thread may pop.
    let buffer = RewindBuffer(maxEntries: 50)
    DispatchQueue.concurrentPerform(iterations: 200) { i in
        if i % 3 == 0 { _ = buffer.pop() } else { buffer.push(state(i, size: 4096)) }
    }
    check(buffer.count <= 50, "safe to use from several threads")
}

do {
    check([2, 3, 4].contains(TimeControls.fastForwardSpeed), "fast-forward speed defaults to a supported value")
}

print(failures == 0 ? "\nall rewind checks passed" : "\n\(failures) rewind check(s) failed")
exit(failures == 0 ? 0 : 1)
