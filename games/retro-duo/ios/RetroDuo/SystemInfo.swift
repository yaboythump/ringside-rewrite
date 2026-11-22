import SwiftUI

/// Universal button bits used by the on-screen controls, controllers and every
/// single-screen backend. The low 8 bits match RD_KEY_* (Game Boy) exactly.
enum PadKey {
    static let right = Int(RD_KEY_RIGHT)
    static let left = Int(RD_KEY_LEFT)
    static let up = Int(RD_KEY_UP)
    static let down = Int(RD_KEY_DOWN)
    static let a = Int(RD_KEY_A)
    static let b = Int(RD_KEY_B)
    static let select = Int(RD_KEY_SELECT)
    static let start = Int(RD_KEY_START)
    static let x = 1 << 8
    static let y = 1 << 9
    static let l = 1 << 10
    static let r = 1 << 11
    static let c = 1 << 12
    static let z = 1 << 13
    static let mode = 1 << 14
}

/// One face button in a system's on-screen layout.
struct FaceKey: Identifiable {
    let label: String
    let key: Int
    let color: Color
    var id: String { label }
}

/// Everything that differs between the single-screen systems in one place:
/// names, picture shape, buttons and where cover art comes from.
extension GameSystem: CaseIterable {
    static var allCases: [GameSystem] { [.nes, .snes, .genesis, .masterSystem, .gameGear, .gameBoy, .gameBoyColor, .gameBoyAdvance, .nintendoDS] }

    /// Short badge text.
    var shortName: String {
        switch self {
        case .nes: return "NES"
        case .snes: return "SNES"
        case .genesis: return "GEN"
        case .masterSystem: return "SMS"
        case .gameGear: return "GG"
        case .gameBoy: return "GB"
        case .gameBoyColor: return "GBC"
        case .gameBoyAdvance: return "GBA"
        case .nintendoDS: return "DS"
        }
    }

    /// Library filter label.
    var filterName: String { displayName.uppercased() }

    /// Picture height / width.
    var aspect: CGFloat {
        switch self {
        case .nes, .snes: return 224.0 / 256.0
        case .genesis: return 224.0 / 320.0
        case .masterSystem: return 192.0 / 256.0
        case .gameGear: return 144.0 / 160.0
        case .gameBoyAdvance: return 160.0 / 240.0
        case .nintendoDS: return 0.75
        default: return 144.0 / 160.0
        }
    }

    /// Folder name in the libretro thumbnail collection used for cover art.
    var artworkFolder: String {
        switch self {
        case .nes: return "Nintendo - Nintendo Entertainment System"
        case .snes: return "Nintendo - Super Nintendo Entertainment System"
        case .genesis: return "Sega - Mega Drive - Genesis"
        case .masterSystem: return "Sega - Master System - Mark III"
        case .gameGear: return "Sega - Game Gear"
        case .gameBoy: return "Nintendo - Game Boy"
        case .gameBoyColor: return "Nintendo - Game Boy Color"
        case .gameBoyAdvance: return "Nintendo - Game Boy Advance"
        case .nintendoDS: return "Nintendo - Nintendo DS"
        }
    }

    /// Face buttons from left to right.
    var faceKeys: [FaceKey] {
        if self == .snes {
            // Diamond in SNES order: Y left, X top, B bottom, A right.
            return [FaceKey(label: "Y", key: PadKey.y, color: Theme.buttonY),
                    FaceKey(label: "X", key: PadKey.x, color: Theme.buttonX),
                    FaceKey(label: "B", key: PadKey.b, color: Theme.buttonB),
                    FaceKey(label: "A", key: PadKey.a, color: Theme.buttonA)]
        }
        switch self {
        case .genesis:
            // Arc of three, A B C like the Genesis pad. X/Y/Z come from a controller.
            return [FaceKey(label: "A", key: PadKey.a, color: Theme.buttonY),
                    FaceKey(label: "B", key: PadKey.b, color: Theme.buttonB),
                    FaceKey(label: "C", key: PadKey.c, color: Theme.buttonA)]
        case .masterSystem, .gameGear:
            // 1 on the left, 2 on the right (B/A positions, so controllers match too).
            return [FaceKey(label: "1", key: PadKey.b, color: Theme.buttonB),
                    FaceKey(label: "2", key: PadKey.a, color: Theme.buttonA)]
        default: break
        }
        return [FaceKey(label: "B", key: PadKey.b, color: Theme.buttonB),
         FaceKey(label: "A", key: PadKey.a, color: Theme.buttonA)]
    }

    var hasShoulders: Bool { self == .gameBoyAdvance || self == .nintendoDS || self == .snes }

    /// The small buttons between the D-pad and the face buttons.
    var menuKeys: [(label: String, key: Int)] {
        switch self {
        case .genesis: return [("MODE", PadKey.mode), ("START", PadKey.start)]
        case .masterSystem: return [("PAUSE", PadKey.start)]
        case .gameGear: return [("START", PadKey.start)]
        default: return [("SELECT", PadKey.select), ("START", PadKey.start)]
        }
    }
}
