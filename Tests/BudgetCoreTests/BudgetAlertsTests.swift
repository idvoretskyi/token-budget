import BudgetCore
import Foundation
import XCTest

final class BudgetAlertsTests: XCTestCase {
    private let now = fixtureDate("2024-02-15T12:00:00Z")

    private func settings() -> AppSettings {
        var settings = fixtureSettings()
        settings.notificationsEnabled = true
        return settings
    }

    private func summary(_ spent: Decimal, settings: AppSettings? = nil) throws -> BudgetSummary {
        let settings = settings ?? self.settings()
        var summary = try BudgetEngine.summarize(events: [], settings: settings, at: now)
        summary.spent = spent
        summary.remaining = settings.budget.amount - spent
        return summary
    }

    private func observe(_ policy: inout BudgetAlerts, _ spent: Decimal,
                         settings: AppSettings? = nil) throws -> [BudgetAlert] {
        let settings = settings ?? self.settings()
        return policy.observe(summary: try summary(spent, settings: settings), settings: settings,
                              canShowEstimate: true, successfulScan: true)
    }

    func testFirstHistoricalSummarySilentlyConsumesReachedThresholds() throws {
        for spent: Decimal in [0, 79, 80, 99, 100, 150] {
            var policy = BudgetAlerts()
            let baseline = try observe(&policy, spent)
            XCTAssertEqual(baseline.map(\.threshold), [80, 100].filter { spent >= Decimal($0) })
            XCTAssertTrue(baseline.allSatisfy { !$0.shouldNotify })
            XCTAssertTrue(try observe(&policy, spent).isEmpty)
            let later = try observe(&policy, 120)
            XCTAssertEqual(later.map(\.threshold), [80, 100].filter { spent < Decimal($0) })
            XCTAssertTrue(later.allSatisfy(\.shouldNotify))
        }
    }

    func testExactCrossingsAndRepeatedScansIncludingDownwardCorrections() throws {
        var policy = BudgetAlerts()
        XCTAssertTrue(try observe(&policy, Decimal(string: "79.999999999999")!).isEmpty)
        XCTAssertEqual(try observe(&policy, 80).map(\.threshold), [80])
        XCTAssertTrue(try observe(&policy, 80).isEmpty)
        XCTAssertTrue(try observe(&policy, 79).isEmpty)
        XCTAssertTrue(try observe(&policy, 90).isEmpty)
        let hundred = try observe(&policy, 100)
        XCTAssertEqual(hundred.map(\.threshold), [100])
        XCTAssertTrue(hundred.allSatisfy(\.shouldNotify))
        XCTAssertTrue(try observe(&policy, 120).isEmpty)
    }

    func testJumpAcrossBothThresholds() throws {
        var policy = BudgetAlerts()
        _ = try observe(&policy, 20)
        let alerts = try observe(&policy, 110)
        XCTAssertEqual(alerts.map(\.threshold), [80, 100])
        XCTAssertTrue(alerts.allSatisfy(\.shouldNotify))
    }

    func testDisabledSetupUnavailableUnpricedAndFailedScansNeverEstablishBaseline() throws {
        for mode in 0..<8 {
            var policy = BudgetAlerts()
            var settings = settings()
            var summary: BudgetSummary? = try self.summary(10)
            switch mode {
            case 0: settings.notificationsEnabled = false
            case 1: settings.enabledSources = []
            case 2: settings.selections = []
            case 3: summary = nil
            case 4: summary?.unpricedCount = 1
            case 5: summary?.spent = .nan
            default: break
            }
            XCTAssertTrue(policy.observe(summary: summary, settings: settings,
                                         canShowEstimate: mode != 6, successfulScan: mode != 7).isEmpty)
            let baseline = try observe(&policy, 110)
            XCTAssertEqual(baseline.map(\.threshold), [80, 100])
            XCTAssertTrue(baseline.allSatisfy { !$0.shouldNotify })
        }
    }

    func testImporterProblemsAndUnknownWarningsResetBaselineButDisclaimersAllowCrossings() throws {
        let informational = [
            "Full-period history has not been confirmed; recorded usage may be incomplete.",
            "OpenCode: Local usage records do not prove complete billing coverage.",
            "Codex CLI: Codex model attribution uses recorded turn configuration; actual backend reroutes may not be recorded.",
            "OpenCode: Only canonical OpenCode step-finish usage is imported; message and session totals are not added."
        ]
        var policy = BudgetAlerts()
        var initial = try summary(10)
        initial.warnings = informational
        XCTAssertTrue(policy.observe(summary: initial, settings: settings(),
                                     canShowEstimate: true, successfulScan: true).isEmpty)
        initial.spent = 80
        let crossing = policy.observe(summary: initial, settings: settings(),
                                      canShowEstimate: true, successfulScan: true)
        XCTAssertEqual(crossing.map(\.threshold), [80])
        XCTAssertTrue(crossing.allSatisfy(\.shouldNotify))

        for warning in ["OpenCode: Malformed or invalid usage records were skipped.",
                        "Codex CLI: Some usage sources were missing or inaccessible.",
                        "Codex CLI: An ambiguous cumulative snapshot was retained only as a baseline; usage was omitted.",
                        "OpenCode: No supported usage records were found.", "Unknown future warning"] {
            var policy = BudgetAlerts()
            _ = try observe(&policy, 10)
            var invalid = try summary(90)
            invalid.warnings = informational + [warning]
            XCTAssertTrue(policy.observe(summary: invalid, settings: settings(),
                                         canShowEstimate: true, successfulScan: true).isEmpty)
            XCTAssertTrue(try observe(&policy, 100).allSatisfy { !$0.shouldNotify })
        }
    }

    func testBudgetWindowSourceProfileAndToggleChangesEstablishNewBaseline() throws {
        for mode in 0..<8 {
            var policy = BudgetAlerts()
            _ = try observe(&policy, 10)
            var changed = settings()
            var changedSummary = try summary(220)
            switch mode {
            case 0: changed.budget.amount = 200
            case 1: changed.budget.currency = "EUR"
            case 2: changedSummary.window = DateInterval(start: fixtureDate("2024-03-01T00:00:00Z"),
                                                        end: fixtureDate("2024-04-01T00:00:00Z"))
            case 3: changed.openCodePath = "/synthetic/new-source"
            case 4: changed.prices[0].inputPerMillion = 3
            case 5: changed.selections[0].model = "other-synthetic-model"
            case 6: changed.enabledSources.append(.codex)
            default:
                changed.notificationsEnabled = false
                _ = try observe(&policy, 10, settings: changed)
                changed.notificationsEnabled = true
            }
            let baseline = policy.observe(summary: changedSummary, settings: changed,
                                          canShowEstimate: true, successfulScan: true)
            XCTAssertEqual(baseline.map(\.threshold), [80, 100])
            XCTAssertTrue(baseline.allSatisfy { !$0.shouldNotify })
        }
    }

    func testDurableKeysIncludeExactBudgetWindowCurrencyThresholdAndStableSelectionHash() throws {
        let original = settings()
        let window = try summary(0).window
        let key = BudgetAlerts.notificationKey(settings: original, window: window, threshold: 80)
        XCTAssertFalse(key.contains("synthetic-provider"))
        XCTAssertFalse(key.contains("synthetic-model"))
        for mode in 0..<11 {
            var changed = original
            var interval = window
            var threshold = 80
            switch mode {
            case 0: changed.budget.amount += Decimal(string: "0.000000000001")!
            case 1: changed.budget.currency = "EUR"
            case 2: changed.budget.period = .weekly
            case 3: changed.budget.timeZoneID = "Europe/London"
            case 4: changed.budget.weekday = 3
            case 5: changed.budget.hour = 1
            case 6: changed.budget.minute = 1
            case 7: interval = DateInterval(start: window.start.addingTimeInterval(0.001), end: window.end)
            case 8: changed.selections[0].model += "-other"
            case 9: changed.enabledSources.append(.codex)
            default: threshold = 100
            }
            XCTAssertNotEqual(key, BudgetAlerts.notificationKey(settings: changed, window: interval, threshold: threshold))
        }
        var reordered = original
        reordered.enabledSources = [.opencode, .codex]
        reordered.selections.append(.init(source: .codex, provider: "other", model: "model"))
        let orderedKey = BudgetAlerts.notificationKey(settings: reordered, window: window, threshold: 80)
        reordered.enabledSources.reverse()
        reordered.selections.reverse()
        XCTAssertEqual(orderedKey, BudgetAlerts.notificationKey(settings: reordered, window: window, threshold: 80))
        reordered.selections = []
        XCTAssertTrue(BudgetAlerts.notificationKey(settings: reordered, window: window, threshold: 80)
            .contains("16:cbf29ce484222325"))
        var pathsAndPrices = original
        pathsAndPrices.openCodePath = "/synthetic/changed"
        pathsAndPrices.prices[0].inputPerMillion = 2
        XCTAssertEqual(key, BudgetAlerts.notificationKey(settings: pathsAndPrices, window: window, threshold: 80))
    }

    @MainActor
    func testDuplicateImportsAndPersistentThresholdRecordsAcrossRestart() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("alerts.sqlite")
        let settings = settings()
        var policy = BudgetAlerts()
        let ledger = try Ledger(url: url)
        let event = fixtureEvent(tokens: .init(input: 80_000_000))
        try await ledger.merge([event, event])
        try await ledger.merge([event])
        let events = try await ledger.events()
        let summary = try BudgetEngine.summarize(events: events, settings: settings, at: now)
        XCTAssertEqual(summary.spent, 80)
        let baseline = policy.observe(summary: summary, settings: settings,
                                      canShowEstimate: true, successfulScan: true)
        XCTAssertEqual(baseline.count, 1)
        XCTAssertFalse(try XCTUnwrap(baseline.first).shouldNotify)
        for alert in baseline {
            try await ledger.recordNotification(key: alert.key)
            try await ledger.recordNotification(key: alert.key)
        }
        XCTAssertTrue(policy.observe(summary: summary, settings: settings,
                                     canShowEstimate: true, successfulScan: true).isEmpty)
        let reopened = try Ledger(url: url)
        var restarted = BudgetAlerts()
        _ = try observe(&restarted, 10)
        let crossings = try observe(&restarted, 100)
        for alert in crossings {
            let recorded = try await reopened.notificationRecorded(key: alert.key)
            XCTAssertEqual(recorded, alert.threshold == 80)
        }
    }
}
