// Checks the live-streaming code (LiveRTMP, LiveEncoders, LiveStreamCore) on a Mac: the RTMP
// pieces on their own, then a real 6-second stream of a moving test picture and a tone to
// tests/live/fake_rtmp_server.py, which checks what arrives, then a refused stream key.
//   swiftc LiveRTMP.swift LiveEncoders.swift LiveStreamCore.swift tests/live/main.swift -o live_test
//   python3 tests/live/fake_rtmp_server.py --port 19350 --out OUT &  live_test 19350
import AVFoundation
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0
func check(_ condition: Bool, _ message: String) {
    print((condition ? "ok   " : "FAIL ") + message)
    if !condition { failures += 1 }
}

// MARK: AMF0

do {
    let values: [AMF0] = [.string("connect"), .number(1), .object([("app", .string("live2")), ("n", .number(2.5)), ("b", .bool(true))]),
                          .null, .ecmaArray([("width", .number(1280))]), .string(String(repeating: "é", count: 40_000))]
    let decoded = AMF0.decodeAll(AMF0.encode(values))
    check(decoded == values, "AMF0 values survive encoding (including a long string)")
    check(decoded[2]["app"]?.string == "live2", "AMF0 object lookup")
}

// MARK: Chunks

do {
    var writer = RTMPChunkWriter()
    var reader = RTMPChunkReader()
    let payload = Data((0..<10_000).map { UInt8($0 % 251) })
    for size in [128, 4096] {
        writer.chunkSize = size
        reader.chunkSize = size
        var wire = writer.encode(RTMPMessage(type: 9, streamID: 1, timestamp: 1234, payload: payload), chunkStream: 6)
        wire += writer.encode(RTMPMessage(type: 8, streamID: 1, timestamp: 0x0123_4567, payload: Data([1, 2, 3])), chunkStream: 5)
        var messages: [RTMPMessage] = []
        // Arrive in awkward pieces.
        var offset = 0
        while offset < wire.count {
            let end = min(wire.count, offset + 777)
            messages += (try? reader.feed(wire.subdata(in: offset..<end))) ?? []
            offset = end
        }
        check(messages.count == 2 && messages[0].payload == payload && messages[0].timestamp == 1234 && messages[0].type == 9,
              "a 10KB message survives \(size)-byte chunks")
        check(messages.count == 2 && messages[1].timestamp == 0x0123_4567 && messages[1].payload == Data([1, 2, 3]),
              "extended timestamps (\(size)-byte chunks)")
    }
}

do {
    // The server's new chunk size arrives in the same read as the next (large) message.
    var serverWriter = RTMPChunkWriter()
    var size = Data(); size.appendBE(UInt32(4096))
    var wire = serverWriter.encode(RTMPMessage(type: 1, streamID: 0, timestamp: 0, payload: size), chunkStream: 2)
    serverWriter.chunkSize = 4096
    let big = AMF0.encode([.string("_result"), .number(1), .null, .object([("padding", .string(String(repeating: "x", count: 5000)))])])
    wire += serverWriter.encode(RTMPMessage(type: 20, streamID: 0, timestamp: 0, payload: big), chunkStream: 3)
    var reader = RTMPChunkReader()
    let messages = (try? reader.feed(wire)) ?? []
    check(messages.count == 2 && messages[1].payload == big, "a new chunk size applies to the rest of the same read")
}

// MARK: Server addresses

do {
    let twitch = RTMPDestination(server: "rtmp://ingest.global-contribute.live-video.net/app", key: " live_123_abc ")
    check(twitch?.secure == false && twitch?.port == 1935 && twitch?.app == "app" && twitch?.key == "live_123_abc", "Twitch address")
    let youtube = RTMPDestination(server: "rtmps://a.rtmps.youtube.com:443/live2", key: "abcd-efgh")
    check(youtube?.secure == true && youtube?.port == 443 && youtube?.app == "live2" &&
          youtube?.tcUrl == "rtmps://a.rtmps.youtube.com:443/live2", "YouTube RTMPS address")
    let kick = RTMPDestination(server: "rtmps://fa723fc1b171.global-contribute.live-video.net/app/", key: "sk_us-west-2_x")
    check(kick?.port == 443 && kick?.app == "app", "Kick address without a port uses 443")
    check(RTMPDestination(server: "rtmps://a.rtmps.youtube.com/live2", key: "  ") == nil, "an empty key is refused")
    check(RTMPDestination(server: "https://twitch.tv", key: "k") == nil, "a web address is refused")
    check(RTMPDestination(server: "rtmp://host", key: "k") == nil, "an address without an app path is refused")
}

// MARK: Picture

do {
    var canvas = [UInt32](repeating: 0, count: 8 * 4)
    let red: UInt32 = 0x0000_00FF, blue: UInt32 = 0x00FF_0000 // RGBX: red byte first
    canvas.withUnsafeMutableBufferPointer { out in
        LiveStreamCore.draw([red, blue], width: 2, height: 1, into: out.baseAddress!, stride: 8,
                            x: 0, y: 0, boxWidth: 8, boxHeight: 4)
    }
    // 2x1 picture fits 8x4 at 4x: rows 0...3, red in columns 0...3, blue in 4...7 (BGRA words).
    check(canvas[0] == 0xFFFF_0000 && canvas[3] == 0xFFFF_0000 && canvas[4] == 0xFF00_00FF && canvas[8 * 3 + 7] == 0xFF00_00FF,
          "the picture is scaled with sharp pixels and converted to BGRA")
}

// MARK: A real stream

guard CommandLine.arguments.count > 1, let port = Int(CommandLine.arguments[1]) else {
    print(failures == 0 ? "\nunit checks passed (no server port given)" : "\n\(failures) check(s) failed")
    exit(failures == 0 ? 0 : 1)
}

final class StateLog {
    private let lock = NSLock()
    private var states: [LiveStreamCore.State] = []
    func add(_ state: LiveStreamCore.State) { lock.lock(); states.append(state); lock.unlock() }
    var all: [LiveStreamCore.State] { lock.lock(); defer { lock.unlock() }; return states }
    func wait(_ seconds: Double, until done: ([LiveStreamCore.State]) -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if done(all) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return done(all)
    }
}

func stream(key: String, seconds: Double, log: StateLog) -> LiveStreamCore {
    var config = LiveStreamCore.Config(destination: RTMPDestination(server: "rtmp://127.0.0.1:\(port)/app", key: key)!)
    config.videoBitrate = 2_000_000
    // CI's Mac is a virtual machine without a hardware encoder; the app streams 1280x720 on an
    // iPhone's hardware encoder, the software one here keeps 30 fps at 640x360.
    config.width = 640
    config.height = 360
    let core = LiveStreamCore(config: config)
    core.onState = { log.add($0) }
    core.start()
    guard seconds > 0 else { return core }
    _ = log.wait(10) { $0.contains(.live) }

    // A Game Boy-sized picture with a square moving across it, at the emulator's 60 fps, and a
    // 440 Hz tone at the GBA's odd 32768 Hz in 20 ms pieces, like an audio tap delivers.
    let format = AVAudioFormat(standardFormatWithSampleRate: 32_768, channels: 2)!
    var phase = 0.0
    let start = Date()
    var frame = 0
    var nextAudio = 0.0
    while Date().timeIntervalSince(start) < seconds {
        var pixels = [UInt32](repeating: 0x0040_2010, count: 160 * 144)
        let left = (frame * 2) % 140
        for y in 60..<80 { for x in left..<(left + 20) { pixels[y * 160 + x] = 0x0000_FFFF } }
        pixels.withUnsafeBufferPointer { core.pushVideo(pixels: $0.baseAddress!, width: 160, height: 144, screen: 0) }
        frame += 1
        let now = Date().timeIntervalSince(start)
        while nextAudio <= now {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 655)!
            buffer.frameLength = 655
            for i in 0..<655 {
                let sample = Float(sin(phase) * 0.3)
                buffer.floatChannelData![0][i] = sample
                buffer.floatChannelData![1][i] = sample
                phase += 2 * .pi * 440 / 32_768
            }
            core.pushGameAudio(buffer)
            nextAudio += 0.02
        }
        Thread.sleep(forTimeInterval: 1.0 / 60)
    }
    return core
}

do {
    let log = StateLog()
    let core = stream(key: "good-key", seconds: 6, log: log)
    let stats = core.currentStats
    check(log.all.first == .connecting || log.all.first == .live, "connects")
    check(log.all.contains(.live), "goes live after the server says NetStream.Publish.Start")
    check(stats.sentFrames >= 150, "sends about 30 frames a second (\(stats.sentFrames) in 6 s)")
    check(stats.droppedFrames == 0, "drops no frames on a fast connection (\(stats.droppedFrames))")
    check(stats.kilobitsPerSecond > 20, "reports its upload rate (\(stats.kilobitsPerSecond) kbps)")
    core.stop()
    check(log.wait(5) { $0.last == .ended }, "ends cleanly")
    Thread.sleep(forTimeInterval: 1) // let FCUnpublish / deleteStream reach the server
}

do {
    let log = StateLog()
    let core = stream(key: "bad-key", seconds: 0, log: log)
    let refused = log.wait(10) { states in states.contains { if case .failed = $0 { return true }; return false } }
    var message = ""
    if case .failed(let text)? = log.all.last { message = text }
    check(refused && message.contains("stream key"), "a refused key fails with advice about the stream key: \(message)")
    check(!log.all.contains(.live), "a refused key never goes live")
    core.stop()
}

print(failures == 0 ? "\nall live streaming checks passed" : "\n\(failures) live streaming check(s) failed")
exit(failures == 0 ? 0 : 1)
