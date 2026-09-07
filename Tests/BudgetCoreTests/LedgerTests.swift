import BudgetCore
import Foundation
import XCTest
#if canImport(CSQLite)
import CSQLite
#endif

@MainActor
final class LedgerTests: XCTestCase {
    func testMergeIsIdempotentAndMutationReplacesEntirePayload() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try Ledger(url: directory.appendingPathComponent("ledger.sqlite"))
        let original = fixtureEvent()
        try await ledger.merge([original, original])
        try await ledger.merge([original])
        let first = try await ledger.events()
        XCTAssertEqual(first, [original])

        var replacement = original
        replacement.provider = "replacement-provider"
        replacement.model = "replacement-model"
        replacement.timestamp.addTimeInterval(0.125)
        replacement.tokens = .init(input: 7, cacheRead: 6, cacheWrite: 5, output: 4)
        try await ledger.merge([replacement])
        try await ledger.merge([])
        let updated = try await ledger.events()
        XCTAssertEqual(updated, [replacement])
    }

    func testSameIdentityAcrossSourcesIsIsolatedAndResultsAreDeterministicallyOrdered() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try Ledger(url: directory.appendingPathComponent("ledger.sqlite"))
        let openCode = fixtureEvent(id: "same")
        let codex = fixtureEvent(id: "same", source: .codex)
        let earlier = fixtureEvent(id: "aaa", source: .codex)
        try await ledger.merge([openCode, codex, earlier])
        let events = try await ledger.events()
        XCTAssertEqual(events, [earlier, codex, openCode])
        var changed = codex
        changed.tokens.input = 17
        try await ledger.merge([changed])
        let updated = try await ledger.events()
        XCTAssertEqual(updated, [earlier, changed, openCode])
    }

    func testInvalidBatchRollsBackBothEarlierInsertAndMutationAndConnectionRemainsUsable() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.sqlite")
        let ledger = try Ledger(url: url)
        let original = fixtureEvent()
        try await ledger.merge([original])
        var changed = original
        changed.tokens.input = 9
        let inserted = fixtureEvent(id: "new")
        var emptyID = fixtureEvent(id: "")
        emptyID.tokens = .init()
        let invalidEvents = [emptyID, fixtureEvent(tokens: .init(input: -1)),
                             fixtureEvent(tokens: .init(cacheRead: -1)),
                             fixtureEvent(tokens: .init(cacheWrite: -1)),
                             fixtureEvent(tokens: .init(output: -1)),
                             fixtureEvent(at: Date(timeIntervalSince1970: .nan)),
                             fixtureEvent(at: Date(timeIntervalSince1970: .infinity))]
        for invalid in invalidEvents {
            do {
                try await ledger.merge([changed, inserted, invalid])
                XCTFail("An invalid batch must fail")
            } catch {
                XCTAssertEqual(error as? BudgetError, .invalidUsage)
            }
            let events = try await ledger.events()
            XCTAssertEqual(events, [original])
            let reopened = try Ledger(url: url)
            let persisted = try await reopened.events()
            XCTAssertEqual(persisted, [original])
        }
        try await ledger.merge([inserted])
        let recovered = try await ledger.events()
        XCTAssertEqual(recovered, [inserted, original])
    }

    func testRestartPreservesUsageNotificationsAndRestrictivePermissions() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.sqlite")
        let event = fixtureEvent(tokens: .init(input: .max, cacheRead: 4, cacheWrite: 3, output: 2))
        do {
            let ledger = try Ledger(url: url)
            try await ledger.merge([event])
            let absent = try await ledger.notificationRecorded(key: "synthetic-period-50")
            XCTAssertFalse(absent)
            try await ledger.recordNotification(key: "synthetic-period-50")
            try await ledger.recordNotification(key: "synthetic-period-50")
        }
        let reopened = try Ledger(url: url)
        let persisted = try await reopened.events()
        XCTAssertEqual(persisted, [event])
        let recorded = try await reopened.notificationRecorded(key: "synthetic-period-50")
        let nextThreshold = try await reopened.notificationRecorded(key: "synthetic-period-100")
        XCTAssertTrue(recorded)
        XCTAssertFalse(nextThreshold)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testSeparateDatabasesDoNotShareUsageOrNotificationState() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try Ledger(url: directory.appendingPathComponent("first.sqlite"))
        let second = try Ledger(url: directory.appendingPathComponent("second.sqlite"))
        try await first.merge([fixtureEvent()])
        try await first.recordNotification(key: "synthetic-key")
        let events = try await second.events()
        let recorded = try await second.notificationRecorded(key: "synthetic-key")
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(recorded)
    }

    func testConcurrentActorMergesPreserveAllDistinctEvents() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try Ledger(url: directory.appendingPathComponent("ledger.sqlite"))
        let expected = (0..<20).map { fixtureEvent(id: String(format: "synthetic-%02d", $0)) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for event in expected {
                group.addTask { try await ledger.merge([event, event]) }
            }
            try await group.waitForAll()
        }
        let events = try await ledger.events()
        XCTAssertEqual(events, expected)
    }

    func testSQLMetacharactersAreBoundAsLiteralIdentities() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try Ledger(url: directory.appendingPathComponent("ledger.sqlite"))
        let event = fixtureEvent(id: "synthetic'); DROP TABLE usage; --")
        let key = "synthetic'); DROP TABLE notification; --"
        try await ledger.merge([event])
        try await ledger.recordNotification(key: key)
        let events = try await ledger.events()
        let recorded = try await ledger.notificationRecorded(key: key)
        XCTAssertEqual(events, [event])
        XCTAssertTrue(recorded)
    }

    func testOpeningMissingParentOrNonDatabaseFileFails() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try Ledger(url: directory.appendingPathComponent("missing/ledger.sqlite"))) {
            XCTAssertEqual($0 as? BudgetError, .storage)
        }
        let invalid = directory.appendingPathComponent("invalid.sqlite")
        try Data("Synthetic non-database fixture".utf8).write(to: invalid)
        XCTAssertThrowsError(try Ledger(url: invalid)) { XCTAssertEqual($0 as? BudgetError, .storage) }
    }

    #if canImport(CSQLite)
    func testFutureStorageVersionIsRejectedWithoutChangingSchemaOrVersion() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("future.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        let db = try XCTUnwrap(handle)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version = 2; CREATE TABLE future_marker(value TEXT); INSERT INTO future_marker VALUES ('synthetic');", nil, nil, nil), SQLITE_OK)
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try Ledger(url: url)) { XCTAssertEqual($0 as? BudgetError, .unsupportedStorageVersion) }
        XCTAssertEqual(try Data(contentsOf: url), before)

        var query: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &query, nil), SQLITE_OK)
        let statement = try XCTUnwrap(query)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 2)
    }
    #endif
}
