import Foundation
import Network

// A small RTMP / RTMPS publisher for live streaming (Twitch, YouTube, Kick or any RTMP
// server): handshake, chunked messages, the connect / createStream / publish commands,
// then FLV-wrapped H.264 and AAC. Platform-neutral so tests/live can run it on a Mac.

// MARK: - AMF0

/// The AMF0 values RTMP commands use.
indirect enum AMF0: Equatable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case object([(String, AMF0)])
    case ecmaArray([(String, AMF0)])
    case null
    case undefined

    static func == (a: AMF0, b: AMF0) -> Bool {
        switch (a, b) {
        case let (.number(x), .number(y)): return x == y
        case let (.bool(x), .bool(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.object(x), .object(y)), let (.ecmaArray(x), .ecmaArray(y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.null, .null), (.undefined, .undefined): return true
        default: return false
        }
    }

    func encode(into data: inout Data) {
        switch self {
        case .number(let value):
            data.append(0x00)
            data.appendBE(value.bitPattern)
        case .bool(let value):
            data.append(0x01)
            data.append(value ? 1 : 0)
        case .string(let value):
            let bytes = Data(value.utf8)
            if bytes.count > 0xFFFF {
                data.append(0x0C)
                data.appendBE(UInt32(bytes.count))
            } else {
                data.append(0x02)
                data.appendBE(UInt16(bytes.count))
            }
            data.append(bytes)
        case .object(let pairs):
            data.append(0x03)
            AMF0.encodePairs(pairs, into: &data)
        case .ecmaArray(let pairs):
            data.append(0x08)
            data.appendBE(UInt32(pairs.count))
            AMF0.encodePairs(pairs, into: &data)
        case .null:
            data.append(0x05)
        case .undefined:
            data.append(0x06)
        }
    }

    private static func encodePairs(_ pairs: [(String, AMF0)], into data: inout Data) {
        for (key, value) in pairs {
            let bytes = Data(key.utf8)
            data.appendBE(UInt16(bytes.count))
            data.append(bytes)
            value.encode(into: &data)
        }
        data.append(contentsOf: [0x00, 0x00, 0x09])
    }

    static func encode(_ values: [AMF0]) -> Data {
        var data = Data()
        for value in values { value.encode(into: &data) }
        return data
    }

    /// Every value in a command message; stops at anything it doesn't know.
    static func decodeAll(_ data: Data) -> [AMF0] {
        var index = data.startIndex
        var values: [AMF0] = []
        while index < data.endIndex, let value = decode(data, at: &index) { values.append(value) }
        return values
    }

    static func decode(_ data: Data, at index: inout Data.Index) -> AMF0? {
        guard index < data.endIndex else { return nil }
        let marker = data[index]
        index += 1
        switch marker {
        case 0x00:
            guard let bits: UInt64 = data.readBE(at: &index) else { return nil }
            return .number(Double(bitPattern: bits))
        case 0x01:
            guard index < data.endIndex else { return nil }
            defer { index += 1 }
            return .bool(data[index] != 0)
        case 0x02:
            guard let length: UInt16 = data.readBE(at: &index) else { return nil }
            return readString(data, at: &index, length: Int(length)).map { .string($0) }
        case 0x0C:
            guard let length: UInt32 = data.readBE(at: &index) else { return nil }
            return readString(data, at: &index, length: Int(length)).map { .string($0) }
        case 0x03:
            return decodePairs(data, at: &index).map { .object($0) }
        case 0x08:
            guard let _: UInt32 = data.readBE(at: &index) else { return nil }
            return decodePairs(data, at: &index).map { .ecmaArray($0) }
        case 0x0A:
            guard let count: UInt32 = data.readBE(at: &index), count < 10_000 else { return nil }
            var items: [(String, AMF0)] = []
            for i in 0..<Int(count) {
                guard let value = decode(data, at: &index) else { return nil }
                items.append((String(i), value))
            }
            return .ecmaArray(items)
        case 0x05: return .null
        case 0x06: return .undefined
        default: return nil
        }
    }

    private static func readString(_ data: Data, at index: inout Data.Index, length: Int) -> String? {
        guard data.endIndex - index >= length else { return nil }
        defer { index += length }
        return String(decoding: data[index..<index + length], as: UTF8.self)
    }

    private static func decodePairs(_ data: Data, at index: inout Data.Index) -> [(String, AMF0)]? {
        var pairs: [(String, AMF0)] = []
        while true {
            guard let length: UInt16 = data.readBE(at: &index) else { return nil }
            if length == 0 {
                guard index < data.endIndex else { return nil }
                index += 1 // object end marker 0x09
                return pairs
            }
            guard let key = readString(data, at: &index, length: Int(length)),
                  let value = decode(data, at: &index) else { return nil }
            pairs.append((key, value))
        }
    }

    subscript(key: String) -> AMF0? {
        switch self {
        case .object(let pairs), .ecmaArray(let pairs): return pairs.first { $0.0 == key }?.1
        default: return nil
        }
    }

    var string: String? { if case .string(let value) = self { return value }; return nil }
    var number: Double? { if case .number(let value) = self { return value }; return nil }
}

extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendBE24(_ value: UInt32) {
        append(UInt8((value >> 16) & 0xFF)); append(UInt8((value >> 8) & 0xFF)); append(UInt8(value & 0xFF))
    }

    func readBE<T: FixedWidthInteger>(at index: inout Index) -> T? {
        let size = MemoryLayout<T>.size
        guard endIndex - index >= size else { return nil }
        var value: T = 0
        for i in 0..<size { value = value << 8 | T(self[index + i]) }
        index += size
        return value
    }
}

// MARK: - Messages and chunks

struct RTMPMessage {
    enum Kind: UInt8 {
        case setChunkSize = 1, abort = 2, acknowledgement = 3, userControl = 4
        case windowAckSize = 5, setPeerBandwidth = 6, audio = 8, video = 9
        case dataAMF0 = 18, commandAMF0 = 20
    }

    var type: UInt8
    var streamID: UInt32
    var timestamp: UInt32
    var payload: Data
}

/// Splits messages into chunks (always a full type-0 header on a message's first chunk).
struct RTMPChunkWriter {
    var chunkSize = 128

    func encode(_ message: RTMPMessage, chunkStream csid: UInt8) -> Data {
        precondition(csid >= 2 && csid < 64)
        var out = Data()
        let extended = message.timestamp >= 0xFFFFFF
        out.append(csid) // fmt 0
        out.appendBE24(extended ? 0xFFFFFF : message.timestamp)
        out.appendBE24(UInt32(message.payload.count))
        out.append(message.type)
        withUnsafeBytes(of: message.streamID.littleEndian) { out.append(contentsOf: $0) }
        if extended { out.appendBE(message.timestamp) }
        var offset = message.payload.startIndex
        var first = true
        while first || offset < message.payload.endIndex {
            if !first {
                out.append(0xC0 | csid) // fmt 3
                if extended { out.appendBE(message.timestamp) }
            }
            let end = Swift.min(offset + chunkSize, message.payload.endIndex)
            out.append(message.payload[offset..<end])
            offset = end
            first = false
        }
        return out
    }
}

/// Reassembles messages from the chunks a server sends.
struct RTMPChunkReader {
    var chunkSize = 128
    private var buffer = Data()

    private struct StreamState {
        var timestamp: UInt32 = 0
        var delta: UInt32 = 0
        var length = 0
        var type: UInt8 = 0
        var streamID: UInt32 = 0
        var extended = false
        var partial = Data()
    }
    private var streams: [UInt32: StreamState] = [:]

    enum Failure: Error { case malformed }

    /// Adds received bytes; returns every message they complete.
    mutating func feed(_ data: Data) throws -> [RTMPMessage] {
        buffer.append(data)
        var messages: [RTMPMessage] = []
        while let message = try next() {
            if let message { messages.append(message) }
            if buffer.isEmpty { break }
        }
        return messages
    }

    /// nil: need more bytes. .some(nil): a chunk was consumed without finishing a message.
    private mutating func next() throws -> RTMPMessage?? {
        var index = buffer.startIndex
        guard index < buffer.endIndex else { return nil }
        let first = buffer[index]; index += 1
        let fmt = first >> 6
        var csid = UInt32(first & 0x3F)
        if csid == 0 {
            guard index < buffer.endIndex else { return nil }
            csid = 64 + UInt32(buffer[index]); index += 1
        } else if csid == 1 {
            guard buffer.endIndex - index >= 2 else { return nil }
            csid = 64 + UInt32(buffer[index]) + UInt32(buffer[index + 1]) * 256; index += 2
        }
        var state = streams[csid] ?? StreamState()
        let headerSize = [11, 7, 3, 0][Int(fmt)]
        guard buffer.endIndex - index >= headerSize else { return nil }
        func be24(_ at: Int) -> UInt32 {
            UInt32(buffer[index + at]) << 16 | UInt32(buffer[index + at + 1]) << 8 | UInt32(buffer[index + at + 2])
        }
        var timeField: UInt32 = 0
        if fmt <= 2 { timeField = be24(0) }
        if fmt <= 1 {
            state.length = Int(be24(3))
            state.type = buffer[index + 6]
        }
        if fmt == 0 {
            state.streamID = UInt32(buffer[index + 7]) | UInt32(buffer[index + 8]) << 8 |
                UInt32(buffer[index + 9]) << 16 | UInt32(buffer[index + 10]) << 24
        }
        index += headerSize
        if fmt <= 2 { state.extended = timeField == 0xFFFFFF }
        if state.extended {
            guard let ext: UInt32 = buffer.readBE(at: &index) else { return nil }
            timeField = ext
        }
        let starting = state.partial.isEmpty
        if starting {
            switch fmt {
            case 0: state.timestamp = timeField
            case 1, 2: state.delta = timeField; state.timestamp &+= timeField
            default: state.timestamp &+= state.delta
            }
        }
        guard state.length >= 0, state.length < 16 << 20 else { throw Failure.malformed }
        let wanted = Swift.min(chunkSize, state.length - state.partial.count)
        guard buffer.endIndex - index >= wanted else { return nil }
        state.partial.append(buffer[index..<index + wanted])
        index += wanted
        buffer.removeSubrange(buffer.startIndex..<index)
        buffer = Data(buffer) // keep indices zero-based
        if state.partial.count >= state.length {
            let message = RTMPMessage(type: state.type, streamID: state.streamID, timestamp: state.timestamp, payload: state.partial)
            state.partial = Data()
            streams[csid] = state
            return .some(message)
        }
        streams[csid] = state
        return .some(nil)
    }
}

// MARK: - FLV payloads

enum FLV {
    /// AVCDecoderConfigurationRecord in an FLV video tag body.
    static func videoSequenceHeader(sps: Data, pps: Data) -> Data {
        var body = Data([0x17, 0x00, 0x00, 0x00, 0x00])
        let s = [UInt8](sps)
        body.append(contentsOf: [0x01, s.count > 1 ? s[1] : 0x4D, s.count > 2 ? s[2] : 0x00, s.count > 3 ? s[3] : 0x1F, 0xFF, 0xE1])
        body.appendBE(UInt16(sps.count)); body.append(sps)
        body.append(0x01)
        body.appendBE(UInt16(pps.count)); body.append(pps)
        return body
    }

    /// Length-prefixed (AVCC) NAL units of one frame.
    static func videoFrame(_ avcc: Data, keyframe: Bool) -> Data {
        var body = Data([keyframe ? 0x17 : 0x27, 0x01, 0x00, 0x00, 0x00])
        body.append(avcc)
        return body
    }

    /// AAC LC, 48 kHz, stereo AudioSpecificConfig.
    static let aacConfig = Data([0x11, 0x90])

    static func audioSequenceHeader(_ config: Data = aacConfig) -> Data { Data([0xAF, 0x00]) + config }
    static func audioFrame(_ aac: Data) -> Data { Data([0xAF, 0x01]) + aac }

    static func metadata(width: Int, height: Int, fps: Int, videoKbps: Int, audioKbps: Int) -> Data {
        AMF0.encode([.string("@setDataFrame"), .string("onMetaData"), .ecmaArray([
            ("width", .number(Double(width))), ("height", .number(Double(height))),
            ("framerate", .number(Double(fps))), ("videocodecid", .number(7)),
            ("videodatarate", .number(Double(videoKbps))),
            ("audiocodecid", .number(10)), ("audiodatarate", .number(Double(audioKbps))),
            ("audiosamplerate", .number(48000)), ("audiosamplesize", .number(16)),
            ("audiochannels", .number(2)), ("stereo", .bool(true)),
            ("encoder", .string("AVYDRIX Play")),
        ])])
    }
}

// MARK: - Publisher

/// Where to stream: rtmp(s)://host[:port]/app plus the stream key.
struct RTMPDestination: Equatable {
    var secure: Bool
    var host: String
    var port: UInt16
    var app: String
    var key: String

    /// nil when the server address isn't an rtmp:// or rtmps:// URL with an app path.
    init?(server: String, key: String) {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "rtmp" || scheme == "rtmps", let host = url.host, !host.isEmpty else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return nil }
        secure = scheme == "rtmps"
        self.host = host
        port = UInt16(url.port ?? (secure ? 443 : 1935))
        app = path
        self.key = cleanKey
    }

    var tcUrl: String { "\(secure ? "rtmps" : "rtmp")://\(host):\(port)/\(app)" }
}

/// Talks RTMP to one server. All work happens on its own queue; `onState` is called there.
final class RTMPPublisher {
    enum State: Equatable {
        case connecting
        case publishing
        case failed(String)
        case closed
    }

    let destination: RTMPDestination
    var onState: ((State) -> Void)?
    private(set) var state: State = .connecting
    let queue = DispatchQueue(label: "avydrix.live.rtmp")

    private var connection: NWConnection?
    private var writer = RTMPChunkWriter()
    private var reader = RTMPChunkReader()
    private var handshake = Data()
    private var handshakeDone = false
    private var sentC2 = false
    private var streamID: UInt32 = 0
    private var transaction = 1.0
    private var bytesReceived: UInt64 = 0
    private var lastAck: UInt64 = 0
    private var ackWindow: UInt64 = 2_500_000
    private var pending = 0
    private var timeout: DispatchWorkItem?

    /// Bytes handed to the network that haven't been sent yet (read on `queue`).
    var pendingBytes: Int { pending }
    private(set) var bytesSent: UInt64 = 0

    init(destination: RTMPDestination) {
        self.destination = destination
    }

    func start() {
        queue.async { [self] in
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let parameters = destination.secure ? NWParameters(tls: .init(), tcp: tcp) : NWParameters(tls: nil, tcp: tcp)
            let endpoint = NWEndpoint.hostPort(host: .init(destination.host), port: .init(rawValue: destination.port) ?? 1935)
            let connection = NWConnection(to: endpoint, using: parameters)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in self?.connectionChanged(state) }
            connection.start(queue: queue)
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.state == .connecting else { return }
                self.fail("Couldn't reach \(self.destination.host). Check your internet connection and the server address.")
            }
            self.timeout = timeout
            queue.asyncAfter(deadline: .now() + 15, execute: timeout)
        }
    }

    func close() {
        queue.async { [self] in
            guard state == .publishing || state == .connecting else { return }
            if state == .publishing, streamID != 0 {
                sendCommand("FCUnpublish", [.null, .string(destination.key)])
                sendCommand("deleteStream", [.null, .number(Double(streamID))])
            }
            set(.closed)
            let connection = self.connection
            queue.asyncAfter(deadline: .now() + 0.3) { connection?.cancel() }
        }
    }

    /// FLV video / audio tag bodies and metadata; call on any thread.
    func sendVideo(_ body: Data, timestamp: UInt32) { send(type: 9, csid: 6, body, timestamp) }
    func sendAudio(_ body: Data, timestamp: UInt32) { send(type: 8, csid: 5, body, timestamp) }
    func sendMetadata(_ body: Data) { send(type: 18, csid: 4, body, 0) }

    private func send(type: UInt8, csid: UInt8, _ body: Data, _ timestamp: UInt32) {
        queue.async { [self] in
            guard state == .publishing else { return }
            write(writer.encode(RTMPMessage(type: type, streamID: streamID, timestamp: timestamp, payload: body), chunkStream: csid))
        }
    }

    // MARK: Connection

    private func connectionChanged(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            var c0c1 = Data([0x03])
            c0c1.append(Data(count: 8))
            c0c1.append(Data((0..<1528).map { _ in UInt8.random(in: 0...255) }))
            write(c0c1)
            receive()
        case .failed(let error):
            fail(describe(error))
        case .waiting(let error):
            if state == .connecting { fail(describe(error)) }
        case .cancelled:
            if state == .connecting || state == .publishing { fail("The stream disconnected.") }
        default:
            break
        }
    }

    private func describe(_ error: NWError) -> String {
        switch error {
        case .tls: return "The secure connection to \(destination.host) failed. Check the server address (it should start with rtmps://)."
        case .dns: return "Couldn't find \(destination.host). Check the server address and your internet connection."
        default: return "Couldn't connect to \(destination.host): \(error.localizedDescription)"
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.received(data) }
            if let error { self.fail(self.describe(error)); return }
            if complete {
                self.fail(self.state == .publishing ? "The server ended the stream." :
                            "The server closed the connection. Check your stream key, and that your channel can go live.")
                return
            }
            if self.state == .connecting || self.state == .publishing { self.receive() }
        }
    }

    private func received(_ data: Data) {
        bytesReceived += UInt64(data.count)
        if !handshakeDone {
            handshake.append(data)
            // C2 (an echo of S1) goes as soon as S0 + S1 arrive: some servers wait for it before S2.
            if !sentC2 && handshake.count >= 1 + 1536 {
                guard handshake[0] == 3 else { fail("\(destination.host) isn't an RTMP server."); return }
                write(handshake.subdata(in: 1..<1537))
                sentC2 = true
            }
            guard handshake.count >= 1 + 1536 + 1536 else { return }
            let rest = handshake.subdata(in: 3073..<handshake.count)
            handshake = Data()
            handshakeDone = true
            var size = Data(); size.appendBE(UInt32(4096))
            write(writer.encode(RTMPMessage(type: 1, streamID: 0, timestamp: 0, payload: size), chunkStream: 2))
            writer.chunkSize = 4096
            sendCommand("connect", [.object([
                ("app", .string(destination.app)), ("type", .string("nonprivate")),
                ("flashVer", .string("FMLE/3.0 (compatible; AVYDRIX Play)")),
                ("tcUrl", .string(destination.tcUrl)),
            ])], transaction: 1)
            if !rest.isEmpty { process(rest) }
            return
        }
        process(data)
    }

    private func process(_ data: Data) {
        let messages: [RTMPMessage]
        do { messages = try reader.feed(data) } catch { fail("The server sent something unexpected."); return }
        if bytesReceived - lastAck >= ackWindow {
            lastAck = bytesReceived
            var ack = Data(); ack.appendBE(UInt32(truncatingIfNeeded: bytesReceived))
            write(writer.encode(RTMPMessage(type: 3, streamID: 0, timestamp: 0, payload: ack), chunkStream: 2))
        }
        for message in messages { handle(message) }
    }

    private func handle(_ message: RTMPMessage) {
        var index = message.payload.startIndex
        switch message.type {
        case 1:
            if let size: UInt32 = message.payload.readBE(at: &index) { reader.chunkSize = Int(size & 0x7FFF_FFFF) }
        case 5:
            if let size: UInt32 = message.payload.readBE(at: &index), size > 0 { ackWindow = UInt64(size) }
        case 6:
            var size = Data(); size.appendBE(UInt32(2_500_000))
            write(writer.encode(RTMPMessage(type: 5, streamID: 0, timestamp: 0, payload: size), chunkStream: 2))
        case 4:
            if let event: UInt16 = message.payload.readBE(at: &index), event == 6,
               let stamp: UInt32 = message.payload.readBE(at: &index) {
                var pong = Data(); pong.appendBE(UInt16(7)); pong.appendBE(stamp)
                write(writer.encode(RTMPMessage(type: 4, streamID: 0, timestamp: 0, payload: pong), chunkStream: 2))
            }
        case 20:
            command(AMF0.decodeAll(message.payload))
        default:
            break
        }
    }

    private func command(_ values: [AMF0]) {
        guard let name = values.first?.string else { return }
        let id = values.count > 1 ? values[1].number ?? 0 : 0
        switch name {
        case "_result" where id == 1:
            sendCommand("releaseStream", [.null, .string(destination.key)], transaction: 2)
            sendCommand("FCPublish", [.null, .string(destination.key)], transaction: 3)
            sendCommand("createStream", [.null], transaction: 4)
        case "_result" where id == 4:
            streamID = UInt32(values.count > 3 ? values[3].number ?? 1 : 1)
            let body = AMF0.encode([.string("publish"), .number(5), .null, .string(destination.key), .string("live")])
            write(writer.encode(RTMPMessage(type: 20, streamID: streamID, timestamp: 0, payload: body), chunkStream: 4))
        case "_error":
            let info = values.count > 3 ? values[3] : .null
            let detail = info["description"]?.string ?? info["code"]?.string ?? "unknown error"
            fail(id == 1 ? "The server refused the connection (\(detail)). Check the server address." :
                    "The server refused the stream (\(detail)). Check your stream key.")
        case "onStatus":
            let info = values.count > 3 ? values[3] : .null
            let code = info["code"]?.string ?? ""
            if code == "NetStream.Publish.Start" {
                timeout?.cancel()
                set(.publishing)
            } else if info["level"]?.string == "error" || code.contains("BadName") || code.contains("Failed") || code.contains("Rejected") {
                fail("The server refused the stream (\(info["description"]?.string ?? code)). Check your stream key.")
            }
        default:
            break
        }
    }

    private func sendCommand(_ name: String, _ arguments: [AMF0], transaction id: Double? = nil) {
        var number = id ?? 0
        if id == nil {
            transaction += 1
            number = transaction + 10
        }
        let body = AMF0.encode([.string(name), .number(number)] + arguments)
        write(writer.encode(RTMPMessage(type: 20, streamID: 0, timestamp: 0, payload: body), chunkStream: 3))
    }

    private func write(_ data: Data) {
        guard let connection else { return }
        pending += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.pending -= data.count
            self.bytesSent += UInt64(data.count)
            if let error, self.state == .publishing { self.fail(self.describe(error)) }
        })
    }

    private func fail(_ message: String) {
        guard state == .connecting || state == .publishing else { return }
        timeout?.cancel()
        set(.failed(message))
        connection?.cancel()
    }

    private func set(_ newState: State) {
        state = newState
        onState?(newState)
    }
}
