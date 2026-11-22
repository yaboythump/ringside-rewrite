import SwiftUI
import UIKit

@main
struct MacDuoApp: App {
    @StateObject private var library = MacLibrary()

    init() {
        DebugLaunch.prepare()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .onOpenURL { url in library.importFiles([url]) }
                .task { await DebugSnapshot.runIfAsked() }
        }
    }
}

/// Launch options for simulator checks in CI (no real ROM is ever bundled):
///   -MacDuoTestROM   writes the original test ROM from tests/make_test_rom.py
///                    and turns the Mac on, so the play screen can be checked
///   -MacDuoFakeFold  lays the play screen out as if iPhone Duo were half-folded
///   -MacDuoSnapshot  saves pictures of the app into its tmp folder
enum DebugLaunch {
    static var autoStart: Bool { ProcessInfo.processInfo.arguments.contains("-MacDuoTestROM") }

    static func prepare() {
        guard autoStart else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("ROM", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? testROM().write(to: folder.appendingPathComponent("MacDuoTest.rom"))
    }

    /// Same bytes as tests/make_test_rom.py: a valid header and a loop that
    /// fills the video card's memory with a pattern. Not Apple code.
    static func testROM() -> Data {
        let size = Int(MV_ROM_SIZE)
        var rom = [UInt8](repeating: 0, count: size)
        let code: [UInt8] = [0x41, 0xF9, 0xF9, 0x90, 0x00, 0x00,
                             0x20, 0x3C, 0x12, 0x34, 0x56, 0x78,
                             0x20, 0xC0,
                             0xB1, 0xFC, 0xF9, 0x91, 0x00, 0x00,
                             0x66, 0xF6,
                             0x60, 0xFE]
        rom.replaceSubrange(0x100..<(0x100 + code.count), with: code)
        let pc: UInt32 = 0x4080_0000 + 0x100
        rom[4] = UInt8(pc >> 24); rom[5] = UInt8((pc >> 16) & 0xFF); rom[6] = UInt8((pc >> 8) & 0xFF); rom[7] = UInt8(pc & 0xFF)
        let tag = Array("MacDuoTestROM".utf8)
        rom.replaceSubrange(0x1000..<(0x1000 + tag.count), with: tag)
        var sum: UInt32 = 0
        var i = 4
        while i < size {
            sum = sum &+ (UInt32(rom[i]) << 8 | UInt32(rom[i + 1]))
            i += 2
        }
        rom[0] = UInt8(sum >> 24); rom[1] = UInt8((sum >> 16) & 0xFF); rom[2] = UInt8((sum >> 8) & 0xFF); rom[3] = UInt8(sum & 0xFF)
        return Data(rom)
    }
}

enum DebugSnapshot {
    @MainActor
    static func runIfAsked() async {
        guard ProcessInfo.processInfo.arguments.contains("-MacDuoSnapshot") else { return }
        for (index, delay) in [7.0, 5.0].enumerated() {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            save(name: "snapshot-\(index + 1)")
        }
    }

    @MainActor
    static func save(name: String) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            for window in windows.sorted(by: { $0.windowLevel < $1.windowLevel }) where !window.isHidden {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try? image.pngData()?.write(to: url)
        let layout = "ticks=\(MVCoreTickCount()) state=\(MVCoreGetState().rawValue) disks=\(MVCoreDiskCount()) window=\(window.bounds.size)\n"
        try? layout.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("layout.txt"), atomically: true, encoding: .utf8)
        print("MacDuo snapshot \(name) \(layout)")
    }
}
