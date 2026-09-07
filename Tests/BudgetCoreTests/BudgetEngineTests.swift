import BudgetCore
import Foundation
import XCTest

func fixtureDate(_ value: String) -> Date {
    // Fixtures deliberately use explicit UTC instants, never the machine's zone.
    ISO8601DateFormatter().date(from: value)!
}

func fixtureEvent(id: String = "synthetic-event", source: UsageSource = .opencode,
                  at timestamp: Date = fixtureDate("2024-02-02T00:00:00Z"),
                  tokens: TokenCounts = .init(input: 1_000_000)) -> UsageEvent {
    UsageEvent(id: id, source: source, timestamp: timestamp,
               provider: "synthetic-provider", model: "synthetic-model", tokens: tokens)
}

func fixturePrice(id: String = "synthetic-price", source: UsageSource = .opencode,
                  currency: String = "USD",
                  from date: Date = fixtureDate("2024-01-01T00:00:00Z"),
                  input: Decimal = 1, cacheRead: Decimal = 0,
                  cacheWrite: Decimal = 0, output: Decimal = 0) -> PriceProfile {
    PriceProfile(id: id, source: source, provider: "synthetic-provider", model: "synthetic-model",
                 currency: currency, effectiveFrom: date, inputPerMillion: input,
                 cacheReadPerMillion: cacheRead, cacheWritePerMillion: cacheWrite,
                 outputPerMillion: output, provenance: "Synthetic test rates, not vendor pricing")
}

func fixtureSettings() -> AppSettings {
    AppSettings(budget: .init(amount: 100, timeZoneID: "UTC"), enabledSources: [.opencode],
                selections: [.init(source: .opencode, provider: "synthetic-provider", model: "synthetic-model")],
                prices: [fixturePrice()], coverageStart: fixtureDate("2024-02-01T00:00:00Z"))
}

final class BudgetEngineTests: XCTestCase {
    private let now = fixtureDate("2024-02-15T12:00:00Z")

    func testAllDisjointTokenCategoriesUseExactDecimalPrices() throws {
        var settings = fixtureSettings()
        settings.prices = [fixturePrice(input: Decimal(string: "0.1")!, cacheRead: Decimal(string: "0.2")!,
                                        cacheWrite: Decimal(string: "0.3")!, output: Decimal(string: "0.4")!)]
        let event = fixtureEvent(tokens: .init(input: 1, cacheRead: 2, cacheWrite: 3, output: 4))
        let summary = try BudgetEngine.summarize(events: [event], settings: settings, at: now)
        XCTAssertEqual(summary.spent, Decimal(string: "0.000003")!)
        XCTAssertEqual(summary.remaining, Decimal(string: "99.999997")!)
        XCTAssertEqual(summary.bySource, [.opencode: Decimal(string: "0.000003")!])
        XCTAssertEqual(summary.unpricedCount, 0)
        XCTAssertTrue(summary.warnings.isEmpty)
    }

    func testRepeatedFractionalChargesDoNotAccumulateBinaryRoundingError() throws {
        var settings = fixtureSettings()
        settings.prices = [fixturePrice(input: Decimal(string: "0.1")!)]
        let events = (0..<10).map { fixtureEvent(id: "synthetic-\($0)") }
        XCTAssertEqual(try BudgetEngine.summarize(events: events, settings: settings, at: now).spent, 1)
    }

    func testLargeTokenCountsAreNotSummedUsingInt64Arithmetic() throws {
        var settings = fixtureSettings()
        settings.prices = [fixturePrice(input: 1, cacheRead: 1, cacheWrite: 1, output: 1)]
        let event = fixtureEvent(tokens: .init(input: .max, cacheRead: .max, cacheWrite: .max, output: .max))
        let summary = try BudgetEngine.summarize(events: [event], settings: settings, at: now)
        XCTAssertEqual(summary.spent, Decimal(string: "36893488147419.103228")!)
        XCTAssertLessThan(summary.remaining, 0)
    }

    func testMissingPriceIsUnpricedButExplicitZeroPriceIsKnown() throws {
        var settings = fixtureSettings()
        settings.prices = []
        let missing = try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now)
        XCTAssertEqual(missing.spent, 0)
        XCTAssertEqual(missing.unpricedCount, 1)
        XCTAssertTrue(missing.bySource.isEmpty)
        XCTAssertEqual(missing.warnings, ["Some selected usage is unpriced. This is a priced subtotal."])
        XCTAssertNil(missing.forecast)

        settings.prices = [fixturePrice(input: 0)]
        let zero = try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now)
        XCTAssertEqual(zero.spent, 0)
        XCTAssertEqual(zero.bySource, [.opencode: 0])
        XCTAssertEqual(zero.unpricedCount, 0)
        XCTAssertTrue(zero.warnings.isEmpty)
        XCTAssertEqual(zero.forecast, 0)
    }

    func testLatestEffectivePriceIsInclusiveAndIndependentOfInputOrder() throws {
        let change = fixtureDate("2024-02-10T00:00:00Z")
        let prices = [fixturePrice(id: "new", from: change, input: 3),
                      fixturePrice(id: "future", from: now.addingTimeInterval(1), input: 99),
                      fixturePrice(id: "old", input: 1)]
        let events = [fixtureEvent(id: "before", at: change.addingTimeInterval(-0.25)),
                      fixtureEvent(id: "exact", at: change),
                      fixtureEvent(id: "after", at: change.addingTimeInterval(0.25))]
        for ordered in [prices, Array(prices.reversed())] {
            var settings = fixtureSettings()
            settings.prices = ordered
            XCTAssertEqual(try BudgetEngine.summarize(events: events, settings: settings, at: now).spent, 7)
        }
    }

    func testFutureOnlyPriceDoesNotBackfillEarlierUsage() throws {
        var settings = fixtureSettings()
        settings.prices = [fixturePrice(from: now)]
        let summary = try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now)
        XCTAssertEqual(summary.unpricedCount, 1)
        XCTAssertEqual(summary.spent, 0)
    }

    func testCurrencyIsMatchedWithoutConversionOrFallback() throws {
        var settings = fixtureSettings()
        settings.prices = [fixturePrice(id: "eur", currency: "EUR", input: 90), fixturePrice(input: 2)]
        XCTAssertEqual(try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now).spent, 2)
        settings.budget.currency = "EUR"
        XCTAssertEqual(try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now).spent, 90)
        settings.budget.currency = "GBP"
        let summary = try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now)
        XCTAssertEqual(summary.unpricedCount, 1)
        XCTAssertEqual(summary.spent, 0)
    }

    func testSelectionsRequireExactSourceProviderAndModelAndEnabledSource() throws {
        let selected = fixtureEvent()
        var provider = fixtureEvent(id: "other-provider")
        provider.provider = "Synthetic-provider"
        var model = fixtureEvent(id: "other-model")
        model.model = "synthetic-model-extra"
        let codex = fixtureEvent(source: .codex)
        let events = [selected, provider, model, codex]
        var settings = fixtureSettings()
        settings.enabledSources = [.opencode, .codex]
        settings.prices.append(fixturePrice(id: "codex", source: .codex, input: 4))
        let selection = settings.selections[0]
        XCTAssertTrue(selection.matches(selected))
        for other in [provider, model, codex] { XCTAssertFalse(selection.matches(other)) }
        XCTAssertEqual(try BudgetEngine.summarize(events: events, settings: settings, at: now).spent, 1)

        settings.selections.append(.init(source: .codex, provider: codex.provider, model: codex.model))
        let both = try BudgetEngine.summarize(events: events, settings: settings, at: now)
        XCTAssertEqual(both.spent, 5)
        XCTAssertEqual(both.bySource, [.opencode: 1, .codex: 4])
        XCTAssertEqual(both.unpricedCount, 0)
        settings.enabledSources = [.opencode]
        XCTAssertEqual(try BudgetEngine.summarize(events: events, settings: settings, at: now).spent, 1)
    }

    func testPricesAlsoRequireExactSourceProviderAndModel() throws {
        var wrongProvider = fixturePrice(id: "provider")
        wrongProvider.provider = "other-provider"
        var wrongModel = fixturePrice(id: "model")
        wrongModel.model = "other-model"
        var settings = fixtureSettings()
        settings.prices = [wrongProvider, wrongModel, fixturePrice(source: .codex)]
        XCTAssertEqual(try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now).unpricedCount, 1)
    }

    func testSummaryIncludesWindowStartAndNowButExcludesEndAndFuture() throws {
        let start = fixtureDate("2024-02-01T00:00:00Z")
        let end = fixtureDate("2024-03-01T00:00:00Z")
        let events = [fixtureEvent(id: "previous", at: start.addingTimeInterval(-0.25)),
                      fixtureEvent(id: "start", at: start), fixtureEvent(id: "now", at: now),
                      fixtureEvent(id: "future", at: now.addingTimeInterval(0.25)),
                      fixtureEvent(id: "end", at: end)]
        let summary = try BudgetEngine.summarize(events: events, settings: fixtureSettings(), at: now)
        XCTAssertEqual(summary.spent, 2)
        XCTAssertEqual(summary.window, DateInterval(start: start, end: end))
    }

    func testDuplicateIdentityWithinSourceIsRejectedButCrossSourceIdentityIsAllowed() throws {
        let event = fixtureEvent()
        XCTAssertThrowsError(try BudgetEngine.summarize(events: [event, event], settings: fixtureSettings(), at: now)) {
            XCTAssertEqual($0 as? BudgetError, .invalidUsage)
        }
        var settings = fixtureSettings()
        settings.enabledSources.append(.codex)
        settings.selections.append(.init(source: .codex, provider: event.provider, model: event.model))
        settings.prices.append(fixturePrice(source: .codex))
        XCTAssertEqual(try BudgetEngine.summarize(events: [event, fixtureEvent(source: .codex)],
                                                 settings: settings, at: now).spent, 2)
    }

    func testInvalidUsageIsRejectedEvenWhenOutsideSelection() throws {
        let invalidTokens: [TokenCounts] = [.init(input: -1), .init(cacheRead: -1),
                                           .init(cacheWrite: -1), .init(output: -1)]
        for tokens in invalidTokens {
            XCTAssertFalse(tokens.isValid)
            let event = fixtureEvent(source: .codex, tokens: tokens)
            XCTAssertThrowsError(try BudgetEngine.summarize(events: [event], settings: fixtureSettings(), at: now)) {
                XCTAssertEqual($0 as? BudgetError, .invalidUsage)
            }
        }
        for value in [Double.nan, .infinity, -.infinity] {
            let event = fixtureEvent(at: Date(timeIntervalSince1970: value))
            XCTAssertThrowsError(try BudgetEngine.summarize(events: [event], settings: fixtureSettings(), at: now)) {
                XCTAssertEqual($0 as? BudgetError, .invalidUsage)
            }
        }
        XCTAssertTrue(TokenCounts().isValid)
        XCTAssertTrue(TokenCounts().isEmpty)
        XCTAssertFalse(TokenCounts(cacheWrite: 1).isEmpty)
    }

    func testForecastRequiresConfirmedFullPeriodAndAtLeastOneDay() throws {
        let start = fixtureDate("2024-02-01T00:00:00Z")
        let day = start.addingTimeInterval(86_400)
        let events = [fixtureEvent(at: start)]
        var settings = fixtureSettings()
        XCTAssertNil(try BudgetEngine.summarize(events: events, settings: settings, at: day.addingTimeInterval(-0.25)).forecast)
        XCTAssertEqual(try BudgetEngine.summarize(events: events, settings: settings, at: day).forecast, 29)
        settings.coverageStart = start.addingTimeInterval(-1)
        XCTAssertEqual(try BudgetEngine.summarize(events: events, settings: settings, at: day).forecast, 29)
        for coverage in [nil, start.addingTimeInterval(0.25), day] as [Date?] {
            settings.coverageStart = coverage
            let summary = try BudgetEngine.summarize(events: events, settings: settings, at: day)
            XCTAssertNil(summary.forecast)
            XCTAssertEqual(summary.warnings, ["Full-period history has not been confirmed; recorded usage may be incomplete."])
        }
    }

    func testInformationalNoticesRemainVisibleWithoutSuppressingConfirmedForecast() throws {
        let notices = ["OpenCode: Local usage records do not prove complete billing coverage.",
                       "OpenCode: Only canonical OpenCode step-finish usage is imported; message and session totals are not added."]
        let result = try BudgetEngine.summarize(events: [fixtureEvent()], settings: fixtureSettings(), at: now, warnings: notices)
        XCTAssertNotNil(result.forecast)
        XCTAssertEqual(result.warnings, notices.sorted())
        let blocked = try BudgetEngine.summarize(events: [fixtureEvent()], settings: fixtureSettings(), at: now,
                                                warnings: notices + ["OpenCode: Malformed or invalid usage records were skipped."])
        XCTAssertNil(blocked.forecast)
    }

    func testImportProblemSuppressesForecastAndWarningsAreSortedAndDeduplicated() throws {
        let warnings = ["Synthetic warning Z", "Synthetic warning A", "Synthetic warning Z"]
        let summary = try BudgetEngine.summarize(events: [fixtureEvent()], settings: fixtureSettings(), at: now, warnings: warnings)
        XCTAssertNil(summary.forecast)
        XCTAssertEqual(summary.warnings, ["Synthetic warning A", "Synthetic warning Z"])
        var settings = fixtureSettings()
        settings.prices = []
        settings.coverageStart = nil
        let combined = try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now,
                                                 warnings: ["Some selected usage is unpriced. This is a priced subtotal."])
        XCTAssertEqual(combined.warnings.count, 2)
        XCTAssertEqual(combined.warnings, combined.warnings.sorted())
        XCTAssertNil(combined.forecast)
    }

    func testEmptyScopeWarnsWhileConfirmedEmptyUsageCanForecastZero() throws {
        let empty = try BudgetEngine.summarize(events: [], settings: fixtureSettings(), at: now)
        XCTAssertTrue(empty.warnings.isEmpty)
        XCTAssertEqual(empty.forecast, 0)
        for clearSources in [true, false] {
            var settings = fixtureSettings()
            if clearSources { settings.enabledSources = [] } else { settings.selections = [] }
            let summary = try BudgetEngine.summarize(events: [fixtureEvent()], settings: settings, at: now)
            XCTAssertEqual(summary.spent, 0)
            XCTAssertEqual(summary.unpricedCount, 0)
            XCTAssertEqual(summary.warnings, ["Choose sources and models before interpreting the estimate."])
            XCTAssertNil(summary.forecast)
        }
    }

    func testForecastUsesActualDSTWindowDuration() throws {
        var settings = fixtureSettings()
        settings.budget = .init(period: .weekly, timeZoneID: "America/New_York", weekday: 2)
        let start = fixtureDate("2024-03-04T05:00:00Z")
        settings.coverageStart = start
        let summary = try BudgetEngine.summarize(events: [fixtureEvent(at: start)], settings: settings,
                                                 at: start.addingTimeInterval(86_400))
        XCTAssertEqual(summary.window.duration, 167 * 3_600)
        XCTAssertEqual(summary.forecast, Decimal(167) / 24)
    }
}
