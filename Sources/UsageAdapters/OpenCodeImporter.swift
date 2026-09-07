import Foundation
import BudgetCore
import CSQLite

public enum OpenCodeImporter {
    /// Reads a database file, or opencode.db inside the supplied data directory.
    public static func scan(path: String) throws -> ImportReport {
        guard !path.isEmpty else { throw UsageImportError.unavailable }
        var report = ImportReport()
        report.warn(.coverage)
        report.warn(.steps)
        var url = URL(fileURLWithPath: path)
        let type = try fileType(url)
        if type == .typeSymbolicLink { report.warn(.symlink); return report }
        if type == .typeDirectory { url.appendPathComponent("opencode.db") }
        let databaseType = try fileType(url)
        if databaseType == .typeSymbolicLink { report.warn(.symlink); return report }
        guard databaseType == .typeRegular else { throw UsageImportError.unavailable }
        // Validate sidecars before SQLite can open a directory, device, or blocking FIFO.
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: sidecar.path)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                continue
            } catch { throw UsageImportError.unavailable }
            let sidecarType = attributes[.type] as? FileAttributeType
            if sidecarType == .typeSymbolicLink {
                report.warn(.symlink)
                return report
            }
            guard sidecarType == .typeRegular else { throw UsageImportError.unavailable }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw UsageImportError.database
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1_000)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 8_388_608)
        guard sqlite3_exec(db, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF; BEGIN", nil, nil, nil) == SQLITE_OK else {
            throw UsageImportError.database
        }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }

        // Project only accounting metadata. Prompt/text/tool parts never enter Swift.
        // Scan all part rows (bounded), so malformed JSON is visible rather than hidden by WHERE.
        let sql = """
        SELECT p.id, p.session_id, p.time_created,
          CASE WHEN length(CAST(p.data AS BLOB)) <= 1048576 AND json_valid(p.data)
            THEN CASE WHEN json_extract(p.data, '$.type') = 'step-finish'
              THEN json_object('tokens', json_extract(p.data, '$.tokens')) ELSE '{}' END END,
          CASE WHEN length(CAST(m.data AS BLOB)) <= 1048576 AND json_valid(m.data)
            THEN json_object('role', json_extract(m.data, '$.role'),
              'providerID', json_extract(m.data, '$.providerID'), 'modelID', json_extract(m.data, '$.modelID')) END,
          s.version, s.time_created, m.time_created
        FROM part p LEFT JOIN message m ON m.id = p.message_id AND m.session_id = p.session_id
        LEFT JOIN session s ON s.id = p.session_id
        ORDER BY p.id LIMIT 250001
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw UsageImportError.unsupported }
        defer { sqlite3_finalize(statement) }
        func text(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                  let pointer = sqlite3_column_text(statement, column) else { return nil }
            let bytes = UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(statement, column)))
            guard !bytes.contains(0) else { return nil }
            return String(bytes: bytes, encoding: .utf8)
        }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw UsageImportError.database }
            if report.scannedRecords == ScanLimit.sqliteRows || report.events.count == ScanLimit.events {
                report.warn(.limit); break
            }
            report.scannedRecords += 1
            guard let raw = text(3), let part = json(Data(raw.utf8)) else { report.warn(.malformed); continue }
            if part.isEmpty { continue }
            guard text(5) == "1.18.29" else { report.warn(.version); continue }
            guard let id = identifier(text(0)), let session = identifier(text(1)),
                  let rawMessage = text(4), let message = json(Data(rawMessage.utf8)),
                  message["role"] as? String == "assistant",
                  let provider = identifier(message["providerID"]), let model = identifier(message["modelID"]) else {
                report.warn(.metadata); continue
            }
            guard [Int32(2), 6, 7].allSatisfy({ sqlite3_column_type(statement, $0) == SQLITE_INTEGER }),
                  sqlite3_column_int64(statement, 2) >= 0, sqlite3_column_int64(statement, 6) >= 0,
                  sqlite3_column_int64(statement, 7) >= 0 else { report.warn(.malformed); continue }
            // Upstream fork copies the original message creation time into a newly created session.
            guard sqlite3_column_int64(statement, 7) >= sqlite3_column_int64(statement, 6) else {
                report.warn(.fork); continue
            }
            guard let tokens = object(part["tokens"]), let cache = object(tokens["cache"]),
                  let input = integer(tokens["input"]), let output = integer(tokens["output"]),
                  let reasoning = integer(tokens["reasoning"]), let read = integer(cache["read"]),
                  let write = integer(cache["write"]) else { report.warn(.malformed); continue }
            let combined = output.addingReportingOverflow(reasoning)
            guard !combined.overflow else { report.warn(.malformed); continue }
            let counts = TokenCounts(input: input, cacheRead: read, cacheWrite: write, output: combined.partialValue)
            if counts.isEmpty { continue }
            report.events.append(UsageEvent(id: "opencode:step:\(session.utf8.count):\(session):\(id)",
                source: .opencode, timestamp: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1_000),
                provider: provider, model: model, tokens: counts))
        }
        if report.events.isEmpty { report.warn(.empty) }
        return report
    }
}
