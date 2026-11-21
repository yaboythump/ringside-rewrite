var input = InputState()
// Touch down and up both arrive before the next emulated frame.
input.set(0x10, pressed: true)
input.set(0x10, pressed: false)
for _ in 0..<3 { precondition(input.nextFrame() == 0x10, "short A tap lost") }
precondition(input.nextFrame() == 0)
input.directions(1)
input.set(0x20, pressed: true)
precondition(input.nextFrame() == 0x21, "direction + B must coexist")
input.directions(4)
precondition(input.nextFrame() == 0x24, "slide must release the old direction")
input.clear()
precondition(input.nextFrame() == 0, "pause/cancel must release input")
print("Input regression checks passed: short taps, simultaneous keys, slide, cancellation")
