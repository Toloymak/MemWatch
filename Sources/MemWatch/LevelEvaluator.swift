import Foundation

// MARK: - Thresholds (tune here)

enum Thresholds {
    /// The menu bar number is "used percent" = 100 - kern.memorystatus_level.
    /// At or above this number the level is warning (yellow).
    static let warningUsedPercent = 70
    /// At or above this number the level is critical (red).
    static let criticalUsedPercent = 80

    /// Used by the menu to show rates. Shorter history is too noisy to show.
    static let minGrowthWindowSeconds = 20.0

    // Hysteresis: to go DOWN a level, the lower level must be seen this many
    // samples in a row, over at least this many seconds. Going UP is instant.
    static let samplesToGoDown = 2
    static let secondsToGoDown = 5.0

    // Notification cooldowns
    static let warningCooldown: TimeInterval = 15 * 60
    static let criticalCooldown: TimeInterval = 3 * 60
}

enum Level: Int, Comparable, Sendable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .normal: return "NORMAL"
        case .warning: return "WARNING"
        case .critical: return "CRITICAL"
        }
    }
}

struct Evaluation: Sendable {
    var level: Level
    /// Short texts that explain why the level is not normal.
    var reasons: [String]
}

enum LevelEvaluator {
    /// Raw level for one sample, without hysteresis.
    static func evaluate(_ s: MemorySample, _ r: Rates) -> Evaluation {
        // Swap and swapout rates are still shown in the menu, but they do not change the level.
        // A free level of 0 means "unknown", so we skip it.
        let used = s.freeLevelPercent > 0 ? 100 - s.freeLevelPercent : 0

        var critical: [String] = []
        var warning: [String] = []

        // Critical rules
        if used >= Thresholds.criticalUsedPercent {
            critical.append("memory used \(used)% >= \(Thresholds.criticalUsedPercent)%")
        }
        // Safety net: the kernel itself says critical.
        if s.pressureLevel == 4 {
            critical.append("kernel pressure is critical (4)")
        }

        // Warning rule
        if used >= Thresholds.warningUsedPercent {
            warning.append("memory used \(used)% >= \(Thresholds.warningUsedPercent)%")
        }

        if !critical.isEmpty { return Evaluation(level: .critical, reasons: critical + warning) }
        if !warning.isEmpty { return Evaluation(level: .warning, reasons: warning) }
        return Evaluation(level: .normal, reasons: [])
    }
}

/// Stops the level from flapping. Up is instant, down needs a few calm samples.
struct Hysteresis {
    private(set) var level: Level = .normal
    private var lowerCount = 0
    private var lowerSince: Date?

    /// Feeds a raw level and returns the shown level.
    mutating func update(raw: Level, at time: Date = Date()) -> Level {
        if raw > level {
            level = raw
            lowerCount = 0
            lowerSince = nil
        } else if raw < level {
            lowerCount += 1
            if lowerSince == nil { lowerSince = time }
            let calmFor = time.timeIntervalSince(lowerSince ?? time)
            if lowerCount >= Thresholds.samplesToGoDown && calmFor >= Thresholds.secondsToGoDown {
                level = raw
                lowerCount = 0
                lowerSince = nil
            }
        } else {
            lowerCount = 0
            lowerSince = nil
        }
        return level
    }
}
