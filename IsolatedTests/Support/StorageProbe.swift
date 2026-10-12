import Foundation
import Testing

@MainActor
func runStorageProbe(_ scenario: String, directory: URL) throws -> Int32 {
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
