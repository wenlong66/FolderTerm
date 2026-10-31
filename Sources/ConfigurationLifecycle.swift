// This entry point deliberately has no terminal/automation dependency.
final class ConfigurationLifecycle {
    private let showSettings: () -> Void

    init(showSettings: @escaping () -> Void) { self.showSettings = showSettings }

    func didLaunch() { showSettings() }
    func didReopen() { showSettings() }
}
