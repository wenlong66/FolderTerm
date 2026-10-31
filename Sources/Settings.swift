import Foundation

struct Settings: Codable, Equatable {
    enum Terminal: String, Codable { case terminal = "Terminal", iTerm2 = "iTerm2" }
    enum Mode: String, Codable { case window, tab }

    var terminal: Terminal = .terminal
    var mode: Mode = .window
    var command = CommandTemplate.defaultValue

    var effectiveMode: Mode { terminal == .terminal ? .window : mode }

    func validate() throws {
        _ = try CommandTemplate.render(command, path: "/validation-only")
    }

    // Migration is read only and performed by the configuration app, never by
    // the helper. The old 'configured' key has no effect on either entry point.
    static func legacy(_ values: [String: Any]) -> Settings {
        Settings(terminal: Terminal(rawValue: values["terminal"] as? String ?? "") ?? .terminal,
                 mode: Mode(rawValue: values["mode"] as? String ?? "") ?? .window,
                 command: values["command"] as? String ?? CommandTemplate.defaultValue)
    }
}

struct SettingsStore {
    static let applicationID = "app.folderterm.FolderTerm"
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.applicationID, isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    func load() throws -> Settings? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: fileURL))
            try settings.validate()
            return settings
        } catch {
            throw FolderTermError.message("无法读取已保存的设置。请打开 FolderTerm.app 检查并重新保存设置。")
        }
    }

    func requireSaved() throws -> Settings {
        guard let settings = try load() else {
            throw FolderTermError.message("请先打开 FolderTerm.app 配置并保存设置，再点击 Finder 工具栏入口。")
        }
        return settings
    }

    func save(_ settings: Settings) throws {
        try settings.validate()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

enum BundleLocation {
    static let toolbarRelativePath = "Contents/Helpers/FolderTermToolbar.app"

    static func toolbar(in mainAppURL: URL) -> URL {
        mainAppURL.appendingPathComponent(toolbarRelativePath, isDirectory: true)
    }
}
