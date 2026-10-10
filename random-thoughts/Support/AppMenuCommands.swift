import AppKit

@MainActor
final class AppMenuCommands: NSObject, NSMenuItemValidation {
    private let flow: DailyReportFlow
    private let keyWindowKind: () -> AppWindowKind?

    init(flow: DailyReportFlow, keyWindowKind: @escaping () -> AppWindowKind?) {
        self.flow = flow
        self.keyWindowKind = keyWindowKind
    }

    func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let application = NSMenu(title: "随想")
        application.addItem(item("显示工作日报", action: #selector(showReport), key: "1"))
        application.addItem(item("设置…", action: #selector(showSettings), key: ","))
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
        window.addItem(item("最小化日报", action: #selector(minimizeReport), key: "m"))
        add(window, to: menu)
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(minimizeReport) { return keyWindowKind() == .report }
        if menuItem.action == #selector(closeWindow) { return keyWindowKind() != nil }
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

    @objc private func showReport() { flow.send(.open(.report)) }
    @objc private func showSettings() { flow.send(.open(.settings)) }
    @objc private func closeWindow() { flow.send(.closeKeyWindow) }
    @objc private func minimizeReport() { flow.send(.minimizeReport) }
    @objc private func hide() { flow.send(.hide) }
    @objc private func quit() { flow.send(.quit) }
}
