import Foundation
import SQLite3

struct DatabaseMigration: Sendable, Equatable {
    let version: Int
    let name: String
    let apply: @Sendable (OpaquePointer) throws -> Void

    static func == (lhs: DatabaseMigration, rhs: DatabaseMigration) -> Bool {
        lhs.version == rhs.version && lhs.name == rhs.name
    }
}

enum DatabaseMigrations {
    static let latestVersion = 1

    static let all: [DatabaseMigration] = [
        DatabaseMigration(version: 1, name: "create_metadata") { database in
            try sqliteExecute(
                "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);",
                on: database
            )
        }
    ]
}

enum DatabaseError: Error, Equatable {
    case invalidPath
    case unableToOpenDatabase(String)
    case corruptDatabase(String)
    case migrationVersionMismatch(expected: Int, actual: Int)
    case sqliteFailure(String)
}

struct DatabaseLocation: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case inMemory
        case temporary
        case file(URL)
    }

    let kind: Kind

    static var inMemory: DatabaseLocation {
        DatabaseLocation(kind: .inMemory)
    }

    static var temporary: DatabaseLocation {
        DatabaseLocation(kind: .temporary)
    }

    static func file(_ url: URL) -> DatabaseLocation {
        DatabaseLocation(kind: .file(url))
    }
}

final class Database {
    let location: DatabaseLocation
    private let migrations: [DatabaseMigration]
    private var database: OpaquePointer?

    init(location: DatabaseLocation, migrations: [DatabaseMigration] = DatabaseMigrations.all) {
        self.location = location
        self.migrations = migrations.sorted { $0.version < $1.version }
    }

    deinit {
        close()
    }

    func open() throws {
        guard database == nil else { return }

        if case .file(let fileURL) = location.kind {
            let directory = fileURL.deletingLastPathComponent()
            let exists = FileManager.default.fileExists(atPath: directory.path)
            guard exists else {
                throw DatabaseError.invalidPath
            }
        }

        var handle: OpaquePointer?
        let sqlitePath = try resolvedSQLitePath()
        let openResult = sqlite3_open_v2(
            sqlitePath,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        )

        guard openResult == SQLITE_OK, let database = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle {
                sqlite3_close(handle)
            }
            throw DatabaseError.unableToOpenDatabase(message)
        }

        self.database = database

        do {
            try sqliteExecute("PRAGMA foreign_keys = ON;", on: database)
            try verifyDatabaseIsHealthy(on: database)
            try applyMigrationsIfNeeded(on: database)
        } catch {
            close()
            throw error
        }
    }

    func close() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    func userVersion() throws -> Int {
        try withOpenDatabase { database in
            try querySingleInt("PRAGMA user_version;", on: database)
        }
    }

    func execute(_ sql: String) throws {
        try withOpenDatabase { database in
            try sqliteExecute(sql, on: database)
        }
    }

    private func applyMigrationsIfNeeded(on database: OpaquePointer) throws {
        let currentVersion = try querySingleInt("PRAGMA user_version;", on: database)
        guard currentVersion <= DatabaseMigrations.latestVersion else {
            throw DatabaseError.migrationVersionMismatch(
                expected: DatabaseMigrations.latestVersion,
                actual: currentVersion
            )
        }

        let pending = migrations.filter { $0.version > currentVersion }
        for migration in pending {
            try sqliteExecute("BEGIN IMMEDIATE TRANSACTION;", on: database)
            do {
                try migration.apply(database)
                try sqliteExecute("PRAGMA user_version = \(migration.version);", on: database)
                try sqliteExecute("COMMIT;", on: database)
            } catch {
                _ = try? sqliteExecute("ROLLBACK;", on: database)
                throw error
            }
        }
    }

    private func resolvedSQLitePath() throws -> String {
        switch location.kind {
        case .inMemory:
            return ":memory:"
        case .temporary:
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("leo-\(UUID().uuidString).sqlite")
                .path
        case .file(let url):
            return url.path
        }
    }

    private func withOpenDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let database else {
            throw DatabaseError.unableToOpenDatabase("database is not open")
        }
        return try body(database)
    }

    private func verifyDatabaseIsHealthy(on database: OpaquePointer) throws {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, "PRAGMA quick_check;", -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw DatabaseError.corruptDatabase(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            throw DatabaseError.corruptDatabase(String(cString: sqlite3_errmsg(database)))
        }

        let result = String(cString: sqlite3_column_text(statement, 0))
        guard result == "ok" else {
            throw DatabaseError.corruptDatabase(result)
        }
    }
}

private func sqliteExecute(_ sql: String, on database: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    guard result == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        throw DatabaseError.sqliteFailure(message)
    }
}

private func querySingleInt(_ sql: String, on database: OpaquePointer) throws -> Int {
    var statement: OpaquePointer?
    let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard prepareResult == SQLITE_OK, let statement else {
        throw DatabaseError.sqliteFailure(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }

    let stepResult = sqlite3_step(statement)
    guard stepResult == SQLITE_ROW else {
        throw DatabaseError.corruptDatabase(String(cString: sqlite3_errmsg(database)))
    }
    return Int(sqlite3_column_int(statement, 0))
}
