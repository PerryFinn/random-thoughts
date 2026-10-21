import Darwin
import Foundation
import SQLite3

actor DailyReportDatabase: DailyReportStorage {
    var dataDirectory: URL? { directory }
    private let directory: URL
    private var connection: ReportSQLiteConnection?
    private var directoryAccess: ReportStorageDirectory?
    private let credentialCodec: AICredentialCodec
    private let resetProgress: @Sendable (ReportResetPhase) throws -> Void

    init(directory: URL, credentialCodec: AICredentialCodec = .bundled(),
         resetProgress: @escaping @Sendable (ReportResetPhase) throws -> Void = { _ in }) {
        self.directory = directory
        self.credentialCodec = credentialCodec
        self.resetProgress = resetProgress
    }

    func close() { connection = nil; directoryAccess = nil }

    func reset() async throws -> ReportStorageSnapshot {
        let access = try acquireDirectory()
        connection = nil
        do {
            try access.recordResetIntent()
            try resetProgress(.intentRecorded)
            try access.removeDatabaseFiles()
            try resetProgress(.filesRemoved)
            let fresh = try ReportSQLiteConnection(directory: directory, credentialCodec: credentialCodec)
            let snapshot = try fresh.load()
            try resetProgress(.databaseInitialized)
            try access.completeReset()
            connection = fresh
            return snapshot
        } catch { throw ReportStorageError.resetIncomplete }
    }

    func load() async throws -> ReportStorageSnapshot {
        if connection == nil, try acquireDirectory().hasConfirmedReset() { return try await reset() }
        return try open().load()
    }
    func save(_ report: SavedDailyReport) async throws { try open().save(report) }
    func deleteReports(day: ReportDay?) async throws { try open().deleteReports(day: day) }
    func saveWindowSize(_ size: CGSize) async throws { try open().saveWindowSize(size) }
    func saveGeneralSettings(_ settings: DailyReportGeneralSettings) async throws { try open().saveGeneralSettings(settings) }
    func saveAIService(_ service: SavedAIService) async throws { try open().saveAIService(service) }
    func saveAIValidation(_ proof: AIServiceValidation, matching baseline: AIValidationBaseline) async throws -> Bool {
        try Task.checkCancellation()
        return try open().saveAIValidation(proof, matching: baseline)
    }
    func saveCurrentAIService(_ service: AIServiceType) async throws { try open().saveCurrentAIService(service) }
    func saveCodexSource(_ settings: CodexDataSourceSettings) async throws { try open().saveCodexSource(settings) }
    func saveCodexDiagnostic(identity: CodexSourceIdentity, checkedAt: Date, version: CodexVersion?) async throws {
        try open().saveCodexDiagnostic(identity: identity, checkedAt: checkedAt, version: version)
    }

    private func open() throws -> ReportSQLiteConnection {
        try Task.checkCancellation()
        if let connection { return connection }
        let access = try acquireDirectory()
        guard try !access.hasConfirmedReset() else { throw ReportStorageError.recoveryRequired }
        let opened = try ReportSQLiteConnection(directory: directory, credentialCodec: credentialCodec)
        connection = opened
        return opened
    }

    private func acquireDirectory() throws -> ReportStorageDirectory {
        if let directoryAccess { return directoryAccess }
        let access = try ReportStorageDirectory(directory)
        directoryAccess = access
        return access
    }
}

// The database actor exclusively owns this connection, under its separate directory lock.
private nonisolated final class ReportSQLiteConnection {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL, credentialCodec: AICredentialCodec) throws {
        let url = directory.appendingPathComponent("reports.sqlite")
        let exists = try ReportStorageDirectory.exists(url)
        if !exists {
            for name in ["reports.sqlite-journal", "reports.sqlite-wal", "reports.sqlite-shm"] {
                if try ReportStorageDirectory.exists(directory.appendingPathComponent(name)) { throw ReportStorageError.recoveryRequired }
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
        let version = exists ? try integer("PRAGMA user_version") : 0
        if exists {
            guard (1...5).contains(version) else { throw ReportStorageError.unsupportedVersion }
            guard try text("PRAGMA quick_check") == "ok" else { throw ReportStorageError.invalidData }
            try validateSchema(version: version)
        }
        try execute("PRAGMA journal_mode=DELETE; PRAGMA synchronous=EXTRA; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY")
        guard try text("PRAGMA journal_mode") == "delete",
              try integer("PRAGMA synchronous") == 3,
              try integer("PRAGMA secure_delete") == 1 else { throw ReportStorageError.unavailable }
        if version < 5 {
            do {
                try transaction {
                    if version < 1 {
                        try execute("""
                        CREATE TABLE reports (
                            calendar_date TEXT NOT NULL, time_zone TEXT NOT NULL, markdown TEXT NOT NULL,
                            saved_at REAL NOT NULL, last_edited_at REAL,
                            PRIMARY KEY (calendar_date, time_zone)
                        ) STRICT;
                        CREATE TABLE window_state (
                            id INTEGER PRIMARY KEY CHECK(id=1), width REAL NOT NULL, height REAL NOT NULL
                        ) STRICT;
                        """)
                    }
                    if version < 2 {
                        try execute("""
                        CREATE TABLE general_settings (
                            id INTEGER PRIMARY KEY CHECK(id=1), time_zone_mode TEXT NOT NULL,
                            fixed_time_zone TEXT NOT NULL, output_language TEXT NOT NULL,
                            generation_preferences TEXT NOT NULL, history_lookback_days INTEGER NOT NULL
                        ) STRICT;
                        INSERT INTO general_settings VALUES(1,'followMac','Etc/UTC','chinese','',1);
                        """)
                    }
                    if version < 3 {
                        try execute("""
                        CREATE TABLE codex_source (
                            id INTEGER PRIMARY KEY CHECK(id=1), mode TEXT NOT NULL,
                            executable_path TEXT NOT NULL, explicit_directory TEXT NOT NULL,
                            resolved_directory TEXT, last_successful_check REAL, version TEXT
                        ) STRICT;
                        INSERT INTO codex_source VALUES(1,'automatic','','',NULL,NULL,NULL);
                        """)
                    }
                    if version < 4 {
                        try execute("""
                        CREATE TABLE ai_services (protocol TEXT PRIMARY KEY NOT NULL, record TEXT NOT NULL) STRICT;
                        CREATE TABLE ai_selection (id INTEGER PRIMARY KEY CHECK(id=1), protocol TEXT) STRICT;
                        INSERT INTO ai_selection VALUES(1,NULL);
                        """)
                        for service in AIServiceType.allCases {
                            try writeAIService(SavedAIService(configuration: AIServiceConfiguration(service: service)), insert: true)
                        }
                    }
                    try validateSchema(version: 5)
                    let old = try load()
                    for var service in old.aiServices.configurations.values {
                        guard let envelope = service.credential, envelope.formatVersion == 1 else { continue }
                        let value: String
                        do { value = try credentialCodec.open(envelope) }
                        catch AICredentialError.unsupportedFormat { continue }
                        catch AICredentialError.unknownKeyVersion { continue }
                        catch AICredentialError.authenticationFailed { continue }
                        service.credential = try credentialCodec.seal(value)
                        try writeAIService(service, insert: false)
                    }
                    try execute("PRAGMA user_version=5")
                    _ = try load()
                }
            } catch { throw exists ? ReportStorageError.migrationFailed : .writeFailed }
        }
        _ = try load()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private func validateSchema(version: Int32) throws {
        var names: Set<String> = ["reports", "window_state"]
        if version >= 2 { names.insert("general_settings") }
        if version >= 3 { names.insert("codex_source") }
        if version >= 4 { names.formUnion(["ai_services", "ai_selection"]) }
        var actual: Set<String> = []
        try statement("SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'") { query in
            while try next(query) { actual.insert(try columnText(query, 0)) }
        }
        guard actual == names else { throw ReportStorageError.invalidData }
        try validateColumns("reports", expected: [
            ("calendar_date", "TEXT", true, 1), ("time_zone", "TEXT", true, 2),
            ("markdown", "TEXT", true, 0), ("saved_at", "REAL", true, 0), ("last_edited_at", "REAL", false, 0)
        ])
        try validateColumns("window_state", expected: [
            ("id", "INTEGER", false, 1), ("width", "REAL", true, 0), ("height", "REAL", true, 0)
        ])
        if version >= 2 {
            try validateColumns("general_settings", expected: [
                ("id", "INTEGER", false, 1), ("time_zone_mode", "TEXT", true, 0),
                ("fixed_time_zone", "TEXT", true, 0), ("output_language", "TEXT", true, 0),
                ("generation_preferences", "TEXT", true, 0), ("history_lookback_days", "INTEGER", true, 0)
            ])
        }
        if version >= 3 {
            try validateColumns("codex_source", expected: [
                ("id", "INTEGER", false, 1), ("mode", "TEXT", true, 0),
                ("executable_path", "TEXT", true, 0), ("explicit_directory", "TEXT", true, 0),
                ("resolved_directory", "TEXT", false, 0), ("last_successful_check", "REAL", false, 0),
                ("version", "TEXT", false, 0)
            ])
        }
        if version >= 4 {
            try validateColumns("ai_services", expected: [("protocol", "TEXT", true, 1), ("record", "TEXT", true, 0)])
            try validateColumns("ai_selection", expected: [("id", "INTEGER", false, 1), ("protocol", "TEXT", false, 0)])
        }
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
        let source = try statement("SELECT id,mode,executable_path,explicit_directory,resolved_directory,last_successful_check,version FROM codex_source") { query in
            guard try next(query), sqlite3_column_type(query, 0) == SQLITE_INTEGER, sqlite3_column_int64(query, 0) == 1,
                  let mode = try CodexDiscoveryMode(rawValue: columnText(query, 1)) else { throw ReportStorageError.invalidData }
            let directory = sqlite3_column_type(query, 4) == SQLITE_NULL ? nil : try columnText(query, 4)
            let checkedAt = sqlite3_column_type(query, 5) == SQLITE_NULL ? nil : try columnDate(query, 5)
            let rawVersion = sqlite3_column_type(query, 6) == SQLITE_NULL ? nil : try columnText(query, 6)
            let version = rawVersion.flatMap(CodexVersion.init)
            guard rawVersion == nil || version?.description == rawVersion,
                  directory == nil || (directory!.hasPrefix("/") && !directory!.contains("\u{0}")),
                  version == nil || checkedAt != nil else { throw ReportStorageError.invalidData }
            let value = CodexDataSourceSettings(
                configuration: CodexDataSourceConfiguration(mode: mode, executablePath: try columnText(query, 2), explicitDirectory: try columnText(query, 3)),
                resolvedDirectory: directory, lastSuccessfulCheck: checkedAt, version: version
            )
            guard checkedAt == nil || value.identity != nil, try !next(query) else { throw ReportStorageError.invalidData }
            return value
        }
        var aiServices = AIServiceSettings()
        aiServices.configurations.removeAll()
        try statement("SELECT protocol,record FROM ai_services") { query in
            while try next(query) {
                guard let type = try AIServiceType(rawValue: columnText(query, 0)),
                      let data = try columnText(query, 1).data(using: .utf8),
                      let record = try? JSONDecoder().decode(SavedAIService.self, from: data),
                      record.configuration.service == type, record.configuration.inputError == nil,
                      record.credentialVersion >= 0, record.credential == nil || record.credentialVersion > 0,
                      record.validation.checkedAt?.timeIntervalSince1970.isFinite != false,
                      aiServices.configurations[type] == nil else {
                    throw ReportStorageError.invalidData
                }
                aiServices.configurations[type] = record
            }
        }
        guard aiServices.configurations.count == AIServiceType.allCases.count else { throw ReportStorageError.invalidData }
        try statement("SELECT id,protocol FROM ai_selection") { query in
            guard try next(query), sqlite3_column_type(query, 0) == SQLITE_INTEGER, sqlite3_column_int64(query, 0) == 1 else {
                throw ReportStorageError.invalidData
            }
            if sqlite3_column_type(query, 1) != SQLITE_NULL {
                guard let type = try AIServiceType(rawValue: columnText(query, 1)) else { throw ReportStorageError.invalidData }
                aiServices.current = type
            }
            guard try !next(query) else { throw ReportStorageError.invalidData }
        }
        return ReportStorageSnapshot(reports: reports, windowSize: size, generalSettings: settings, codexSource: source, aiServices: aiServices)
    }

    func saveAIService(_ service: SavedAIService) throws {
        guard service.configuration.inputError == nil, service.credentialVersion >= 0 else { throw ReportStorageError.invalidData }
        try transaction { try writeAIService(service, insert: false) }
    }

    func saveAIValidation(_ proof: AIServiceValidation, matching baseline: AIValidationBaseline) throws -> Bool {
        var applied = false
        try transaction {
            try statement("SELECT record FROM ai_services WHERE protocol=?") { query in
                try bind(baseline.service.rawValue, to: query, at: 1)
                guard try next(query) else { throw ReportStorageError.invalidData }
                var saved = try JSONDecoder().decode(SavedAIService.self, from: Data(columnText(query, 0).utf8))
                guard saved.requestBaseline == baseline else { return }
                try Task.checkCancellation()
                saved.validation = proof
                try writeAIService(saved, insert: false)
                applied = true
            }
        }
        return applied
    }

    func saveCurrentAIService(_ service: AIServiceType) throws {
        try transaction {
            try statement("UPDATE ai_selection SET protocol=? WHERE id=1") { query in
                try bind(service.rawValue, to: query, at: 1)
                guard sqlite3_step(query) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw ReportStorageError.writeFailed }
            }
        }
    }

    private func writeAIService(_ service: SavedAIService, insert: Bool) throws {
        let record = String(decoding: try JSONEncoder().encode(service), as: UTF8.self)
        let sql = insert ? "INSERT INTO ai_services(record,protocol) VALUES(?,?)" : "UPDATE ai_services SET record=? WHERE protocol=?"
        try statement(sql) { query in
            try bind(record, to: query, at: 1)
            try bind(service.configuration.service.rawValue, to: query, at: 2)
            guard sqlite3_step(query) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw ReportStorageError.writeFailed }
        }
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

    func deleteReports(day: ReportDay?) throws {
        try transaction {
            try statement(day == nil ? "DELETE FROM reports" : "DELETE FROM reports WHERE calendar_date=? AND time_zone=?") { query in
                if let day {
                    try bind(day.calendarDate, to: query, at: 1)
                    try bind(day.timeZoneIdentifier, to: query, at: 2)
                }
                guard sqlite3_step(query) == SQLITE_DONE else { throw ReportStorageError.writeFailed }
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

    func saveCodexSource(_ settings: CodexDataSourceSettings) throws {
        guard settings.lastSuccessfulCheck?.timeIntervalSince1970.isFinite != false,
              settings.lastSuccessfulCheck == nil || settings.identity != nil,
              settings.version == nil || settings.lastSuccessfulCheck != nil else { throw ReportStorageError.invalidData }
        try transaction {
            try statement("UPDATE codex_source SET mode=?,executable_path=?,explicit_directory=?,resolved_directory=?,last_successful_check=?,version=? WHERE id=1") { query in
                try bind(settings.configuration.mode.rawValue, to: query, at: 1)
                try bind(settings.configuration.executablePath, to: query, at: 2)
                try bind(settings.configuration.explicitDirectory, to: query, at: 3)
                try bindOptional(settings.resolvedDirectory, to: query, at: 4)
                let status = settings.lastSuccessfulCheck.map { sqlite3_bind_double(query, 5, $0.timeIntervalSince1970) } ?? sqlite3_bind_null(query, 5)
                try bindOptional(settings.version?.description, to: query, at: 6)
                guard status == SQLITE_OK, sqlite3_step(query) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw ReportStorageError.writeFailed }
            }
        }
    }

    func saveCodexDiagnostic(identity: CodexSourceIdentity, checkedAt: Date, version: CodexVersion?) throws {
        guard checkedAt.timeIntervalSince1970.isFinite else { throw ReportStorageError.invalidData }
        try transaction {
            try statement("UPDATE codex_source SET last_successful_check=?,version=? WHERE id=1 AND executable_path=? AND resolved_directory=?") { query in
                guard sqlite3_bind_double(query, 1, checkedAt.timeIntervalSince1970) == SQLITE_OK else { throw ReportStorageError.writeFailed }
                try bindOptional(version?.description, to: query, at: 2)
                try bind(identity.executablePath, to: query, at: 3)
                try bind(identity.dataDirectory, to: query, at: 4)
                guard sqlite3_step(query) == SQLITE_DONE else { throw ReportStorageError.writeFailed }
            }
        }
    }

    private func bindOptional(_ value: String?, to query: OpaquePointer, at index: Int32) throws {
        if let value { try bind(value, to: query, at: index) }
        else if sqlite3_bind_null(query, index) != SQLITE_OK { throw ReportStorageError.writeFailed }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        do {
            try execute("BEGIN IMMEDIATE")
            try operation()
            try Task.checkCancellation()
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
