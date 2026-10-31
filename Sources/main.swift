import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private var settings = Settings()
    private lazy var lifecycle = ConfigurationLifecycle { [weak self] in self?.showSettings() }
    private var settingsWindow: NSWindow?
    private var terminalPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private var modePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private var commandField = NSTextField()
    private let saveStatus = NSTextField(wrappingLabelWithString: "")
    private let toolbarStatus = NSTextField(wrappingLabelWithString: "添加只新增本入口，保留其他按钮，并先保存恢复备份。")
    private lazy var toolbarInstaller = ToolbarInstaller(store: FinderToolbarStore(), backups: FileToolbarBackupRepository(directory: SettingsStore().fileURL.deletingLastPathComponent().appendingPathComponent("ToolbarPlans", isDirectory: true)))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "FolderTerm 设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 FolderTerm", action: #selector(quit), keyEquivalent: "q").target = self
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
        do {
            settings = try store.load() ?? Settings.legacy(UserDefaults.standard.persistentDomain(forName: SettingsStore.applicationID) ?? [:])
        } catch {
            saveStatus.stringValue = error.localizedDescription
        }
        lifecycle.didLaunch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        lifecycle.didReopen()
        return false
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func label(_ text: String, small: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: small ? 12 : 13)
        if small { label.textColor = .secondaryLabelColor }
        return label
    }

    @objc private func showSettings() {
        NSApp.setActivationPolicy(.regular)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "FolderTerm 设置 — 0.4.0"
        window.isReleasedWhenClosed = false
        let content = NSView()
        window.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        let title = label("从 Finder，一键到终端")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(label("在此选择终端和命令；通过 Finder 工具栏入口打开终端。", small: true))
        stack.addArrangedSubview(label("终端应用"))
        terminalPicker.addItems(withTitles: ["Terminal", "iTerm2"])
        terminalPicker.setAccessibilityLabel("终端应用")
        terminalPicker.selectItem(withTitle: settings.terminal.rawValue)
        terminalPicker.target = self
        terminalPicker.action = #selector(terminalChanged)
        stack.addArrangedSubview(terminalPicker)
        stack.addArrangedSubview(label("打开方式"))
        modePicker.setAccessibilityLabel("打开方式")
        stack.addArrangedSubview(modePicker)
        stack.addArrangedSubview(label("执行命令"))
        commandField.stringValue = settings.command
        commandField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        commandField.usesSingleLineMode = true
        commandField.setAccessibilityLabel("执行命令")
        stack.addArrangedSubview(commandField)
        stack.addArrangedSubview(label("%PATH% 自动替换为安全转义后的路径，不要加引号。\n保留 cd -- %PATH% 前缀；后续命令以 && 或 ; 分隔。\n自定义命令会以你的账户在终端执行，请只使用信任的命令。", small: true))
        let actions = NSStackView()
        actions.spacing = 10
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetDefaults))
        let save = NSButton(title: "保存设置", target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        actions.addArrangedSubview(reset)
        actions.addArrangedSubview(save)
        stack.addArrangedSubview(actions)
        saveStatus.font = .systemFont(ofSize: 12)
        saveStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(saveStatus)
        stack.addArrangedSubview(NSButton(title: "添加到 Finder 工具栏", target: self, action: #selector(addToToolbar)))
        toolbarStatus.font = .systemFont(ofSize: 12)
        toolbarStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(toolbarStatus)
        stack.addArrangedSubview(NSButton(title: "显示 Finder 工具栏入口…", target: self, action: #selector(toolbarHelp)))
        stack.addArrangedSubview(label("主 App：配置。FolderTermToolbar.app：打开当前文件夹的终端。\n工具栏入口有独立的自动化权限，使用前需单独确认。", small: true))
        for view in [terminalPicker, modePicker, commandField, saveStatus, toolbarStatus] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        terminalChanged()
        if settings.terminal == .iTerm2, settings.mode == .tab {
            modePicker.selectItem(at: 1)
        }
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func terminalChanged() {
        let supportsTabs = terminalPicker.titleOfSelectedItem == "iTerm2"
        let selectedTab = modePicker.indexOfSelectedItem == 1
        modePicker.removeAllItems()
        modePicker.addItem(withTitle: "新窗口")
        if supportsTabs {
            modePicker.addItem(withTitle: "新标签页")
            if selectedTab { modePicker.selectItem(at: 1) }
        }
    }

    @objc private func resetDefaults() {
        terminalPicker.selectItem(at: 0)
        modePicker.selectItem(at: 0)
        commandField.stringValue = CommandTemplate.defaultValue
        terminalChanged()
    }

    @objc private func saveSettings() {
        let value = Settings(terminal: Settings.Terminal(rawValue: terminalPicker.titleOfSelectedItem ?? "") ?? .terminal,
                             mode: modePicker.indexOfSelectedItem == 1 ? .tab : .window,
                             command: commandField.stringValue)
        do { try store.save(value) }
        catch { showError(error.localizedDescription, title: "无法保存设置"); return }
        settings = value
        saveStatus.stringValue = "设置已保存。请在 Finder 中使用工具栏入口。"
    }

    @objc private func toolbarHelp() {
        let alert = NSAlert()
        alert.messageText = "将独立入口加入 Finder 工具栏"
        alert.informativeText = "1. 先把整个 FolderTerm.app 安装到固定位置，并保存设置。\n2. 点击下方按钮，找到内置的 FolderTermToolbar.app。\n3. 按住 ⌘ Command，将 FolderTermToolbar.app 拖到 Finder 右上方工具栏。\n4. 点击该工具栏入口，才会打开当前文件夹的终端。\n\n不要把主 FolderTerm.app 拖入工具栏：主 App 始终打开设置。不要将 helper 单独移出主 App。更换主 App 位置或升级后，如按钮失效请重新添加。"
        alert.addButton(withTitle: "显示 FolderTermToolbar.app")
        alert.addButton(withTitle: "知道了")
        if alert.runModal() == .alertFirstButtonReturn {
            let helper = BundleLocation.toolbar(in: Bundle.main.bundleURL)
            guard FileManager.default.fileExists(atPath: helper.path) else {
                showError("安装包缺少 FolderTermToolbar.app，请重新构建或安装完整的 FolderTerm.app。", title: "找不到工具栏入口")
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([helper])
        }
    }

    @objc private func addToToolbar() {
        do {
            let report = try toolbarInstaller.add(helperURL: BundleLocation.toolbar(in: Bundle.main.bundleURL))
            toolbarStatus.stringValue = ToolbarInstaller.message(for: report)
        } catch { showError(error.localizedDescription, title: "未能添加工具栏入口") }
    }

    private func showError(_ message: String, title: String = "无法完成操作") {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
