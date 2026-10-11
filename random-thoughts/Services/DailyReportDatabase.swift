import Darwin
import Foundation
import SQLite3

actor DailyReportDatabase: DailyReportStorage {
    private let directory: URL
    private var connection: ReportSQLiteConnection?

    init(directory: URL) { self.directory = directory }

    func load() async throws -> ReportStorageSnapshot { try open().load() }
    func save(_ report: SavedDailyReport) async throws { try open().save(report) }
    func saveWindowSize(_ size: CGSize) async throws { try open().saveWindowSize(size) }
    func saveGeneralSettings(_ settings: DailyReportGeneralSettings) async throws { try open().saveGeneralSettings(settings) }

    private func open() throws -> ReportSQLiteConnection {
        if let connection { return connection }
        let opened = try ReportSQLiteConnection(directory: directory)
        connection = opened
        return opened
    }
}

// The database actor exclusively owns this connection and its lifetime lock.
private nonisolated final class ReportSQLiteConnection {
    private var database: OpaquePointer?
    private var lockDescriptor: Int32 = -1
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { throw ReportStorageError.unavailable }
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              directoryInfo.st_mode & S_IFMT == S_IFDIR, directoryInfo.st_uid == getuid(),
              chmod(directory.path, 0o700) == 0 else { throw ReportStorageError.unavailable }

        lockDescriptor = Darwin.open(directory.appendingPathComponent("storage.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockDescriptor >= 0, fchmod(lockDescriptor, 0o600) == 0 else { throw ReportStorageError.unavailable }
        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw errno == EWOULDBLOCK ? ReportStorageError.occupied : .unavailable
        }
        let url = directory.appendingPathComponent("reports.sqlite")
        if try Self.exists(directory.appendingPathComponent("reset-intent")) {
            throw ReportStorageError.recoveryRequired
        }
        let exists = try Self.exists(url)
        if !exists {
            for name in ["reports.sqlite-journal", "reports.sqlite-wal", "reports.sqlite-shm"] {
                if try Self.exists(directory.appendingPathComponent(name)) { throw ReportStorageError.recoveryRequired }
            }
            let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw ReportStorageError.unavailable }
            Darwin.close(descriptor)
        }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o600 == 0o600,
              chmod(url.path, 0o600) == 0 else { throw ReportStorageError.unavailable }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw ReportStorageError.unavailable
        }
        if exists {
            guard try integer("PRAGMA user_version") == 2 else { throw ReportStorageError.unsupportedVersion }
            guard try text("PRAGMA quick_check") == "ok" else { throw ReportStorageError.invalidData }
            try validateColumns("reports", expected: [
                ("calendar_date", "TEXT", true, 1), ("time_zone", "TEXT", true, 2),
                ("markdown", "TEXT", true, 0), ("saved_at", "REAL", true, 0), ("last_edited_at", "REAL", false, 0)
            ])
            try validateColumns("window_state", expected: [
                ("id", "INTEGER", false, 1), ("width", "REAL", true, 0), ("height", "REAL", true, 0)
            ])
            try validateColumns("general_settings", expected: [
                ("id", "INTEGER", false, 1), ("time_zone_mode", "TEXT", true, 0),
                ("fixed_time_zone", "TEXT", true, 0), ("output_language", "TEXT", true, 0),
                ("generation_preferences", "TEXT", true, 0), ("history_lookback_days", "INTEGER", true, 0)
            ])
        }
        try execute("PRAGMA journal_mode=DELETE; PRAGMA synchronous=EXTRA; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY")
        guard try text("PRAGMA journal_mode") == "delete",
              try integer("PRAGMA synchronous") == 3,
              try integer("PRAGMA secure_delete") == 1 else { throw ReportStorageError.unavailable }
        if !exists {
            try transaction {
                try execute("""
                    CREATE TABLE reports (
                        calendar_date TEXT NOT NULL, time_zone TEXT NOT NULL, markdown TEXT NOT NULL,
                        saved_at REAL NOT NULL, last_edited_at REAL,
                        PRIMARY KEY (calendar_date, time_zone)
                    ) STRICT;
                    CREATE TABLE window_state (
                        id INTEGER PRIMARY KEY CHECK(id=1), width REAL NOT NULL, height REAL NOT NULL
                    ) STRICT;
                    CREATE TABLE general_settings (
                        id INTEGER PRIMARY KEY CHECK(id=1), time_zone_mode TEXT NOT NULL,
                        fixed_time_zone TEXT NOT NULL, output_language TEXT NOT NULL,
                        generation_preferences TEXT NOT NULL, history_lookback_days INTEGER NOT NULL
                    ) STRICT;
                    INSERT INTO general_settings VALUES(1,'followMac','Etc/UTC','chinese','',1);
                    PRAGMA user_version=2;
                    """)
            }
        }
        _ = try load()
    }

    deinit {
        if let database { sqlite3_close(database) }
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
    }

    private static func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        guard errno == ENOENT else { throw ReportStorageError.unavailable }
        return false
    }

    func load() throws -> ReportStorageSnapshot {
        var reports: [SavedDailyReport] = []
        var reportDays: Set<ReportDay> = []
        try statement("SELECT calendar_date,time_zone,markdown,saved_at,last_edited_at FROM reports ORDER BY calendar_date,time_zone") { query in
            while try next(query) {
                let day = try ReportDay(calendarDate: columnText(query, 0), timeZoneIdentifier: columnText(query, 1))
                guard reportDays.insert(day).inserted else { throw ReportStorageError.invalidData }
                let savedAt = try columnDate(query, 3)
                let editedAt = sqlite3_column_type(query, 4) == SQLITE_NULL ? nil : try columnDate(query, 4)
                reports.append(SavedDailyReport(day: day, markdown: try columnText(query, 2), savedAt: savedAt, lastEditedAt: editedAt))
            }
        }
        var size: CGSize?
        try statement("SELECT id,width,height FROM window_state") { query in
            if try next(query) {
                guard sqlite3_column_type(query, 0) == SQLITE_INTEGER, sqlite3_column_int(query, 0) == 1 else {
                    throw ReportStorageError.invalidData
                }
                let width = try columnNumber(query, 1)
                let height = try columnNumber(query, 2)
                guard width > 0, height > 0 else { throw ReportStorageError.invalidData }
                size = CGSize(width: width, height: height)
                guard try !next(query) else { throw ReportStorageError.invalidData }
            }
        }
        let settings = try statement("SELECT id,time_zone_mode,fixed_time_zone,output_language,generation_preferences,history_lookback_days FROM general_settings") { query in
            guard try next(query), sqlite3_column_type(query, 0) == SQLITE_INTEGER, sqlite3_column_int64(query, 0) == 1,
                  let mode = try ReportTimeZoneMode(rawValue: columnText(query, 1)),
                  let language = try ReportOutputLanguage(rawValue: columnText(query, 3)),
                  sqlite3_column_type(query, 5) == SQLITE_INTEGER else { throw ReportStorageError.invalidData }
            let lookback = sqlite3_column_int64(query, 5)
            guard (0...7).contains(lookback) else { throw ReportStorageError.invalidData }
            let value = DailyReportGeneralSettings(
                timeZoneMode: mode, fixedTimeZoneIdentifier: try columnText(query, 2),
                outputLanguage: language, generationPreferences: try columnText(query, 4),
                historyLookbackDays: Int(lookback)
            )
            guard try !next(query) else { throw ReportStorageError.invalidData }
            return value
        }
        return ReportStorageSnapshot(reports: reports, windowSize: size, generalSettings: settings)
    }

    func save(_ report: SavedDailyReport) throws {
        guard report.savedAt.timeIntervalSince1970.isFinite,
              report.lastEditedAt?.timeIntervalSince1970.isFinite != false else { throw ReportStorageError.invalidData }
        try transaction {
            try statement("""
                INSERT INTO reports(calendar_date,time_zone,markdown,saved_at,last_edited_at) VALUES(?,?,?,?,?)
                ON CONFLICT(calendar_date,time_zone) DO UPDATE SET
                    markdown=excluded.markdown,saved_at=excluded.saved_at,last_edited_at=excluded.last_edited_at
                """) { query in
                try bind(report.day.calendarDate, to: query, at: 1)
                try bind(report.day.timeZoneIdentifier, to: query, at: 2)
                try bind(report.markdown, to: query, at: 3)
                guard sqlite3_bind_double(query, 4, report.savedAt.timeIntervalSince1970) == SQLITE_OK else {
                    throw ReportStorageError.writeFailed
                }
                let status = report.lastEditedAt.map { sqlite3_bind_double(query, 5, $0.timeIntervalSince1970) }
                    ?? sqlite3_bind_null(query, 5)
                guard status == SQLITE_OK, sqlite3_step(query) == SQLITE_DONE else { throw ReportStorageError.writeFailed }
            }
        }
    }

    func saveWindowSize(_ size: CGSize) throws {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw ReportStorageError.invalidData
        }
        try transaction {
            try statement("INSERT INTO window_state VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET width=excluded.width,height=excluded.height") { query in
                guard sqlite3_bind_double(query, 1, size.width) == SQLITE_OK,
                      sqlite3_bind_double(query, 2, size.height) == SQLITE_OK,
                      sqlite3_step(query) == SQLITE_DONE else { throw ReportStorageError.writeFailed }
            }
        }
    }

    func saveGeneralSettings(_ settings: DailyReportGeneralSettings) throws {
        guard settings.validationError == nil else { throw ReportStorageError.invalidData }
        try transaction {
            try statement("UPDATE general_settings SET time_zone_mode=?,fixed_time_zone=?,output_language=?,generation_preferences=?,history_lookback_days=? WHERE id=1") { query in
                try bind(settings.timeZoneMode.rawValue, to: query, at: 1)
                try bind(settings.fixedTimeZoneIdentifier, to: query, at: 2)
                try bind(settings.outputLanguage.rawValue, to: query, at: 3)
                try bind(settings.generationPreferences, to: query, at: 4)
                guard sqlite3_bind_int(query, 5, Int32(settings.historyLookbackDays)) == SQLITE_OK,
                      sqlite3_step(query) == SQLITE_DONE, sqlite3_changes(database) == 1 else {
                    throw ReportStorageError.writeFailed
                }
            }
        }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        do {
            try execute("BEGIN IMMEDIATE")
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw ReportStorageError.writeFailed
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw ReportStorageError.invalidData }
    }

    private func statement<T>(_ sql: String, _ operation: (OpaquePointer) throws -> T) throws -> T {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &query, nil) == SQLITE_OK, let query else {
            throw ReportStorageError.invalidData
        }
        defer { sqlite3_finalize(query) }
        return try operation(query)
    }

    private func next(_ query: OpaquePointer) throws -> Bool {
        switch sqlite3_step(query) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw ReportStorageError.invalidData
        }
    }

    private func bind(_ value: String, to query: OpaquePointer, at index: Int32) throws {
        let status = value.withCString { bytes in
            sqlite3_bind_text64(query, index, bytes, UInt64(value.utf8.count), transient, UInt8(SQLITE_UTF8))
        }
        guard status == SQLITE_OK else { throw ReportStorageError.writeFailed }
    }

    private func columnText(_ query: OpaquePointer, _ index: Int32) throws -> String {
        guard sqlite3_column_type(query, index) == SQLITE_TEXT, let bytes = sqlite3_column_text(query, index),
              let text = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(query, index))), encoding: .utf8) else {
            throw ReportStorageError.invalidData
        }
        return text
    }

    private func columnNumber(_ query: OpaquePointer, _ index: Int32) throws -> Double {
        guard [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(query, index)) else { throw ReportStorageError.invalidData }
        let value = sqlite3_column_double(query, index)
        guard value.isFinite else { throw ReportStorageError.invalidData }
        return value
    }

    private func columnDate(_ query: OpaquePointer, _ index: Int32) throws -> Date {
        Date(timeIntervalSince1970: try columnNumber(query, index))
    }

    private func integer(_ sql: String) throws -> Int32 {
        try statement(sql) { query in
            guard try next(query), sqlite3_column_type(query, 0) == SQLITE_INTEGER else { throw ReportStorageError.invalidData }
            return sqlite3_column_int(query, 0)
        }
    }

    private func validateColumns(_ table: String, expected: [(name: String, type: String, required: Bool, key: Int32)]) throws {
        var count = 0
        try statement("PRAGMA table_info(\(table))") { query in
            while try next(query) {
                guard count < expected.count else { throw ReportStorageError.invalidData }
                let column = expected[count]
                guard try columnText(query, 1) == column.name, try columnText(query, 2) == column.type,
                      (sqlite3_column_int(query, 3) != 0) == column.required,
                      sqlite3_column_int(query, 5) == column.key else { throw ReportStorageError.invalidData }
                count += 1
            }
        }
        guard count == expected.count,
              try integer("SELECT strict FROM pragma_table_list WHERE schema='main' AND name='\(table)'") == 1 else {
            throw ReportStorageError.invalidData
        }
    }

    private func text(_ sql: String) throws -> String {
        try statement(sql) { query in
            guard try next(query) else { throw ReportStorageError.invalidData }
            return try columnText(query, 0)
        }
    }
}
