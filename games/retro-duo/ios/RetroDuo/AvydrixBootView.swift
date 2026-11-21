import AVFoundation
import SwiftUI

/// AVYDRIX Play's offline native console start-up.
/// Kept separate from emulation, controller handling, and the foldable layouts.
struct AvydrixBootView: View {
    let finished: () -> Void

    @State private var emblemVisible = false
    @State private var wordmarkVisible = false
    @State private var sweepVisible = false
    @State private var taglineVisible = false
    @State private var leaving = false
    @State private var hasFinished = false
    @State private var bootTask: Task<Void, Never>?
    @State private var sound = AvydrixBootSound()
    @AppStorage("avydrix.bootSoundEnabled") private var bootSoundEnabled = true

    private let blue = Color(red: 0.09, green: 0.54, blue: 1)
    private let violet = Color(red: 0.43, green: 0.22, blue: 1)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scale = min(max(width / 500, 0.55), 1.3)
            ZStack {
                Color.black.ignoresSafeArea()

                RadialGradient(colors: [blue.opacity(emblemVisible ? 0.17 : 0), .black],
                               center: .center, startRadius: 10, endRadius: max(width, geo.size.height) * 0.65)
                    .ignoresSafeArea()

                // Distant illuminated arcs echo the AVYDRIX launch artwork.
                Ellipse()
                    .stroke(LinearGradient(colors: [.clear, blue.opacity(0.85), .clear],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    .frame(width: width * 1.2, height: geo.size.height * 1.4)
                    .rotationEffect(.degrees(27))
                    .offset(x: -width * 0.85, y: -geo.size.height * 0.34)
                    .blur(radius: 2)
                Ellipse()
                    .stroke(LinearGradient(colors: [.clear, violet.opacity(0.85), blue.opacity(0.65), .clear],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    .frame(width: width * 1.1, height: geo.size.height * 1.4)
                    .rotationEffect(.degrees(27))
                    .offset(x: width * 0.9, y: geo.size.height * 0.3)
                    .blur(radius: 2)

                VStack(spacing: 0) {
                    Spacer(minLength: 20)

                    AvydrixMark()
                        .frame(width: 260, height: 180)
                        .scaleEffect(scale * (emblemVisible ? 1 : 0.74))
                        .opacity(emblemVisible ? 1 : 0)
                        .shadow(color: blue.opacity(emblemVisible ? 0.5 : 0), radius: 18)

                    Text("AVYDRIX")
                        .font(.system(size: min(width * 0.12, 67), weight: .medium, design: .rounded))
                        .tracking(width < 350 ? 1.5 : 4)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .foregroundStyle(
                            LinearGradient(colors: [.white, Color(red: 0.66, green: 0.79, blue: 1), .white],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: blue.opacity(0.32), radius: 14)
                        .opacity(wordmarkVisible ? 1 : 0)
                        .offset(y: wordmarkVisible ? 0 : 16)
                        .padding(.top, -4)
                        .padding(.horizontal, 12)

                    ZStack {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, blue, violet, .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1.5)
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: blue, radius: 14)
                            .shadow(color: violet, radius: 26)
                    }
                    .frame(width: min(width * 0.67, 360))
                    .scaleEffect(x: sweepVisible ? 1 : 0.001)
                    .opacity(sweepVisible ? 1 : 0)
                    .padding(.top, 22)

                    Text("Play Without Limits.")
                        .font(.system(size: min(width * 0.035, 17), weight: .light, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.92))
                        .opacity(taglineVisible ? 1 : 0)
                        .padding(.top, 19)

                    Spacer(minLength: 20)
                    Text("CTINTERACTIVE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(taglineVisible ? 0.4 : 0))
                        .padding(.bottom, 22)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: finishNow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AVYDRIX. Play Without Limits. Tap to skip introduction.")
        .onAppear { start() }
        .onDisappear {
            bootTask?.cancel()
            sound.stop()
        }
    }

    private func start() {
        guard bootTask == nil else { return }
        // Startup audio is independent of the in-game mute toggle.
        // An explicit startup-sound switch is available on the library dashboard.
        if bootSoundEnabled { sound.play() }
        bootTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.82)) { emblemVisible = true }
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.75)) { wordmarkVisible = true }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.8)) { sweepVisible = true }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.65)) { taglineVisible = true }
            try? await Task.sleep(for: .milliseconds(5_050))
            guard !Task.isCancelled else { return }
            finishNow()
        }
    }

    private func finishNow() {
        guard !hasFinished else { return }
        hasFinished = true
        bootTask?.cancel()
        sound.stop()
        withAnimation(.easeInOut(duration: 0.35)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.37) { finished() }
    }
}

/// A vector AVYDRIX mark, drawn in SwiftUI so the boot screen works without network access.
private struct AvydrixMark: View {
    private let silver = LinearGradient(
        colors: [Color(red: 0.95, green: 0.98, blue: 1),
                 Color(red: 0.54, green: 0.70, blue: 0.98),
                 Color(red: 0.98, green: 0.99, blue: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 130, y: 0))
                p.addLine(to: CGPoint(x: 10, y: 173))
                p.addLine(to: CGPoint(x: 84, y: 134))
                p.addLine(to: CGPoint(x: 130, y: 58))
                p.closeSubpath()
            }
            .fill(silver)
            Path { p in
                p.move(to: CGPoint(x: 130, y: 0))
                p.addLine(to: CGPoint(x: 250, y: 173))
                p.addLine(to: CGPoint(x: 176, y: 134))
                p.addLine(to: CGPoint(x: 130, y: 58))
                p.closeSubpath()
            }
            .fill(silver)
            Path { p in
                p.move(to: CGPoint(x: 130, y: 79))
                p.addLine(to: CGPoint(x: 158, y: 142))
                p.addLine(to: CGPoint(x: 130, y: 179))
                p.addLine(to: CGPoint(x: 102, y: 142))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.76, blue: 1),
                                          Color(red: 0.24, green: 0.24, blue: 1),
                                          Color(red: 0.57, green: 0.23, blue: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .shadow(color: .blue.opacity(0.85), radius: 13)
        }
        .frame(width: 260, height: 180)
    }
}

/// Original AVYDRIX power-on pulse, rising synth and three-tone confirmation chime.
/// Waveform is generated locally so the intro works offline, with no streaming delay.
@MainActor
private final class AvydrixBootSound {
    private var player: AVAudioPlayer?

    func play() {
        let rate = 44_100
        let seconds = 4.2
        var samples = [Int16](repeating: 0, count: Int(Double(rate) * seconds))
        for i in samples.indices {
            let t = Double(i) / Double(rate)
            // Low power-on hum; rising voltage sweep; signature three-tone arpeggio.
            let low = 0.17 * sin(2 * .pi * 72 * t) * exp(-1.5 * t)
            let swell = 0.16 * sin(2 * .pi * (115 * t + 44 * t * t)) * exp(-pow((t - 1.05) / 0.78, 2))
            var chime = 0.0
            for (start, hz) in [(1.15, 523.25), (1.40, 783.99), (1.75, 1046.50)] {
                if t >= start {
                    let d = t - start
                    let env = min(1, d / 0.018) * exp(-d * 2.45)
                    chime += 0.18 * env * (sin(2 * .pi * hz * d) + 0.15 * sin(4 * .pi * hz * d))
                }
            }
            let fade = min(1, max(0, (seconds - t) / 0.3))
            let value = max(-1, min(1, (low + swell + chime) * fade))
            samples[i] = Int16(value * 32_767)
        }

        var wav = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 2)
        wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize).littleEndian)
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(rate).littleEndian); append(UInt32(rate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        wav.append(contentsOf: Array("data".utf8)); append(dataSize.littleEndian)
        samples.withUnsafeBytes { wav.append(contentsOf: $0) }

        do {
            let session = AVAudioSession.sharedInstance()
            // .ambient follows the hardware silent switch and made the intro inaudible.
            // .playback makes the original AVYDRIX startup chime audible on iPhone Duo.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let bootPlayer = try AVAudioPlayer(data: wav)
            bootPlayer.volume = 1.0
            bootPlayer.prepareToPlay()
            if bootPlayer.play() { player = bootPlayer }
        } catch {
            // Boot animation remains available even when an audio route is unavailable.
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
