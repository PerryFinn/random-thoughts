import Darwin
import Bootstrap
import Foundation
import Testing

struct IsolationBoundaryTests {
    @Test func deniesBluetoothServiceLookup() {
        var bootstrap = mach_port_t(MACH_PORT_NULL)
        let status = task_get_special_port(mach_task_self_, TASK_BOOTSTRAP_PORT, &bootstrap)
        #expect(status == KERN_SUCCESS)
        defer { mach_port_deallocate(mach_task_self_, bootstrap) }
        var service = mach_port_t(MACH_PORT_NULL)
        let result = bootstrap_look_up(bootstrap, "com.apple.bluetoothd", &service)
        if result == KERN_SUCCESS { mach_port_deallocate(mach_task_self_, service) }

        #expect(result == BOOTSTRAP_NOT_PRIVILEGED)
    }

    @Test func deniesReadingProductionUserDirectories() throws {
        let home = try #require(ProcessInfo.processInfo.environment["RANDOM_THOUGHTS_PROTECTED_HOME"])
        let descriptor = open(home + "/.codex", O_RDONLY | O_DIRECTORY)
        let error = errno
        if descriptor >= 0 { close(descriptor) }

        #expect(descriptor == -1)
        #expect(error == EPERM)
    }

    @Test func deniesUncontrolledSubprocesses() throws {
        let command = try #require(strdup("/usr/bin/true"))
        defer { free(command) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [command, nil]
        var child = pid_t()
        let result = posix_spawn(&child, command, nil, nil, &arguments, nil)
        if result == 0 { waitpid(child, nil, 0) }

        #expect(result == EPERM)
    }

    @Test func deniesUncontrolledNetworkConnections() {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        if descriptor < 0 {
            #expect(errno == EPERM)
            return
        }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let error = errno

        #expect(result == -1)
        #expect(error == EPERM)
    }

    @Test @MainActor func keepsTemporaryStorageAndPreferencesIndependent() throws {
        let first = try IsolatedTestEnvironment()
        defer { first.close() }
        let second = try IsolatedTestEnvironment()
        defer { second.close() }

        first.defaults.set("synthetic-only", forKey: "isolationMarker")
        try Data("synthetic-storage".utf8).write(to: first.databaseURL)

        #expect(first.databaseURL != second.databaseURL)
        #expect(first.credentialKey.count == 32)
        #expect(second.defaults.string(forKey: "isolationMarker") == nil)
        #expect(!FileManager.default.fileExists(atPath: second.databaseURL.path))
        let directory = first.directory
        first.close()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(first.defaults.string(forKey: "isolationMarker") == nil)
    }
}
