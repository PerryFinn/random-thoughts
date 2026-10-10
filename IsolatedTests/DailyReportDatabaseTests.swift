import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct DailyReportDatabaseTests {
    @Test func directoryLockExcludesAnotherProcessAndReleasesWithTheOwner() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        var owner: DailyReportDatabase? = DailyReportDatabase(directory: environment.directory)
        _ = try await owner?.load()
        #expect(try runStorageProbe("open", directory: environment.directory) == 73)
        owner = nil
        #expect(try runStorageProbe("open", directory: environment.directory) == 0)
    }

    @Test(arguments: ["commit-failure", "unsupported", "bad-field", "missing-with-journal", "missing-with-reset", "existing-with-reset", "permissions", "bad-schema", "duplicate-day"])
    func storageFaultsPreserveDataInDedicatedProcesses(_ scenario: String) throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        #expect(try runStorageProbe(scenario, directory: environment.directory) == 0)
    }

    @Test func sqlitePersistsOnlyExplicitRawReportsAndNormalSize() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let database = DailyReportDatabase(directory: environment.directory)
        let empty = try await database.load()
        #expect(empty.reports.isEmpty)
        let day = ReportDay(date: environment.clock.now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let raw = " 合成 RAW_STORAGE_23\u{0}é\n\n尾行  \n"
        let report = SavedDailyReport(day: day, markdown: raw, savedAt: environment.clock.now, lastEditedAt: nil)
        try await database.save(report)
        try await database.saveWindowSize(CGSize(width: 1234, height: 789))
        let loaded = try await database.load()
        #expect(loaded.reports == [report])
        #expect(loaded.reports.first?.markdown.utf8.elementsEqual(raw.utf8) == true)
        #expect(loaded.windowSize == CGSize(width: 1234, height: 789))
        let attributes = try FileManager.default.attributesOfItem(atPath: environment.databaseURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: environment.directory.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let files = try FileManager.default.contentsOfDirectory(atPath: environment.directory.path)
        #expect(Set(files) == ["reports.sqlite", "storage.lock"])
    }
}

@MainActor
private func runStorageProbe(_ scenario: String, directory: URL) throws -> Int32 {
    let path = try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_STORAGE_PROBE"])
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = [scenario, directory.path]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}
