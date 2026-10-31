import Foundation

enum ToolbarReplaceResult: Equatable { case replaced, conflict, rejected, unknown }

// expectedDigest is the last-moment guard, not a claim of cross-process CAS.
// A CFPreferences adapter can only make a best-effort fresh-read check, write
// one key, synchronize and verify afterward. FinderToolbarStore implements
// that explicitly best-effort boundary and suspends on uncertain outcomes.
protocol ConditionalToolbarStore: AnyObject {
    func read() throws -> ToolbarSnapshot
    func replace(expectedDigest: String, with snapshot: ToolbarSnapshot) throws -> ToolbarReplaceResult
}

struct ToolbarBackup: Codable {
    let schema: Int
    let id: UUID
    let domain: String
    let key: String
    let helperURL: String
    let created: Date
    let before: Data
    let after: Data
    let beforeDigest: String
    let afterDigest: String
    let insertionIndex: Int?
    var state: String

    init(plan: ToolbarPlan) {
        schema = 1; id = UUID(); domain = ToolbarSnapshot.domain; key = ToolbarSnapshot.key
        helperURL = plan.helperURL.absoluteString; created = Date()
        before = plan.before.data; after = plan.after.data
        beforeDigest = plan.before.digest; afterDigest = plan.after.digest
        insertionIndex = plan.insertionIndex; state = "prepared"
    }

    func snapshots() throws -> (ToolbarSnapshot, ToolbarSnapshot) {
        guard schema == 1, domain == ToolbarSnapshot.domain, key == ToolbarSnapshot.key,
              URL(string: helperURL)?.isFileURL == true else { throw ToolbarConfigurationError.corruptBackup }
        let old = try ToolbarSnapshot(data: before), new = try ToolbarSnapshot(data: after)
        guard old.digest == beforeDigest, new.digest == afterDigest else { throw ToolbarConfigurationError.corruptBackup }
        if let index = insertionIndex {
            let restored = try ToolbarPlan.removingInsertion(from: new, at: index,
                                                             originallyHadRecords: old.root["TB Item Plists"] != nil)
            guard restored.digest == old.digest else { throw ToolbarConfigurationError.corruptBackup }
        } else if old.digest != new.digest { throw ToolbarConfigurationError.corruptBackup }
        return (old, new)
    }
}

protocol ToolbarBackupRepository: AnyObject {
    func save(_ backup: ToolbarBackup) throws
    func load(_ id: UUID) throws -> ToolbarBackup
    func mark(_ id: UUID, state: String) throws
}

final class FileToolbarBackupRepository: ToolbarBackupRepository {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".plist") }

    func save(_ backup: ToolbarBackup) throws {
        _ = try backup.snapshots()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard !FileManager.default.fileExists(atPath: url(for: backup.id).path) else {
            throw ToolbarConfigurationError.corruptBackup
        }
        try write(backup)
    }

    private func write(_ backup: ToolbarBackup) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(backup).write(to: url(for: backup.id), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(for: backup.id).path)
    }

    func load(_ id: UUID) throws -> ToolbarBackup {
        let backup = try PropertyListDecoder().decode(ToolbarBackup.self, from: Data(contentsOf: url(for: id)))
        guard backup.id == id else { throw ToolbarConfigurationError.corruptBackup }
        _ = try backup.snapshots()
        return backup
    }

    func mark(_ id: UUID, state: String) throws {
        var backup = try load(id)
        backup.state = state
        try write(backup)
    }
}

struct ToolbarTransactionReport {
    enum Status: Equatable {
        case alreadyConfigured, configurationWrittenPendingReload, alreadyRestored, configurationRestoredPendingReload, unknown
    }
    let status: Status
    let backupID: UUID?
    let warning: String?
}

struct ToolbarTransaction {
    let store: ConditionalToolbarStore
    let backups: ToolbarBackupRepository

    func apply(_ plan: ToolbarPlan) throws -> ToolbarTransactionReport {
        guard try store.read().digest == plan.before.digest else { throw ToolbarConfigurationError.conflict }
        if plan.isNoOp { return ToolbarTransactionReport(status: .alreadyConfigured, backupID: nil, warning: nil) }
        let backup = ToolbarBackup(plan: plan)
        try backups.save(backup) // Must be durable before the first possible write.
        let outcome: ToolbarReplaceResult
        do { outcome = try store.replace(expectedDigest: plan.before.digest, with: plan.after) }
        catch {
            return report(.unknown, backup.id, "写入返回异常，结果未知；禁止自动重试。")
        }
        switch outcome {
        case .conflict:
            try? backups.mark(backup.id, state: "conflict-before-write")
            throw ToolbarConfigurationError.conflict
        case .rejected:
            try? backups.mark(backup.id, state: "rejected-no-write")
            throw ToolbarConfigurationError.realWriteBlocked
        case .unknown:
            return report(.unknown, backup.id, "写入结果未知；禁止自动重试或盲目恢复。")
        case .replaced:
            guard let current = try? store.read(), current.digest == plan.after.digest else {
                return report(.unknown, backup.id, "写入后的回读不一致；未自动回滚，避免覆盖并发修改。")
            }
            return report(.configurationWrittenPendingReload, backup.id, nil)
        }
    }

    func rollback(_ id: UUID) throws -> ToolbarTransactionReport {
        let backup = try backups.load(id)
        let (before, after) = try backup.snapshots()
        let current = try store.read()
        if current.digest == before.digest { return report(.alreadyRestored, id, nil) }
        guard current.digest == after.digest else { throw ToolbarConfigurationError.conflict }
        let outcome: ToolbarReplaceResult
        do { outcome = try store.replace(expectedDigest: after.digest, with: before) }
        catch { return report(.unknown, id, "恢复结果未知；禁止自动重试。") }
        switch outcome {
        case .conflict: throw ToolbarConfigurationError.conflict
        case .rejected: throw ToolbarConfigurationError.realWriteBlocked
        case .unknown: return report(.unknown, id, "恢复结果未知；未报告恢复成功。")
        case .replaced:
            guard let restored = try? store.read(), restored.digest == before.digest else {
                return report(.unknown, id, "恢复回读不一致，已停止。")
            }
            return report(.configurationRestoredPendingReload, id, nil)
        }
    }

    private func report(_ status: ToolbarTransactionReport.Status, _ id: UUID, _ warning: String?) -> ToolbarTransactionReport {
        var message = warning
        do { try backups.mark(id, state: String(describing: status)) }
        catch { message = [warning, "备份状态更新失败；请检查原始备份可读性，禁止盲目重试。"].compactMap { $0 }.joined(separator: " ") }
        return ToolbarTransactionReport(status: status, backupID: id, warning: message)
    }
}

final class BlockedFinderToolbarStore: ConditionalToolbarStore {
    private let reader = FinderToolbarSnapshotReader()
    func read() throws -> ToolbarSnapshot { try reader.read() }
    func replace(expectedDigest: String, with snapshot: ToolbarSnapshot) throws -> ToolbarReplaceResult {
        // No CFPreferences setter, synchronize, signals or subprocesses here.
        .rejected
    }
}
