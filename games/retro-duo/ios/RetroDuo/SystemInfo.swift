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
    static var allCases: [GameSystem] { [.nes, .snes, .gameBoy, .gameBoyColor, .gameBoyAdvance, .nintendoDS] }

    /// Short badge text.
    var shortName: String {
        switch self {
        case .nes: return "NES"
        case .snes: return "SNES"
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
        return [FaceKey(label: "B", key: PadKey.b, color: Theme.buttonB),
         FaceKey(label: "A", key: PadKey.a, color: Theme.buttonA)]
    }

    var hasShoulders: Bool { self == .gameBoyAdvance || self == .nintendoDS || self == .snes }

    /// The small buttons between the D-pad and the face buttons.
    var menuKeys: [(label: String, key: Int)] {
        [("SELECT", PadKey.select), ("START", PadKey.start)]
    }
}
