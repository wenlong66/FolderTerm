import Foundation

enum FolderTermError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum CommandTemplate {
    static let defaultValue = "cd -- %PATH% && clear && pwd"
    static let prefix = "cd -- %PATH%"

    // Restrict the placeholder to a known unquoted shell-command position. Arbitrary
    // shell parsing (including heredocs and nested substitutions) is not attempted.
    static func render(_ template: String, path: String) throws -> String {
        guard !template.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw FolderTermError.message("命令必须为单行，不能包含换行、回车、制表符或其他 ASCII 控制字符。")
        }
        guard template.hasPrefix(prefix), template.components(separatedBy: "%PATH%").count == 2 else {
            throw FolderTermError.message("命令必须以 cd -- %PATH% 开头，且只能包含一个 %PATH%。不要给占位符加引号。")
        }
        let suffix = String(template.dropFirst(prefix.count))
        guard suffix.isEmpty || suffix.hasPrefix(" && ") || suffix.hasPrefix("; ") else {
            throw FolderTermError.message("路径之后只能接空白分隔的 && 或 ;，例如：cd -- %PATH% && clear && pwd")
        }
        guard !path.isEmpty, path.hasPrefix("/"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw FolderTermError.message("路径或命令无效。为避免终端控制字符注入，暂不支持包含换行、制表符或其他 ASCII 控制字符的目录名。")
        }
        return "cd -- " + shellQuote(path) + suffix
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum FolderResolver {
    // Finder's built-in smart locations can be real directories on disk, for
    // example myDocuments.cannedSearch. They are query definitions, never cwd.
    static func isSearchDefinition(_ path: String) -> Bool {
        (path as NSString).pathComponents.contains {
            let ext = ($0 as NSString).pathExtension.lowercased()
            return ext == "cannedsearch" || ext == "savedsearch"
        }
    }

    static func resolve(windowPath: String?, selectedPaths: [String], exists: (String) -> Bool, isDirectory: (String) -> Bool) throws -> String {
        if let path = windowPath, path.hasPrefix("/"), !isSearchDefinition(path), isDirectory(path) { return path }
        let folders = Set(selectedPaths.filter { $0.hasPrefix("/") }.map { path in
            isDirectory(path) ? path : (path as NSString).deletingLastPathComponent
        }.filter { isDirectory($0) })
        // Never discard an invalid selection and silently choose another one.
        guard selectedPaths.count == 1, folders.count == 1,
              selectedPaths.allSatisfy({ path in
                  path.hasPrefix("/") && !isSearchDefinition(path) && exists(path) && isDirectory(isDirectory(path) ? path : (path as NSString).deletingLastPathComponent)
              }), let folder = folders.first else {
            throw FolderTermError.message("此 Finder 窗口不是实际文件夹（可能是“最近使用”或搜索结果）。请打开实际文件夹，或只选择一个文件／文件夹后重试。")
        }
        return folder
    }
}
