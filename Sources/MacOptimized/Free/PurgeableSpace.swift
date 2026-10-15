import Foundation

/// Purgeable space = what CacheDelete can reclaim (snapshots, caches, iCloud evictable files...).
/// It is measured with public URL resource keys as importantUsage - available.
enum PurgeableSpace {
    struct Volume {
        let total: Int64
        let available: Int64
        let availableImportant: Int64
        var purgeable: Int64 { max(0, availableImportant - available) }
    }

    static func volume(_ url: URL = URL(fileURLWithPath: "/")) -> Volume? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let avail = v.volumeAvailableCapacity,
              let important = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return Volume(total: Int64(total), available: Int64(avail), availableImportant: important)
    }

    // CSDiskSpaceStartRecovery(CFURL volume, UInt64 bytesNeeded, Int32 flags, CFUUID* outOp, dispatch_queue_t, block)
    private typealias StartRecovery = @convention(c) (
        CFURL, UInt64, Int32, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>?, DispatchQueue, AnyObject
    ) -> Void

    private static let startRecovery: StartRecovery? = {
        guard let h = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW),
              let sym = dlsym(h, "CSDiskSpaceStartRecovery") else { return nil }
        return unsafeBitCast(sym, to: StartRecovery.self)
    }()

    static var isSupported: Bool { startRecovery != nil }

    /// Asks CacheDelete to purge `available + purgeable` bytes (i.e. everything it can).
    /// Returns bytes reclaimed, measured by re-reading available capacity.
    static func freeUp(timeout: TimeInterval = 120) async -> Int64 {
        let root = URL(fileURLWithPath: "/")
        guard let before = volume(root), let start = startRecovery else { return 0 }
        let needed = UInt64(before.available + before.purgeable)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let once = OnceFlag()
            // Block arguments are opaque to us; we only use the callback as a completion signal.
            let completion: @convention(block) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Void = { _, _, _ in
                if once.claim() { cont.resume() }
            }
            var op: Unmanaged<CFTypeRef>?
            start(root as CFURL, needed, 0, &op, DispatchQueue.global(), completion as AnyObject)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { cont.resume() }
            }
        }
        guard let after = volume(root) else { return 0 }
        return max(0, after.available - before.available)
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
