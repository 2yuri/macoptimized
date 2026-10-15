import Darwin
import Foundation

/// One directory entry as returned by `getattrlistbulk`.
struct DirEntry {
    enum Kind { case file, directory, symlink, other }

    let name: String
    let kind: Kind
    let device: Int32
    /// On-disk size (0 for directories).
    let allocated: Int64
    let fileID: UInt64
    let linkCount: UInt32
    /// Only a placeholder is on disk; the content lives in iCloud or another file provider.
    let isDataless: Bool
}

/// Fast file-tree walking for care and lens.
///
/// - Reads a whole directory per syscall with `getattrlistbulk` instead of one `stat` per file.
/// - Walks directories on several threads at once.
/// - Never follows symlinks, never enters dataless (cloud-only) folders, which would make macOS download them.
/// - Counts hard-linked files once, so pnpm stores, Homebrew and simulators aren't inflated.
final class FastScanner: @unchecked Sendable {
    struct Options {
        var excluded: Set<String> = []
        /// Only enter directories on these devices; nil means any device.
        var devices: Set<Int32>?
        /// Folders listed at once. The work is almost all kernel time in APFS; measured on a 4M-file home folder,
        /// 8 → 12 saves about 20%, and going past 12–16 only burns CPU.
        var width = min(12, max(4, ProcessInfo.processInfo.activeProcessorCount))
    }

    let options: Options

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "macoptimized.scan", qos: .userInitiated, attributes: .concurrent)
    private let group = DispatchGroup()
    private let slots: DispatchSemaphore
    private var seenLinks = Set<UInt64>()
    private var cancelled = false
    private var _bytes: Int64 = 0
    private var _currentPath = ""

    init(options: Options = Options()) {
        self.options = options
        slots = DispatchSemaphore(value: options.width)
    }

    var scannedBytes: Int64 { lock.withLock { _bytes } }
    var currentPath: String { lock.withLock { _currentPath } }
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Walks `root`; `visit` is called once per directory, possibly from several threads at once.
    /// It receives the directory path and its counted entries, and returns the subdirectories to enter.
    func walk(_ root: String, visit: @escaping @Sendable (_ path: String, _ entries: [DirEntry]) -> [String]) {
        walk(root, context: (), visit: { path, _, entries in visit(path, entries).map { ($0, ()) } })
    }

    /// Same walk, carrying a value from each directory to its subdirectories (lens passes the tree node,
    /// so building the tree needs no shared lookup table and no lock).
    func walk<Context>(_ root: String, context: Context,
                       visit: @escaping @Sendable (_ path: String, _ context: Context, _ entries: [DirEntry]) -> [(String, Context)]) {
        submit(root, Unchecked(context), visit)
        group.wait()
    }

    private func submit<Context>(_ path: String, _ context: Unchecked<Context>,
                                 _ visit: @escaping @Sendable (String, Context, [DirEntry]) -> [(String, Context)]) {
        group.enter()
        queue.async { [self] in
            defer { group.leave() }
            if isCancelled { return }
            slots.wait()
            let raw = Self.list(path)
            slots.signal()

            var counted: [DirEntry] = []
            counted.reserveCapacity(raw.count)
            var bytes: Int64 = 0
            for e in raw {
                if e.isDataless || e.kind == .symlink { continue }
                if e.kind == .file, e.linkCount > 1, !lock.withLock({ seenLinks.insert(e.fileID).inserted }) { continue }
                if e.kind == .directory {
                    let child = Self.join(path, e.name)
                    if options.excluded.contains(child) { continue }
                    if let devices = options.devices, !devices.contains(e.device) { continue }
                }
                bytes += e.allocated
                counted.append(e)
            }
            lock.withLock {
                _bytes += bytes
                _currentPath = path
            }

            for (sub, ctx) in visit(path, context.value, counted) { submit(sub, Unchecked(ctx), visit) }
        }
    }

    static func join(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }

    // MARK: - getattrlistbulk

    static func list(_ path: String) -> [DirEntry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(bitPattern: Int32(bitPattern: UInt32(ATTR_CMN_RETURNED_ATTRS)))
            | attrgroup_t(ATTR_CMN_NAME | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE | ATTR_CMN_FLAGS | ATTR_CMN_FILEID)
        request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE)

        let buffer = BufferPool.shared.take()
        defer { BufferPool.shared.give(buffer) }
        let bufferSize = BufferPool.size

        var entries: [DirEntry] = []
        while true {
            // FSOPT_PACK_INVAL_ATTRS keeps every record in the same layout, with zeros where a value doesn't apply.
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if count <= 0 { break }
            var record = buffer
            for _ in 0..<count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                // Layout, in attribute bit order: length, returned set, name ref, dev, type, flags, file id, link count, alloc size.
                var p = record + 4 + MemoryLayout<attribute_set_t>.size
                let nameRef = p.loadUnaligned(as: attrreference_t.self)
                let name = String(cString: (p + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                p += MemoryLayout<attrreference_t>.size
                let device = p.loadUnaligned(as: Int32.self); p += 4
                let type = p.loadUnaligned(as: UInt32.self); p += 4
                let flags = p.loadUnaligned(as: UInt32.self); p += 4
                let fileID = p.loadUnaligned(as: UInt64.self); p += 8
                let links = p.loadUnaligned(as: UInt32.self); p += 4
                let allocated = p.loadUnaligned(as: Int64.self)

                let kind: DirEntry.Kind = switch type {
                case VREG.rawValue: .file
                case VDIR.rawValue: .directory
                case VLNK.rawValue: .symlink
                default: .other
                }
                entries.append(DirEntry(name: name, kind: kind, device: device,
                                        allocated: kind == .directory ? 0 : allocated,
                                        fileID: fileID, linkCount: links,
                                        isDataless: flags & UInt32(SF_DATALESS) != 0))
                record += length
            }
        }
        return entries
    }
}

/// Lets a value cross into the scan queue; the walker hands each one to exactly one task.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Reuses the large listing buffers. Allocating 256 KB per folder goes through mmap/munmap,
/// two extra syscalls for every folder on the disk.
private final class BufferPool: @unchecked Sendable {
    static let shared = BufferPool()
    static let size = 256 * 1024

    private let lock = NSLock()
    private var free: [UnsafeMutableRawPointer] = []

    func take() -> UnsafeMutableRawPointer {
        lock.withLock { free.popLast() } ?? UnsafeMutableRawPointer.allocate(byteCount: Self.size, alignment: 8)
    }

    func give(_ buffer: UnsafeMutableRawPointer) {
        lock.withLock { free.append(buffer) }
    }
}
