import Darwin
import Foundation

/// lens scanner: builds a `FileNode` tree with `FastScanner`, staying on the starting volume
/// and skipping virtual or duplicate locations.
final class DiskScanner: @unchecked Sendable {
    private static let excluded: Set<String> = [
        "/private/var/vm", "/home", "/net", "/Volumes", "/System/Volumes", "/dev",
    ]
    /// Files smaller than this are summed per folder instead of kept as nodes.
    static let smallFile: Int64 = 512 * 1024

    private let lock = NSLock()
    private var scanner: FastScanner?

    var scannedBytes: Int64 { lock.withLock { scanner?.scannedBytes ?? 0 } }
    var currentPath: String { lock.withLock { scanner?.currentPath ?? "" } }
    func cancel() { lock.withLock { scanner?.cancel() } }

    func scan(_ root: URL) async -> FileNode {
        await Task.detached(priority: .userInitiated) { self.build(root.path) }.value
    }

    private func build(_ rootPath: String) -> FileNode {
        var devices: Set<Int32> = []
        if let d = Self.device(rootPath) { devices.insert(d) }
        // "/" is the sealed system volume; user data lives on the Data volume, reached through firmlinks.
        if rootPath == "/", let d = Self.device("/System/Volumes/Data") { devices.insert(d) }

        let scanner = FastScanner(options: .init(excluded: Self.excluded, devices: devices))
        lock.withLock { self.scanner = scanner }

        let root = FileNode(rootPath: rootPath)
        // Each folder's node travels with its listing task, and only that task touches it.
        scanner.walk(rootPath, context: root) { path, dir, entries in
            var subdirs: [(String, FileNode)] = []
            for e in entries {
                switch e.kind {
                case .directory:
                    let child = FileNode(name: e.name, isDirectory: true, parent: dir)
                    dir.children.append(child)
                    subdirs.append((FastScanner.join(path, e.name), child))
                case .file where e.allocated >= Self.smallFile:
                    dir.children.append(FileNode(name: e.name, isDirectory: false, size: e.allocated, parent: dir))
                    dir.size += e.allocated
                    dir.fileCount += 1
                default:
                    dir.looseSize += e.allocated
                    dir.looseCount += 1
                    dir.size += e.allocated
                    dir.fileCount += 1
                }
            }
            return subdirs
        }
        Self.finish(root)
        return root
    }

    /// Turns a folder's summed small files into real nodes, by listing just that one folder.
    /// Called when a folder is shown, so nothing in view is hidden behind an aggregate.
    static func expandSmallFiles(of node: FileNode) {
        guard node.looseCount > 0 else { return }
        for e in FastScanner.list(node.path) where e.kind == .file && !e.isDataless && e.allocated < smallFile {
            node.children.append(FileNode(name: e.name, isDirectory: false, size: e.allocated, parent: node))
        }
        node.looseSize = 0
        node.looseCount = 0
        node.children.sort { $0.size > $1.size }
    }

    /// Adds folder totals bottom-up and sorts children by size.
    private static func finish(_ node: FileNode) {
        for child in node.children where child.isDirectory {
            finish(child)
            node.size += child.size
            node.fileCount += child.fileCount
        }
        node.children.sort { $0.size > $1.size }
    }

    private static func device(_ path: String) -> Int32? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_dev : nil
    }
}
