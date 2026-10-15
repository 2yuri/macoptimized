import Darwin
import Foundation

/// Deletes a file or folder tree permanently, quickly and with live progress.
///
/// Lists each folder with `getattrlistbulk` (so the size of every file is known as it goes),
/// unlinks files relative to the folder's descriptor, and works on subfolders in parallel.
/// Symlinks are removed, never followed.
final class TreeRemover: @unchecked Sendable {
    private let lock = NSLock()
    private var _removed: Int64 = 0
    private var _failures = 0
    private let slots = DispatchSemaphore(value: 8)

    /// Called with the running total of bytes removed, from any thread.
    var onProgress: (@Sendable (Int64) -> Void)?

    var removed: Int64 { lock.withLock { _removed } }
    var failures: Int { lock.withLock { _failures } }

    /// Returns true when `path` itself is gone.
    @discardableResult
    func remove(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        if st.st_mode & S_IFMT != S_IFDIR {
            let size = Int64(st.st_blocks) * 512
            guard unlink(path) == 0 else { fail(); return false }
            add(size)
            return true
        }
        removeDirectory(path, depth: 0)
        return access(path, F_OK) != 0
    }

    private func removeDirectory(_ path: String, depth: Int) {
        slots.wait()
        let entries = FastScanner.list(path)
        var subdirs: [String] = []
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd >= 0 {
            var batch: Int64 = 0
            for e in entries {
                if e.kind == .directory {
                    subdirs.append(FastScanner.join(path, e.name))
                } else if unlinkat(fd, e.name, 0) == 0 {
                    batch += e.allocated
                } else {
                    fail()
                }
            }
            close(fd)
            add(batch)
        }
        slots.signal()

        // Fan out near the top of the tree, where folders are big; go sequential below.
        if depth < 3, subdirs.count > 1 {
            DispatchQueue.concurrentPerform(iterations: subdirs.count) { i in
                removeDirectory(subdirs[i], depth: depth + 1)
            }
        } else {
            for sub in subdirs { removeDirectory(sub, depth: depth + 1) }
        }
        if rmdir(path) != 0 { fail() }
    }

    private func add(_ bytes: Int64) {
        guard bytes > 0 else { return }
        let total = lock.withLock { _removed += bytes; return _removed }
        onProgress?(total)
    }

    private func fail() { lock.withLock { _failures += 1 } }
}
