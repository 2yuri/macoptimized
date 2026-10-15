import Foundation

/// Junk categories. Only user-level locations, so no privileged helper is needed.
struct JunkRule {
    enum Mode {
        /// Every top-level entry inside each root is one removable item.
        case contentsOf([String])
        /// Each path itself is one removable item.
        case paths([String])
        /// Custom finder.
        case custom(() -> [URL])
    }

    let id: String
    let title: String
    let detail: String
    let icon: String
    let mode: Mode
    /// Selected for removal by default on "run"; only junk that is safe to delete.
    let autoSelect: Bool
    /// Moved to Trash instead of deleted permanently.
    var useTrash = false
    var skipNames: Set<String> = []
}

enum JunkRules {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func expand(_ p: String) -> String { p.hasPrefix("~") ? home + p.dropFirst() : p }

    /// Caches that are state, not cache: removing them logs you out of iCloud/Family etc.
    static let protectedCaches: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.nsurlsessiond", "com.apple.homed", "FamilyCircle",
        "com.apple.containermanagerd", "com.apple.ap.adprivacyd", "com.apple.akd", "com.apple.findmy.fmipcore",
        "com.apple.iCloudHelper", "com.apple.Safari.SafeBrowsing", "GeoServices",
    ]

    /// Caches that are really downloaded tools; listed but left unchecked.
    static let reviewCaches: Set<String> = ["ms-playwright", "JetBrains"]

    static let all: [JunkRule] = [
        JunkRule(id: "userCache", title: "user cache", detail: "~/Library/Caches",
                 icon: "archivebox", mode: .contentsOf(["~/Library/Caches"]), autoSelect: true,
                 skipNames: protectedCaches),
        JunkRule(id: "userLogs", title: "logs", detail: "~/Library/Logs, DiagnosticReports",
                 icon: "doc.text", mode: .contentsOf(["~/Library/Logs"]), autoSelect: true),
        JunkRule(id: "xcode", title: "xcode junk", detail: "DerivedData, ModuleCache, Simulator caches",
                 icon: "hammer", mode: .contentsOf([
                    "~/Library/Developer/Xcode/DerivedData",
                    "~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex",
                    "~/Library/Developer/CoreSimulator/Caches",
                 ]), autoSelect: true, skipNames: ["ModuleCache.noindex"]),
        JunkRule(id: "xcodeDeviceSupport", title: "xcode device support", detail: "Symbols for old devices",
                 icon: "iphone", mode: .contentsOf([
                    "~/Library/Developer/Xcode/iOS DeviceSupport",
                    "~/Library/Developer/Xcode/watchOS DeviceSupport",
                    "~/Library/Developer/Xcode/tvOS DeviceSupport",
                    "~/Library/Developer/Xcode/macOS DeviceSupport",
                 ]), autoSelect: false),
        JunkRule(id: "devCaches", title: "developer caches", detail: "npm, Gradle, CocoaPods, Bun, pnpm",
                 icon: "shippingbox", mode: .paths([
                    "~/.npm/_cacache", "~/.gradle/caches", "~/.bun/install/cache", "~/Library/pnpm/store",
                    "~/.cocoapods/repos",
                 ]), autoSelect: false),
        JunkRule(id: "brokenPrefs", title: "broken preferences", detail: ".plist files in ~/Library/Preferences that fail to parse",
                 icon: "gearshape.2", mode: .custom(brokenPreferences), autoSelect: true),
        JunkRule(id: "iosBackups", title: "ios backups", detail: "MobileSync/Backup",
                 icon: "externaldrive.badge.timemachine", mode: .contentsOf(["~/Library/Application Support/MobileSync/Backup"]),
                 autoSelect: false, useTrash: true),
        JunkRule(id: "trash", title: "trash bins", detail: "~/.Trash, external volumes, iCloud Drive",
                 icon: "trash", mode: .custom(trashContents), autoSelect: true),
    ]

    static func brokenPreferences() -> [URL] {
        let dir = URL(fileURLWithPath: expand("~/Library/Preferences"))
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { url in
            guard url.pathExtension == "plist", let data = try? Data(contentsOf: url) else { return false }
            if data.isEmpty { return true }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil
        }
    }

    static func trashContents() -> [URL] {
        TrashBins.locations().flatMap { url, _ in
            ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent != ".DS_Store" }
        }
    }
}
