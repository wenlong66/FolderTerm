import AppKit

final class ToolbarDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let automation = Automation()
    private lazy var lifecycle = ToolbarLifecycle(run: { [unowned self] in
        try ToolbarAction(loadSettings: { try self.store.requireSaved() }, automation: self.automation).perform()
    }, showError: { error in
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "暂时无法在终端中打开文件夹"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }, finish: {
        NSApp.terminate(nil)
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Do not activate a window before capturing Finder's current location.
        lifecycle.didLaunch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        lifecycle.didReopen()
        return false
    }
}

let app = NSApplication.shared
let delegate = ToolbarDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
