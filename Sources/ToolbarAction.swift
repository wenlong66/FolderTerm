import Foundation

protocol TerminalAutomation {
    func currentFolder() throws -> String
    func open(command: String, terminal: String, mode: String) throws
}

struct ToolbarAction {
    let loadSettings: () throws -> Settings
    let automation: TerminalAutomation

    func perform() throws {
        // Missing or invalid settings must not request Finder/Terminal access.
        let settings = try loadSettings()
        try settings.validate()
        let folder = try automation.currentFolder()
        let command = try CommandTemplate.render(settings.command, path: folder)
        try automation.open(command: command, terminal: settings.terminal.rawValue,
                            mode: settings.effectiveMode.rawValue)
    }
}

final class ToolbarLifecycle {
    private let run: () throws -> Void
    private let showError: (Error) -> Void
    private let finish: () -> Void
    private var running = false
    private var finished = false

    init(run: @escaping () throws -> Void, showError: @escaping (Error) -> Void,
         finish: @escaping () -> Void) {
        self.run = run
        self.showError = showError
        self.finish = finish
    }

    func didLaunch() { performOnce() }
    func didReopen() { performOnce() }

    private func performOnce() {
        guard !running, !finished else { return }
        running = true
        do { try run() } catch { showError(error) }
        finished = true
        running = false
        finish()
    }
}
