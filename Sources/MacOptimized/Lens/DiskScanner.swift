import Darwin
import Foundation

/// lens scanner: one directory listing at a time via
/// contentsOfDirectory (hidden files included), allocated size, no symlink following,
/// stays on the starting volume, skips a few virtual/duplicate locations.
final class DiskScanner: @unchecked Sendable {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]
    private static let excluded: Set<String> = [
        "/private/var/vm", "/home", "/net", "/Volumes", "/System/Volumes/Data", "/dev",
    ]
    private static let parallelDepth = 3

    private let lock = NSLock()
    private var _scannedBytes: Int64 = 0
    private var _currentPath = ""
    private var _cancelled = false
    private var allowedDevices: Set<dev_t> = []

    var scannedBytes: Int64 { lock.withLock { _scannedBytes } }
    var currentPath: String { lock.withLock { _currentPath } }
    func cancel() { lock.withLock { _cancelled = true } }
    private var isCancelled: Bool { lock.withLock { _cancelled } }

    func scan(_ root: URL) async -> FileNode {
        allowedDevices = [Self.device(of: root.path)].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
        // "/" is the sealed system volume; user data lives on the Data volume reached via firmlinks.
        if root.path == "/", let d = Self.device(of: "/System/Volumes/Data") { allowedDevices.insert(d) }

        let node = FileNode(url: root, isDirectory: true)
        await fill(node, depth: 0)
        return node
    }

    private func fill(_ dir: FileNode, depth: Int) async {
        if isCancelled { return }
        lock.withLock { _currentPath = dir.url.path }
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir.url, includingPropertiesForKeys: Self.keys, options: [])) ?? []
        var subdirs: [FileNode] = []

        for url in entries {
            if Self.excluded.contains(url.path) { continue }
            guard let v = try? url.resourceValues(forKeys: Set(Self.keys)) else { continue }
            if v.isSymbolicLink == true {
                continue
            }
            if v.isDirectory == true {
                guard let d = Self.device(of: url.path), allowedDevices.contains(d) else { continue }
                let child = FileNode(url: url, isDirectory: true)
                child.parent = dir
                dir.children.append(child)
                subdirs.append(child)
            } else {
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
                let child = FileNode(url: url, isDirectory: false, size: size)
                child.parent = dir
                dir.children.append(child)
                dir.size += size
                dir.fileCount += 1
                lock.withLock { _scannedBytes += size }
            }
        }

        if depth < Self.parallelDepth {
            await withTaskGroup(of: Void.self) { group in
                for sub in subdirs { group.addTask { await self.fill(sub, depth: depth + 1) } }
            }
        } else {
            for sub in subdirs { await fill(sub, depth: depth + 1) }
        }
        for sub in subdirs { dir.size += sub.size; dir.fileCount += sub.fileCount }
        dir.children.sort { $0.size > $1.size }
    }

    private static func device(of path: String) -> dev_t? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_dev : nil
    }

    static func usedSpace(of url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let t = v.volumeTotalCapacity, let a = v.volumeAvailableCapacity else { return 0 }
        return Int64(t - a)
    }
}
