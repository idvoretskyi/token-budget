import Foundation

public enum UsageSource: String, Codable, CaseIterable, Sendable {
    case opencode, codex
    public var label: String { self == .opencode ? "OpenCode" : "Codex CLI" }
}

/// Disjoint billable categories. Adapters normalize provider-specific subsets.
public struct TokenCounts: Codable, Equatable, Sendable {
    public var input: Int64
    public var cacheRead: Int64
    public var cacheWrite: Int64
    public var output: Int64
    public init(input: Int64 = 0, cacheRead: Int64 = 0, cacheWrite: Int64 = 0, output: Int64 = 0) {
        self.input = input; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite; self.output = output
    }
    public var isValid: Bool { [input, cacheRead, cacheWrite, output].allSatisfy { $0 >= 0 } }
    public var isEmpty: Bool { input == 0 && cacheRead == 0 && cacheWrite == 0 && output == 0 }
}

public struct UsageEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: UsageSource
    public var timestamp: Date
    public var provider: String
    public var model: String
    public var tokens: TokenCounts
    public init(id: String, source: UsageSource, timestamp: Date, provider: String, model: String, tokens: TokenCounts) {
        self.id = id; self.source = source; self.timestamp = timestamp
        self.provider = provider; self.model = model; self.tokens = tokens
    }
}

public struct ImportReport: Sendable {
    public var events: [UsageEvent]
    /// Static, public-safe messages only: never raw records, identifiers or paths.
    public var warnings: [String]
    public var scannedRecords: Int
    public init(events: [UsageEvent] = [], warnings: [String] = [], scannedRecords: Int = 0) {
        self.events = events; self.warnings = warnings; self.scannedRecords = scannedRecords
    }
}

public struct PriceProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: UsageSource
    public var provider: String
    public var model: String
    public var currency: String
    public var effectiveFrom: Date
    public var inputPerMillion: Decimal
    public var cacheReadPerMillion: Decimal
    public var cacheWritePerMillion: Decimal
    public var outputPerMillion: Decimal
    public var provenance: String
    public init(id: String = UUID().uuidString, source: UsageSource, provider: String, model: String,
                currency: String = "USD", effectiveFrom: Date, inputPerMillion: Decimal,
                cacheReadPerMillion: Decimal, cacheWritePerMillion: Decimal, outputPerMillion: Decimal,
                provenance: String) {
        self.id = id; self.source = source; self.provider = provider; self.model = model
        self.currency = currency; self.effectiveFrom = effectiveFrom; self.inputPerMillion = inputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion; self.cacheWritePerMillion = cacheWritePerMillion
        self.outputPerMillion = outputPerMillion; self.provenance = provenance
    }
}

public struct UsageSelection: Codable, Equatable, Hashable, Sendable {
    public var source: UsageSource
    public var provider: String
    public var model: String
    public init(source: UsageSource, provider: String, model: String) {
        self.source = source; self.provider = provider; self.model = model
    }
    public func matches(_ event: UsageEvent) -> Bool {
        event.source == source && event.provider == provider && event.model == model
    }
}

public enum BudgetPeriod: String, Codable, CaseIterable, Sendable { case weekly, monthly }

public struct BudgetConfiguration: Codable, Equatable, Sendable {
    public var amount: Decimal
    public var currency: String
    public var period: BudgetPeriod
    public var timeZoneID: String
    /// Foundation weekday: Sunday = 1, Monday = 2.
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public init(amount: Decimal = 100, currency: String = "USD", period: BudgetPeriod = .monthly,
                timeZoneID: String = "UTC", weekday: Int = 2, hour: Int = 0, minute: Int = 0) {
        self.amount = amount; self.currency = currency; self.period = period
        self.timeZoneID = timeZoneID; self.weekday = weekday; self.hour = hour; self.minute = minute
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var budget: BudgetConfiguration
    public var openCodePath: String
    public var codexPath: String
    public var enabledSources: [UsageSource]
    public var selections: [UsageSelection]
    public var prices: [PriceProfile]
    public var notificationsEnabled: Bool
    /// User-confirmed coverage start. Logs alone cannot prove complete history.
    public var coverageStart: Date?
    public init(budget: BudgetConfiguration = .init(), openCodePath: String = "", codexPath: String = "",
                enabledSources: [UsageSource] = [], selections: [UsageSelection] = [],
                prices: [PriceProfile] = [], notificationsEnabled: Bool = false, coverageStart: Date? = nil) {
        self.budget = budget; self.openCodePath = openCodePath; self.codexPath = codexPath
        self.enabledSources = enabledSources; self.selections = selections; self.prices = prices
        self.notificationsEnabled = notificationsEnabled; self.coverageStart = coverageStart
    }
}
