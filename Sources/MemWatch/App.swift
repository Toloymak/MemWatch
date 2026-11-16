import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

@main
@MainActor
enum MemWatchMain {
    // Kept here so the delegate lives as long as the app (NSApp.delegate is weak).
    static var delegate: AppDelegate?

    static func main() {
        let args = CommandLine.arguments.dropFirst()

        if args.contains("--status") {
            CLI.printStatus()
            return
        }
        if args.contains("--test-notify") {
            exit(CLI.testNotify())
        }
        if let index = args.firstIndex(of: "--login-item") {
            let mode = args.index(after: index) < args.endIndex ? args[args.index(after: index)] : "status"
            CLI.loginItem(mode)
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

/// Command line modes, useful for testing without the UI.
@MainActor
enum CLI {
    static func printStatus() {
        // Two samples 2 s apart so we can show rates.
        var tracker = RateTracker()
        tracker.add(Metrics.sample())
        Thread.sleep(forTimeInterval: 2)
        let s = Metrics.sample()
        tracker.add(s)
        let r = tracker.rates()
        let e = LevelEvaluator.evaluate(s, r)
        let p = Processes.snapshot()

        func line(_ label: String, _ value: String) {
            print(label.padding(toLength: 15, withPad: " ", startingAt: 0) + value)
        }
        let date = ISO8601DateFormatter().string(from: s.time)
        print("MemWatch status  \(date)")
        line("Level:", e.level.name + "  (raw, no hysteresis)")
        for reason in e.reasons { line("", "- " + reason) }
        line("Pressure:", "\(s.pressureLevel) (\(s.pressureName))   kern.memorystatus_vm_pressure_level")
        line("Free level:", "\(s.freeLevelPercent)%   kern.memorystatus_level")
        line("RAM:", "\(Format.gb(s.totalRAM)), page size \(s.pageSize)")
        line("App memory:", Format.gb(s.appMemory))
        line("Wired:", Format.gb(s.wired))
        line("Compressed:", "\(Format.gb(s.compressed))  (holds \(Format.gb(s.compressedOriginal)) of data)")
        line("Cached files:", Format.gb(s.cachedFiles))
        line("Memory used:", "\(Format.gb(s.memoryUsed))  (App + Wired + Compressed)")
        line("Free pages:", "\(Format.gb(s.free))  active \(Format.gb(s.active))  inactive \(Format.gb(s.inactive))")
        line(
            "Swap:",
            "used \(Format.size(s.swapUsed)) / total \(Format.size(s.swapTotal)), free \(Format.size(s.swapFree))")
        line("Swap counters:", "swapins \(s.swapins)  swapouts \(s.swapouts) pages")
        line(
            "Rates:",
            String(
                format: "over %.1f s: swapouts %.0f pages/s, swapins %.0f pages/s, swap %@, compressed %@",
                r.windowSeconds, r.swapoutPagesPerSec, r.swapinPagesPerSec,
                Format.rate(r.swapGrowthMBPerMin), Format.rate(r.compressedGrowthMBPerMin)))
        line(
            "Processes:",
            "\(p.pidCount) pids, \(p.pidCount - p.deniedCount) read, \(p.deniedCount) not allowed (root, EPERM)")
        print("Top apps:")
        func row(_ i: Int, _ name: String, _ bytes: UInt64, _ tail: String) {
            let shortName = name.count > 40 ? String(name.prefix(39)) + "…" : name
            let size = Format.size(bytes)
            print(
                String(format: "  %2d. ", i + 1) + shortName.padding(toLength: 41, withPad: " ", startingAt: 0)
                    + String(repeating: " ", count: max(0, 8 - size.count)) + size + "  " + tail)
        }
        for (i, g) in p.groups.prefix(10).enumerated() {
            row(i, g.name, g.footprint, "(\(g.count) procs)")
        }
        print("Top processes:")
        for (i, entry) in p.processes.prefix(5).enumerated() {
            row(i, entry.name, entry.footprint, "pid \(entry.pid)")
        }
    }

    /// Sends one notification and waits up to 20 s for the result.
    static func testNotify() -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let notifier = Notifier()
        notifier.setUp()
        let s = Metrics.sample()
        let p = Processes.snapshot()
        var result: String?
        print("Bundle: \(Bundle.main.bundleURL.path) id=\(Bundle.main.bundleIdentifier ?? "none")")
        print("UNUserNotificationCenter usable: \(notifier.canUseUserNotifications)")
        notifier.send(
            title: "MemWatch test notification",
            body: "Swap \(Format.gbNumber(s.swapUsed))/\(Format.gb(s.swapTotal)). Free \(s.freeLevelPercent)%. Top: \(p.topGroupsText(3))",
            critical: false
        ) { result = $0 }

        let deadline = Date().addingTimeInterval(20)
        while result == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        print("Result: \(result ?? "timeout, no result in 20 s")")
        return result == nil ? 1 : 0
    }

    static func loginItem(_ mode: String) {
        switch mode {
        case "on": print(LoginItem.enable())
        case "off": print(LoginItem.disable())
        default: print(LoginItem.describe())
        }
    }
}
