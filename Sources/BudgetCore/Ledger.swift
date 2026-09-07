import CSQLite
import Foundation

/// Connection never leaves this actor; each reconciliation is all-or-nothing.
public actor Ledger {
    private let connection: SQLiteConnection

    public init(url: URL) throws {
        connection = try SQLiteConnection(url: url)
    }

    public func merge(_ events: [UsageEvent]) throws {
        try connection.execute("BEGIN IMMEDIATE")
        do {
            let sql = "INSERT INTO usage(source, identity, payload) VALUES (?, ?, ?) ON CONFLICT(source, identity) DO UPDATE SET payload=excluded.payload"
            let statement = try connection.prepare(sql)
            defer { sqlite3_finalize(statement) }
            let encoder = JSONEncoder()
            for event in events {
                guard event.tokens.isValid, !event.id.isEmpty,
                      event.timestamp.timeIntervalSince1970.isFinite else { throw BudgetError.invalidUsage }
                let payload = String(decoding: try encoder.encode(event), as: UTF8.self)
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try connection.bind(event.source.rawValue, to: statement, index: 1)
                try connection.bind(event.id, to: statement, index: 2)
                try connection.bind(payload, to: statement, index: 3)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw BudgetError.storage }
            }
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    public func events() throws -> [UsageEvent] {
        let statement = try connection.prepare("SELECT payload FROM usage ORDER BY source, identity")
        defer { sqlite3_finalize(statement) }
        var events: [UsageEvent] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return events }
            guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw BudgetError.storage }
            let payload = Data(String(cString: text).utf8)
            events.append(try JSONDecoder().decode(UsageEvent.self, from: payload))
        }
    }

    public func notificationRecorded(key: String) throws -> Bool {
        let statement = try connection.prepare("SELECT 1 FROM notification WHERE identity = ?")
        defer { sqlite3_finalize(statement) }
        try connection.bind(key, to: statement, index: 1)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw BudgetError.storage }
        return result == SQLITE_ROW
    }

    public func recordNotification(key: String) throws {
        let statement = try connection.prepare("INSERT OR IGNORE INTO notification(identity) VALUES (?)")
        defer { sqlite3_finalize(statement) }
        try connection.bind(key, to: statement, index: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw BudgetError.storage }
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    // Owned only by Ledger. Wrapper permits deterministic close outside actor deinit isolation.
    private var db: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            db = nil
            throw BudgetError.storage
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            sqlite3_busy_timeout(db, 3_000)
            let versionQuery = try prepare("PRAGMA user_version")
            let result = sqlite3_step(versionQuery)
            let version = sqlite3_column_int(versionQuery, 0)
            sqlite3_finalize(versionQuery)
            guard result == SQLITE_ROW else { throw BudgetError.storage }
            guard version <= 1 else { throw BudgetError.unsupportedStorageVersion }
            try execute("PRAGMA journal_mode = WAL")
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE IF NOT EXISTS usage(source TEXT NOT NULL, identity TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(source, identity))")
                try execute("CREATE TABLE IF NOT EXISTS notification(identity TEXT PRIMARY KEY NOT NULL)")
                try execute("PRAGMA user_version = 1")
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        } catch {
            sqlite3_close(db); db = nil
            throw error
        }
    }
    deinit { sqlite3_close(db) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw BudgetError.storage }
    }
    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw BudgetError.storage
        }
        return statement
    }
    func bind(_ text: String, to statement: OpaquePointer, index: Int32) throws {
        let result = text.withCString { value in
            sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw BudgetError.storage }
    }
}
