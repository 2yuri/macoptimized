import Foundation
import Testing
@testable import MacOptimized

struct CoreTests {
    @Test func circlePackingHasNoOverlaps() {
        let radii: [CGFloat] = [50, 40, 30, 30, 20, 15, 10, 10, 8, 5, 5, 3]
        let c = CirclePacking.pack(radii: radii)
        #expect(c.count == radii.count)
        for i in 0..<c.count {
            for j in (i + 1)..<c.count {
                #expect(hypot(c[i].x - c[j].x, c[i].y - c[j].y) >= c[i].r + c[j].r - 0.01)
            }
        }
    }

    @Test func diskScannerSumsSizesSkipsSymlinksAndCountsHardlinksOnce() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = root.appendingPathComponent("a/b")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        let big = sub.appendingPathComponent("big.bin")
        try Data(repeating: 1, count: 2_000_000).write(to: big)
        try Data(repeating: 1, count: 10_000).write(to: root.appendingPathComponent("small.bin"))
        try fm.linkItem(at: big, to: root.appendingPathComponent("big-hardlink.bin"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        defer { try? fm.removeItem(at: root) }

        let node = await DiskScanner().scan(root)
        // The symlink is skipped, small.bin is summed as a loose file, and the 2 MB file is counted once,
        // under whichever of its two hard-linked names was listed first.
        func names(_ n: FileNode) -> [String] { n.children.flatMap { [$0.name] + names($0) } }
        #expect(!names(node).contains("loop"))
        #expect(names(node).filter { $0.hasPrefix("big") }.count == 1)
        #expect(node.looseCount == 1)
        #expect(node.size == node.children.reduce(node.looseSize) { $0 + $1.size })
        #expect(node.size >= 2_000_000 && node.size < 3_000_000)
        #expect(DirectorySize.allocated(of: root) == node.size)

        let before = node.size
        let a = try #require(node.children.first { $0.name == "a" })
        a.detach()
        #expect(node.size == before - a.size)
    }

    @Test func treeRemoverDeletesTreeButNeverFollowsSymlinks() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let victim = base.appendingPathComponent("cache")
        let outside = base.appendingPathComponent("keep/important.txt")
        try fm.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: outside)
        for i in 0..<5 {
            let dir = victim.appendingPathComponent("d\(i)/nested")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for j in 0..<20 { try Data(repeating: 7, count: 50_000).write(to: dir.appendingPathComponent("f\(j).bin")) }
        }
        try fm.createSymbolicLink(at: victim.appendingPathComponent("link-out"), withDestinationURL: outside.deletingLastPathComponent())
        defer { try? fm.removeItem(at: base) }

        let expected = DirectorySize.allocated(of: victim)
        let remover = TreeRemover()
        #expect(remover.remove(victim.path))
        #expect(!fm.fileExists(atPath: victim.path))
        #expect(fm.fileExists(atPath: outside.path), "symlink target must survive")
        #expect(remover.failures == 0)
        #expect(remover.removed == expected)
    }

    @Test func bytesFormatting() {
        #expect(Bytes.format(Int64(37_600_000_000)) == "37.6 GB")
        #expect(Bytes.format(Int64(22_000_000_000)) == "22 GB")
        #expect(Bytes.format(Int64(412_000_000)) == "412 MB")
        #expect(Bytes.format(Int64(214_600_000_000)) == "215 GB")
        #expect(Bytes.format(UInt64(48) << 30, binary: true) == "48 GB")
    }

    @Test func safetyGuard() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(CareModel.isSafe(home.appendingPathComponent("Library/Caches/foo")))
        #expect(!CareModel.isSafe(home))
        #expect(!CareModel.isSafe(URL(fileURLWithPath: "/Library/Caches/foo")))
        #expect(!CareModel.isSafe(URL(fileURLWithPath: "/System/foo")))
        #expect(CareModel.isSafe(URL(fileURLWithPath: "/Volumes/X/.Trashes/501/file")))
    }

    @Test func metrics() throws {
        let m = try #require(MemoryStats.current())
        #expect(m.total == ProcessInfo.processInfo.physicalMemory)
        #expect(m.used > 0)
        #expect(m.used <= m.total)
        #expect(m.pressure != .unknown)

        let v = try #require(PurgeableSpace.volume())
        #expect(v.total > v.available)
        #expect(v.purgeable >= 0)
        #expect(PurgeableSpace.isSupported)
    }

    @Test func junkScanIsReadOnlyAndSorted() {
        let groups = CareModel.scanJunk()
        for g in groups {
            #expect(g.items.map(\.size) == g.items.map(\.size).sorted(by: >))
            #expect(g.selected.isSubset(of: Set(g.items.map(\.url))))
            if !g.rule.autoSelect { #expect(g.selected.isEmpty) }
            for item in g.items where g.rule.id == "userCache" {
                #expect(!JunkRules.protectedCaches.contains(item.url.lastPathComponent))
            }
        }
        for g in groups { print("\(g.rule.title): \(Bytes.format(g.size)) (\(g.items.count) items, \(Bytes.format(g.selectedSize)) selected)") }
    }
}
