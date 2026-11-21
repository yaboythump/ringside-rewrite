/// Keep a short tap visible to the console even when it ends between display ticks.
struct InputState {
    private(set) var held: UInt8 = 0
    private var remaining = [Int](repeating: 0, count: 8)

    mutating func set(_ bits: UInt8, pressed: Bool) {
        if pressed {
            for i in 0..<8 where bits & (1 << i) != 0 && held & (1 << i) == 0 {
                remaining[i] = 3
            }
            held |= bits
        } else { held &= ~bits }
    }

    mutating func directions(_ bits: UInt8) {
        // Directions follow the thumb immediately, without latching old diagonals.
        held = (held & 0xF0) | (bits & 0x0F)
    }

    mutating func nextFrame() -> UInt8 {
        var result = held
        for i in 0..<8 where remaining[i] > 0 {
            result |= 1 << i
            remaining[i] -= 1
        }
        return result
    }

    mutating func clear() {
        held = 0
        remaining = [Int](repeating: 0, count: 8)
    }
}
