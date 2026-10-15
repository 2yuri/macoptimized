import Darwin
import Foundation

/// Frees RAM with a memory balloon in our own process.
/// We allocate 256 MiB chunks filled with incompressible data, which forces the kernel to evict
/// file cache and compress/swap idle pages. Then everything is released at once, leaving free RAM.
final class RAMCleaner: @unchecked Sendable {
    private static let chunkSize = 256 * 1024 * 1024
    static let timeout: TimeInterval = 30
    private let cancelled = ManagedAtomicFlag()

    func cancel() { cancelled.set() }

    /// Returns bytes of RAM freed (difference of `available` before/after).
    func run(progress: @escaping @Sendable (Double) -> Void) async -> Int64 {
        await Task.detached(priority: .userInitiated) { [cancelled] in
            guard let before = MemoryStats.current() else { return 0 }
            let seed = Self.makeSeed()
            let maxChunks = Int(before.total / UInt64(Self.chunkSize))
            let deadline = Date().addingTimeInterval(Self.timeout)
            var chunks: [UnsafeMutableRawPointer] = []

            while chunks.count < maxChunks, !cancelled.isSet, Date() < deadline {
                guard let stats = MemoryStats.current() else { break }
                // Stop once the system is under pressure or compression dominates resident memory.
                if stats.pressure == .warning || stats.pressure == .critical { break }
                if stats.compressed > 2 * (stats.wired + stats.active + stats.inactive) { break }
                // Keep a safety margin: never push free+cache below ~1 GiB.
                if stats.free + stats.cached < UInt64(Self.chunkSize) * 4 && stats.free < UInt64(Self.chunkSize) { break }

                let p = mmap(nil, Self.chunkSize, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)
                guard let p, p != MAP_FAILED else { break }
                Self.fill(p, with: seed)
                chunks.append(p)
                progress(Double(chunks.count) / Double(max(maxChunks, 1)))
            }

            for c in chunks { munmap(c, Self.chunkSize) }
            progress(1)
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let after = MemoryStats.current() else { return 0 }
            return Int64(after.available) - Int64(before.available)
        }.value
    }

    /// 10 random 1 KiB blocks, so pages can't be deduplicated or compressed.
    private static func makeSeed() -> [UInt8] {
        var seed = [UInt8](repeating: 0, count: 10 * 1024)
        arc4random_buf(&seed, seed.count)
        return seed
    }

    private static func fill(_ p: UnsafeMutableRawPointer, with seed: [UInt8]) {
        seed.withUnsafeBytes { s in
            var offset = 0
            while offset < chunkSize {
                let n = min(s.count, chunkSize - offset)
                (p + offset).copyMemory(from: s.baseAddress!, byteCount: n)
                // Perturb so no two pages are identical.
                (p + offset).storeBytes(of: UInt64(offset), as: UInt64.self)
                offset += n
            }
        }
    }
}

final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
