/// Keep a short tap visible to the console even when it ends between display ticks.
/// Bits are PadKey values (see SystemInfo.swift).
struct InputState {
    private static let slots = 16
    private(set) var held: UInt32 = 0
    private var remaining = [Int](repeating: 0, count: slots)

    mutating func set(_ bits: UInt32, pressed: Bool) {
        if pressed {
            for i in 0..<Self.slots where bits & (1 << i) != 0 && held & (1 << i) == 0 {
                remaining[i] = 3
            }
            held |= bits
        } else { held &= ~bits }
    }

    mutating func directions(_ bits: UInt8) {
        // Directions follow the thumb immediately, without latching old diagonals.
        held = (held & ~0x0F) | UInt32(bits & 0x0F)
    }

    mutating func nextFrame() -> UInt32 {
        var result = held
        for i in 0..<Self.slots where remaining[i] > 0 {
            result |= 1 << i
            remaining[i] -= 1
        }
        return result
    }

    mutating func clear() {
        held = 0
        remaining = [Int](repeating: 0, count: Self.slots)
    }
}
