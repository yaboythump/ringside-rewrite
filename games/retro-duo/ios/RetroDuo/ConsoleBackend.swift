import Foundation

/// One single-screen console (Game Boy or NES) behind a common interface, so
/// EmulatorSession and GameView can run either. Input uses RD_KEY_* bits for both.
@MainActor
protocol ConsoleBackend: AnyObject {
    var frameRate: Double { get }
    var frameCount: UInt64 { get }
    var rumble: Double { get }
    func setKeys(_ keys: UInt8)
    func runFrame()
    func show(on view: PixelScreenView)
    func battery() -> Data?
    func saveState() -> Data?
    func loadState(_ data: Data) -> Bool
    func reset()
    func startAudio(_ audio: AudioOutput)
    func destroy()
}

enum ConsoleBackends {
    /// Creates the right console for a game, or returns a message for the player.
    @MainActor
    static func make(for game: Game, rom: Data, battery: Data?) -> Result<ConsoleBackend, ConsoleError> {
        switch game.system {
        case .nes: return NESBackend.make(rom: rom, battery: battery)
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
            return .failure(ConsoleError(message: "Retro Duo is missing its start-up file. Reinstall the app."))
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
            return .failure(ConsoleError(message: "\(name) isn't a Game Boy game Retro Duo can run."))
        }
        if let battery, !battery.isEmpty {
            battery.withUnsafeBytes { RDCoreLoadBattery(created, $0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
        }
        return .success(GameBoyBackend(core: created))
    }

    var frameCount: UInt64 { core.map { RDCoreFrameCount($0) } ?? 0 }
    var rumble: Double { core.map { RDCoreRumble($0) } ?? 0 }

    func setKeys(_ keys: UInt8) {
        guard let core else { return }
        RDCoreSetKeys(core, keys)
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
            return .failure(ConsoleError(message: "This NES game uses hardware Retro Duo can't run yet, or the file is damaged."))
        }
        return .success(NESBackend(core: created))
    }

    var frameCount: UInt64 { core.map { NESCoreFrameCount($0) } ?? 0 }

    /// RD_KEY_* bits (as the shared controls send them) to NES_KEY_* bits.
    func setKeys(_ keys: UInt8) {
        guard let core else { return }
        var nes = 0
        if keys & UInt8(RD_KEY_RIGHT) != 0 { nes |= Int(NES_KEY_RIGHT) }
        if keys & UInt8(RD_KEY_LEFT) != 0 { nes |= Int(NES_KEY_LEFT) }
        if keys & UInt8(RD_KEY_UP) != 0 { nes |= Int(NES_KEY_UP) }
        if keys & UInt8(RD_KEY_DOWN) != 0 { nes |= Int(NES_KEY_DOWN) }
        if keys & UInt8(RD_KEY_A) != 0 { nes |= Int(NES_KEY_A) }
        if keys & UInt8(RD_KEY_B) != 0 { nes |= Int(NES_KEY_B) }
        if keys & UInt8(RD_KEY_SELECT) != 0 { nes |= Int(NES_KEY_SELECT) }
        if keys & UInt8(RD_KEY_START) != 0 { nes |= Int(NES_KEY_START) }
        NESCoreSetKeys(core, UInt8(truncatingIfNeeded: nes))
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
