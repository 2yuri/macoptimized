import AppKit

/// Every Trash folder the current user owns: local, external volumes and iCloud Drive.
enum TrashBins {
    struct Bin: Identifiable {
        let url: URL
        let label: String
        var size: Int64
        var id: URL { url }
    }

    static func locations() -> [(URL, String)] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var result: [(URL, String)] = [(home.appendingPathComponent(".Trash"), "~/.Trash")]

        let uid = getuid()
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) {
            for v in vols {
                result.append((v.appendingPathComponent(".Trashes/\(uid)"), v.lastPathComponent))
            }
        }

        let mobile = home.appendingPathComponent("Library/Mobile Documents")
        result.append((mobile.appendingPathComponent(".Trash"), "iCloud Drive"))
        result.append((mobile.appendingPathComponent("com~apple~CloudDocs/.Trash"), "iCloud Drive"))
        result.append((home.appendingPathComponent("Library/CloudStorage/iCloud Drive/.Trash"), "iCloud Drive"))
        if let containers = try? fm.contentsOfDirectory(at: mobile, includingPropertiesForKeys: nil) {
            for c in containers where c.lastPathComponent != "com~apple~CloudDocs" {
                result.append((c.appendingPathComponent("Documents/.Trash"), "iCloud Drive"))
            }
        }
        return result.filter { fm.fileExists(atPath: $0.0.path) }
    }

    static func scan() -> [Bin] {
        locations().compactMap { url, label in
            let size = DirectorySize.allocated(of: url)
            return size > 0 ? Bin(url: url, label: label, size: size) : nil
        }
    }

    /// Removes the bin contents (not the bin folder itself). Returns bytes removed.
    @discardableResult
    static func empty(_ bins: [Bin]) -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        for bin in bins {
            guard let items = try? fm.contentsOfDirectory(at: bin.url, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.lastPathComponent != ".DS_Store" {
                let size = DirectorySize.allocated(of: item)
                if (try? fm.removeItem(at: item)) != nil { freed += size }
            }
        }
        if freed > 0 { NSSound(named: "dragToTrash")?.play() }
        return freed
    }
}
