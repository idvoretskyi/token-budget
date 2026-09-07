import BudgetCore
import Foundation
import XCTest

func fixtureDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("budget-core-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

final class SettingsStoreTests: XCTestCase {
    func testRoundTripPreservesEverySettingAndPrivatePermissions() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        var settings = fixtureSettings()
        settings.budget = .init(amount: Decimal(string: "123.456789")!, currency: "EUR", period: .weekly,
                                timeZoneID: "America/New_York", weekday: 6, hour: 17, minute: 45)
        settings.openCodePath = "/synthetic/opencode"
        settings.codexPath = "/synthetic/codex"
        settings.enabledSources = [.codex, .opencode]
        settings.selections.append(.init(source: .codex, provider: "synthetic-provider", model: "synthetic-model"))
        settings.notificationsEnabled = true
        settings.coverageStart = fixtureDate("2024-02-01T00:00:00Z").addingTimeInterval(0.125)
        settings.prices = [fixturePrice(currency: "EUR", input: Decimal(string: "0.123456789")!,
                                        cacheRead: Decimal(string: "0.01")!, cacheWrite: 2, output: 3)]
        try SettingsStore.save(settings, to: url)
        XCTAssertEqual(try SettingsStore.load(from: url), settings)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        settings.notificationsEnabled = false
        settings.coverageStart = nil
        try SettingsStore.save(settings, to: url)
        XCTAssertEqual(try SettingsStore.load(from: url), settings)
        let replacedPermissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(replacedPermissions?.intValue, 0o600)
    }

    func testInvalidSavePreservesExistingFileAndDoesNotCreateNewFile() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let original = fixtureSettings()
        try SettingsStore.save(original, to: url)
        let bytes = try Data(contentsOf: url)
        var invalid = original
        invalid.budget.amount = -1
        XCTAssertThrowsError(try SettingsStore.save(invalid, to: url)) {
            XCTAssertEqual($0 as? BudgetError, .invalidConfiguration)
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try SettingsStore.load(from: url), original)
        let missing = directory.appendingPathComponent("not-created.json")
        XCTAssertThrowsError(try SettingsStore.save(invalid, to: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testLoadRejectsMissingMalformedAndSemanticallyInvalidSettings() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        XCTAssertThrowsError(try SettingsStore.load(from: url))
        for content in ["{", "{}", "null", "[]"] {
            try Data(content.utf8).write(to: url)
            XCTAssertThrowsError(try SettingsStore.load(from: url))
        }
        var invalid = fixtureSettings()
        invalid.budget.currency = "INVALID"
        try JSONEncoder().encode(invalid).write(to: url)
        XCTAssertThrowsError(try SettingsStore.load(from: url)) {
            XCTAssertEqual($0 as? BudgetError, .invalidConfiguration)
        }
        invalid = fixtureSettings()
        invalid.prices[0].inputPerMillion = -1
        try JSONEncoder().encode(invalid).write(to: url)
        XCTAssertThrowsError(try SettingsStore.load(from: url)) {
            XCTAssertEqual($0 as? BudgetError, .invalidPrice)
        }
    }

    func testSettingsValidationRejectsDuplicateScopesAndNonfiniteCoverage() throws {
        var settings = fixtureSettings()
        settings.enabledSources.append(.opencode)
        XCTAssertThrowsError(try BudgetEngine.validate(settings)) { XCTAssertEqual($0 as? BudgetError, .invalidConfiguration) }
        settings = fixtureSettings()
        settings.selections.append(settings.selections[0])
        XCTAssertThrowsError(try BudgetEngine.validate(settings)) { XCTAssertEqual($0 as? BudgetError, .invalidConfiguration) }
        for value in [Double.nan, .infinity, -.infinity] {
            settings = fixtureSettings()
            settings.coverageStart = Date(timeIntervalSince1970: value)
            XCTAssertThrowsError(try BudgetEngine.validate(settings)) { XCTAssertEqual($0 as? BudgetError, .invalidConfiguration) }
        }
    }

    func testPriceValidationRejectsEveryInvalidRateAndRequiredMetadata() throws {
        let rates: [WritableKeyPath<PriceProfile, Decimal>] = [\.inputPerMillion, \.cacheReadPerMillion,
                                                             \.cacheWritePerMillion, \.outputPerMillion]
        for key in rates {
            for value in [Decimal(-1), .nan, Decimal(1_000_000_001)] {
                var settings = fixtureSettings()
                settings.prices[0][keyPath: key] = value
                XCTAssertThrowsError(try BudgetEngine.validate(settings)) { XCTAssertEqual($0 as? BudgetError, .invalidPrice) }
            }
            for value in [Decimal(0), Decimal(1_000_000_000)] {
                var settings = fixtureSettings()
                settings.prices[0][keyPath: key] = value
                XCTAssertNoThrow(try BudgetEngine.validate(settings))
            }
        }
        let mutations: [(inout PriceProfile) -> Void] = [
            { $0.id = "" }, { $0.provider = "" }, { $0.model = "" },
            { $0.provenance = " \n\t" }, { $0.currency = "usd" },
            { $0.effectiveFrom = Date(timeIntervalSince1970: .nan) },
            { $0.effectiveFrom = Date(timeIntervalSince1970: .infinity) }
        ]
        for mutate in mutations {
            var settings = fixtureSettings()
            mutate(&settings.prices[0])
            XCTAssertThrowsError(try BudgetEngine.validate(settings)) { XCTAssertEqual($0 as? BudgetError, .invalidPrice) }
        }
    }

    func testDuplicatePriceScopeCurrencyAndInstantAreRejectedRegardlessOfID() throws {
        var settings = fixtureSettings()
        settings.prices.append(fixturePrice(id: "different-id", input: 2))
        XCTAssertThrowsError(try BudgetEngine.validate(settings)) { XCTAssertEqual($0 as? BudgetError, .invalidPrice) }
        settings.prices[1].effectiveFrom.addTimeInterval(0.125)
        XCTAssertNoThrow(try BudgetEngine.validate(settings))
        settings.prices[1] = fixturePrice(id: "eur", currency: "EUR")
        XCTAssertNoThrow(try BudgetEngine.validate(settings))
        settings.prices[1] = fixturePrice(id: "codex", source: .codex)
        XCTAssertNoThrow(try BudgetEngine.validate(settings))
    }
}
