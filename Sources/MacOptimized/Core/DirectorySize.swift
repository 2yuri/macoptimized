import Foundation

enum DirectorySize {
    static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]

    /// Allocated size on disk of a file or directory tree (best effort; unreadable items are skipped).
    static func allocated(of url: URL) -> Int64 {
        let set = Set(keys)
        guard let v = try? url.resourceValues(forKeys: set) else { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let r = try? f.resourceValues(forKeys: set), r.isDirectory != true {
                total += Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
