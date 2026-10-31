import Foundation

var count = 0
func expect(_ condition: Bool, _ message: String) {
    count += 1
    if !condition { fatalError("FAIL: \(message)") }
}
func mustReject(_ body: () throws -> Void) {
    do { try body(); fatalError("Expected rejection") } catch { count += 1 }
}
let paths = ["/tmp/hello world", "/tmp/中文 🚀", "/tmp/O'Reilly", "/tmp/$HOME;echo bad", "/tmp/`uname`", "/tmp/\"quoted\"", "/tmp/$(echo bad)", "/tmp/back\\slash", "/tmp/%PATH%", "/"]
for path in paths {
    let command = try CommandTemplate.render(CommandTemplate.defaultValue, path: path)
    expect(command == "cd -- " + CommandTemplate.shellQuote(path) + " && clear && pwd", "render \(path)")
    for shell in ["/bin/zsh", "/bin/bash"] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-f", "-c", "printf '%s' " + CommandTemplate.shellQuote(path)]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        expect(process.terminationStatus == 0 && String(data: bytes, encoding: .utf8) == path, "shell argument round trip")
    }
}
expect(CommandTemplate.shellQuote("a'b") == "'a'\\''b'", "single quote")
for template in ["echo %PATH%", "cd -- '%PATH%'", "cd -- %PATH%xxx", "cd -- %PATH% && echo %PATH%", "cd -- %PATH%\nwhoami"] {
    mustReject { _ = try CommandTemplate.render(template, path: "/tmp") }
}
mustReject { _ = try CommandTemplate.render(CommandTemplate.defaultValue, path: "relative") }
mustReject { _ = try CommandTemplate.render(CommandTemplate.defaultValue, path: "/a\0b") }
for scalar in Array(UInt32(0)...UInt32(31)) + [UInt32(127)] {
    let control = String(UnicodeScalar(scalar)!)
    mustReject { _ = try CommandTemplate.render(CommandTemplate.defaultValue, path: "/tmp/a" + control + "b") }
    mustReject { _ = try CommandTemplate.render("cd -- %PATH% && echo a" + control + "b", path: "/tmp") }
}
let dirs: Set<String> = ["/work", "/work/sub", "/other"]
let files: Set<String> = ["/work/a", "/work/b", "/other/c"]
func resolve(_ window: String?, _ paths: [String]) throws -> String {
    try FolderResolver.resolve(windowPath: window, selectedPaths: paths, exists: { dirs.contains($0) || files.contains($0) }, isDirectory: { dirs.contains($0) })
}
let actual = try resolve("/work", ["/other/c"])
expect(actual == "/work", "actual folder has priority")
let parent = try resolve(nil, ["/work/a"])
expect(parent == "/work", "selected file parent")
let folder = try resolve("/savedSearch", ["/work/sub"])
expect(folder == "/work/sub", "selected folder")
for selection in [[], ["/work/a", "/work/b"], ["/work/a", "/other/c"], [""], ["/work/missing"], ["/work/sub", "/work/a"]] {
    mustReject { _ = try resolve(nil, selection) }
}
for path in ["/System/Library/CoreServices/Finder.app/Contents/Resources/MyLibraries/myDocuments.cannedSearch/", "/tmp/Test.savedSearch", "/tmp/Test.CANNEDSEARCH/inside"] {
    expect(FolderResolver.isSearchDefinition(path), "search definition")
    mustReject { _ = try FolderResolver.resolve(windowPath: path, selectedPaths: [], exists: { _ in true }, isDirectory: { _ in true }) }
}
// Real disk sharing, isolated entirely inside the project. Never touch the
// installed app's UserDefaults or Application Support directory during tests.
guard let testRoot = ProcessInfo.processInfo.environment["FOLDERTERM_TEST_ROOT"] else {
    fatalError("FOLDERTERM_TEST_ROOT must point inside the project")
}
let testDirectory = URL(fileURLWithPath: testRoot).appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: testDirectory) }
let settingsFile = testDirectory.appendingPathComponent("shared/settings.json")
let configStore = SettingsStore(fileURL: settingsFile)
let toolbarStore = SettingsStore(fileURL: settingsFile)
expect(try toolbarStore.load() == nil, "new toolbar requires saved settings")
mustReject { _ = try toolbarStore.requireSaved() }
let saved = Settings(terminal: .iTerm2, mode: .tab, command: "cd -- %PATH% && pwd")
try configStore.save(saved)
expect(try toolbarStore.requireSaved() == saved, "helper reads configuration app's shared file")
let updated = Settings(terminal: .terminal, mode: .tab, command: "cd -- %PATH%")
try configStore.save(updated)
expect(try toolbarStore.requireSaved() == updated, "fresh helper reads updated configuration")
expect(updated.effectiveMode == .window, "Terminal coerces stale tab mode")
let permissions = try FileManager.default.attributesOfItem(atPath: settingsFile.path)[.posixPermissions] as? Int
expect(permissions == 0o600, "settings file is private to the user")
mustReject { try configStore.save(Settings(command: "pwd")) }
expect(try toolbarStore.requireSaved() == updated, "invalid save leaves valid settings intact")
let old = Settings.legacy(["terminal": "iTerm2", "mode": "tab", "configured": true])
expect(old.terminal == .iTerm2 && old.mode == .tab, "old settings migrate without old entry behavior")

// Both real delegate callbacks call this lifecycle; it accepts no automation
// object and cannot route a configuration launch/reopen to a terminal action.
var configurationShows = 0
let configLifecycle = ConfigurationLifecycle { configurationShows += 1 }
configLifecycle.didLaunch()
configLifecycle.didReopen()
configLifecycle.didReopen()
expect(configurationShows == 3, "first launch and all reopens always show configuration")

for root in ["/Applications/FolderTerm.app", "/Volumes/Other Disk/FolderTerm.app", "/tmp/中文 O'Reilly/FolderTerm.app"] {
    let mainURL = URL(fileURLWithPath: root, isDirectory: true)
    let helperURL = BundleLocation.toolbar(in: mainURL)
    expect(helperURL.path == root + "/Contents/Helpers/FolderTermToolbar.app", "helper follows relocated main bundle")
}

final class FakeAutomation: TerminalAutomation {
    var folder = "/tmp/中文 O'Reilly $HOME `literal`"
    var calls: [String] = []
    var opened: (String, String, String)?
    var folderError: Error?
    func currentFolder() throws -> String {
        calls.append("finder")
        if let folderError { throw folderError }
        return folder
    }
    func open(command: String, terminal: String, mode: String) throws {
        calls.append("terminal")
        opened = (command, terminal, mode)
    }
}
let fake = FakeAutomation()
try ToolbarAction(loadSettings: { saved }, automation: fake).perform()
expect(fake.calls == ["finder", "terminal"], "only toolbar action opens terminal after capturing Finder")
expect(fake.opened?.0 == "cd -- " + CommandTemplate.shellQuote(fake.folder) + " && pwd", "helper passes safely quoted path")
expect(fake.opened?.1 == "iTerm2" && fake.opened?.2 == "tab", "helper uses saved terminal settings")
let missing = FakeAutomation()
mustReject { try ToolbarAction(loadSettings: { throw FolderTermError.message("missing") }, automation: missing).perform() }
expect(missing.calls.isEmpty, "missing configuration sends no Apple Events")
mustReject { try ToolbarAction(loadSettings: { Settings(command: "invalid") }, automation: missing).perform() }
expect(missing.calls.isEmpty, "invalid configuration sends no Apple Events")
let denied = FakeAutomation()
denied.folderError = FolderTermError.message("Finder unavailable")
mustReject { try ToolbarAction(loadSettings: { saved }, automation: denied).perform() }
expect(denied.calls == ["finder"], "Finder failure never opens terminal")
let controlPath = FakeAutomation()
controlPath.folder = "/tmp/bad\nname"
mustReject { try ToolbarAction(loadSettings: { saved }, automation: controlPath).perform() }
expect(controlPath.calls == ["finder"], "control-character path never reaches terminal")

var runs = 0
var finishes = 0
var errors = 0
var toolbarLifecycle: ToolbarLifecycle!
toolbarLifecycle = ToolbarLifecycle(run: {
    runs += 1
    toolbarLifecycle.didReopen()
}, showError: { _ in errors += 1 }, finish: { finishes += 1 })
toolbarLifecycle.didLaunch()
toolbarLifecycle.didReopen()
expect(runs == 1 && finishes == 1 && errors == 0, "helper executes once despite startup/reopen reentry")
let failedLifecycle = ToolbarLifecycle(run: { throw FolderTermError.message("test") },
                                      showError: { _ in errors += 1 }, finish: { finishes += 1 })
failedLifecycle.didLaunch()
failedLifecycle.didReopen()
expect(errors == 1 && finishes == 2, "helper reports error and finishes once")
print("PASS: \(count) native Swift assertions (core, shared settings, and entry lifecycle)")
