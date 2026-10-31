import Foundation

final class ToolbarInstaller {
    private let store: FinderToolbarStore
    private let backups: ToolbarBackupRepository
    private let reference: (URL) throws -> [String: Any]
    private let resolve: ([String: Any]) throws -> URL?
    private var busy = false
    private(set) var lastBackupID: UUID?

    init(store: FinderToolbarStore, backups: ToolbarBackupRepository,
         reference: @escaping (URL) throws -> [String: Any] = ToolbarReference.make,
         resolve: @escaping ([String: Any]) throws -> URL? = ToolbarReference.resolve) {
        self.store = store; self.backups = backups
        self.reference = reference; self.resolve = resolve
    }

    func add(helperURL: URL) throws -> ToolbarTransactionReport {
        guard !busy else { throw FinderToolbarStoreError.busy }
        busy = true
        defer { busy = false }
        let snapshot = try store.read()
        let record = try reference(helperURL)
        let plan = try ToolbarPlan.make(snapshot: snapshot, helperURL: helperURL, reference: record, resolve: resolve)
        let report = try ToolbarTransaction(store: store, backups: backups).apply(plan)
        if let id = report.backupID { lastBackupID = id }
        if report.status == .unknown { store.suspendWrites() }
        return report
    }

    static func message(for report: ToolbarTransactionReport) -> String {
        let text: String
        switch report.status {
        case .alreadyConfigured:
            text = "配置中已有本入口，未重复添加。旧窗口未显示时，请新开 Finder 窗口查看。"
        case .configurationWrittenPendingReload:
            text = "已备份并写入工具栏配置。请查看 Finder；旧窗口可能尚未刷新，可新开 Finder 窗口检查。"
        case .unknown:
            text = "写入结果未确认，已停止后续操作。请保留备份，不要连续重试。"
        case .alreadyRestored, .configurationRestoredPendingReload:
            text = "配置恢复已核对，Finder 实际显示仍需确认。"
        }
        return [text, report.warning].compactMap { $0 }.joined(separator: "\n")
    }
}
