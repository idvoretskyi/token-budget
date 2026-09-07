import Foundation

public enum BudgetError: Error, Equatable {
    case invalidConfiguration, invalidPrice, invalidUsage, storage, unsupportedStorageVersion
}

public struct BudgetSummary: Sendable {
    public var window: DateInterval
    public var spent: Decimal
    public var remaining: Decimal
    public var bySource: [UsageSource: Decimal]
    public var unpricedCount: Int
    public var warnings: [String]
    public var forecast: Decimal?
}

public enum BudgetEngine {
    public static func window(for configuration: BudgetConfiguration, at now: Date) throws -> DateInterval {
        guard !configuration.amount.isNaN, configuration.amount > 0,
              Locale.commonISOCurrencyCodes.contains(configuration.currency),
              let zone = TimeZone(identifier: configuration.timeZoneID),
              (1...7).contains(configuration.weekday), (0...23).contains(configuration.hour),
              (0...59).contains(configuration.minute), now.timeIntervalSince1970.isFinite else {
            throw BudgetError.invalidConfiguration
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        let match = DateComponents(hour: configuration.hour, minute: configuration.minute, second: 0)
        // Resolve each candidate civil day forwards, consistently choosing the first
        // repeated time and next valid skipped time. Backward matching varies across
        // Foundation implementations near DST folds and monthly boundaries.
        let boundaries: [Date] = (-40...40).compactMap { offset in
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let day = calendar.startOfDay(for: candidate)
            let matchesDay = configuration.period == .weekly
                ? calendar.component(.weekday, from: day) == configuration.weekday
                : calendar.component(.day, from: day) == 1
            guard matchesDay else { return nil }
            return calendar.nextDate(after: day.addingTimeInterval(-1), matching: match,
                                     matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        }
        guard let start = boundaries.filter({ $0 <= now }).max(),
              let end = boundaries.filter({ $0 > now }).min() else { throw BudgetError.invalidConfiguration }
        return DateInterval(start: start, end: end)
    }

    public static func validate(_ settings: AppSettings) throws {
        _ = try window(for: settings.budget, at: Date())
        guard Set(settings.enabledSources).count == settings.enabledSources.count,
              Set(settings.selections).count == settings.selections.count,
              settings.coverageStart?.timeIntervalSince1970.isFinite != false else {
            throw BudgetError.invalidConfiguration
        }
        var keys = Set<String>()
        for price in settings.prices {
            let rates = [price.inputPerMillion, price.cacheReadPerMillion,
                         price.cacheWritePerMillion, price.outputPerMillion]
            guard rates.allSatisfy({ !$0.isNaN && $0 >= 0 && $0 <= Decimal(1_000_000_000) }),
                  !price.provider.isEmpty, !price.model.isEmpty, !price.id.isEmpty,
                  !price.provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Locale.commonISOCurrencyCodes.contains(price.currency),
                  price.effectiveFrom.timeIntervalSince1970.isFinite else { throw BudgetError.invalidPrice }
            // Same scope/currency/effective instant would make price selection nondeterministic.
            let key = [price.source.rawValue, price.provider, price.model, price.currency,
                       String(price.effectiveFrom.timeIntervalSince1970)].joined(separator: "\u{0}")
            guard keys.insert(key).inserted else { throw BudgetError.invalidPrice }
        }
    }

    public static func summarize(events: [UsageEvent], settings: AppSettings, at now: Date,
                                 warnings: [String] = []) throws -> BudgetSummary {
        try validate(settings)
        let interval = try window(for: settings.budget, at: now)
        var spent: Decimal = 0
        var totals: [UsageSource: Decimal] = [:]
        var unpriced = 0
        var messages = warnings
        var seen = Set<String>()
        for event in events {
            guard event.tokens.isValid, event.timestamp.timeIntervalSince1970.isFinite else {
                throw BudgetError.invalidUsage
            }
            guard settings.enabledSources.contains(event.source),
                  event.timestamp >= interval.start, event.timestamp < interval.end,
                  event.timestamp <= now else { continue }
            guard settings.selections.contains(where: { $0.matches(event) }) else { continue }
            guard seen.insert(event.source.rawValue + "\u{0}" + event.id).inserted else {
                throw BudgetError.invalidUsage
            }
            let price = settings.prices.filter {
                $0.source == event.source && $0.provider == event.provider && $0.model == event.model &&
                $0.currency == settings.budget.currency && $0.effectiveFrom <= event.timestamp
            }.max { $0.effectiveFrom < $1.effectiveFrom }
            guard let price else { unpriced += 1; continue }
            let cost = (Decimal(event.tokens.input) * price.inputPerMillion +
                        Decimal(event.tokens.cacheRead) * price.cacheReadPerMillion +
                        Decimal(event.tokens.cacheWrite) * price.cacheWritePerMillion +
                        Decimal(event.tokens.output) * price.outputPerMillion) / 1_000_000
            guard !cost.isNaN else { throw BudgetError.invalidPrice }
            spent += cost
            totals[event.source, default: 0] += cost
        }
        if settings.enabledSources.isEmpty || settings.selections.isEmpty {
            messages.append("Choose sources and models before interpreting the estimate.")
        }
        if unpriced > 0 { messages.append("Some selected usage is unpriced. This is a priced subtotal.") }
        let historyComplete = settings.coverageStart.map { $0 <= interval.start } ?? false
        if !historyComplete { messages.append("Full-period history has not been confirmed; recorded usage may be incomplete.") }
        let elapsed = now.timeIntervalSince(interval.start)
        let forecast: Decimal? = historyComplete && messages.allSatisfy(UsageCoverage.isInformationalWarning) && elapsed >= 86_400
            ? spent * Decimal(interval.duration) / Decimal(elapsed) : nil
        return BudgetSummary(window: interval, spent: spent, remaining: settings.budget.amount - spent,
                             bySource: totals, unpricedCount: unpriced,
                             warnings: Array(Set(messages)).sorted(), forecast: forecast)
    }
}
