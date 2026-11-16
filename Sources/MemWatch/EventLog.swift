import Foundation

/// Writes JSON lines to ~/Library/Logs/MemWatch.log. Rotates at 5 MB (keeps one old file).
enum EventLog {
    static let maxBytes: UInt64 = 5 * 1024 * 1024

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MemWatch.log")
    }

    static func write(_ event: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = event
        record["time"] = ISO8601DateFormatter().string(from: Date())
        guard JSONSerialization.isValidJSONObject(record),
            var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        else { return }
        data.append(0x0A)

        let fm = FileManager.default
        let path = url.path
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? UInt64, size > maxBytes {
            let old = path + ".1"
            try? fm.removeItem(atPath: old)
            try? fm.moveItem(atPath: path, toPath: old)
        }
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Main numbers and top consumers in a JSON friendly form.
    static func snapshotFields(
        _ s: MemorySample, _ r: Rates, _ e: Evaluation, _ p: ProcessSnapshot?
    ) -> [String: Any] {
        let mb = { (b: UInt64) -> Int in Int(b / 1_048_576) }
        var fields: [String: Any] = [
            "level": e.level.name,
            "reasons": e.reasons,
            "pressure": s.pressureLevel,
            "freeLevel": s.freeLevelPercent,
            "appMB": mb(s.appMemory),
            "wiredMB": mb(s.wired),
            "compressedMB": mb(s.compressed),
            "cachedMB": mb(s.cachedFiles),
            "swapUsedMB": mb(s.swapUsed),
            "swapTotalMB": mb(s.swapTotal),
            "swapGrowthMBPerMin": Int(r.swapGrowthMBPerMin.rounded()),
            "swapoutPagesPerSec": Int(r.swapoutPagesPerSec.rounded()),
        ]
        if let p {
            fields["topApps"] = p.groups.prefix(10).map {
                ["name": $0.name, "mb": mb($0.footprint), "count": $0.count] as [String: Any]
            }
            fields["topProcesses"] = p.processes.prefix(5).map {
                ["name": $0.name, "pid": Int($0.pid), "mb": mb($0.footprint)] as [String: Any]
            }
        }
        return fields
    }
}
