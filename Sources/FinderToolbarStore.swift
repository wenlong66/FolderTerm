import Foundation
import CoreFoundation

protocol FinderToolbarPreferenceIO: AnyObject {
    func synchronize() -> Bool
    func copyValue() -> Any?
    func setValue(_ value: [String: Any]) throws
}

final class SystemFinderToolbarPreferenceIO: FinderToolbarPreferenceIO {
    func synchronize() -> Bool {
        CFPreferencesSynchronize(ToolbarSnapshot.domain as CFString,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    func copyValue() -> Any? {
        CFPreferencesCopyValue(ToolbarSnapshot.key as CFString, ToolbarSnapshot.domain as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    func setValue(_ value: [String: Any]) throws {
        // Exactly one key in one user/host scope. Never import the Finder domain.
        CFPreferencesSetValue(ToolbarSnapshot.key as CFString, value as CFPropertyList,
                              ToolbarSnapshot.domain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

enum FinderToolbarStoreError: LocalizedError {
    case synchronizationFailed, suspended, busy
    var errorDescription: String? {
        switch self {
        case .synchronizationFailed: return "无法同步读取 Finder 工具栏配置，已停止。"
        case .suspended: return "上一次工具栏写入结果未知，已暂停后续操作。请保留备份并核查，不要重复添加。"
        case .busy: return "工具栏操作正在进行，请等待结果。"
        }
    }
}

final class ToolbarWriteLatch {
    static let live = ToolbarWriteLatch()
    var suspended = false
}

final class FinderToolbarStore: ConditionalToolbarStore {
    private let io: FinderToolbarPreferenceIO
    private let latch: ToolbarWriteLatch

    init(io: FinderToolbarPreferenceIO = SystemFinderToolbarPreferenceIO(),
         latch: ToolbarWriteLatch = .live) {
        self.io = io; self.latch = latch
    }

    func suspendWrites() { latch.suspended = true }

    private func snapshot() throws -> ToolbarSnapshot {
        guard let root = io.copyValue() as? [String: Any] else {
            throw ToolbarConfigurationError.unsupported("目标用户／主机位置没有有效的工具栏字典")
        }
        return try ToolbarSnapshot(root: root)
    }

    func read() throws -> ToolbarSnapshot {
        guard !latch.suspended else { throw FinderToolbarStoreError.suspended }
        guard io.synchronize() else { throw FinderToolbarStoreError.synchronizationFailed }
        return try snapshot()
    }

    func replace(expectedDigest: String, with proposed: ToolbarSnapshot) throws -> ToolbarReplaceResult {
        guard !latch.suspended else { return .rejected }
        // Last-moment optimistic guard; no claim of an OS-level atomic CAS.
        guard io.synchronize() else { return .rejected }
        guard let current = try? snapshot(), current.digest == expectedDigest else { return .conflict }
        do { try io.setValue(proposed.root) }
        catch { latch.suspended = true; return .unknown }
        guard io.synchronize(), let persisted = try? snapshot(), persisted.digest == proposed.digest else {
            latch.suspended = true
            return .unknown
        }
        return .replaced
    }
}
