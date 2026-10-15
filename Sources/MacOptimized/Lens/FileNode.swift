import Foundation

/// A folder or file in a lens scan. Small files are not kept as nodes; each folder sums them
/// in `looseSize` / `looseCount`, which keeps a whole-disk scan to a manageable size in memory.
final class FileNode: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    /// Total on-disk size, including children and loose files.
    var size: Int64
    /// Number of files below this node (1 for a file).
    var fileCount: Int
    var looseSize: Int64 = 0
    var looseCount = 0
    var children: [FileNode] = []
    weak var parent: FileNode?
    private let rootPath: String?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// The scan root.
    init(rootPath: String) {
        self.rootPath = rootPath
        name = rootPath == "/" ? "/" : (rootPath as NSString).lastPathComponent
        isDirectory = true
        size = 0
        fileCount = 0
    }

    init(name: String, isDirectory: Bool, size: Int64 = 0, parent: FileNode) {
        rootPath = nil
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.fileCount = isDirectory ? 0 : 1
        self.parent = parent
    }

    var path: String {
        if let rootPath { return rootPath }
        return FastScanner.join(parent?.path ?? "", name)
    }

    var url: URL { URL(fileURLWithPath: path) }

    /// A folder with something inside it to look at.
    var canOpen: Bool { isDirectory && (!children.isEmpty || looseCount > 0) }

    static func == (a: FileNode, b: FileNode) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    var pathFromRoot: [FileNode] {
        var chain: [FileNode] = [self]
        while let p = chain.last?.parent { chain.append(p) }
        return chain.reversed()
    }

    /// Removes this node from its parent and propagates the size change upward.
    func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var p: FileNode? = parent
        while let n = p { n.size -= size; n.fileCount -= fileCount; p = n.parent }
        self.parent = nil
    }
}
