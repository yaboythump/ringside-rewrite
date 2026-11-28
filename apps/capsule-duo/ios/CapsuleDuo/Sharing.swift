import AVFoundation
import AVKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Capsule files (.dtcapsule)

extension UTType {
    static let dearTomorrowCapsule = UTType(exportedAs: "com.ctnetworkstudios.deartomorrow.capsule", conformingTo: .data)
}

enum CapsuleFileError: LocalizedError {
    case unreadable
    var errorDescription: String? { "This capsule file couldn't be read. Ask the sender to send it again." }
}

/// A capsule packed into one file so it can travel by Messages, AirDrop or email.
/// Layout: "DTCAPSULE1", manifest length (UInt32), manifest JSON, file count (UInt32),
/// then for each file: name length (UInt16), name, data length (UInt64), data.
enum CapsulePackage {
    private static let magic = Data("DTCAPSULE1".utf8)

    static func pack(manifest: Data, files: [(String, Data)]) -> Data {
        var out = magic
        append(&out, UInt32(manifest.count))
        out.append(manifest)
        append(&out, UInt32(files.count))
        for (name, data) in files {
            let nameData = Data(name.utf8)
            append(&out, UInt16(nameData.count))
            out.append(nameData)
            append(&out, UInt64(data.count))
            out.append(data)
        }
        return out
    }

    static func unpack(_ data: Data) throws -> (manifest: Data, files: [(String, Data)]) {
        var reader = Reader(data: data)
        guard try reader.bytes(magic.count) == magic else { throw CapsuleFileError.unreadable }
        let manifestLength = Int(try reader.integer(UInt32.self))
        let manifest = try reader.bytes(manifestLength)
        let count = Int(try reader.integer(UInt32.self))
        guard count <= 64 else { throw CapsuleFileError.unreadable }
        var files: [(String, Data)] = []
        for _ in 0..<count {
            let nameLength = Int(try reader.integer(UInt16.self))
            guard let name = String(data: try reader.bytes(nameLength), encoding: .utf8) else { throw CapsuleFileError.unreadable }
            let length = try reader.integer(UInt64.self)
            guard length <= UInt64(Int.max) else { throw CapsuleFileError.unreadable }
            files.append((name, try reader.bytes(Int(length))))
        }
        return (manifest, files)
    }

    private static func append<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private struct Reader {
        let data: Data
        var offset = 0

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, offset + count <= data.count else { throw CapsuleFileError.unreadable }
            let start = data.startIndex + offset
            offset += count
            return data.subdata(in: start..<(start + count))
        }

        mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let raw = try bytes(MemoryLayout<T>.size)
            return raw.reduce(T(0)) { ($0 << 8) | T($1) }
        }
    }
}

extension CapsuleStore {
    /// Packs a capsule into a file to send. The person who receives it can't open it early either.
    func exportFile(for capsule: Capsule, from senderName: String) throws -> URL {
        var copy = capsule
        copy.openedAt = nil
        copy.transcript = nil
        copy.replyToID = nil
        copy.sender = senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "A friend" : senderName
        copy.originID = capsule.originID ?? capsule.id
        let manifest = try JSONEncoder.capsule.encode(copy)

        var files: [(String, Data)] = []
        let media = mediaURL(for: capsule)
        if let data = try? Data(contentsOf: media) { files.append((media.lastPathComponent, data)) }
        for url in photoURLs(for: capsule) {
            if let data = try? Data(contentsOf: url) { files.append((url.lastPathComponent, data)) }
        }

        let who = capsule.recipient.map { "For \($0)" } ?? "Dear Tomorrow capsule"
        let safe = who.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Outbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(safe).dtcapsule")
        try CapsulePackage.pack(manifest: manifest, files: files).write(to: url, options: .atomic)
        return url
    }

    /// Adds a capsule someone sent you. It arrives sealed.
    func importCapsule(from url: URL) throws -> Capsule {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let (manifest, files) = try CapsulePackage.unpack(try Data(contentsOf: url))
        guard var incoming = try? JSONDecoder.capsule.decode(Capsule.self, from: manifest) else {
            throw CapsuleFileError.unreadable
        }
        let origin = incoming.originID ?? incoming.id
        if let existing = capsules.first(where: { $0.originID == origin || $0.id == origin }) { return existing }

        incoming.id = UUID()
        incoming.originID = origin
        incoming.openedAt = nil
        incoming.transcript = nil
        incoming.replyToID = nil
        incoming.recipient = nil
        if incoming.sender == nil { incoming.sender = "A friend" }

        let allowed = Set(["voice.m4a", "video.mov"] + (0..<8).map { "photo-\($0).jpg" })
        let folder = self.folder(for: incoming.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files where allowed.contains(name) {
            try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        }
        incoming.isVideo = files.contains { $0.0 == "video.mov" } ? true : nil
        incoming.photoCount = files.filter { $0.0.hasPrefix("photo-") }.count
        try add(incoming)
        return incoming
    }
}

extension JSONEncoder {
    static var capsule: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var capsule: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// A file waiting to be shared.
struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Video

/// The camera, set up to record a video message (front camera, up to 10 minutes).
struct CameraRecorder: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(UTType.movie.identifier)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.videoMaximumDuration = VoiceRecorder.maxLength
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let source = info[.mediaURL] as? URL else { onFinish(nil); return }
            // The camera's file is temporary, so keep our own copy as the draft.
            let draft = FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID().uuidString).mov")
            do {
                try FileManager.default.copyItem(at: source, to: draft)
                onFinish(draft)
            } catch {
                onFinish(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

enum VideoInfo {
    static func duration(of url: URL) async -> TimeInterval {
        let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        return seconds.isFinite ? seconds : 0
    }
}

/// Plays a video message inside the app.
struct VideoMessage: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.black.opacity(0.4)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.line, lineWidth: 1))
        .onAppear {
            if player == nil {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                player = AVPlayer(url: url)
            }
        }
        .onDisappear { player?.pause() }
    }
}
