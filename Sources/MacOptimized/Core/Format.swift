import Foundation

/// Decimal (Finder-style) byte sizes, always with a "." separator: "37.6 GB", "412 MB", "22 GB".
enum Bytes {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// `binary` uses 1024 steps, the convention for RAM ("48 GB" of memory).
    static func split(_ value: Int64, binary: Bool = false) -> (value: String, unit: String) {
        let step: Double = binary ? 1024 : 1000
        var v = Double(max(0, value))
        var i = 0
        while v >= step, i < units.count - 1 {
            v /= step
            i += 1
        }
        // Whole numbers below GB; one decimal from GB up, dropped when it is ".0".
        let decimals = i >= 3 && v < 100 ? 1 : 0
        var text = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return (text, units[i])
    }

    static func format(_ value: Int64, binary: Bool = false) -> String {
        let (v, u) = split(value, binary: binary)
        return "\(v) \(u)"
    }

    static func format(_ value: UInt64, binary: Bool = false) -> String { format(Int64(clamping: value), binary: binary) }

    static func memory(_ value: UInt64) -> String { format(value, binary: true) }
}
