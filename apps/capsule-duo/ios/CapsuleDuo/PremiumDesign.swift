import SwiftUI
import AVFoundation

/// Production artwork is separate from every interactive and accessible control.
struct EnvelopeEmblem: View {
    var size: CGFloat = 140
    var body: some View {
        Image("EnvelopeEmblem").resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GoldenUnderline: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 8))
                p.addQuadCurve(to: CGPoint(x: g.size.width, y: 8), control: CGPoint(x: g.size.width / 2, y: -7))
                p.addQuadCurve(to: CGPoint(x: 0, y: 8), control: CGPoint(x: g.size.width / 2, y: 0))
            }
            .fill(LinearGradient(colors: [.clear, Palette.gold, Color(red: 1, green: 0.91, blue: 0.72), Palette.gold, .clear], startPoint: .leading, endPoint: .trailing))
            .shadow(color: Palette.gold.opacity(0.85), radius: 5)
        }.frame(height: 10).accessibilityHidden(true)
    }
}

struct BrandWordmark: View {
    var size: CGFloat = 38
    var body: some View {
        VStack(spacing: 1) {
            Text("Dear Tomorrow")
                .font(.custom("Baskerville-Italic", size: size, relativeTo: .largeTitle))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.91, blue: 0.68), Palette.gold, Color(red: 0.69, green: 0.43, blue: 0.23)], startPoint: .top, endPoint: .bottom))
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            GoldenUnderline().frame(maxWidth: size * 6)
        }
    }
}

struct GlassSurface: View {
    var radius: CGFloat = 18
    var illuminated = false
    var body: some View {
        GeometryReader { g in
            Image("PurpleGlass").resizable().scaledToFill()
                .frame(width: g.size.width, height: g.size.height).clipped()
                .overlay(illuminated ? Color.purple.opacity(0.16) : Color.black.opacity(0.16))
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(LinearGradient(colors: [illuminated ? Color(red: 1, green: 0.8, blue: 1) : Palette.lavender.opacity(0.66), Palette.lavender.opacity(0.18), illuminated ? .purple : Palette.lavender.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: illuminated ? 1.5 : 0.85))
        .shadow(color: illuminated ? Color.purple.opacity(0.5) : .clear, radius: 10)
        .accessibilityHidden(true)
    }
}

/// A bespoke line icon family, drawn at any display scale without SF Symbol substitutions.
struct PremiumIcon: View {
    var name: String
    var size: CGFloat = 28
    var gold = false
    var glow = false
    var body: some View {
        PremiumIconShape(name: name)
            .stroke(LinearGradient(colors: [gold ? Color(red: 1, green: 0.9, blue: 0.64) : Color(red: 0.91, green: 0.78, blue: 1), gold ? Palette.gold : Palette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: max(1.5, size * 0.065), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .shadow(color: glow ? (gold ? Palette.gold : .purple) : .clear, radius: glow ? 7 : 0)
            .accessibilityHidden(true)
    }
}

struct PremiumIconShape: Shape {
    let name: String
    func path(in r: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        func line(_ coords: [(CGFloat, CGFloat)]) {
            guard let first = coords.first else { return }
            p.move(to: point(first.0, first.1))
            for c in coords.dropFirst() { p.addLine(to: point(c.0, c.1)) }
        }
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) { p.addEllipse(in: CGRect(x: r.minX+x*r.width,y:r.minY+y*r.height,width:w*r.width,height:h*r.height)) }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) { p.addRoundedRect(in: CGRect(x:r.minX+x*r.width,y:r.minY+y*r.height,width:w*r.width,height:h*r.height),cornerSize:CGSize(width:radius*r.width,height:radius*r.height)) }
        switch name {
        case "Record":
            box(0.35,0.06,0.3,0.56,0.15)
            p.move(to:point(0.22,0.45)); p.addCurve(to:point(0.78,0.45),control1:point(0.18,0.94),control2:point(0.82,0.94))
            line([(0.5,0.79),(0.5,0.96)]); line([(0.34,0.96),(0.66,0.96)])
        case "Write":
            line([(0.16,0.83),(0.25,0.58),(0.77,0.08),(0.94,0.25),(0.43,0.76),(0.16,0.83)])
            line([(0.26,0.58),(0.43,0.76)]); line([(0.68,0.17),(0.85,0.34)])
        case "Scheduled":
            box(0.13,0.18,0.74,0.73,0.07)
            line([(0.13,0.39),(0.87,0.39)]); line([(0.3,0.07),(0.3,0.28)]); line([(0.7,0.07),(0.7,0.28)])
        case "Vault":
            box(0.1,0.12,0.8,0.78,0.08); ellipse(0.37,0.38,0.27,0.27); ellipse(0.46,0.47,0.09,0.09)
            for x in [0.23,0.77] as [CGFloat] { for y in [0.34,0.56,0.75] as [CGFloat] { line([(x,y),(x,y+0.025)]) } }
        case "Home":
            line([(0.07,0.46),(0.5,0.08),(0.93,0.46)]); line([(0.19,0.36),(0.19,0.91),(0.4,0.91),(0.4,0.66),(0.6,0.66),(0.6,0.91),(0.81,0.91),(0.81,0.36)])
        case "Profile":
            ellipse(0.05,0.05,0.9,0.9); ellipse(0.36,0.25,0.28,0.28)
            p.move(to:point(0.26,0.78)); p.addCurve(to:point(0.74,0.78),control1:point(0.26,0.51),control2:point(0.74,0.51))
        case "Notifications":
            p.move(to:point(0.17,0.73));p.addCurve(to:point(0.31,0.35),control1:point(0.3,0.63),control2:point(0.24,0.44));p.addCurve(to:point(0.69,0.35),control1:point(0.32,0.12),control2:point(0.68,0.12));p.addCurve(to:point(0.83,0.73),control1:point(0.76,0.44),control2:point(0.7,0.63));p.closeSubpath()
            p.move(to:point(0.41,0.85));p.addQuadCurve(to:point(0.59,0.85),control:point(0.5,1.02));line([(0.5,0.1),(0.5,0.17)])
        case "Settings":
            for i in 0..<32 {
                let a=Double(i)*Double.pi/16-Double.pi/2
                let radius:Double = i%4 == 0 || i%4 == 3 ? 0.46 : 0.36
                let q=point(0.5+CGFloat(cos(a)*radius),0.5+CGFloat(sin(a)*radius))
                if i==0 {p.move(to:q)} else {p.addLine(to:q)}
            };p.closeSubpath();ellipse(0.35,0.35,0.3,0.3)
        case "Lock":
            box(0.2,0.43,0.6,0.47,0.06)
            p.move(to:point(0.31,0.43));p.addLine(to:point(0.31,0.29));p.addCurve(to:point(0.69,0.29),control1:point(0.31,0.03),control2:point(0.69,0.03));p.addLine(to:point(0.69,0.43));line([(0.5,0.62),(0.5,0.73)])
        case "Delivered":
            line([(0.08,0.44),(0.5,0.08),(0.92,0.44),(0.92,0.91),(0.08,0.91),(0.08,0.44),(0.5,0.72),(0.92,0.44)])
            line([(0.32,0.34),(0.48,0.47),(0.69,0.28)])
        default:
            box(0.08,0.25,0.84,0.59,0.05);line([(0.09,0.3),(0.5,0.61),(0.91,0.3)])
        }
        return p
    }
}

struct QuoteBanner: View {
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topTrailing) {
                Image("SunsetSkyline").resizable().scaledToFill().frame(width:g.size.width,height:g.size.height).clipped()
                VStack(spacing: 8) {
                    Text("“ One day, your past will call. ”")
                        .font(.custom("Baskerville-Italic", size: max(17,g.size.width * 0.049), relativeTo: .title3))
                        .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    GoldenUnderline().frame(width:g.size.width*0.29)
                }.frame(width:g.size.width*0.64).padding(.top,18).padding(.trailing,9)
            }
        }
        .frame(height: 94)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius:20).stroke(Palette.lavender.opacity(0.2)))
        .accessibilityElement(children:.combine)
    }
}

/// A local, unobtrusive signature chime. The ambient category respects silent mode.
@MainActor final class SignatureAudio {
    static let shared = SignatureAudio()
    private var player: AVAudioPlayer?
    func play() {
        guard UserDefaults.standard.object(forKey:"dearTomorrowSound") as? Bool ?? true else {return}
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("dear-tomorrow-chime.wav")
        if !FileManager.default.fileExists(atPath:url.path) {
            let rate=22050, count=26460
            var samples=Data()
            for i in 0..<count {
                let t=Double(i)/Double(rate)
                let envelope=min(1,t/0.03)*exp(-t*4)
                let tone=sin(2 * .pi * 523.25 * t)+0.5*sin(2 * .pi * 659.25 * t)+0.35*sin(2 * .pi * 783.99 * t)
                var value=Int16(max(-1,min(1,tone*envelope*0.12))*32767).littleEndian
                withUnsafeBytes(of:&value) { samples.append(contentsOf:$0) }
            }
            var wav=Data("RIFF".utf8)
            func put(_ n:UInt32) {var n=n.littleEndian;withUnsafeBytes(of:&n){wav.append(contentsOf:$0)}}
            func short(_ n:UInt16) {var n=n.littleEndian;withUnsafeBytes(of:&n){wav.append(contentsOf:$0)}}
            put(UInt32(36+samples.count));wav.append(Data("WAVEfmt ".utf8));put(16);short(1);short(1);put(UInt32(rate));put(UInt32(rate*2));short(2);short(16);wav.append(Data("data".utf8));put(UInt32(samples.count));wav.append(samples)
            try? wav.write(to:url,options:.atomic)
        }
        try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default)
        player=try? AVAudioPlayer(contentsOf:url);player?.play()
    }
}

struct StartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared=false
    var body: some View {
        ZStack {
            CosmicBackground()
            VStack(spacing:14) {
                EnvelopeEmblem(size:190).scaleEffect(appeared || reduceMotion ? 1 : 0.86)
                BrandWordmark(size:42)
                Text("MESSAGES TO YOUR FUTURE SELF").font(.system(size:9,weight:.medium)).tracking(2.6).foregroundStyle(Palette.muted)
                Text("CTNETWORK Studios").font(.caption2).foregroundStyle(Palette.gold.opacity(0.65)).padding(.top,30)
            }.opacity(appeared || reduceMotion ? 1 : 0)
        }.onAppear {
            withAnimation(.easeOut(duration:0.7)){appeared=true}
            SignatureAudio.shared.play()
        }
    }
}
