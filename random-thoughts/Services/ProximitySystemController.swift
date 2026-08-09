import AppKit
import ApplicationServices
import Foundation
import Security
import ServiceManagement
import UserNotifications

@MainActor
protocol ProximitySystemControlling: AnyObject {
    var isScreenLocked: Bool { get }
    var isAccessibilityTrusted: Bool { get }
    var containsPassword: Bool { get }
    var isLaunchAtLoginRequested: Bool { get }
    var applicationScriptURL: URL? { get }

    func requestAccessibilityPermission()
    func promptForPassword() -> String?
    func storePassword(_ password: String) throws
    func fetchPassword() throws -> String?
    func deletePassword() throws
    func lockScreen(useScreensaver: Bool, turnOffDisplay: Bool) throws
    func wakeDisplay()
    func sendEscapeKey()
    func enterPassword(_ password: String)
    func pauseNowPlaying(completion: @escaping (Bool) -> Void)
    func resumeNowPlaying()
    func runEventScript(argument: String, rssi: Int?)
    func openApplicationScriptsFolder()
    func requestNotificationAuthorization()
    func notifyLocked(reason: ProximityPresenceReason)
    func removeLockNotification()
    func notifyUpdateAvailable(version: String, releasesURL: URL)
    func setLaunchAtLogin(_ enabled: Bool) throws
    func presentBluetoothPowerWarning()
}

@MainActor
final class ProximitySystemController: NSObject, ProximitySystemControlling {
    private static let lockNotificationIdentifier = "proximity.locked"
    private static let updateNotificationIdentifier = "application.update.available"

    private var keychainService: String {
        (Bundle.main.bundleIdentifier ?? "com.perryfinn.random-thoughts")
            + ".proximity-unlock"
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var isScreenLocked: Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let locked = dictionary["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        if let locked = dictionary["CGSSessionScreenIsLocked"] as? Int {
            return locked == 1
        }
        return false
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var containsPassword: Bool {
        var query = keychainQuery
        query[String(kSecMatchLimit)] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    var isLaunchAtLoginRequested: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var applicationScriptURL: URL? {
        try? FileManager.default
            .url(
                for: .applicationScriptsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("event")
    }

    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
        )
        if !trusted {
            // Posting a harmless Fn key event is the fallback BLEUnlock uses when
            // macOS does not surface the accessibility prompt from the check alone.
            postKey(code: 63, isDown: true)
            postKey(code: 63, isDown: false)
        }
    }

    func promptForPassword() -> String? {
        let alert = NSAlert()
        alert.messageText = "设置蓝牙解锁密码"
        alert.informativeText = "请输入当前 macOS 登录密码。密码将存储在登录钥匙串中，并仅在锁屏界面自动解锁时读取。"
        alert.addButton(withTitle: "存储密码")
        alert.addButton(withTitle: "取消")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "macOS 登录密码"
        alert.accessoryView = field

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              !field.stringValue.isEmpty else {
            return nil
        }
        return field.stringValue
    }

    func storePassword(_ password: String) throws {
        var query = keychainQuery
        SecItemDelete(query as CFDictionary)
        query[String(kSecAttrLabel)] = "随想蓝牙解锁密码"
        query[String(kSecValueData)] = Data(password.utf8)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProximitySystemError.keychain(status)
        }
    }

    func fetchPassword() throws -> String? {
        var query = keychainQuery
        query[String(kSecReturnData)] = kCFBooleanTrue
        query[String(kSecMatchLimit)] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw ProximitySystemError.keychain(status)
        }
        return password
    }

    func deletePassword() throws {
        let status = SecItemDelete(keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProximitySystemError.keychain(status)
        }
    }

    func lockScreen(useScreensaver: Bool, turnOffDisplay: Bool) throws {
        if useScreensaver {
            let url = URL(
                fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"
            )
            NSWorkspace.shared.open(url)
            return
        }

        if RTLockScreenImmediate() != 0 {
            throw ProximitySystemError.lockFailed
        }

        if turnOffDisplay {
            RTSleepDisplay()
        }
    }

    func wakeDisplay() {
        RTWakeDisplay()
    }

    func sendEscapeKey() {
        postKey(code: 0x35, isDown: true)
        postKey(code: 0x35, isDown: false)
    }

    func enterPassword(_ password: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let charactersPerEvent = 20
        let utf16 = Array(password.utf16)

        for offset in stride(from: 0, to: utf16.count, by: charactersPerEvent) {
            let end = min(offset + charactersPerEvent, utf16.count)
            let characters = Array(utf16[offset..<end])
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: 49,
                keyDown: true
            )
            characters.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                event?.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
            }
            event?.post(tap: .cghidEventTap)
            CGEvent(
                keyboardEventSource: source,
                virtualKey: 49,
                keyDown: false
            )?.post(tap: .cghidEventTap)
        }

        postKey(code: 52, isDown: true)
        postKey(code: 52, isDown: false)
    }

    func pauseNowPlaying(completion: @escaping (Bool) -> Void) {
        RTGetNowPlayingApplicationIsPlaying(.main) { isPlaying in
            if isPlaying {
                _ = RTSendMediaCommand(RTMediaCommandPause)
            }
            completion(isPlaying)
        }
    }

    func resumeNowPlaying() {
        _ = RTSendMediaCommand(RTMediaCommandPlay)
    }

    func runEventScript(argument: String, rssi: Int?) {
        guard let applicationScriptURL,
              FileManager.default.isExecutableFile(atPath: applicationScriptURL.path) else {
            return
        }

        let process = Process()
        process.executableURL = applicationScriptURL
        process.arguments = [argument] + (rssi.map { [String($0)] } ?? [])
        try? process.run()
    }

    func openApplicationScriptsFolder() {
        guard let applicationScriptURL else { return }
        let directory = applicationScriptURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(directory)
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func notifyLocked(reason: ProximityPresenceReason) {
        let content = UNMutableNotificationContent()
        content.title = "随想"
        content.subtitle = reason == .lost ? "蓝牙信号丢失" : "设备已经远离"
        content.body = "这台 Mac 已由蓝牙接近功能锁定。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.lockNotificationIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    func removeLockNotification() {
        let identifiers = [Self.lockNotificationIdentifier]
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: identifiers
        )
    }

    func notifyUpdateAvailable(version: String, releasesURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "随想有新版本"
        content.subtitle = version
        content.userInfo = ["url": releasesURL.absoluteString]

        let request = UNNotificationRequest(
            identifier: Self.updateNotificationIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    func presentBluetoothPowerWarning() {
        let alert = NSAlert()
        alert.messageText = "蓝牙已关闭"
        alert.informativeText = "请打开蓝牙，以继续使用自动锁定和解锁功能。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private var keychainQuery: [String: Any] {
        [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): NSUserName(),
            String(kSecAttrService): keychainService
        ]
    }

    private func postKey(code: CGKeyCode, isDown: Bool) {
        CGEvent(
            keyboardEventSource: CGEventSource(stateID: .hidSystemState),
            virtualKey: code,
            keyDown: isDown
        )?.post(tap: .cghidEventTap)
    }
}

extension ProximitySystemController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: value) else {
            return
        }
        _ = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}

enum ProximitySystemEvent: Sendable {
    case displaySleep
    case displayWake
    case systemSleep
    case systemWake
    case screenUnlocked
    case screensaverStarted
    case screensaverStopped
}

@MainActor
final class ProximitySystemEventMonitor: NSObject {
    var handler: ((ProximitySystemEvent) -> Void)?

    override init() {
        super.init()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(displayDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(screensaverDidStart),
            name: Notification.Name("com.apple.screensaver.didstart"),
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(screensaverDidStop),
            name: Notification.Name("com.apple.screensaver.didstop"),
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func displayDidSleep() { handler?(.displaySleep) }
    @objc private func displayDidWake() { handler?(.displayWake) }
    @objc private func systemWillSleep() { handler?(.systemSleep) }
    @objc private func systemDidWake() { handler?(.systemWake) }
    @objc private func screenDidUnlock() { handler?(.screenUnlocked) }
    @objc private func screensaverDidStart() { handler?(.screensaverStarted) }
    @objc private func screensaverDidStop() { handler?(.screensaverStopped) }
}

enum ProximitySystemError: LocalizedError {
    case keychain(OSStatus)
    case lockFailed

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "钥匙串操作失败（\(status)）"
        case .lockFailed:
            return "系统拒绝了锁屏请求。"
        }
    }
}

struct ReleaseUpdateChecker: Sendable {
    private let endpoint = URL(
        string: "https://api.github.com/repos/PerryFinn/random-thoughts/releases/latest"
    )!
    let releasesURL = URL(
        string: "https://github.com/PerryFinn/random-thoughts/releases"
    )!

    func latestVersion() async -> String? {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("random-thoughts", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["tag_name"] as? String
    }

    static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let candidateComponents = numericVersionComponents(candidate)
        let currentComponents = numericVersionComponents(current)
        guard !candidateComponents.isEmpty,
              !currentComponents.isEmpty else {
            return candidate.compare(current, options: .numeric) == .orderedDescending
        }

        let componentCount = max(candidateComponents.count, currentComponents.count)
        for index in 0..<componentCount {
            let candidateValue = index < candidateComponents.count
                ? candidateComponents[index]
                : 0
            let currentValue = index < currentComponents.count
                ? currentComponents[index]
                : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }
        return false
    }

    private static func numericVersionComponents(_ version: String) -> [Int] {
        let normalized = version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? version
        var components: [Int] = []
        for component in normalized.split(separator: ".") {
            guard let value = Int(component) else { return [] }
            components.append(value)
        }
        return components
    }
}
