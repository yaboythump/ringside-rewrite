import Foundation

/// Rewind and fast-forward settings, shared by every console.
enum TimeControls {
    static let rewindKey = "avydrix.rewind.enabled"
    static let speedKey = "avydrix.fastForward.speed"
    static let speeds = [2, 3, 4]

    static var rewindEnabled: Bool { UserDefaults.standard.object(forKey: rewindKey) as? Bool ?? true }

    static var fastForwardSpeed: Int {
        let value = UserDefaults.standard.integer(forKey: speedKey)
        return speeds.contains(value) ? value : 2
    }
}

/// The last few seconds of play as compressed save states, newest last. Thread-safe: the DS
/// compresses on a background queue.
final class RewindBuffer {
    let maxEntries: Int
    let maxBytes: Int
    private let lock = NSLock()
    private var entries: [Data] = []
    private var bytes = 0

    init(maxEntries: Int, maxBytes: Int = 48 << 20) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = maxBytes
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    var isEmpty: Bool { count == 0 }
    var storedBytes: Int { lock.lock(); defer { lock.unlock() }; return bytes }

    /// Adds the newest state, dropping the oldest past the entry or memory limit.
    func push(_ state: Data) {
        guard !state.isEmpty, let packed = try? (state as NSData).compressed(using: .lz4) as Data else { return }
        lock.lock()
        entries.append(packed)
        bytes += packed.count
        while entries.count > 1 && (entries.count > maxEntries || bytes > maxBytes) {
            bytes -= entries.removeFirst().count
        }
        lock.unlock()
    }

    /// Takes the newest state off (stepping back in time).
    func pop() -> Data? {
        lock.lock()
        let packed = entries.popLast()
        if let packed { bytes -= packed.count }
        lock.unlock()
        return packed.flatMap { try? ($0 as NSData).decompressed(using: .lz4) as Data }
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        bytes = 0
        lock.unlock()
    }
}
