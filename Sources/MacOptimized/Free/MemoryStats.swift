import Darwin
import Foundation

/// Snapshot of VM statistics, using the same formula Activity Monitor uses for "Memory Used".
struct MemoryStats {
    var total: UInt64
    var wired: UInt64
    var active: UInt64
    var inactive: UInt64
    var compressed: UInt64
    var appMemory: UInt64   // internal - purgeable
    var cached: UInt64      // external + purgeable
    var free: UInt64
    var swapUsed: UInt64
    var pressure: Pressure

    var used: UInt64 { appMemory + wired + compressed }
    var available: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    enum Pressure: String {
        case normal = "Normal", warning = "Warning", critical = "Critical", unknown = "—"
    }

    static func current() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        return MemoryStats(
            total: ProcessInfo.processInfo.physicalMemory,
            wired: UInt64(stats.wire_count) * page,
            active: UInt64(stats.active_count) * page,
            inactive: UInt64(stats.inactive_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            appMemory: (internalPages > purgeable ? internalPages - purgeable : 0) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page,
            free: UInt64(stats.free_count) * page,
            swapUsed: swapUsage(),
            pressure: pressureLevel()
        )
    }

    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical.
    static func pressureLevel() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .unknown }
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 3, 4: return .critical
        default: return .unknown
        }
    }

    static func swapUsage() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }
}
