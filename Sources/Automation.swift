import AppKit
import Carbon

final class Automation: TerminalAutomation {
    private func script(_ name: String) throws -> NSAppleScript {
        guard let url = Bundle.main.url(forResource: name, withExtension: "applescript"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let script = NSAppleScript(source: source) else {
            throw FolderTermError.message("无法读取自动化脚本：\(name)")
        }
        return script
    }

    private func check(_ error: NSDictionary?) throws {
        guard let error else { return }
        let number = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = error[NSAppleScript.errorMessage] as? String ?? "自动化失败"
        if number == -1743 || number == -1744 {
            throw FolderTermError.message("工具栏入口未获自动化权限。此独立入口名为 FolderTerm 工具栏，需要单独允许控制 Finder 和所选终端；主配置 App 的旧授权不能代替它。请在用户确认后，通过系统授权提示或“系统设置 → 隐私与安全性 → 自动化”允许该入口，再重试。\n\n\(message) (\(number))")
        }
        throw FolderTermError.message("\(message)（错误 \(number)）")
    }

    func currentFolder() throws -> String {
        var error: NSDictionary?
        let reply = try script("Finder").executeAndReturnError(&error)
        try check(error)
        guard reply.numberOfItems == 2 else { throw FolderTermError.message("Finder 返回了无法识别的目录信息。") }
        let windowPath = reply.atIndex(1)?.stringValue
        let selection = reply.atIndex(2)
        var paths: [String] = []
        if let selection, selection.numberOfItems > 0 {
            for index in 1...selection.numberOfItems { paths.append(selection.atIndex(index)?.stringValue ?? "") }
        }
        // A saved search is a file, not a directory, and therefore cannot be cwd.
        return try FolderResolver.resolve(windowPath: windowPath, selectedPaths: paths, exists: { FileManager.default.fileExists(atPath: $0) }) { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }
    }

    func open(command: String, terminal: String, mode: String) throws {
        let bundleID = terminal == "iTerm2" ? "com.googlecode.iterm2" : "com.apple.Terminal"
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            throw FolderTermError.message("找不到 \(terminal)。请先安装它，或在设置中改用 Terminal。")
        }
        let script = try script(terminal)
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "openfolder"), forKeyword: AEKeyword(keyASSubroutineName))
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: command), at: 1)
        arguments.insert(NSAppleEventDescriptor(string: mode), at: 2)
        event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        _ = script.executeAppleEvent(event, error: &error)
        try check(error)
    }
}
