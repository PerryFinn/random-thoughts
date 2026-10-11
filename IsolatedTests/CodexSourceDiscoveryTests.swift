import Darwin
import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct CodexSourceDiscoveryTests {
    @Test func directoryPriorityRejectsInvalidSelectionsAndResolvesOneIdentity() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let home = environment.directory.appendingPathComponent("home")
        let inherited = environment.directory.appendingPathComponent("inherited")
        let explicit = environment.directory.appendingPathComponent("explicit")
        let defaultDirectory = home.appendingPathComponent(".codex")
        for directory in [inherited, explicit, defaultDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let alias = environment.directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: explicit.path)
        let binary = try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"])
        var configuration = CodexDataSourceConfiguration(mode: .manual, executablePath: binary)
        let reader = CodexDataSourceReader(homeDirectory: home, environment: ["CODEX_HOME": inherited.path], homebrewDirectories: [], scanLockDirectory: environment.directory.appendingPathComponent("locks"))
        #expect(await reader.resolve(configuration, rediscover: false).settings.resolvedDirectory == inherited.path)
        configuration.explicitDirectory = alias.path
        let selected = await reader.resolve(configuration, rediscover: false)
        #expect(selected.settings.resolvedDirectory == explicit.path)
        #expect(selected.settings.configuration.explicitDirectory == alias.path)
        #expect(selected.error == nil)
        let missing = environment.directory.appendingPathComponent("missing").path
        configuration.explicitDirectory = missing
        let invalid = await reader.resolve(configuration, rediscover: false)
        #expect(invalid.error == .directoryMissing)
        #expect(invalid.settings.resolvedDirectory == nil)
        #expect(invalid.settings.configuration == configuration)
        #expect(!FileManager.default.fileExists(atPath: missing))
        configuration.explicitDirectory = ""
        let invalidInherited = CodexDataSourceReader(homeDirectory: home, environment: ["CODEX_HOME": ""], homebrewDirectories: [], scanLockDirectory: environment.directory.appendingPathComponent("locks"))
        #expect(await invalidInherited.resolve(configuration, rediscover: false).error == .invalidDirectory)
        let defaultReader = CodexDataSourceReader(homeDirectory: home, environment: [:], homebrewDirectories: [], scanLockDirectory: environment.directory.appendingPathComponent("locks"))
        #expect(await defaultReader.resolve(configuration, rediscover: false).settings.resolvedDirectory == defaultDirectory.path)
        configuration.explicitDirectory = explicit.path
        #expect(chmod(explicit.path, 0) == 0)
        defer { chmod(explicit.path, 0o700) }
        #expect(await reader.resolve(configuration, rediscover: false).error == .directoryPermission)
    }

    @Test func discoverySkipsPrivateBundlesAndManualPathsReportFixedRepairErrors() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let home = environment.directory.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let bundledDirectory = environment.directory.appendingPathComponent("Synthetic.app/Contents/MacOS")
        let publicDirectory = environment.directory.appendingPathComponent("public")
        for directory in [bundledDirectory, publicDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("codex").path,
                                                       withDestinationPath: try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"]))
        }
        let reader = CodexDataSourceReader(homeDirectory: home, environment: ["PATH": bundledDirectory.path + ":" + publicDirectory.path], homebrewDirectories: [], scanLockDirectory: environment.directory.appendingPathComponent("locks"))
        #expect(await reader.resolve(CodexDataSourceConfiguration(), rediscover: false).settings.configuration.executablePath == publicDirectory.appendingPathComponent("codex").path)
        var configuration = CodexDataSourceConfiguration(mode: .manual, executablePath: bundledDirectory.appendingPathComponent("codex").path)
        #expect(await reader.resolve(configuration, rediscover: false).error == .invalidExecutable)
        configuration.executablePath = "relative/codex"
        #expect(await reader.resolve(configuration, rediscover: false).error == .invalidExecutable)
        configuration.executablePath = publicDirectory.path
        #expect(await reader.resolve(configuration, rediscover: false).error == .invalidExecutable)
        let denied = environment.directory.appendingPathComponent("non-executable")
        try Data("SYNTHETIC_NOT_AN_EXECUTABLE".utf8).write(to: denied)
        #expect(chmod(denied.path, 0o600) == 0)
        configuration.executablePath = denied.path
        #expect(await reader.resolve(configuration, rediscover: false).error == .executablePermission)
    }

    @Test func discoveryFollowsTheFourLevelsAndKeepsAChosenEntryUntilRediscovery() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let home = environment.directory.appendingPathComponent("home")
        let directories = [home.appendingPathComponent(".local/bin"), environment.directory.appendingPathComponent("path"),
                           environment.directory.appendingPathComponent("apple/bin"), environment.directory.appendingPathComponent("intel/bin")]
        let binary = try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_CODEX_PROBE"])
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let entry = directory.appendingPathComponent("codex")
            try FileManager.default.createSymbolicLink(atPath: entry.path, withDestinationPath: binary)
        }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let reader = CodexDataSourceReader(homeDirectory: home, environment: ["PATH": "relative:" + directories[1].path],
                                          homebrewDirectories: Array(directories.suffix(2)),
                                          scanLockDirectory: environment.directory.appendingPathComponent("locks"))
        var selection = await reader.resolve(CodexDataSourceConfiguration(), rediscover: false)
        #expect(selection.settings.identity == CodexSourceIdentity(executablePath: directories[0].appendingPathComponent("codex").path,
                                                                  dataDirectory: home.appendingPathComponent(".codex").path))
        for index in 0..<3 {
            try FileManager.default.removeItem(at: directories[index].appendingPathComponent("codex"))
            let retained = await reader.resolve(selection.settings.configuration, rediscover: false)
            #expect(retained.error == .executableMissing)
            #expect(retained.settings.configuration == selection.settings.configuration)
            selection = await reader.resolve(selection.settings.configuration, rediscover: true)
            #expect(selection.settings.configuration.executablePath == directories[index + 1].appendingPathComponent("codex").path)
            #expect(selection.settings.configuration.mode == .automatic)
        }
    }
}
