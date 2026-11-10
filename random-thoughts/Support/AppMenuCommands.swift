import AppKit

@MainActor
final class AppMenuCommands: NSObject, NSMenuItemValidation {
    private let showSettings: () -> Void
    private let isSettingsKeyWindow: () -> Bool

    init(showSettings: @escaping () -> Void, isSettingsKeyWindow: @escaping () -> Bool) {
        self.showSettings = showSettings
        self.isSettingsKeyWindow = isSettingsKeyWindow
    }

    static func openSettingsFromMenuBarPanel(dismissPanel: () -> Void, showSettings: () -> Void) {
        dismissPanel()
        showSettings()
    }

    func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let application = NSMenu(title: "随想")
        application.addItem(item("设置…", action: #selector(openSettings), key: ","))
        application.addItem(.separator())
        application.addItem(item("隐藏随想", action: #selector(hide), key: "h"))
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        application.addItem(hideOthers)
        application.addItem(NSMenuItem(title: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        application.addItem(.separator())
        application.addItem(item("退出随想", action: #selector(quit), key: "q"))
        add(application, to: menu)

        let editing = NSMenu(title: "编辑")
        for (title, selector, key) in [
            ("撤销", "undo:", "z"), ("重做", "redo:", "Z"),
            ("剪切", "cut:", "x"), ("复制", "copy:", "c"),
            ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")
        ] {
            let item = NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key.lowercased())
            item.keyEquivalentModifierMask = key == "Z" ? [.command, .shift] : .command
            editing.addItem(item)
        }
        add(editing, to: menu)

        let window = NSMenu(title: "窗口")
        window.addItem(item("关闭窗口", action: #selector(closeWindow), key: "w"))
        add(window, to: menu)
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeWindow) { return isSettingsKeyWindow() }
        return true
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = .command
        return item
    }

    private func add(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func openSettings() { showSettings() }

    @objc private func closeWindow() {
        if isSettingsKeyWindow() {
            NSApplication.shared.keyWindow?.performClose(nil)
        }
    }

    @objc private func hide() { NSApplication.shared.hide(nil) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
