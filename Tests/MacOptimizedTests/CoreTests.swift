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

    @Test func diskScannerSumsSizesAndSkipsSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: sub.appendingPathComponent("big.bin"))
        try Data(count: 10_000).write(to: root.appendingPathComponent("small.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let node = await DiskScanner().scan(root)
        #expect(node.children.count == 2)
        #expect(node.children.first?.name == "a")
        #expect(node.size >= 110_000)
        #expect(node.size == node.children.reduce(0) { $0 + $1.size })

        let a = node.children[0]
        a.detach()
        #expect(node.children.count == 1)
        #expect(node.size == node.children[0].size)
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
