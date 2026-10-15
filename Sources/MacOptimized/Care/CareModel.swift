import AppKit
import CryptoKit
import Foundation

struct CareItem: Identifiable, Hashable {
    let url: URL
    let size: Int64
    /// Why an item starts unselected ("app running", "tool download").
    var note: String?
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct JunkGroup: Identifiable {
    let rule: JunkRule
    var items: [CareItem]
    var selected: Set<URL>
    var id: String { rule.id }
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size } }
    var isOn: Bool { !selected.isEmpty }
}

struct MaintenanceTask: Identifiable {
    enum Kind { case flushDNS, purgeable }
    let kind: Kind
    let title: String
    let value: String
    var selected: Bool
    var id: String { title }
}

/// Copies of one file in ~/Downloads, oldest first. The oldest is always kept.
struct DuplicateGroup: Identifiable {
    let copies: [CareItem]
    var id: URL { copies[0].url }
    var extras: [CareItem] { Array(copies.dropFirst()) }
    var wasted: Int64 { extras.reduce(0) { $0 + $1.size } }
}

struct ReportLine: Identifiable {
    let label: String
    let value: String
    var ok = true
    var note: String?
    var id: String { label }
}

/// care: modules are scanned one after another, then "run" executes everything that is
/// selected. Review-only items (developer caches, backups, duplicates) start unselected.
@MainActor
final class CareModel: ObservableObject {
    enum Phase { case idle, scanning, results, running, done }
    enum Module: Int, CaseIterable {
        case cleanup, maintenance, duplicates
        var title: String { ["cleanup", "maintenance", "duplicates"][rawValue] }
    }

    @Published var phase: Phase = .idle
    @Published var activeModule: Module = .cleanup
    @Published var progress: Double = 0
    @Published var currentPath = ""

    @Published var junk: [JunkGroup] = []
    @Published var tasks: [MaintenanceTask] = []
    @Published var duplicates: [DuplicateGroup] = []
    @Published var selectedDuplicates: Set<URL> = []

    @Published var removedSoFar: Int64 = 0
    @Published var report: [ReportLine] = []
    @Published var skipped: [ReportLine] = []
    @Published var freedTotal: Int64 = 0
    @Published var summary = ""

    private var scanTask: Task<Void, Never>?
    private var runStarted = Date()

    // MARK: Totals

    var junkSelectedSize: Int64 { junk.reduce(0) { $0 + $1.selectedSize } }
    var junkTotalSize: Int64 { junk.reduce(0) { $0 + $1.size } }
    var selectedTasks: [MaintenanceTask] { tasks.filter(\.selected) }
    var selectedDuplicateItems: [CareItem] { duplicates.flatMap(\.extras).filter { selectedDuplicates.contains($0.url) } }
    var duplicatesSelectedSize: Int64 { selectedDuplicateItems.reduce(0) { $0 + $1.size } }
    var duplicatesWasted: Int64 { duplicates.reduce(0) { $0 + $1.wasted } }
    var foundTotal: Int64 { junkTotalSize + duplicatesWasted }

    // MARK: Last scan

    var lastScan: (date: Date, size: Int64)? {
        let d = UserDefaults.standard.double(forKey: "care.lastScanDate")
        guard d > 0 else { return nil }
        return (Date(timeIntervalSince1970: d), Int64(UserDefaults.standard.double(forKey: "care.lastScanSize")))
    }

    private func rememberScan() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "care.lastScanDate")
        UserDefaults.standard.set(Double(junkSelectedSize), forKey: "care.lastScanSize")
    }

    // MARK: Selection

    func toggleGroup(_ id: String) {
        guard let i = junk.firstIndex(where: { $0.id == id }) else { return }
        if junk[i].isOn {
            junk[i].selected = []
        } else {
            let safe = junk[i].items.filter { $0.note == nil }
            junk[i].selected = Set((safe.isEmpty ? junk[i].items : safe).map(\.url))
        }
    }

    func toggleItem(_ url: URL, in id: String) {
        guard let i = junk.firstIndex(where: { $0.id == id }) else { return }
        if junk[i].selected.contains(url) { junk[i].selected.remove(url) } else { junk[i].selected.insert(url) }
    }

    func toggleTask(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].selected.toggle()
    }

    func toggleDuplicates(_ group: DuplicateGroup) {
        let urls = Set(group.extras.map(\.url))
        if urls.isSubset(of: selectedDuplicates) { selectedDuplicates.subtract(urls) } else { selectedDuplicates.formUnion(urls) }
    }

    // MARK: Scan

    func scan() {
        phase = .scanning
        progress = 0
        currentPath = ""
        scanTask = Task {
            activeModule = .cleanup
            let found = await Task.detached { [weak self] in
                Self.scanJunk { fraction, path in
                    Task { @MainActor in
                        self?.progress = fraction * 0.8
                        self?.currentPath = path
                    }
                }
            }.value
            if Task.isCancelled { return reset() }
            junk = found

            activeModule = .maintenance
            progress = 0.82
            tasks = Self.maintenanceTasks()

            activeModule = .duplicates
            currentPath = "~/Downloads"
            let dups = await Task.detached { Self.findDuplicateDownloads() }.value
            if Task.isCancelled { return reset() }
            duplicates = dups
            selectedDuplicates = []
            progress = 1

            rememberScan()
            phase = .results
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        reset()
    }

    func reset() { phase = .idle }

    // MARK: Run

    func run() {
        phase = .running
        report = []
        skipped = []
        removedSoFar = 0
        runStarted = Date()
        let total = max(1, junkSelectedSize + duplicatesSelectedSize)
        progress = 0
        activeModule = .cleanup

        Task {
            let groups = junk
            // The remover reports very often; the UI samples the latest value a few times a second.
            let latest = LatestProgress()
            let ticker = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    let (bytes, path) = latest.value
                    self?.removedSoFar = bytes
                    self?.progress = min(1, Double(bytes) / Double(total))
                    self?.currentPath = path
                }
            }
            let result = await Task.detached { Self.remove(groups) { latest.set($0, $1) } }.value
            ticker.invalidate()
            removedSoFar = result.freed
            for g in groups where g.isOn {
                report.append(ReportLine(label: g.rule.title, value: Bytes.format(result.perGroup[g.id] ?? 0)))
            }
            if result.skippedCount > 0 {
                skipped.append(ReportLine(label: "\(result.skippedCount) items partly in use or locked", value: Bytes.format(result.skippedSize), ok: false, note: "locked"))
            }

            activeModule = .maintenance
            var purged: Int64 = 0
            for t in selectedTasks {
                currentPath = t.title
                switch t.kind {
                case .flushDNS:
                    let r = await Task.detached {
                        Shell.runAsAdmin("/bin/sh", ["-c", "dscacheutil -flushcache; killall -HUP mDNSResponder"])
                    }.value
                    if r.status == 0 { report.append(ReportLine(label: t.title, value: "done")) }
                    else { skipped.append(ReportLine(label: t.title, value: "cancelled", ok: false)) }
                case .purgeable:
                    purged = await PurgeableSpace.freeUp()
                    report.append(ReportLine(label: t.title, value: Bytes.format(purged)))
                }
            }

            activeModule = .duplicates
            var moved: Int64 = 0
            for item in selectedDuplicateItems {
                currentPath = item.url.path
                if (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil { moved += item.size }
            }
            if moved > 0 { report.append(ReportLine(label: "duplicates to Trash", value: Bytes.format(moved))) }

            freedTotal = result.freed + purged
            let seconds = Int(Date().timeIntervalSince(runStarted))
            let time = seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
            summary = "\(Bytes.format(result.freed)) cleaned · \(Bytes.format(purged)) purged · in \(time)"
            progress = 1
            phase = .done
        }
    }

    // MARK: - Scanning

    nonisolated static func scanJunk(progress: (Double, String) -> Void = { _, _ in }) -> [JunkGroup] {
        let fm = FileManager.default
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let rules = JunkRules.all
        return rules.enumerated().compactMap { index, rule in
            progress(Double(index) / Double(rules.count), rule.detail)
            var urls: [URL] = []
            switch rule.mode {
            case .contentsOf(let roots):
                for root in roots {
                    let dir = URL(fileURLWithPath: JunkRules.expand(root))
                    let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                    urls += entries.filter { !rule.skipNames.contains($0.lastPathComponent) && $0.lastPathComponent != ".DS_Store" }
                }
            case .paths(let paths):
                urls = paths.map { URL(fileURLWithPath: JunkRules.expand($0)) }.filter { fm.fileExists(atPath: $0.path) }
            case .custom(let finder):
                urls = finder()
            }
            let items: [CareItem] = urls.compactMap { url in
                progress(Double(index) / Double(rules.count), url.path.replacingOccurrences(of: JunkRules.home, with: "~"))
                let size = DirectorySize.allocated(of: url)
                guard size > 0 else { return nil }
                // Caches of running apps and caches that are downloaded tools start unselected.
                let note: String? = running.contains(url.lastPathComponent) ? "app running"
                    : JunkRules.reviewCaches.contains(url.lastPathComponent) ? "tool download" : nil
                return CareItem(url: url, size: size, note: note)
            }
            .sorted { $0.size > $1.size }
            guard !items.isEmpty else { return nil }
            let selected = rule.autoSelect ? Set(items.filter { $0.note == nil }.map(\.url)) : []
            return JunkGroup(rule: rule, items: items, selected: selected)
        }
    }

    nonisolated static func maintenanceTasks() -> [MaintenanceTask] {
        var list = [MaintenanceTask(kind: .flushDNS, title: "flush dns", value: "password", selected: true)]
        if let v = PurgeableSpace.volume(), v.purgeable > 0, PurgeableSpace.isSupported {
            list.append(MaintenanceTask(kind: .purgeable, title: "purgeable space", value: Bytes.format(v.purgeable), selected: true))
        }
        return list
    }

    /// Duplicate files in ~/Downloads: same size, then same SHA-256.
    nonisolated static func findDuplicateDownloads() -> [DuplicateGroup] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey]
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var bySize: [Int: [(URL, Date)]] = [:]
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let size = v.fileSize, size > 1024 else { continue }
            bySize[size, default: []].append((url, v.creationDate ?? .distantPast))
        }
        var groups: [DuplicateGroup] = []
        for (size, files) in bySize where files.count > 1 {
            var byHash: [String: [(URL, Date)]] = [:]
            for f in files { if let h = sha256(f.0) { byHash[h, default: []].append(f) } }
            for (_, same) in byHash where same.count > 1 {
                groups.append(DuplicateGroup(copies: same.sorted { $0.1 < $1.1 }.map { CareItem(url: $0.0, size: Int64(size)) }))
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    nonisolated private static func sha256(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Removal

    struct RemovalResult {
        var freed: Int64 = 0
        var perGroup: [String: Int64] = [:]
        var skippedCount = 0
        var skippedSize: Int64 = 0
    }

    /// Junk is deleted permanently; rules flagged `useTrash` go to the Trash instead.
    nonisolated static func remove(_ groups: [JunkGroup], progress: @escaping @Sendable (Int64, String) -> Void = { _, _ in }) -> RemovalResult {
        var result = RemovalResult()
        for g in groups {
            for item in g.items where g.selected.contains(item.url) {
                guard isSafe(item.url) else { continue }
                let label = item.url.path.replacingOccurrences(of: JunkRules.home, with: "~")
                let base = result.freed
                progress(base, label)

                if g.rule.useTrash {
                    if (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil {
                        result.freed += item.size
                        result.perGroup[g.id, default: 0] += item.size
                    } else {
                        result.skippedCount += 1
                        result.skippedSize += item.size
                    }
                    continue
                }

                // Permanent delete with live progress; files that are locked or in use stay behind.
                let remover = TreeRemover()
                remover.onProgress = { bytes in progress(base + bytes, label) }
                remover.remove(item.url.path)
                result.freed += remover.removed
                result.perGroup[g.id, default: 0] += remover.removed
                if remover.failures > 0 {
                    result.skippedCount += 1
                    result.skippedSize += max(0, item.size - remover.removed)
                }
            }
        }
        progress(result.freed, "")
        return result
    }

    /// Guard rails: only inside the home folder or a trash, never through a symlinked parent.
    nonisolated static func isSafe(_ url: URL) -> Bool {
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        let inHome = resolved.hasPrefix(home + "/")
        let inVolumeTrash = resolved.hasPrefix("/Volumes/") && resolved.contains("/.Trashes/")
        return (inHome || inVolumeTrash) && url.path != home
    }
}

/// Latest (bytes, path) pair written by a worker thread and read by the UI.
private final class LatestProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var path = ""

    func set(_ bytes: Int64, _ path: String) { lock.withLock { self.bytes = bytes; self.path = path } }
    var value: (Int64, String) { lock.withLock { (bytes, path) } }
}
