import AppKit

/// Owns the menu bar item, the sampling timer and the pressure event source.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    static let sampleInterval: TimeInterval = 3
    private static let notificationsKey = "notificationsEnabled"
    private static let activityMonitorURL = URL(
        fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let notifier = Notifier()

    private var tracker = RateTracker()
    private var hysteresis = Hysteresis()
    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?

    private var sample: MemorySample?
    private var rates = Rates()
    private var evaluation = Evaluation(level: .normal, reasons: [])
    private var shownLevel: Level = .normal
    private var lastNotified: [Level: Date] = [:]
    private var lastPressureEvent: String = "none yet"

    private var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.notificationsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.notificationsKey) }
    }

    func start() {
        notifier.setUp()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.title = "MEM …"

        EventLog.write("start", ["pid": Int(ProcessInfo.processInfo.processIdentifier)])
        tick(reason: "start")

        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(reason: "timer") }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // The kernel tells us right away when pressure changes, so we do not wait for the timer.
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            let event = source?.data ?? []
            let name =
                event.contains(.critical) ? "critical" : event.contains(.warning) ? "warning" : "normal"
            MainActor.assumeIsolated {
                self?.lastPressureEvent = name
                self?.tick(reason: "pressure event: \(name)")
            }
        }
        source.activate()
        pressureSource = source
    }

    // MARK: - Sampling

    private func tick(reason: String) {
        let s = Metrics.sample()
        tracker.add(s)
        rates = tracker.rates()
        evaluation = LevelEvaluator.evaluate(s, rates)
        sample = s

        let previous = shownLevel
        shownLevel = hysteresis.update(raw: evaluation.level, at: s.time)
        updateTitle()

        if shownLevel != previous {
            let processes = Processes.snapshot()
            var fields = EventLog.snapshotFields(s, rates, evaluation, processes)
            fields["from"] = previous.name
            fields["to"] = shownLevel.name
            fields["trigger"] = reason
            EventLog.write("levelChange", fields)
            if shownLevel > previous {
                maybeNotify(s, processes)
            }
        } else if shownLevel == .critical {
            // While it stays critical, remind again after the cooldown.
            maybeNotify(s, nil)
        }
    }

    private func maybeNotify(_ s: MemorySample, _ snapshot: ProcessSnapshot?) {
        guard notificationsEnabled, shownLevel != .normal else { return }
        let cooldown =
            shownLevel == .critical ? Thresholds.criticalCooldown : Thresholds.warningCooldown
        if let last = lastNotified[shownLevel], Date().timeIntervalSince(last) < cooldown { return }
        lastNotified[shownLevel] = Date()

        let processes = snapshot ?? Processes.snapshot()
        let critical = shownLevel == .critical
        let title =
            critical
            ? "Memory CRITICAL – save your work"
            : "Memory pressure: WARNING"
        notifier.send(title: title, body: notificationBody(s, processes), critical: critical)
    }

    private func notificationBody(_ s: MemorySample, _ p: ProcessSnapshot) -> String {
        var text = "Swap \(Format.gbNumber(s.swapUsed))/\(Format.gb(s.swapTotal))"
        if rates.windowSeconds >= Thresholds.minGrowthWindowSeconds {
            text += ", growing \(String(format: "%.0f", rates.swapGrowthMBPerMin)) MB/min"
        }
        text += ". Free \(s.freeLevelPercent)%. Top: \(p.topGroupsText(3))"
        return text
    }

    // MARK: - Menu bar title

    private func updateTitle() {
        guard let button = statusItem.button, let s = sample else { return }
        let text = "MEM \(max(0, 100 - s.freeLevelPercent))%"
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)

        switch shownLevel {
        case .normal:
            button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
        case .warning:
            // A yellow dot plus normal text: yellow text is hard to read on a light menu bar.
            let title = NSMutableAttributedString(
                string: "● ", attributes: [.font: font, .foregroundColor: NSColor.systemYellow])
            title.append(NSAttributedString(string: text, attributes: [.font: font]))
            button.attributedTitle = title
        case .critical:
            let bold = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize(for: .regular), weight: .bold)
            button.attributedTitle = NSAttributedString(
                string: "● " + text, attributes: [.font: bold, .foregroundColor: NSColor.systemRed])
        }
        button.toolTip = "MemWatch: \(shownLevel.name). Title = 100 - kern.memorystatus_level"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let s = sample else { return }
        let processes = Processes.snapshot()

        let color: NSColor =
            shownLevel == .critical ? .systemRed : shownLevel == .warning ? .systemOrange : .labelColor
        let levelItem = NSMenuItem()
        levelItem.attributedTitle = NSAttributedString(
            string: "Level: \(shownLevel.name)",
            attributes: [
                .foregroundColor: color, .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            ])
        menu.addItem(levelItem)
        for reason in evaluation.reasons {
            menu.addItem(info("    \(reason)"))
        }
        menu.addItem(.separator())

        menu.addItem(info("Pressure: \(s.pressureName) (\(s.pressureLevel)), last event: \(lastPressureEvent)"))
        menu.addItem(info("Free (kernel): \(s.freeLevelPercent)%"))
        menu.addItem(
            info("App \(Format.gb(s.appMemory))  ·  Wired \(Format.gb(s.wired))  ·  Compressed \(Format.gb(s.compressed))"))
        menu.addItem(info("Cached files \(Format.gb(s.cachedFiles))  ·  Used \(Format.gb(s.memoryUsed)) of \(Format.gb(s.totalRAM))"))
        menu.addItem(
            info("Swap \(Format.gbNumber(s.swapUsed)) / \(Format.gb(s.swapTotal))  ·  \(Format.rate(rates.swapGrowthMBPerMin))"))
        menu.addItem(
            info(
                String(
                    format: "Swapouts %.0f pages/s  ·  Compressed %@  (over %.0f s)",
                    rates.swapoutPagesPerSec, Format.rate(rates.compressedGrowthMBPerMin),
                    rates.windowSeconds)))
        menu.addItem(.separator())

        menu.addItem(header("Top apps"))
        for group in processes.groups.prefix(10) {
            let count = group.count > 1 ? "  (\(group.count))" : ""
            menu.addItem(action("\(Format.size(group.footprint))   \(group.name)\(count)", #selector(openActivityMonitor)))
        }
        menu.addItem(header("Top processes"))
        for entry in processes.processes.prefix(5) {
            menu.addItem(action("\(Format.size(entry.footprint))   \(entry.name) [\(entry.pid)]", #selector(openActivityMonitor)))
        }
        if processes.deniedCount > 0 {
            menu.addItem(info("\(processes.deniedCount) of \(processes.pidCount) processes not readable (root)"))
        }
        menu.addItem(.separator())

        menu.addItem(action("Open Activity Monitor", #selector(openActivityMonitor)))
        let notify = action("Notifications", #selector(toggleNotifications))
        notify.state = notificationsEnabled ? .on : .off
        menu.addItem(notify)
        let login = action("Launch at Login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(action("Send Test Notification", #selector(sendTestNotification)))
        menu.addItem(info("Last notification: \(notifier.lastResult)"))
        menu.addItem(.separator())
        let quit = action("Quit MemWatch", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func header(_ text: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: text) }
        return info(text)
    }

    private func action(_ text: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    // MARK: - Actions

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.openApplication(
            at: Self.activityMonitorURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func toggleNotifications() {
        notificationsEnabled.toggle()
    }

    @objc private func toggleLoginItem() {
        if LoginItem.isEnabled { LoginItem.disable() } else { LoginItem.enable() }
    }

    @objc private func sendTestNotification() {
        guard let s = sample else { return }
        notifier.send(
            title: "MemWatch test (\(shownLevel.name))",
            body: notificationBody(s, Processes.snapshot()), critical: false)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
