import Foundation

/// Shared quota bands; bar styling and readable overlay text use separate palettes.
enum RemainingQuotaTier {
    case meadow, water, sunset, danger

    static func forPercent(_ percent: Int) -> RemainingQuotaTier {
        switch percent {
        case 70...: return .meadow
        case 40..<70: return .water
        case 10..<40: return .sunset
        default: return .danger
        }
    }
}

struct LimitWindow {
    let title: String
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

struct UsageSnapshot {
    let fiveHour: LimitWindow?
    let weekly: LimitWindow?
    let resetCredits: Int?
    let planType: String?
    let updatedAt: Date
    let status: String

    var hasUsageData: Bool {
        fiveHour != nil || weekly != nil
    }
}
