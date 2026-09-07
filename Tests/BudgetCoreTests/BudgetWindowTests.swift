import BudgetCore
import Foundation
import XCTest

final class BudgetWindowTests: XCTestCase {
    func testMondayResetAtExactBoundaryStartsNewWeek() throws {
        let configuration = BudgetConfiguration(period: .weekly, timeZoneID: "UTC")
        let monday = fixtureDate("2024-02-05T00:00:00Z")
        let window = try BudgetEngine.window(for: configuration, at: monday)
        XCTAssertEqual(window.start, monday)
        XCTAssertEqual(window.end, fixtureDate("2024-02-12T00:00:00Z"))
        XCTAssertEqual(try BudgetEngine.window(for: configuration, at: monday.addingTimeInterval(0.25)), window)
    }

    func testSubsecondBeforeMondayResetStillBelongsToPreviousWeek() throws {
        let configuration = BudgetConfiguration(period: .weekly, timeZoneID: "UTC")
        let monday = fixtureDate("2024-02-05T00:00:00Z")
        for offset in [-1.0, -0.999, -0.5, -0.001] {
            do {
                let window = try BudgetEngine.window(for: configuration, at: monday.addingTimeInterval(offset))
                XCTAssertEqual(window.start, fixtureDate("2024-01-29T00:00:00Z"), "offset \(offset)")
                XCTAssertEqual(window.end, monday, "offset \(offset)")
            } catch {
                XCTFail("Valid weekly instant at offset \(offset) threw \(error)")
            }
        }
    }

    func testWeeklyCalendarDurationChangesAcrossDST() throws {
        let configuration = BudgetConfiguration(period: .weekly, timeZoneID: "America/New_York")
        for (instant, start, end, hours) in [
            ("2024-03-10T12:00:00Z", "2024-03-04T05:00:00Z", "2024-03-11T04:00:00Z", 167),
            ("2024-11-03T12:00:00Z", "2024-10-28T04:00:00Z", "2024-11-04T05:00:00Z", 169)
        ] {
            let window = try BudgetEngine.window(for: configuration, at: fixtureDate(instant))
            XCTAssertEqual(window.start, fixtureDate(start))
            XCTAssertEqual(window.end, fixtureDate(end))
            XCTAssertEqual(window.duration, Double(hours * 3_600))
        }
    }

    func testNonexistentWeeklyResetMovesToNextValidWallClockTime() throws {
        let configuration = BudgetConfiguration(period: .weekly, timeZoneID: "America/New_York",
                                                weekday: 1, hour: 2, minute: 30)
        let reset = fixtureDate("2024-03-10T07:00:00Z") // 02:30 is skipped; reset at 03:00 EDT.
        let previous = try BudgetEngine.window(for: configuration, at: reset.addingTimeInterval(-60))
        XCTAssertEqual(previous.start, fixtureDate("2024-03-03T07:30:00Z"))
        XCTAssertEqual(previous.end, reset)
        for now in [reset, reset.addingTimeInterval(1_800), fixtureDate("2024-03-13T12:00:00Z")] {
            let window = try BudgetEngine.window(for: configuration, at: now)
            XCTAssertEqual(window.start, reset)
            XCTAssertEqual(window.end, fixtureDate("2024-03-17T06:30:00Z"))
        }
    }

    func testAmbiguousWeeklyResetUsesFirstOccurrenceOnly() throws {
        let configuration = BudgetConfiguration(period: .weekly, timeZoneID: "America/New_York",
                                                weekday: 1, hour: 1, minute: 30)
        let first = fixtureDate("2024-11-03T05:30:00Z")
        let second = fixtureDate("2024-11-03T06:30:00Z")
        let previous = try BudgetEngine.window(for: configuration, at: first.addingTimeInterval(-60))
        XCTAssertEqual(previous.start, fixtureDate("2024-10-27T05:30:00Z"))
        XCTAssertEqual(previous.end, first)
        for now in [first, first.addingTimeInterval(1_800), second, second.addingTimeInterval(1_800),
                    fixtureDate("2024-11-06T12:00:00Z")] {
            let window = try BudgetEngine.window(for: configuration, at: now)
            XCTAssertEqual(window.start, first, "instant \(now)")
            XCTAssertEqual(window.end, fixtureDate("2024-11-10T06:30:00Z"))
        }
    }

    func testMonthlyLeapNonLeapAndYearBoundaries() throws {
        let configuration = BudgetConfiguration(period: .monthly, timeZoneID: "UTC")
        for (instant, start, end, days) in [
            ("2024-02-29T12:00:00Z", "2024-02-01T00:00:00Z", "2024-03-01T00:00:00Z", 29),
            ("2023-02-28T12:00:00Z", "2023-02-01T00:00:00Z", "2023-03-01T00:00:00Z", 28),
            ("2024-04-30T12:00:00Z", "2024-04-01T00:00:00Z", "2024-05-01T00:00:00Z", 30),
            ("2024-12-31T12:00:00Z", "2024-12-01T00:00:00Z", "2025-01-01T00:00:00Z", 31),
            ("2025-01-01T00:00:00Z", "2025-01-01T00:00:00Z", "2025-02-01T00:00:00Z", 31)
        ] {
            do {
                let window = try BudgetEngine.window(for: configuration, at: fixtureDate(instant))
                XCTAssertEqual(window.start, fixtureDate(start), instant)
                XCTAssertEqual(window.end, fixtureDate(end), instant)
                XCTAssertEqual(window.duration, Double(days * 86_400), instant)
            } catch {
                XCTFail("Valid monthly instant \(instant) threw \(error)")
            }
        }
    }

    func testMonthlyResetUsesStoredZoneHourAndMinute() throws {
        let configuration = BudgetConfiguration(period: .monthly, timeZoneID: "Asia/Kathmandu", hour: 9, minute: 15)
        let boundary = fixtureDate("2024-03-01T03:30:00Z")
        let before = try BudgetEngine.window(for: configuration, at: boundary.addingTimeInterval(-60))
        XCTAssertEqual(before.start, fixtureDate("2024-02-01T03:30:00Z"))
        XCTAssertEqual(before.end, boundary)
        for offset in [0.0, 0.25, 1.0, 60.0] {
            do {
                let exact = try BudgetEngine.window(for: configuration, at: boundary.addingTimeInterval(offset))
                XCTAssertEqual(exact.start, boundary, "offset \(offset)")
                XCTAssertEqual(exact.end, fixtureDate("2024-04-01T03:30:00Z"), "offset \(offset)")
            } catch {
                XCTFail("Valid monthly reset at offset \(offset) threw \(error)")
            }
        }
    }

    func testSubsecondBeforeMonthlyResetStillBelongsToPreviousMonth() throws {
        let configuration = BudgetConfiguration(period: .monthly, timeZoneID: "Asia/Kathmandu", hour: 9, minute: 15)
        let boundary = fixtureDate("2024-03-01T03:30:00Z")
        let window = try BudgetEngine.window(for: configuration, at: boundary.addingTimeInterval(-0.25))
        XCTAssertEqual(window.start, fixtureDate("2024-02-01T03:30:00Z"))
        XCTAssertEqual(window.end, boundary)
    }

    func testInvalidConfigurationAndNonfiniteNowAreRejected() throws {
        let mutations: [(inout BudgetConfiguration) -> Void] = [
            { $0.amount = 0 }, { $0.amount = -1 }, { $0.amount = .nan },
            { $0.currency = "usd" }, { $0.currency = "NOT_A_CURRENCY" },
            { $0.timeZoneID = "Synthetic/Invalid" },
            { $0.weekday = 0 }, { $0.weekday = 8 },
            { $0.hour = -1 }, { $0.hour = 24 }, { $0.minute = -1 }, { $0.minute = 60 }
        ]
        for (index, mutate) in mutations.enumerated() {
            var configuration = BudgetConfiguration()
            mutate(&configuration)
            XCTAssertThrowsError(try BudgetEngine.window(for: configuration, at: fixtureDate("2024-02-15T12:00:00Z")), "case \(index)") {
                XCTAssertEqual($0 as? BudgetError, .invalidConfiguration)
            }
        }
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try BudgetEngine.window(for: .init(), at: Date(timeIntervalSince1970: value))) {
                XCTAssertEqual($0 as? BudgetError, .invalidConfiguration)
            }
        }
    }
}
