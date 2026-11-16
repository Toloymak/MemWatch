import Foundation
import UserNotifications

/// Sends a pop-up notification. Tries UNUserNotificationCenter first and falls back to
/// `osascript -e 'display notification ...'` when that is not possible.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// What happened with the last notification, for the menu and the log.
    private(set) var lastResult = "none yet"

    /// How long we wait for the user to answer the permission prompt.
    private let authorizationTimeout: TimeInterval = 8

    /// UNUserNotificationCenter needs a real .app bundle with an identifier.
    /// Without one, UNUserNotificationCenter.current() crashes.
    var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func setUp() {
        guard canUseUserNotifications else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// Sends one notification. `done` gets a text that says which path was used.
    func send(
        title: String, body: String, critical: Bool,
        done: (@MainActor (String) -> Void)? = nil
    ) {
        let finish: @MainActor (String) -> Void = { [weak self] result in
            self?.lastResult = result
            EventLog.write("notification", ["title": title, "result": result])
            done?(result)
        }

        guard canUseUserNotifications else {
            sendWithOsascript(
                title: title, body: body, critical: critical,
                why: "no .app bundle", done: finish)
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self.continueSend(
                    status: status, title: title, body: body, critical: critical, done: finish)
            }
        }
    }

    private func continueSend(
        status: UNAuthorizationStatus, title: String, body: String, critical: Bool,
        done: @escaping @MainActor (String) -> Void
    ) {
        switch status {
        case .authorized, .provisional, .ephemeral:
            deliver(title: title, body: body, critical: critical, done: done)
        case .notDetermined:
            requestThenDeliver(title: title, body: body, critical: critical, done: done)
        case .denied:
            sendWithOsascript(
                title: title, body: body, critical: critical,
                why: "UNUserNotificationCenter permission denied", done: done)
        @unknown default:
            sendWithOsascript(
                title: title, body: body, critical: critical,
                why: "unknown permission status \(status.rawValue)", done: done)
        }
    }

    private func requestThenDeliver(
        title: String, body: String, critical: Bool,
        done: @escaping @MainActor (String) -> Void
    ) {
        // The answer comes only after the user clicks the system prompt.
        // If nobody answers in time, use the fallback so the warning is not lost.
        let handled = OnceFlag()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            granted, error in
            let errorText = error.map { String(describing: $0) }
            Task { @MainActor in
                guard handled.take() else { return }
                if granted {
                    self.deliver(title: title, body: body, critical: critical, done: done)
                } else {
                    self.sendWithOsascript(
                        title: title, body: body, critical: critical,
                        why: "permission not granted (\(errorText ?? "no error"))", done: done)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + authorizationTimeout) {
            MainActor.assumeIsolated {
                guard handled.take() else { return }
                self.sendWithOsascript(
                    title: title, body: body, critical: critical,
                    why: "no answer to permission prompt in \(Int(self.authorizationTimeout)) s",
                    done: done)
            }
        }
    }

    private func deliver(
        title: String, body: String, critical: Bool,
        done: @escaping @MainActor (String) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = critical ? .defaultCritical : nil
        if critical { content.interruptionLevel = .timeSensitive }
        let request = UNNotificationRequest(
            identifier: "memwatch-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            let errorText = error.map { String(describing: $0) }
            Task { @MainActor in
                if let errorText {
                    self.sendWithOsascript(
                        title: title, body: body, critical: critical,
                        why: "UNUserNotificationCenter add failed: \(errorText)", done: done)
                } else {
                    done("UNUserNotificationCenter: delivered (add() returned no error)")
                }
            }
        }
    }

    private func sendWithOsascript(
        title: String, body: String, critical: Bool, why: String,
        done: @escaping @MainActor (String) -> Void
    ) {
        func quote(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var script = "display notification \(quote(body)) with title \(quote(title))"
        if critical { script += " sound name \"Sosumi\"" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { finished in
            let code = finished.terminationStatus
            let stderr =
                String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                if code == 0 {
                    done("osascript fallback: exit 0 (reason: \(why))")
                } else {
                    done("osascript fallback FAILED: exit \(code) \(stderr) (reason: \(why))")
                }
            }
        }
        do {
            try process.run()
        } catch {
            done("osascript fallback FAILED to start: \(error) (reason: \(why))")
        }
    }

    // Show banners even when our app counts as active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// True only for the first caller. Used so a late answer does not send twice.
@MainActor
final class OnceFlag {
    private var used = false
    func take() -> Bool {
        if used { return false }
        used = true
        return true
    }
}
