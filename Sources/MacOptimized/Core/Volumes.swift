import Foundation

enum Volumes {
    /// "Macintosh HD", or whatever the startup volume is called.
    static var rootName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "Macintosh HD"
    }

    static func available(_ url: URL = URL(fileURLWithPath: "/")) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity) ?? 0)
    }

    static func used(_ url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let t = v.volumeTotalCapacity, let a = v.volumeAvailableCapacity else { return 0 }
        return Int64(t - a)
    }
}
