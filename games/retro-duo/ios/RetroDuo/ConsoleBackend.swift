import Foundation

/// One single-screen console (Game Boy, NES, SNES, GBA) behind a common interface, so
/// EmulatorSession and GameView can run either. Input uses RD_KEY_* bits for both.
@MainActor
protocol ConsoleBackend: AnyObject {
    var frameRate: Double { get }
    var frameCount: UInt64 { get }
    var rumble: Double { get }
    /// PadKey bits.
    func setKeys(_ keys: UInt32)
    func runFrame()
    func show(on view: PixelScreenView)
    func battery() -> Data?
    func saveState() -> Data?
    func loadState(_ data: Data) -> Bool
    func reset()
    func startAudio(_ audio: AudioOutput)
    func destroy()
    /// Why the console stopped for good, or nil while it runs.
    var failure: String? { get }
    /// One byte of the game's work RAM at the address its own CPU uses (for example $D163 on
    /// the Game Boy, $7E0577 on the SNES, $FFFE20 on the Genesis), or nil where it can't be read.
    func peek(_ address: UInt32) -> UInt8?
    /// Consoles with a second controller port (NES, SNES, Genesis, Master System).
    var supportsTwoPlayers: Bool { get }
    /// Buttons for player 2, in the same bits as `setKeys`.
    func setPlayer2Keys(_ keys: UInt32)
    /// Replaces the cheats with these (the enabled ones); returns which were understood.
    func setCheats(_ cheats: [Cheat]) -> [Bool]
}

extension ConsoleBackend {
    var failure: String? { nil }
    func peek(_ address: UInt32) -> UInt8? { nil }
    var supportsTwoPlayers: Bool { false }
    func setPlayer2Keys(_ keys: UInt32) {}
    func setCheats(_ cheats: [Cheat]) -> [Bool] { cheats.map { _ in false } }
}

enum ConsoleBackends {
    /// Creates the right console for a game, or returns a message for the player.
    @MainActor
    static func make(for game: Game, rom: Data, battery: Data?) -> Result<ConsoleBackend, ConsoleError> {
        switch game.system {
        case .nes: return NESBackend.make(rom: rom, battery: battery)
        case .gameBoyAdvance: return GBABackend.make(rom: rom, battery: battery)
        case .snes: return LibretroBackend.make(system: Int32(RDLR_SYSTEM_SNES), rom: rom, battery: battery,
                                                fileExtension: game.url.pathExtension.lowercased(), consoleName: "Super Nintendo")
        case .genesis:
            // BlastEm picks the console from the file extension.
            return LibretroBackend.make(system: Int32(RDLR_SYSTEM_SEGA), rom: rom, battery: battery,
                                        fileExtension: game.url.pathExtension.lowercased(),
                                        consoleName: game.system.displayName, padMap: LibretroBackend.segaPad, ram: .genesis)
        case .masterSystem, .gameGear:
            let gameGear = game.system == .gameGear
            return LibretroBackend.make(system: Int32(RDLR_SYSTEM_SEGA), rom: rom, battery: battery,
                                        fileExtension: game.url.pathExtension.lowercased(),
                                        consoleName: game.system.displayName, padMap: LibretroBackend.masterSystemPad,
                                        ram: .masterSystem, twoPlayers: !gameGear) { core in
                // BlastEm draws these inside a Genesis-sized picture: the 192 visible lines start
                // 16 lines down (24 on PAL), and the Game Gear shows only the middle 160x144.
                let top: UInt32 = RDLRFrameRate(core) < 55 ? 24 : 16
                if gameGear { RDLRSetCrop(core, 48, top + 24, 160, 144) } else { RDLRSetCrop(core, 0, top, 256, 192) }
            }
        default: return GameBoyBackend.make(rom: rom, battery: battery, name: game.name)
        }
    }
}

struct ConsoleError: Error {
    let message: String
}

// MARK: - Game Boy / Game Boy Color (SameBoy)

@MainActor
final class GameBoyBackend: ConsoleBackend {
    private var core: OpaquePointer?
    let frameRate = 59.7275

    private init(core: OpaquePointer) { self.core = core }

    static func make(rom: Data, battery: Data?, name: String) -> Result<ConsoleBackend, ConsoleError> {
        guard let bootURL = Bundle.main.url(forResource: "cgb_boot", withExtension: "bin"),
              let boot = try? Data(contentsOf: bootURL) else {
            return .failure(ConsoleError(message: "AVYDRIX Play is missing its start-up file. Reinstall the app."))
        }
        guard GameLibrary.looksLikeROM(rom) else {
            return .failure(ConsoleError(message: "\(name) couldn't be opened. The file may be damaged or not a Game Boy game."))
        }
        let created = boot.withUnsafeBytes { bytes in
            RDCoreCreate(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, UInt32(AudioOutput.sampleRate))
        }
        guard let created else { return .failure(ConsoleError(message: "The emulator couldn't start.")) }
        let loaded = rom.withUnsafeBytes { bytes in
            RDCoreLoadROM(created, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard loaded else {
            RDCoreDestroy(created)
            return .failure(ConsoleError(message: "\(name) isn't a Game Boy game AVYDRIX Play can run."))
        }
        if let battery, !battery.isEmpty {
            battery.withUnsafeBytes { RDCoreLoadBattery(created, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
        }
        return .success(GameBoyBackend(core: created))
    }

    var frameCount: UInt64 { core.map { RDCoreFrameCount($0) } ?? 0 }
    var rumble: Double { core.map { RDCoreRumble($0) } ?? 0 }

    func peek(_ address: UInt32) -> UInt8? {
        guard let core, address <= 0xFFFF else { return nil }
        return RDCoreReadMemory(core, UInt16(address))
    }

    func setCheats(_ cheats: [Cheat]) -> [Bool] {
        guard let core else { return cheats.map { _ in false } }
        var accepted = [Bool](repeating: false, count: cheats.count)
        withCStrings(cheats.map(CheatCodes.entry)) { RDCoreSetCheats(core, $0, $0.count, &accepted) }
        return accepted
    }

    func setKeys(_ keys: UInt32) {
        guard let core else { return }
        RDCoreSetKeys(core, UInt8(truncatingIfNeeded: keys))
    }

    func runFrame() {
        guard let core else { return }
        RDCoreRunFrame(core)
    }

    func show(on view: PixelScreenView) {
        guard let core else { return }
        view.show(core)
    }

    func battery() -> Data? {
        guard let core else { return nil }
        let size = RDCoreBatterySize(core)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let written = data.withUnsafeMutableBytes {
            RDCoreSaveBattery(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        return written > 0 ? data.prefix(written) : nil
    }

    func saveState() -> Data? {
        guard let core else { return nil }
        let size = RDCoreStateSize(core)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        data.withUnsafeMutableBytes { RDCoreSaveState(core, $0.bindMemory(to: UInt8.self).baseAddress) }
        return data
    }

    func loadState(_ data: Data) -> Bool {
        guard let core else { return false }
        return data.withUnsafeBytes {
            RDCoreLoadState(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
    }

    func reset() {
        guard let core else { return }
        RDCoreReset(core)
    }

    func startAudio(_ audio: AudioOutput) {
        guard let core else { return }
        audio.start(core: core)
    }

    func destroy() {
        guard let core else { return }
        RDCoreDestroy(core)
        self.core = nil
    }
}

// MARK: - NES (Nestopia)

@MainActor
final class NESBackend: ConsoleBackend {
    private var core: OpaquePointer?
    let frameRate = 60.0988
    let rumble = 0.0

    private init(core: OpaquePointer) { self.core = core }

    static func make(rom: Data, battery: Data?) -> Result<ConsoleBackend, ConsoleError> {
        guard let created = NESCoreCreate(UInt32(AudioOutput.sampleRate)) else {
            return .failure(ConsoleError(message: "The NES emulator couldn't start."))
        }
        let save = battery ?? Data()
        let loaded = rom.withUnsafeBytes { romBytes in
            save.withUnsafeBytes { saveBytes in
                NESCoreLoadROM(created,
                               romBytes.bindMemory(to: UInt8.self).baseAddress, romBytes.count,
                               saveBytes.bindMemory(to: UInt8.self).baseAddress, saveBytes.count)
            }
        }
        guard loaded else {
            NESCoreDestroy(created)
            return .failure(ConsoleError(message: "This NES game uses hardware AVYDRIX Play can't run yet, or the file is damaged."))
        }
        return .success(NESBackend(core: created))
    }

    var frameCount: UInt64 { core.map { NESCoreFrameCount($0) } ?? 0 }

    func peek(_ address: UInt32) -> UInt8? {
        guard let core, address < 0x2000 else { return nil }
        return NESCoreReadRAM(core, UInt16(address))
    }

    var supportsTwoPlayers: Bool { true }
    func setCheats(_ cheats: [Cheat]) -> [Bool] {
        guard let core else { return cheats.map { _ in false } }
        var accepted = [Bool](repeating: false, count: cheats.count)
        withCStrings(cheats.map(CheatCodes.entry)) { NESCoreSetCheats(core, $0, $0.count, &accepted) }
        return accepted
    }

    /// RD_KEY_* bits (as the shared controls send them) to NES_KEY_* bits.
    func setKeys(_ keys: UInt32) { set(keys, player: 0) }
    func setPlayer2Keys(_ keys: UInt32) { set(keys, player: 1) }

    private func set(_ keys: UInt32, player: UInt32) {
        guard let core else { return }
        var nes = 0
        if keys & UInt32(RD_KEY_RIGHT) != 0 { nes |= Int(NES_KEY_RIGHT) }
        if keys & UInt32(RD_KEY_LEFT) != 0 { nes |= Int(NES_KEY_LEFT) }
        if keys & UInt32(RD_KEY_UP) != 0 { nes |= Int(NES_KEY_UP) }
        if keys & UInt32(RD_KEY_DOWN) != 0 { nes |= Int(NES_KEY_DOWN) }
        if keys & UInt32(RD_KEY_A) != 0 { nes |= Int(NES_KEY_A) }
        if keys & UInt32(RD_KEY_B) != 0 { nes |= Int(NES_KEY_B) }
        if keys & UInt32(RD_KEY_SELECT) != 0 { nes |= Int(NES_KEY_SELECT) }
        if keys & UInt32(RD_KEY_START) != 0 { nes |= Int(NES_KEY_START) }
        NESCoreSetPlayerKeys(core, player, UInt8(truncatingIfNeeded: nes))
    }

    func runFrame() {
        guard let core else { return }
        NESCoreRunFrame(core)
    }

    func show(on view: PixelScreenView) {
        guard let core, let pixels = NESCorePixels(core) else { return }
        view.show(pixels: pixels, width: Int(NES_SCREEN_WIDTH), height: Int(NES_SCREEN_HEIGHT))
    }

    func battery() -> Data? {
        guard let core else { return nil }
        let size = NESCoreBatterySize(core)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let copied = data.withUnsafeMutableBytes {
            NESCoreCopyBattery(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        return copied == size ? data : nil
    }

    func saveState() -> Data? {
        guard let core else { return nil }
        var length = 0
        guard let buffer = NESCoreSaveState(core, &length) else { return nil }
        defer { NESCoreFreeBuffer(buffer) }
        return Data(bytes: buffer, count: length)
    }

    func loadState(_ data: Data) -> Bool {
        guard let core else { return false }
        return data.withUnsafeBytes {
            NESCoreLoadState(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
    }

    func reset() {
        guard let core else { return }
        NESCoreReset(core)
    }

    func startAudio(_ audio: AudioOutput) {
        guard let core else { return }
        audio.start(nesCore: core)
    }

    func destroy() {
        guard let core else { return }
        NESCoreDestroy(core)
        self.core = nil
    }
}

// MARK: - Game Boy Advance (mGBA)

@MainActor
final class GBABackend: ConsoleBackend {
    private var core: OpaquePointer?
    let frameRate = 59.7275

    private init(core: OpaquePointer) { self.core = core }

    static func make(rom: Data, battery: Data?) -> Result<ConsoleBackend, ConsoleError> {
        guard let created = RDGBACreate(UInt32(AudioOutput.sampleRate)) else {
            return .failure(ConsoleError(message: "The Game Boy Advance emulator couldn't start."))
        }
        let save = battery ?? Data()
        let loaded = rom.withUnsafeBytes { romBytes in
            save.withUnsafeBytes { saveBytes in
                RDGBALoadROM(created,
                             romBytes.bindMemory(to: UInt8.self).baseAddress, romBytes.count,
                             saveBytes.bindMemory(to: UInt8.self).baseAddress, saveBytes.count)
            }
        }
        guard loaded else {
            RDGBADestroy(created)
            return .failure(ConsoleError(message: "This file isn't a Game Boy Advance game AVYDRIX Play can run, or it's damaged."))
        }
        return .success(GBABackend(core: created))
    }

    var frameCount: UInt64 { core.map { RDGBAFrameCount($0) } ?? 0 }
    var rumble: Double { core.map { RDGBARumble($0) } ?? 0 }

    func peek(_ address: UInt32) -> UInt8? {
        guard let core, (0x0200_0000..<0x0400_0000).contains(address) else { return nil }
        return RDGBARead8(core, address)
    }

    func setCheats(_ cheats: [Cheat]) -> [Bool] {
        guard let core else { return cheats.map { _ in false } }
        var accepted = [Bool](repeating: false, count: cheats.count)
        withCStrings(cheats.map(CheatCodes.entry)) { RDGBASetCheats(core, $0, $0.count, &accepted) }
        return accepted
    }

    func setKeys(_ keys: UInt32) {
        guard let core else { return }
        let map: [(Int, Int)] = [
            (PadKey.a, Int(GBA_PAD_A)), (PadKey.b, Int(GBA_PAD_B)),
            (PadKey.select, Int(GBA_PAD_SELECT)), (PadKey.start, Int(GBA_PAD_START)),
            (PadKey.right, Int(GBA_PAD_RIGHT)), (PadKey.left, Int(GBA_PAD_LEFT)),
            (PadKey.up, Int(GBA_PAD_UP)), (PadKey.down, Int(GBA_PAD_DOWN)),
            (PadKey.r, Int(GBA_PAD_R)), (PadKey.l, Int(GBA_PAD_L)),
        ]
        var gba = 0
        for (pad, bit) in map where Int(keys) & pad != 0 { gba |= bit }
        RDGBASetKeys(core, UInt16(truncatingIfNeeded: gba))
    }

    func runFrame() {
        guard let core else { return }
        RDGBARunFrame(core)
    }

    func show(on view: PixelScreenView) {
        guard let core, let pixels = RDGBAPixels(core) else { return }
        view.show(pixels: pixels, width: Int(GBA_SCREEN_WIDTH), height: Int(GBA_SCREEN_HEIGHT))
    }

    func battery() -> Data? {
        guard let core else { return nil }
        var length = 0
        guard let buffer = RDGBACopySave(core, &length) else { return nil }
        defer { RDGBAFreeBuffer(buffer) }
        return Data(bytes: buffer, count: length)
    }

    func saveState() -> Data? {
        guard let core else { return nil }
        var length = 0
        guard let buffer = RDGBASaveState(core, &length) else { return nil }
        defer { RDGBAFreeBuffer(buffer) }
        return Data(bytes: buffer, count: length)
    }

    func loadState(_ data: Data) -> Bool {
        guard let core else { return false }
        return data.withUnsafeBytes {
            RDGBALoadState(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
    }

    func reset() {
        guard let core else { return }
        RDGBAReset(core)
    }

    func startAudio(_ audio: AudioOutput) {
        guard let core else { return }
        audio.start(gbaCore: core)
    }

    func destroy() {
        guard let core else { return }
        RDGBADestroy(core)
        self.core = nil
    }
}

// MARK: - libretro cores (Super Nintendo: bsnes; Genesis, Master System, Game Gear: BlastEm)

@MainActor
final class LibretroBackend: ConsoleBackend {
    private var core: OpaquePointer?
    let frameRate: Double
    let rumble = 0.0

    private let padMap: [(Int, Int)]
    private let ram: ConsoleRAM
    let supportsTwoPlayers: Bool

    private init(core: OpaquePointer, padMap: [(Int, Int)], ram: ConsoleRAM, twoPlayers: Bool) {
        self.core = core
        self.padMap = padMap
        self.ram = ram
        supportsTwoPlayers = twoPlayers
        frameRate = RDLRFrameRate(core)
    }

    func peek(_ address: UInt32) -> UInt8? {
        guard let core, let offset = ram.offset(of: address) else { return nil }
        var byte: UInt8 = 0
        return RDLRReadRAM(core, offset, &byte, 1) == 1 ? byte : nil
    }

    /// RAM writes made before every frame, for a core without its own cheat engine (BlastEm).
    private var ramCheats: [CheatCodes.RAMWrite] = []

    func setCheats(_ cheats: [Cheat]) -> [Bool] {
        guard let core else { return cheats.map { _ in false } }
        if RDLRHasCheatEngine(core) {
            let decoded = cheats.map(CheatCodes.snesCodes)
            withCStrings(decoded.compactMap { $0 }.flatMap { $0 }) { RDLRSetCheats(core, $0, $0.count) }
            return decoded.map { $0 != nil }
        }
        let writes = cheats.map { CheatCodes.segaRAMWrites($0, genesis: ram == .genesis) }
        ramCheats = writes.compactMap { $0 }.flatMap { $0 }
        return writes.map { $0 != nil }
    }

    private func applyRAMCheats(_ core: OpaquePointer) {
        for write in ramCheats {
            for (i, byte) in write.bytes.enumerated() {
                guard let offset = ram.offset(of: write.address + UInt32(i)) else { continue }
                var value = byte
                RDLRWriteRAM(core, offset, &value, 1)
            }
        }
    }

    /// PadKey bits to RetroPad bits, SNES layout (also the RetroPad's own).
    static let snesPad: [(Int, Int)] = [
        (PadKey.a, Int(RDLR_PAD_A)), (PadKey.b, Int(RDLR_PAD_B)),
        (PadKey.x, Int(RDLR_PAD_X)), (PadKey.y, Int(RDLR_PAD_Y)),
        (PadKey.l, Int(RDLR_PAD_L)), (PadKey.r, Int(RDLR_PAD_R)),
        (PadKey.select, Int(RDLR_PAD_SELECT)), (PadKey.start, Int(RDLR_PAD_START)),
        (PadKey.right, Int(RDLR_PAD_RIGHT)), (PadKey.left, Int(RDLR_PAD_LEFT)),
        (PadKey.up, Int(RDLR_PAD_UP)), (PadKey.down, Int(RDLR_PAD_DOWN)),
    ]

    /// Genesis pads through BlastEm's RetroPad layout: A=B, B=A, C=R, X=Y, Y=X, Z=L, MODE=SELECT.
    static let segaPad: [(Int, Int)] = [
        (PadKey.a, Int(RDLR_PAD_B)), (PadKey.b, Int(RDLR_PAD_A)), (PadKey.c, Int(RDLR_PAD_R)),
        (PadKey.x, Int(RDLR_PAD_Y)), (PadKey.y, Int(RDLR_PAD_X)), (PadKey.z, Int(RDLR_PAD_L)),
        (PadKey.mode, Int(RDLR_PAD_SELECT)), (PadKey.start, Int(RDLR_PAD_START)),
        (PadKey.right, Int(RDLR_PAD_RIGHT)), (PadKey.left, Int(RDLR_PAD_LEFT)),
        (PadKey.up, Int(RDLR_PAD_UP)), (PadKey.down, Int(RDLR_PAD_DOWN)),
    ]

    /// Master System / Game Gear: button 1 is the Sega pad's B, button 2 its C; START is PAUSE.
    static let masterSystemPad: [(Int, Int)] = [
        (PadKey.b, Int(RDLR_PAD_A)), (PadKey.a, Int(RDLR_PAD_R)), (PadKey.start, Int(RDLR_PAD_START)),
        (PadKey.right, Int(RDLR_PAD_RIGHT)), (PadKey.left, Int(RDLR_PAD_LEFT)),
        (PadKey.up, Int(RDLR_PAD_UP)), (PadKey.down, Int(RDLR_PAD_DOWN)),
    ]

    static func make(system: Int32, rom: Data, battery: Data?, fileExtension: String,
                     consoleName: String, padMap: [(Int, Int)] = snesPad, ram: ConsoleRAM = .snes,
                     twoPlayers: Bool = true, configure: ((OpaquePointer) -> Void)? = nil) -> Result<ConsoleBackend, ConsoleError> {
        // Some cores read the game from disk, so each session gets a scratch folder.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("libretro", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        guard let created = RDLRCreate(system, work.path) else {
            return .failure(ConsoleError(message: "The \(consoleName) emulator couldn't start. Close any other game and try again."))
        }
        let save = battery ?? Data()
        let name = "game." + (fileExtension.isEmpty ? "bin" : fileExtension)
        let loaded = rom.withUnsafeBytes { romBytes in
            save.withUnsafeBytes { saveBytes in
                RDLRLoadROM(created,
                            romBytes.bindMemory(to: UInt8.self).baseAddress, romBytes.count,
                            saveBytes.bindMemory(to: UInt8.self).baseAddress, saveBytes.count, name)
            }
        }
        guard loaded else {
            RDLRDestroy(created)
            return .failure(ConsoleError(message: "This file isn't a \(consoleName) game AVYDRIX Play can run, or it's damaged."))
        }
        configure?(created)
        return .success(LibretroBackend(core: created, padMap: padMap, ram: ram, twoPlayers: twoPlayers))
    }

    var frameCount: UInt64 { core.map { RDLRFrameCount($0) } ?? 0 }

    /// PadKey bits to RetroPad bits.
    func setKeys(_ keys: UInt32) { set(keys, player: 0) }
    func setPlayer2Keys(_ keys: UInt32) { if supportsTwoPlayers { set(keys, player: 1) } }

    private func set(_ keys: UInt32, player: UInt32) {
        guard let core else { return }
        var pad = 0
        for (key, bit) in padMap where Int(keys) & key != 0 { pad |= bit }
        RDLRSetPlayerKeys(core, player, UInt32(pad))
    }

    func runFrame() {
        guard let core else { return }
        if !ramCheats.isEmpty { applyRAMCheats(core) }
        RDLRRunFrame(core)
    }

    var failure: String? {
        guard let core, let reason = RDLRFailure(core) else { return nil }
        return String(cString: reason)
    }

    func show(on view: PixelScreenView) {
        guard let core, let pixels = RDLRPixels(core) else { return }
        let width = Int(RDLRWidth(core)), height = Int(RDLRHeight(core))
        guard width > 0, height > 0 else { return }
        view.show(pixels: pixels, width: width, height: height)
    }

    func battery() -> Data? {
        guard let core else { return nil }
        var length = 0
        guard let buffer = RDLRCopySave(core, &length) else { return nil }
        defer { RDLRFreeBuffer(buffer) }
        return Data(bytes: buffer, count: length)
    }

    func saveState() -> Data? {
        guard let core else { return nil }
        var length = 0
        guard let buffer = RDLRSaveState(core, &length) else { return nil }
        defer { RDLRFreeBuffer(buffer) }
        return Data(bytes: buffer, count: length)
    }

    func loadState(_ data: Data) -> Bool {
        guard let core else { return false }
        return data.withUnsafeBytes {
            RDLRLoadState(core, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
    }

    func reset() {
        guard let core else { return }
        RDLRReset(core)
    }

    func startAudio(_ audio: AudioOutput) {
        guard let core else { return }
        audio.start(libretroCore: core, rate: RDLRSampleRate(core))
    }

    func destroy() {
        guard let core else { return }
        RDLRDestroy(core)
        self.core = nil
    }
}
