import Foundation
import CoreFoundation
import CryptoKit

enum ToolbarConfigurationError: LocalizedError {
    case unsupported(String), conflict, corruptBackup, realWriteBlocked
    var errorDescription: String? {
        switch self {
        case .unsupported(let reason): return "工具栏配置格式无法安全处理：\(reason)。没有修改 Finder。"
        case .conflict: return "工具栏配置已被其他操作改变。为保留现有布局，已停止；没有覆盖新配置。"
        case .corruptBackup: return "方案或备份校验失败，不能安全恢复。没有修改 Finder。"
        case .realWriteBlocked: return "本次工具栏写入被安全检查拒绝，尚未修改 Finder。请核查同步状态与备份。"
        }
    }
}

struct ToolbarSnapshot {
    static let domain = "com.apple.finder"
    static let key = "NSToolbar Configuration Browser"
    let data: Data
    let digest: String

    init(root: [String: Any]) throws {
        try self.init(data: PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0))
    }

    init(data: Data) throws {
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ToolbarConfigurationError.unsupported("目标键不是字典")
        }
        self.data = data
        self.digest = SHA256.hash(data: try Self.canonical(root)).map { String(format: "%02x", $0) }.joined()
    }

    var root: [String: Any] {
        // Construction validates this immutable data once.
        try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    }

    // Dictionary serialization order is not a revision. Use typed canonical
    // bytes so booleans, integers, reals, dates and opaque data stay distinct.
    private static func canonical(_ value: Any, depth: Int = 0) throws -> Data {
        guard depth < 64 else { throw ToolbarConfigurationError.unsupported("嵌套过深") }
        func number(_ value: UInt64) -> Data {
            var n = value.bigEndian
            return withUnsafeBytes(of: &n) { Data($0) }
        }
        func sized(_ tag: UInt8, _ bytes: Data) -> Data { Data([tag]) + number(UInt64(bytes.count)) + bytes }
        if let value = value as? Data { return sized(0x64, value) }
        if let value = value as? String { return sized(0x73, Data(value.utf8)) }
        if let value = value as? Date { return Data([0x74]) + number(value.timeIntervalSinceReferenceDate.bitPattern) }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return Data([0x62, value.boolValue ? 1 : 0]) }
            let type = String(cString: value.objCType)
            if type == "f" || type == "d" { return Data([0x72]) + number(value.doubleValue.bitPattern) }
            if type == "Q", value.uint64Value > UInt64(Int64.max) { return Data([0x75]) + number(value.uint64Value) }
            return Data([0x69]) + number(UInt64(bitPattern: value.int64Value))
        }
        if let value = value as? [Any] {
            return try value.reduce(Data([0x61]) + number(UInt64(value.count))) { $0 + (try canonical($1, depth: depth + 1)) }
        }
        if let value = value as? [String: Any] {
            return try value.keys.sorted().reduce(Data([0x6d]) + number(UInt64(value.count))) {
                $0 + (try canonical($1, depth: depth + 1)) + (try canonical(value[$1]!, depth: depth + 1))
            }
        }
        throw ToolbarConfigurationError.unsupported("包含非 property-list 类型")
    }
}

struct ToolbarLayout {
    let identifiers: [String]
    let records: [String: Any]
    init(_ root: [String: Any]) throws {
        guard let ids = root["TB Item Identifiers"] as? [String] else {
            throw ToolbarConfigurationError.unsupported("缺少项目标识数组")
        }
        guard root["TB Item Plists"] == nil || root["TB Item Plists"] is [String: Any] else {
            throw ToolbarConfigurationError.unsupported("项目记录不是字典")
        }
        let records = root["TB Item Plists"] as? [String: Any] ?? [:]
        for key in records.keys {
            guard let index = Int(key), index >= 0, index < ids.count, String(index) == key else {
                throw ToolbarConfigurationError.unsupported("存在无法配对的位置索引")
            }
        }
        self.identifiers = ids
        self.records = records
    }
}

struct ToolbarPlan {
    static let applicationItemIdentifier = "com.apple.finder.loc "
    let before: ToolbarSnapshot
    let after: ToolbarSnapshot
    let helperURL: URL
    let insertionIndex: Int?
    let existingIndices: [Int]
    var isNoOp: Bool { insertionIndex == nil }

    private init(before: ToolbarSnapshot, after: ToolbarSnapshot, helperURL: URL,
                 insertionIndex: Int?, existingIndices: [Int]) {
        self.before = before; self.after = after; self.helperURL = helperURL
        self.insertionIndex = insertionIndex; self.existingIndices = existingIndices
    }

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func make(snapshot: ToolbarSnapshot, helperURL: URL, reference: [String: Any],
                     resolve: ([String: Any]) throws -> URL?) throws -> ToolbarPlan {
        guard helperURL.isFileURL,
              let newReferenceURL = try resolve(reference),
              canonicalPath(newReferenceURL) == canonicalPath(helperURL) else {
            throw ToolbarConfigurationError.unsupported("新引用没有准确指向自己的 helper")
        }
        let layout = try ToolbarLayout(snapshot.root)
        var matches: [Int] = []
        for (index, identifier) in layout.identifiers.enumerated() {
            let record = layout.records[String(index)] as? [String: Any]
            if identifier.hasPrefix("com.apple.finder.loc"), record == nil {
                throw ToolbarConfigurationError.unsupported("自定义项目缺少可识别记录")
            }
            guard let record else { continue }
            let isReference = record["_CFURLString"] != nil || record["_CFURLAliasData"] != nil
            if !isReference && !identifier.hasPrefix("com.apple.finder.loc") { continue }
            guard let url = try resolve(record), url.isFileURL else {
                // Cannot prove an opaque custom reference is not our item.
                throw ToolbarConfigurationError.unsupported("有自定义引用无法解析，不能保证不重复添加")
            }
            if canonicalPath(url) == canonicalPath(helperURL) { matches.append(index) }
        }
        if !matches.isEmpty {
            return ToolbarPlan(before: snapshot, after: snapshot, helperURL: helperURL,
                               insertionIndex: nil, existingIndices: matches)
        }
        let position = layout.identifiers.firstIndex(of: "com.apple.finder.SRCH") ?? layout.identifiers.count
        var ids = layout.identifiers
        ids.insert(applicationItemIdentifier, at: position)
        var records: [String: Any] = [:]
        for (key, value) in layout.records {
            let index = Int(key)!
            records[String(index >= position ? index + 1 : index)] = value
        }
        records[String(position)] = reference
        var root = snapshot.root
        root["TB Item Identifiers"] = ids
        root["TB Item Plists"] = records
        let after = try ToolbarSnapshot(root: root)
        guard try removingInsertion(from: after, at: position,
                                    originallyHadRecords: snapshot.root["TB Item Plists"] != nil).digest == snapshot.digest else {
            throw ToolbarConfigurationError.corruptBackup
        }
        return ToolbarPlan(before: snapshot, after: after, helperURL: helperURL,
                           insertionIndex: position, existingIndices: [])
    }

    static func removingInsertion(from snapshot: ToolbarSnapshot, at position: Int,
                                  originallyHadRecords: Bool) throws -> ToolbarSnapshot {
        let layout = try ToolbarLayout(snapshot.root)
        guard layout.identifiers.indices.contains(position),
              layout.identifiers[position] == applicationItemIdentifier,
              layout.records[String(position)] != nil else { throw ToolbarConfigurationError.corruptBackup }
        var ids = layout.identifiers
        ids.remove(at: position)
        var records: [String: Any] = [:]
        for (key, value) in layout.records {
            let index = Int(key)!
            if index != position { records[String(index > position ? index - 1 : index)] = value }
        }
        var root = snapshot.root
        root["TB Item Identifiers"] = ids
        if originallyHadRecords { root["TB Item Plists"] = records }
        else { root.removeValue(forKey: "TB Item Plists") }
        return try ToolbarSnapshot(root: root)
    }
}
