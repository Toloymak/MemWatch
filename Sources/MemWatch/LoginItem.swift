import Foundation
import ServiceManagement

/// "Launch at login". First tries SMAppService.mainApp. If that throws,
/// writes a LaunchAgent plist to ~/Library/LaunchAgents/local.memwatch.plist.
@MainActor
enum LoginItem {
    static let agentLabel = "local.memwatch"

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
            || FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func describe() -> String {
        let status: String
        switch SMAppService.mainApp.status {
        case .enabled: status = "enabled"
        case .requiresApproval: status = "requiresApproval (allow it in System Settings > General > Login Items)"
        case .notRegistered: status = "notRegistered"
        case .notFound: status = "notFound"
        @unknown default: status = "unknown"
        }
        let agent = FileManager.default.fileExists(atPath: agentURL.path) ? "present" : "absent"
        return "SMAppService.mainApp: \(status); LaunchAgent plist: \(agent)"
    }

    /// Turns launch at login on. Returns a text that says which way worked.
    @discardableResult
    static func enable() -> String {
        do {
            try SMAppService.mainApp.register()
            let result = "SMAppService.register() OK -> \(describe())"
            EventLog.write("loginItem", ["action": "enable", "result": result])
            return result
        } catch {
            let smError = String(describing: error)
            let result: String
            do {
                try writeLaunchAgent()
                result = "SMAppService.register() failed: \(smError); LaunchAgent written to \(agentURL.path)"
            } catch {
                result = "SMAppService.register() failed: \(smError); LaunchAgent write failed: \(error)"
            }
            EventLog.write("loginItem", ["action": "enable", "result": result])
            return result
        }
    }

    @discardableResult
    static func disable() -> String {
        var parts: [String] = []
        let status = SMAppService.mainApp.status
        if status == .enabled || status == .requiresApproval {
            do {
                try SMAppService.mainApp.unregister()
                parts.append("SMAppService.unregister() OK")
            } catch {
                parts.append("SMAppService.unregister() failed: \(error)")
            }
        }
        if FileManager.default.fileExists(atPath: agentURL.path) {
            do {
                try FileManager.default.removeItem(at: agentURL)
                parts.append("LaunchAgent removed")
            } catch {
                parts.append("LaunchAgent remove failed: \(error)")
            }
        }
        let result = (parts.isEmpty ? "nothing to do" : parts.joined(separator: "; ")) + " -> \(describe())"
        EventLog.write("loginItem", ["action": "disable", "result": result])
        return result
    }

    /// The plist runs `open -a <app>` once at login.
    private static func writeLaunchAgent() throws {
        let appPath = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.bundleURL.path
            : FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/MemWatch.app").path
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: agentURL)
    }
}
