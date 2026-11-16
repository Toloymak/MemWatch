import Darwin
import Foundation

/// One process and its memory, as Activity Monitor shows it in the "Memory" column.
struct ProcessEntry: Sendable {
    var pid: pid_t
    var name: String
    var group: String
    var footprint: UInt64
}

/// Processes added up per app.
struct AppGroup: Sendable {
    var name: String
    var footprint: UInt64
    var count: Int
}

struct ProcessSnapshot: Sendable {
    var processes: [ProcessEntry]  // biggest first
    var groups: [AppGroup]  // biggest first
    var pidCount: Int
    /// PIDs we could not read, mostly root processes (EPERM).
    var deniedCount: Int

    func topGroupsText(_ count: Int) -> String {
        groups.prefix(count).map { "\($0.name) \(Format.size($0.footprint))" }
            .joined(separator: ", ")
    }
}

enum Processes {
    private static let maxPathSize = 4 * Int(MAXPATHLEN)

    static func allPids() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Add room in case new processes start between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 128)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    /// phys_footprint of one process, or nil if we may not read it.
    static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: maxPathSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return text(buffer, length: Int(length))
    }

    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return text(buffer, length: Int(length))
    }

    /// Turns a C char buffer into a String. `length` is the byte count without the final 0.
    private static func text(_ buffer: [CChar], length: Int) -> String {
        let bytes = buffer.prefix(min(length, buffer.count)).prefix { $0 != 0 }
        return String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The app a path belongs to: the first path part that ends in ".app".
    /// "/Applications/Google Chrome.app/.../Google Chrome Helper (Renderer).app/..." -> "Google Chrome".
    static func appName(fromPath path: String) -> String? {
        for part in path.split(separator: "/") where part.hasSuffix(".app") {
            return String(part.dropLast(4))
        }
        return nil
    }

    /// Some tools name their binary by version, like ".../sometool/versions/2.1.322".
    /// For those, use the nearest folder name that is not a version, "versions" or "bin".
    static func toolName(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last, isVersion(last) else { return nil }
        let skip: Set<String> = ["versions", "version", "bin", "current"]
        return parts.dropLast().last { !isVersion($0) && !skip.contains($0.lowercased()) }
    }

    private static func isVersion(_ text: String) -> Bool {
        guard let first = text.first, first.isNumber || first == "v" else { return false }
        return text.allSatisfy { $0.isNumber || $0 == "." || $0 == "v" || $0 == "-" }
    }

    static func snapshot() -> ProcessSnapshot {
        let pids = allPids()
        var entries: [ProcessEntry] = []
        var denied = 0
        for pid in pids {
            guard let footprint = footprint(of: pid) else {
                denied += 1
                continue
            }
            let path = path(of: pid)
            // The path gives the full name. proc_name cuts names at 32 characters.
            let processName =
                path.map { ($0 as NSString).lastPathComponent } ?? name(of: pid) ?? "pid \(pid)"
            let group =
                path.flatMap(appName(fromPath:)) ?? path.flatMap(toolName(fromPath:)) ?? processName
            entries.append(
                ProcessEntry(pid: pid, name: processName, group: group, footprint: footprint))
        }

        var byGroup: [String: AppGroup] = [:]
        for entry in entries {
            byGroup[entry.group, default: AppGroup(name: entry.group, footprint: 0, count: 0)]
                .footprint += entry.footprint
            byGroup[entry.group]!.count += 1
        }

        return ProcessSnapshot(
            processes: entries.sorted { $0.footprint > $1.footprint },
            groups: byGroup.values.sorted { $0.footprint > $1.footprint },
            pidCount: pids.count,
            deniedCount: denied
        )
    }
}
