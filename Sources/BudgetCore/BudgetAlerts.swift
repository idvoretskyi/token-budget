import Foundation

public struct BudgetAlert: Equatable, Sendable {
    public let threshold: Int
    public let key: String
    /// Baseline thresholds are recorded silently, never delivered as historical alerts.
    public let shouldNotify: Bool
}

/// Observes successful scan summaries, not settings previews or cached ledger loads.
public struct BudgetAlerts: Sendable {
    private var configuration: AppSettings?
    private var window: DateInterval?
    private var previousSpend: Decimal?
    private var consumed: Set<String> = []

    public init() {}

    public mutating func resetBaseline() {
        configuration = nil
        window = nil
        previousSpend = nil
    }

    public mutating func observe(summary: BudgetSummary?, settings: AppSettings,
                                 canShowEstimate: Bool, successfulScan: Bool) -> [BudgetAlert] {
        guard settings.notificationsEnabled, successfulScan, canShowEstimate,
              settings.selections.contains(where: { settings.enabledSources.contains($0.source) }),
              let summary, summary.unpricedCount == 0,
              !summary.spent.isNaN, summary.spent >= 0,
              !settings.budget.amount.isNaN, settings.budget.amount > 0,
               summary.warnings.allSatisfy(UsageCoverage.isInformationalWarning) else {
            resetBaseline()
            return []
        }
        let previous = configuration == settings && window == summary.window ? previousSpend : nil
        configuration = settings
        window = summary.window
        previousSpend = summary.spent
        return [80, 100].compactMap { threshold in
            let amount = settings.budget.amount * (Decimal(threshold) / 100)
            guard summary.spent >= amount else { return nil }
            if let previous, previous >= amount { return nil }
            let key = Self.notificationKey(settings: settings, window: summary.window, threshold: threshold)
            guard consumed.insert(key).inserted else { return nil }
            return BudgetAlert(threshold: threshold, key: key, shouldNotify: previous != nil)
        }
    }

    public static func notificationKey(settings: AppSettings, window: DateInterval, threshold: Int) -> String {
        let budget = settings.budget
        // Length framing avoids delimiter ambiguity; FNV-1a is stable across launches/platforms.
        // This is a local deduplication fingerprint, not a privacy or cryptographic boundary.
        let selections = Set(settings.selections).map {
            framed([$0.source.rawValue, $0.provider, $0.model])
        }.sorted()
        let selectionBytes = framed(selections).utf8
        let selectionHash = selectionBytes.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return "budget-alert-v1:" + framed([
            NSDecimalNumber(decimal: budget.amount).stringValue, budget.currency,
            budget.period.rawValue, budget.timeZoneID,
            String(budget.weekday), String(budget.hour), String(budget.minute),
            String(window.start.timeIntervalSince1970.bitPattern, radix: 16),
            String(window.end.timeIntervalSince1970.bitPattern, radix: 16),
            framed(Set(settings.enabledSources.map(\.rawValue)).sorted()),
            String(selectionHash, radix: 16), String(threshold)
        ])
    }

    private static func framed(_ fields: [String]) -> String {
        fields.map { "\($0.utf8.count):\($0)" }.joined()
    }

}

public enum UsageCoverage {
    /// Disclaimers remain visible but are not evidence of a specific import gap.
    public static func isInformationalWarning(_ warning: String) -> Bool {
        if warning == "Full-period history has not been confirmed; recorded usage may be incomplete." {
            return true
        }
        // Exact allowlist: new importer warnings fail closed until reviewed.
        let notices = [
            "Local usage records do not prove complete billing coverage.",
            "Codex model attribution uses recorded turn configuration; actual backend reroutes may not be recorded.",
            "Only canonical OpenCode step-finish usage is imported; message and session totals are not added."
        ]
        return notices.contains { notice in
            warning == notice || UsageSource.allCases.contains { warning == "\($0.label): \(notice)" }
        }
    }
}
