import AppKit
import Foundation

struct LensLocation: Identifiable {
    let name: String
    let detail: String
    let url: URL?
    var id: String { name + (url?.path ?? "") }
}

@MainActor
final class LensModel: ObservableObject {
    enum Phase { case idle, scanning, done }

    @Published var phase: Phase = .idle
    @Published var root: FileNode?
    @Published var current: FileNode?
    @Published var selection: Set<FileNode> = []
    @Published var scannedBytes: Int64 = 0
    @Published var expectedBytes: Int64 = 0
    @Published var currentPath = ""
    @Published var scanTarget = ""
    @Published var toast: Toast?

    private var scanner: DiskScanner?
    private var timer: Timer?

    static let maxBubbles = 30

    /// Fraction of the volume scanned; nil when scanning a plain folder (its size isn't known up front).
    var progress: Double? {
        expectedBytes > 0 ? min(0.99, Double(scannedBytes) / Double(expectedBytes)) : nil
    }

    var locations: [LensLocation] {
        let root = URL(fileURLWithPath: "/")
        let home = FileManager.default.homeDirectoryForCurrentUser
        var list = [
            LensLocation(name: Volumes.rootName, detail: "\(Bytes.format(Volumes.used(root))) used", url: root),
            LensLocation(name: "Home", detail: "~/\(home.lastPathComponent)", url: home),
        ]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        for v in vols where v.path.hasPrefix("/Volumes/") {
            list.append(LensLocation(name: v.lastPathComponent, detail: "external · \(Bytes.format(Volumes.used(v))) used", url: v))
        }
        list.append(LensLocation(name: "Choose folder…", detail: "⌘O", url: nil))
        return list
    }

    func open(_ location: LensLocation) {
        if let url = location.url { scan(url, name: location.name) } else { chooseFolder() }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { scan(url, name: url.lastPathComponent) }
    }

    func scan(_ url: URL, name: String) {
        let scanner = DiskScanner()
        self.scanner = scanner
        phase = .scanning
        selection = []
        scannedBytes = 0
        scanTarget = name
        let isVolume = url.path == "/" || (url.path.hasPrefix("/Volumes/") && url.pathComponents.count == 3)
        expectedBytes = isVolume ? Volumes.used(url) : 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let s = self.scanner else { return }
                self.currentPath = s.currentPath
                self.scannedBytes = s.scannedBytes
            }
        }
        Task {
            let node = await scanner.scan(url)
            timer?.invalidate()
            guard self.scanner === scanner else { return }
            root = node
            current = node
            phase = .done
        }
    }

    func cancelScan() {
        scanner?.cancel()
        scanner = nil
        timer?.invalidate()
        phase = .idle
    }

    func reset() {
        phase = .idle
        root = nil
        current = nil
        selection = []
    }

    func enter(_ node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        current = node
    }

    func goUp() {
        if let p = current?.parent { current = p }
    }

    func toggle(_ node: FileNode) {
        if selection.contains(node) { selection.remove(node) } else { selection.insert(node) }
    }

    var selectedSize: Int64 { selection.reduce(0) { $0 + $1.size } }
    var selectedFiles: Int { selection.reduce(0) { $0 + $1.fileCount } }

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func quickLook(_ node: FileNode) {
        Shell.run("/usr/bin/qlmanage", ["-p", node.url.path])
    }

    /// Moves the selection to the Trash so it can be restored.
    func trashSelection() {
        var failed = 0
        var moved: Int64 = 0
        for node in selection {
            do {
                try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
                moved += node.size
                node.detach()
            } catch {
                failed += 1
            }
        }
        selection = []
        toast = failed > 0
            ? Toast(text: "couldn't move \(failed) \(failed == 1 ? "item" : "items")  ·  permission denied", isError: true)
            : Toast(text: "moved \(Bytes.format(moved)) to the Trash")
        objectWillChange.send()
    }
}
