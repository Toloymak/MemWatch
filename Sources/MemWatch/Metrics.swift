import Darwin
import Foundation

/// One reading of the system memory numbers. Sizes are in bytes.
struct MemorySample: Sendable {
    var time: Date
    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warn, 4 critical.
    var pressureLevel: Int
    /// kern.memorystatus_level: how much memory the kernel thinks is still available, in percent.
    var freeLevelPercent: Int
    var totalRAM: UInt64
    var pageSize: UInt64

    var free: UInt64
    var active: UInt64
    var inactive: UInt64
    var speculative: UInt64
    var wired: UInt64
    /// Memory used by the compressor itself (Activity Monitor "Compressed").
    var compressed: UInt64
    /// Data that sits inside the compressor before it was compressed.
    var compressedOriginal: UInt64
    var internalBytes: UInt64
    var externalBytes: UInt64
    var purgeable: UInt64

    /// Page counts since boot.
    var swapins: UInt64
    var swapouts: UInt64

    var swapTotal: UInt64
    var swapUsed: UInt64
    var swapFree: UInt64

    /// Same formulas as Activity Monitor.
    var appMemory: UInt64 { internalBytes > purgeable ? internalBytes - purgeable : 0 }
    var cachedFiles: UInt64 { externalBytes + purgeable }
    var memoryUsed: UInt64 { appMemory + wired + compressed }

    var pressureName: String {
        switch pressureLevel {
        case 1: return "normal"
        case 2: return "warn"
        case 4: return "critical"
        default: return "unknown(\(pressureLevel))"
        }
    }
}

enum Metrics {
    // mach_host_self() gives a new port reference on each call, so keep one.
    private static let host: mach_port_t = mach_host_self()

    /// Reads an integer sysctl. Works for both 4 byte and 8 byte values.
    static func sysctlInteger(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == 4 { return UInt64(UInt32(truncatingIfNeeded: value)) }
        return value
    }

    static func pageSize() -> UInt64 {
        // Same value as vm_kernel_page_size (16 KB on Apple silicon).
        // We ask the kernel because the C global is not safe to read under Swift 6 rules.
        var size: vm_size_t = 0
        if host_page_size(host, &size) == KERN_SUCCESS, size > 0 { return UInt64(size) }
        return UInt64(getpagesize())
    }

    static func swapUsage() -> xsw_usage? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage
    }

    static func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    /// Takes one full sample. Missing values become 0 so the app keeps working.
    static func sample() -> MemorySample {
        let page = pageSize()
        let vm = vmStatistics() ?? vm_statistics64()
        let swap = swapUsage() ?? xsw_usage()
        func bytes(_ pages: natural_t) -> UInt64 { UInt64(pages) * page }

        return MemorySample(
            time: Date(),
            pressureLevel: Int(sysctlInteger("kern.memorystatus_vm_pressure_level") ?? 0),
            freeLevelPercent: Int(sysctlInteger("kern.memorystatus_level") ?? 0),
            totalRAM: sysctlInteger("hw.memsize") ?? 0,
            pageSize: page,
            free: bytes(vm.free_count),
            active: bytes(vm.active_count),
            inactive: bytes(vm.inactive_count),
            speculative: bytes(vm.speculative_count),
            wired: bytes(vm.wire_count),
            compressed: bytes(vm.compressor_page_count),
            compressedOriginal: vm.total_uncompressed_pages_in_compressor * page,
            internalBytes: bytes(vm.internal_page_count),
            externalBytes: bytes(vm.external_page_count),
            purgeable: bytes(vm.purgeable_count),
            swapins: vm.swapins,
            swapouts: vm.swapouts,
            swapTotal: swap.xsu_total,
            swapUsed: swap.xsu_used,
            swapFree: swap.xsu_avail
        )
    }
}

/// Speeds computed from recent samples.
struct Rates: Sendable {
    /// Time covered by the whole window, in seconds.
    var windowSeconds: Double = 0
    /// Swapouts per second over the last ~15 s.
    var swapoutPagesPerSec: Double = 0
    /// Time really covered by swapoutPagesPerSec (shorter right after start).
    var swapoutSeconds: Double = 0
    /// Swapins per second over the same short span.
    var swapinPagesPerSec: Double = 0
    /// Swap used growth over the whole window.
    var swapGrowthMBPerMin: Double = 0
    /// Compressed memory growth over the whole window.
    var compressedGrowthMBPerMin: Double = 0
}

/// Keeps the last ~60 s of samples and turns them into rates.
struct RateTracker {
    static let window: TimeInterval = 60
    static let shortWindow: TimeInterval = 15

    private(set) var samples: [MemorySample] = []

    mutating func add(_ sample: MemorySample) {
        samples.append(sample)
        samples.removeAll { sample.time.timeIntervalSince($0.time) > Self.window }
    }

    func rates() -> Rates {
        guard let last = samples.last, let first = samples.first, samples.count >= 2 else {
            return Rates()
        }
        var rates = Rates()
        let span = last.time.timeIntervalSince(first.time)
        guard span > 0.5 else { return rates }
        rates.windowSeconds = span

        let mb = 1024.0 * 1024.0
        rates.swapGrowthMBPerMin = (Double(last.swapUsed) - Double(first.swapUsed)) / mb / span * 60
        rates.compressedGrowthMBPerMin =
            (Double(last.compressed) - Double(first.compressed)) / mb / span * 60

        // For the short rate, use the newest sample that is at least 15 s old.
        // If there is none yet, use the oldest one and report the shorter span.
        let cutoff = last.time.addingTimeInterval(-Self.shortWindow + 0.5)
        let base = samples.last(where: { $0.time <= cutoff }) ?? first
        let shortSpan = last.time.timeIntervalSince(base.time)
        if shortSpan > 0.5 {
            rates.swapoutSeconds = shortSpan
            rates.swapoutPagesPerSec = Double(last.swapouts &- base.swapouts) / shortSpan
            rates.swapinPagesPerSec = Double(last.swapins &- base.swapins) / shortSpan
        }
        return rates
    }
}

enum Format {
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    static func gbNumber(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    static func size(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    /// Always in MB, so values near a threshold do not round to the same text.
    static func mb(_ bytes: UInt64) -> String {
        "\(bytes / 1_048_576) MB"
    }

    static func rate(_ mbPerMin: Double) -> String {
        String(format: "%+.0f MB/min", mbPerMin)
    }
}
