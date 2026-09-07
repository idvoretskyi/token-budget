import Foundation
import XCTest
import CSQLite
import BudgetCore
@testable import UsageAdapters
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class UsageAdaptersTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        // Foundation resolvingSymlinksInPath strips /private on macOS; realpath
        // preserves the actual ancestor chain needed by the symlink safety tests.
        let canonical = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(canonical) }
        let directory = URL(fileURLWithPath: String(cString: canonical)).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testCanonicalTemporaryDirectoryIsNotClassifiedAsSymlink() throws {
        let directory = try temporaryDirectory()
        XCTAssertEqual(try fileType(directory), .typeDirectory)
    }

    private func rollout(_ lines: [String], at directory: URL, name: String = "rollout.jsonl", terminated: Bool = true) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + (terminated ? "\n" : "")).utf8).write(to: url)
        return url
    }

    private func meta(_ extra: String = "") -> String {
        """
        {"timestamp":"2026-09-01T00:00:00Z","type":"session_meta","payload":{"id":"synthetic-session","cli_version":"0.153.4","model_provider":"openai"\(extra)}}
        """
    }

    private func context(_ model: String = "synthetic-model") -> String {
        """
        {"timestamp":"2026-09-01T00:00:00Z","type":"turn_context","payload":{"model":"\(model)","cwd":"SYNTHETIC_PRIVATE_SENTINEL"}}
        """
    }

    private func snapshot(_ input: Int, _ cached: Int, _ output: Int, _ reasoning: Int = 0) -> String {
        """
        {"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(input + output)}
        """
    }

    private func count(_ total: String, last: String? = nil, timestamp: String = "2026-09-01T00:00:01.123Z") -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\(total),"last_token_usage":\(last ?? total)}}}
        """
    }

    func testCodexCumulativeDiffRepeatedSnapshotsAndDisjointTokens() throws {
        let directory = try temporaryDirectory()
        let first = snapshot(100, 25, 30, 10)
        let second = snapshot(160, 45, 50, 15)
        let delta = snapshot(60, 20, 20, 5)
        let url = try rollout([meta(), context(), count(first), count(first), context("second-model"),
                               count(second, last: delta), count(second, last: delta)], at: directory)
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.scannedRecords, 7)
        XCTAssertEqual(report.events.count, 2)
        XCTAssertEqual(report.events.map(\.tokens), [TokenCounts(input: 75, cacheRead: 25, output: 30),
                                                     TokenCounts(input: 40, cacheRead: 20, output: 20)])
        XCTAssertEqual(report.events.map(\.model), ["synthetic-model", "second-model"])
        XCTAssertEqual(report.events.first?.provider, "openai")
        XCTAssertEqual(report.events.first?.source, .codex)
        XCTAssertEqual(report.events, try CodexImporter.scan(path: directory.path).events)
        XCTAssertFalse(report.warnings.joined().contains("SYNTHETIC_PRIVATE_SENTINEL"))
    }

    func testCodexPreWindowBaselineAndArchiveStableIDs() throws {
        let directory = try temporaryDirectory()
        let first = snapshot(100, 10, 20)
        let url = try rollout([meta(), context(), count(first, timestamp: "2026-08-31T23:59:00Z"),
                               count(snapshot(150, 20, 30), last: snapshot(50, 10, 10))], at: directory)
        let original = try CodexImporter.scan(path: url.path)
        let window = original.events.filter { $0.timestamp >= Date(timeIntervalSince1970: 1_788_220_800) }
        XCTAssertEqual(window.count, 1)
        XCTAssertEqual(window.first?.tokens.input, 40)
        let archived = directory.appendingPathComponent("archived.jsonl")
        try FileManager.default.moveItem(at: url, to: archived)
        XCTAssertEqual(original.events, try CodexImporter.scan(path: archived.path).events)
    }

    func testCodexAmbiguousInitialBaselineAndResetAreNotCharged() throws {
        let directory = try temporaryDirectory()
        let url = try rollout([meta(), context(), count(snapshot(100, 20, 30), last: snapshot(10, 0, 5)),
                               count(snapshot(120, 20, 35), last: snapshot(20, 0, 5)),
                               count(snapshot(10, 0, 2)), count(snapshot(30, 0, 5), last: snapshot(20, 0, 3))], at: directory)
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.events.map(\.tokens.input), [20, 20])
        XCTAssertTrue(report.warnings.contains(Notice.baseline.rawValue))
        XCTAssertTrue(report.warnings.contains(Notice.reset.rawValue))
    }

    func testCodexForksAndUnsupportedVersionsAreSkipped() throws {
        let directory = try temporaryDirectory()
        for (index, header) in [meta(",\"forked_from_id\":\"parent\""), meta(",\"history_mode\":\"paginated\""),
                                meta(",\"history_base\":{}"), meta(",\"parent_thread_id\":\"parent\""),
                                meta().replacingOccurrences(of: "0.153.4", with: "0.1.0")].enumerated() {
            let url = try rollout([header, context(), count(snapshot(10, 0, 1))], at: directory, name: "\(index).jsonl")
            let report = try CodexImporter.scan(path: url.path)
            XCTAssertTrue(report.events.isEmpty)
            XCTAssertTrue(report.warnings.contains(Notice.fork.rawValue) || report.warnings.contains(Notice.version.rawValue))
        }
        let url = try rollout([meta(), context(), count(snapshot(10, 0, 1)), meta()], at: directory)
        XCTAssertTrue(try CodexImporter.scan(path: url.path).events.isEmpty)
    }

    func testCodexMalformedRecordsInvalidateBaselineAndModel() throws {
        let directory = try temporaryDirectory()
        let url = try rollout([meta(), context(), count(snapshot(10, 0, 1)), "{SYNTHETIC_PRIVATE_SENTINEL",
                               count(snapshot(20, 0, 2), last: snapshot(10, 0, 1)), context(),
                               count(snapshot(30, 0, 3), last: snapshot(10, 0, 1))], at: directory)
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.events.count, 2)
        XCTAssertTrue(report.warnings.contains(Notice.malformed.rawValue))
        XCTAssertFalse(report.warnings.joined().contains("SYNTHETIC_PRIVATE_SENTINEL"))
    }

    func testCodexInvalidPrefixCannotAdoptCopiedParentMetadata() throws {
        let directory = try temporaryDirectory()
        let prefixes = ["{SYNTHETIC_PRIVATE_SENTINEL", String(repeating: "x", count: ScanLimit.lineBytes + 1),
                        context(), "{\"type\":\"session_meta\",\"payload\":null}",
                        meta().replacingOccurrences(of: "0.153.4", with: "unsupported"),
                        meta().replacingOccurrences(of: "\"model_provider\":\"openai\"", with: "\"model_provider\":null")]
        for (index, prefix) in prefixes.enumerated() {
            let url = try rollout([" \t\r", prefix, meta(), context(), count(snapshot(10, 0, 1)),
                                   count(snapshot(20, 0, 2), last: snapshot(10, 0, 1))],
                                  at: directory, name: "invalid-prefix-\(index).jsonl")
            let report = try CodexImporter.scan(path: url.path)
            XCTAssertTrue(report.events.isEmpty)
            XCTAssertEqual(report.scannedRecords, 2)
            XCTAssertTrue(report.warnings.contains(Notice.empty.rawValue))
            XCTAssertFalse(report.warnings.joined().contains("SYNTHETIC_PRIVATE_SENTINEL"))
        }
        XCTAssertTrue(try CodexImporter.scan(path: directory.path).events.isEmpty)
    }

    func testCodexBlankPrefixStillAllowsFirstSessionMetadata() throws {
        let directory = try temporaryDirectory()
        let url = try rollout(["", " \t\r", meta(), context(), count(snapshot(10, 0, 1))], at: directory)
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.events.count, 1)
        XCTAssertEqual(report.scannedRecords, 5)
        XCTAssertFalse(report.warnings.contains(Notice.metadata.rawValue))
    }

    func testCodexOversizedLineAndUnterminatedTail() throws {
        let directory = try temporaryDirectory()
        let url = try rollout([meta(), context(), String(repeating: "x", count: ScanLimit.lineBytes + 1),
                               context(), count(snapshot(100, 0, 10)), count(snapshot(110, 0, 11), last: snapshot(10, 0, 1)),
                               count(snapshot(120, 0, 12), last: snapshot(10, 0, 1))], at: directory, terminated: false)
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.events.count, 1)
        XCTAssertTrue(report.warnings.contains(Notice.oversized.rawValue))
        XCTAssertTrue(report.warnings.contains(Notice.partial.rawValue))
        XCTAssertEqual(report.scannedRecords, 6)
    }

    func testCodexInvalidNumbersAndMissingMetadataAreVisible() throws {
        let directory = try temporaryDirectory()
        let invalid = [snapshot(-1, 0, 1), snapshot(10, 11, 1), snapshot(10, 0, 1, 2),
                       snapshot(10, 0, 1).replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":true"),
                       snapshot(10, 0, 1).replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":1.5"),
                       snapshot(10, 0, 1).replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":9223372036854775808")]
        for (index, value) in invalid.enumerated() {
            let url = try rollout([meta(), context(), count(value)], at: directory, name: "\(index).jsonl")
            let report = try CodexImporter.scan(path: url.path)
            XCTAssertTrue(report.events.isEmpty)
            XCTAssertTrue(report.warnings.contains(Notice.malformed.rawValue))
        }
        let url = try rollout([meta(), count(snapshot(10, 0, 1))], at: directory)
        XCTAssertTrue(try CodexImporter.scan(path: url.path).warnings.contains(Notice.metadata.rawValue))
    }

    func testCodexNullInfoAndCachedWriteLimit() throws {
        let directory = try temporaryDirectory()
        let rate = """
        {"type":"event_msg","payload":{"type":"token_count","info":null}}
        """
        let write = snapshot(10, 0, 1).replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":10,\"cache_write_input_tokens\":2")
        let url = try rollout([meta(), context(), rate, count(snapshot(10, 0, 1)), count(write)], at: directory)
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.events.count, 1)
        XCTAssertTrue(report.warnings.contains(Notice.cacheWrite.rawValue))
    }

    func testCodexCompactionRerouteAndRollbackOmitAmbiguousTransitions() throws {
        let directory = try temporaryDirectory()
        let compacted = "{\"type\":\"compacted\",\"payload\":{}}"
        let reroute = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"model_reroute\"}}"
        let rollback = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"thread_rolled_back\"}}"
        let url = try rollout([meta(), context(), count(snapshot(10, 0, 1)), compacted,
                               count(snapshot(20, 0, 2), last: snapshot(10, 0, 1)), reroute,
                               count(snapshot(30, 0, 3), last: snapshot(10, 0, 1)), context("new-model"),
                               count(snapshot(40, 0, 4), last: snapshot(10, 0, 1)), rollback,
                               count(snapshot(50, 0, 5), last: snapshot(10, 0, 1))], at: directory)
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.events.map(\.model), ["synthetic-model", "new-model"])
        XCTAssertTrue(report.warnings.contains(Notice.reset.rawValue))
        XCTAssertTrue(report.warnings.contains(Notice.reroute.rawValue))
        XCTAssertTrue(report.warnings.contains(Notice.fork.rawValue))
    }

    func testCodexDeferredTailBecomesOneStableEventAfterAppend() throws {
        let directory = try temporaryDirectory()
        let url = try rollout([meta(), context(), count(snapshot(10, 0, 1))], at: directory, terminated: false)
        XCTAssertTrue(try CodexImporter.scan(path: url.path).events.isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        let report = try CodexImporter.scan(path: url.path)
        XCTAssertEqual(report.events.count, 1)
        XCTAssertEqual(report.events, try CodexImporter.scan(path: url.path).events)
    }

    func testMissingPathsEmptySourcesAndSymlinks() throws {
        let directory = try temporaryDirectory()
        let missing = directory.appendingPathComponent("SYNTHETIC_PRIVATE_SENTINEL")
        for scan in [CodexImporter.scan, OpenCodeImporter.scan] {
            XCTAssertThrowsError(try scan(missing.path)) { error in
                XCTAssertFalse(error.localizedDescription.contains("SYNTHETIC_PRIVATE_SENTINEL"))
            }
        }
        XCTAssertTrue(try CodexImporter.scan(path: directory.path).warnings.contains(Notice.empty.rawValue))
        let target = try rollout([meta(), context(), count(snapshot(10, 0, 1))], at: directory)
        let link = directory.appendingPathComponent("linked.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertTrue(try CodexImporter.scan(path: link.path).warnings.contains(Notice.symlink.rawValue))
        XCTAssertEqual(try CodexImporter.scan(path: directory.path).events.count, 1)
        let linkedDirectory = directory.appendingPathComponent("linked-directory")
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: directory)
        XCTAssertTrue(try CodexImporter.scan(path: linkedDirectory.appendingPathComponent("rollout.jsonl").path).events.isEmpty)
    }

    private func database(_ body: (OpaquePointer, URL) throws -> Void) throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let connection = try XCTUnwrap(db)
        defer { sqlite3_close(connection) }
        try execute(connection, """
        PRAGMA journal_mode=WAL;
        PRAGMA wal_autocheckpoint=0;
        CREATE TABLE session (id TEXT PRIMARY KEY, version TEXT, time_created INTEGER);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT);
        CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, data TEXT);
        INSERT INTO session VALUES ('session', '1.18.29', 1788220800000);
        INSERT INTO message VALUES ('message', 'session', 1788220800000,
          '{"role":"assistant","providerID":"synthetic-provider","modelID":"synthetic-model","cost":999,"tokens":{"input":999999}}');
        """)
        try body(connection, url)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw UsageImportError.database }
    }

    private func step(_ db: OpaquePointer, id: String = "part", tokens: String = "{\"input\":100,\"output\":20,\"reasoning\":5,\"cache\":{\"read\":30,\"write\":10}}") throws {
        try execute(db, """
        INSERT INTO part VALUES ('\(id)', 'message', 'session', 1788220801000,
          '{"type":"step-finish","cost":123,"tokens":\(tokens)}');
        """)
    }

    func testOpenCodeReadsLiveWALCanonicalStepsOnlyAndDoesNotMutate() throws {
        try database { db, url in
            try step(db)
            try step(db, id: "second")
            try execute(db, "INSERT INTO part VALUES ('text', 'message', 'session', 1788220801000, '{\"type\":\"text\",\"text\":\"SYNTHETIC_PRIVATE_SENTINEL\"}')")
            let before = try Data(contentsOf: url)
            let wal = URL(fileURLWithPath: url.path + "-wal")
            let beforeWAL = try Data(contentsOf: wal)
            let report = try OpenCodeImporter.scan(path: url.path)
            XCTAssertEqual(report.scannedRecords, 3)
            XCTAssertEqual(report.events.count, 2)
            XCTAssertEqual(report.events.first?.tokens, TokenCounts(input: 100, cacheRead: 30, cacheWrite: 10, output: 25))
            XCTAssertEqual(report.events.first?.timestamp, Date(timeIntervalSince1970: 1_788_220_801))
            XCTAssertEqual(report.events, try OpenCodeImporter.scan(path: url.deletingLastPathComponent().path).events)
            XCTAssertEqual(before, try Data(contentsOf: url))
            XCTAssertEqual(beforeWAL, try Data(contentsOf: wal))
            XCTAssertFalse(report.warnings.joined().contains("SYNTHETIC_PRIVATE_SENTINEL"))
        }
    }

    func testOpenCodeSkipsOldVersionsForkCopiesAndInvalidTokens() throws {
        try database { db, url in
            try step(db)
            try execute(db, "UPDATE session SET version = '1.2.15'")
            XCTAssertTrue(try OpenCodeImporter.scan(path: url.path).warnings.contains(Notice.version.rawValue))
            try execute(db, "UPDATE session SET version = '1.18.29', time_created = 1788220800001")
            XCTAssertTrue(try OpenCodeImporter.scan(path: url.path).warnings.contains(Notice.fork.rawValue))
            try execute(db, "UPDATE session SET time_created = 1788220800000; DELETE FROM part")
            try step(db, tokens: "{\"input\":-1,\"output\":0,\"reasoning\":0,\"cache\":{\"read\":0,\"write\":0}}")
            try step(db, id: "overflow", tokens: "{\"input\":1,\"output\":9223372036854775807,\"reasoning\":1,\"cache\":{\"read\":0,\"write\":0}}")
            try execute(db, "INSERT INTO part VALUES ('bad', 'message', 'session', 1788220801000, '{SYNTHETIC_PRIVATE_SENTINEL')")
            let report = try OpenCodeImporter.scan(path: url.path)
            XCTAssertTrue(report.events.isEmpty)
            XCTAssertTrue(report.warnings.contains(Notice.malformed.rawValue))
        }
    }

    func testOpenCodeUnknownDatabaseFailsWithoutExposingContents() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("opencode.db")
        try Data("SYNTHETIC_PRIVATE_SENTINEL".utf8).write(to: url)
        XCTAssertThrowsError(try OpenCodeImporter.scan(path: url.path)) { error in
            XCTAssertFalse(error.localizedDescription.contains("SYNTHETIC_PRIVATE_SENTINEL"))
        }
    }

    func testOpenCodeRejectsNULAndInvalidUTF8Versions() throws {
        try database { db, url in
            try step(db)
            for value in ["'1.18.29' || char(0) || 'unsupported'", "'1.18.29' || CAST(X'FF' AS TEXT)"] {
                try execute(db, "UPDATE session SET version = \(value)")
                let report = try OpenCodeImporter.scan(path: url.path)
                XCTAssertTrue(report.events.isEmpty)
                XCTAssertTrue(report.warnings.contains(Notice.version.rawValue))
            }
        }
    }

    func testOpenCodeRejectsNULAndInvalidUTF8PartIDsWithoutCollisions() throws {
        try database { db, url in
            try step(db)
            try step(db, id: "second")
            try execute(db, "UPDATE part SET id = 'part' || char(0) || CASE id WHEN 'part' THEN 'a' ELSE 'b' END")
            let nulReport = try OpenCodeImporter.scan(path: url.path)
            XCTAssertEqual(nulReport.scannedRecords, 2)
            XCTAssertTrue(nulReport.events.isEmpty)
            XCTAssertTrue(nulReport.warnings.contains(Notice.metadata.rawValue))
            try execute(db, "DELETE FROM part")
            try step(db)
            try step(db, id: "second")
            try execute(db, "UPDATE part SET id = CASE id WHEN 'part' THEN CAST(X'70617274FF' AS TEXT) ELSE CAST(X'70617274FE' AS TEXT) END")
            let utf8Report = try OpenCodeImporter.scan(path: url.path)
            XCTAssertEqual(utf8Report.scannedRecords, 2)
            XCTAssertTrue(utf8Report.events.isEmpty)
            XCTAssertTrue(utf8Report.warnings.contains(Notice.metadata.rawValue))
        }
    }

    func testOpenCodeRejectsNULAndInvalidUTF8SessionIDs() throws {
        try database { db, url in
            try step(db)
            for value in ["'session' || char(0) || 'a'", "CAST(X'73657373696F6EFF' AS TEXT)"] {
                try execute(db, "UPDATE session SET id = \(value); UPDATE message SET session_id = \(value); UPDATE part SET session_id = \(value)")
                let report = try OpenCodeImporter.scan(path: url.path)
                XCTAssertTrue(report.events.isEmpty)
                XCTAssertTrue(report.warnings.contains(Notice.metadata.rawValue))
            }
        }
    }

    func testOpenCodeMissingMetadataAndZeroUsage() throws {
        try database { db, url in
            try step(db, tokens: "{\"input\":0,\"output\":0,\"reasoning\":0,\"cache\":{\"read\":0,\"write\":0}}")
            XCTAssertTrue(try OpenCodeImporter.scan(path: url.path).events.isEmpty)
            try step(db, id: "missing")
            try execute(db, "UPDATE message SET data = '{\"role\":\"assistant\"}'")
            let report = try OpenCodeImporter.scan(path: url.path)
            XCTAssertTrue(report.events.isEmpty)
            XCTAssertTrue(report.warnings.contains(Notice.metadata.rawValue))
        }
    }

    func testOpenCodeRejectsSymlinkDatabaseAndSidecars() throws {
        let directory = try temporaryDirectory()
        let target = directory.appendingPathComponent("target")
        let database = directory.appendingPathComponent("opencode.db")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(at: database, withDestinationURL: target)
        XCTAssertTrue(try OpenCodeImporter.scan(path: directory.path).warnings.contains(Notice.symlink.rawValue))
        try FileManager.default.removeItem(at: database)
        try Data().write(to: database)
        try FileManager.default.createSymbolicLink(at: URL(fileURLWithPath: database.path + "-wal"), withDestinationURL: target)
        XCTAssertTrue(try OpenCodeImporter.scan(path: database.path).warnings.contains(Notice.symlink.rawValue))
    }

    func testOpenCodeRejectsDirectoryAndFIFOSidecarsBeforeOpeningSQLite() throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            for fifo in [false, true] {
                let directory = try temporaryDirectory()
                let database = directory.appendingPathComponent("opencode.db")
                // An invalid database would fail differently if SQLite were opened first.
                let contents = Data("SYNTHETIC_PRIVATE_SENTINEL".utf8)
                try contents.write(to: database)
                let sidecar = URL(fileURLWithPath: database.path + suffix)
                if fifo {
                    XCTAssertEqual(sidecar.path.withCString { mkfifo($0, 0o600) }, 0)
                } else {
                    try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: false)
                }
                XCTAssertThrowsError(try OpenCodeImporter.scan(path: database.path)) { error in
                    guard case UsageImportError.unavailable = error else {
                        return XCTFail("Expected sidecar validation to reject before opening SQLite.")
                    }
                    XCTAssertFalse(error.localizedDescription.contains("SYNTHETIC_PRIVATE_SENTINEL"))
                }
                XCTAssertEqual(try Data(contentsOf: database), contents)
                let attributes = try FileManager.default.attributesOfItem(atPath: sidecar.path)
                XCTAssertNotEqual(attributes[.type] as? FileAttributeType, .typeRegular)
                if !fifo { XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeDirectory) }
            }
        }
    }

    func testOpenCodeSidecarLookupErrorsAreNotTreatedAsMissing() throws {
        let directory = try temporaryDirectory()
        // The database basename fits NAME_MAX, but appending a sidecar suffix does not.
        let database = directory.appendingPathComponent(String(repeating: "x", count: 253))
        try Data().write(to: database)
        XCTAssertThrowsError(try OpenCodeImporter.scan(path: database.path)) { error in
            guard case UsageImportError.unavailable = error else {
                return XCTFail("Expected a sidecar lookup error to reject before opening SQLite.")
            }
        }
    }

    func testStreamingByteBudgetIsExplicitAndBounded() throws {
        let directory = try temporaryDirectory()
        let url = try rollout(["one", "two", "three"], at: directory)
        var budget = 6
        var lines: [Data] = []
        let result = try streamLines(url, byteBudget: &budget) { data, _ in
            if let data { lines.append(data) }
            return true
        }
        XCTAssertEqual(budget, 0)
        XCTAssertEqual(lines, [Data("one".utf8)])
        XCTAssertTrue(result.limited)
        XCTAssertTrue(result.partial)
    }
}
