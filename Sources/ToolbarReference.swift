import Foundation
import CoreFoundation
import CoreServices

enum ToolbarReference {
    static func resolve(_ record: [String: Any]) throws -> URL? {
        if let alias = record["_CFURLAliasData"] as? Data,
           let bookmark = CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault, alias as CFData)?.takeRetainedValue() {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark as Data, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        }
        guard let string = record["_CFURLString"] as? String,
              let url = URL(string: string), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost",
              !CFURLIsFileReferenceURL(url as CFURL) else { return nil }
        return url
    }

    // Finder's observed record uses legacy AliasData. Create our own record in
    // memory and prove it resolves back; never borrow another app's alias bytes.
    // These deprecated APIs are isolated here as a compatibility risk, not a
    // claim that this private Finder representation is supported by Apple.
    static func make(for helperURL: URL) throws -> [String: Any] {
        guard helperURL.isFileURL,
              Bundle(url: helperURL)?.bundleIdentifier == "app.folderterm.FolderTerm.Toolbar" else {
            throw ToolbarConfigurationError.unsupported("目标不是本项目的工具栏 helper")
        }
        var status: Int32 = 0
        guard let data = FolderTermCreateLegacyAliasData(helperURL as CFURL, &status) else {
            throw ToolbarConfigurationError.unsupported("无法创建独立 alias 引用：\(status)")
        }
        let alias = data as Data
        guard let fileReference = (helperURL as NSURL).fileReferenceURL() else {
            throw ToolbarConfigurationError.unsupported("无法创建 file-reference URL")
        }
        let record: [String: Any] = ["_CFURLAliasData": alias,
                                     "_CFURLString": fileReference.absoluteString,
                                     "_CFURLStringType": 15]
        guard let resolved = try resolve(record),
              ToolbarPlan.canonicalPath(resolved) == ToolbarPlan.canonicalPath(helperURL) else {
            throw ToolbarConfigurationError.unsupported("新 alias 回读不是自己的 helper")
        }
        return record
    }
}

struct FinderToolbarSnapshotReader {
    // Read-only. CFPreferences caches may be stale; this is a planning snapshot,
    // not a compare-and-swap backend and not proof of the visible toolbar state.
    func read() throws -> ToolbarSnapshot {
        guard let root = CFPreferencesCopyAppValue(ToolbarSnapshot.key as CFString,
                                                  ToolbarSnapshot.domain as CFString) as? [String: Any] else {
            throw ToolbarConfigurationError.unsupported("没有可读取的工具栏字典")
        }
        return try ToolbarSnapshot(root: root)
    }
}
