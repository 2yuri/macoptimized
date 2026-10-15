import Foundation

final class FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var size: Int64
    /// Number of files below this node (1 for a file).
    var fileCount: Int
    var children: [FileNode] = []
    weak var parent: FileNode?

    var id: URL { url }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }

    init(url: URL, isDirectory: Bool, size: Int64 = 0) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.fileCount = isDirectory ? 0 : 1
    }

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
