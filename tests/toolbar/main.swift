import Foundation

var assertions = 0
func expect(_ value: Bool, _ message: String) {
    assertions += 1
    if !value { fatalError("FAIL: \(message)") }
}
func rejects(_ action: () throws -> Void) {
    do { try action(); fatalError("Expected rejection") } catch { assertions += 1 }
}
enum TestFailure: Error { case injected }

let helper = URL(fileURLWithPath: "/Applications/FolderTerm.app/Contents/Helpers/FolderTermToolbar.app")
let oldURL = URL(fileURLWithPath: "/Applications/Go2Shell.app/Contents/MacOS/Go2ShellHelper.app")
let newReference: [String: Any] = ["_CFURLString": helper.absoluteString, "_CFURLStringType": 15,
                                    "_CFURLAliasData": Data([0xaa, 0xbb]), "future": ["preserve": true]]
let oldReference: [String: Any] = ["_CFURLString": oldURL.absoluteString, "_CFURLStringType": 15,
                                    "_CFURLAliasData": Data([0x01, 0x02, 0x03])]
func resolveFixture(_ record: [String: Any]) throws -> URL? {
    if record["_CFURLString"] as? String == "file:///.file/id=fixture.own/" { return helper }
    guard let string = record["_CFURLString"] as? String, let url = URL(string: string), url.isFileURL else { return nil }
    return url
}
let root: [String: Any] = [
    "TB Item Identifiers": ["com.apple.finder.BACK", ToolbarPlan.applicationItemIdentifier, "NSToolbarSpaceItem", "com.apple.finder.SRCH", "vendor.unknown"],
    "TB Item Plists": ["1": oldReference, "4": ["opaque": Data([0x13, 0x37])]],
    "TB Display Mode": 2, "TB Is Shown": true,
    "Unknown Future Key": ["bytes": Data([0, 255, 3]), "date": Date(timeIntervalSince1970: 12345),
                           "real": 0.125, "nested": ["a", "b"]]
]
func plan(_ snapshot: ToolbarSnapshot) throws -> ToolbarPlan {
    try ToolbarPlan.make(snapshot: snapshot, helperURL: helper, reference: newReference, resolve: resolveFixture)
}
let before = try ToolbarSnapshot(root: root)
let insertion = try plan(before)
expect(insertion.insertionIndex == 3, "insert just before search")
let afterLayout = try ToolbarLayout(insertion.after.root)
expect(afterLayout.identifiers == ["com.apple.finder.BACK", ToolbarPlan.applicationItemIdentifier, "NSToolbarSpaceItem", ToolbarPlan.applicationItemIdentifier, "com.apple.finder.SRCH", "vendor.unknown"], "preserve every existing identifier and order")
expect((afterLayout.records["1"] as? [String: Any])?["_CFURLAliasData"] as? Data == oldReference["_CFURLAliasData"] as? Data, "old alias bytes unchanged")
expect((afterLayout.records["5"] as? [String: Any])?["opaque"] as? Data == Data([0x13, 0x37]), "shift opaque records with their item")
expect(try ToolbarPlan.removingInsertion(from: insertion.after, at: 3, originallyHadRecords: true).digest == before.digest, "inverse is exact whole-key snapshot")
var reordered: [String: Any] = [:]
for key in root.keys.sorted().reversed() { reordered[key] = root[key] }
expect(try ToolbarSnapshot(root: reordered).digest == before.digest, "dictionary order is not a conflict")
expect(try ToolbarSnapshot(root: ["x": true]).digest != ToolbarSnapshot(root: ["x": 1]).digest, "bool and integer remain distinct")
expect(try ToolbarSnapshot(root: ["x": 1.0]).digest != ToolbarSnapshot(root: ["x": 1]).digest, "real and integer remain distinct")
expect(try ToolbarSnapshot(root: ["x": -0.0]).digest != ToolbarSnapshot(root: ["x": 0.0]).digest, "real bit patterns preserved")
let again = try plan(insertion.after)
expect(again.isNoOp && again.existingIndices == [3], "repeat click is a no-op")
expect(again.before.data == again.after.data, "no-op does not rewrite serialization")
var duplicateRoot = insertion.after.root
var duplicateIDs = try ToolbarLayout(duplicateRoot).identifiers
var duplicateRecords = try ToolbarLayout(duplicateRoot).records
duplicateRecords[String(duplicateIDs.count)] = newReference
duplicateIDs.append(ToolbarPlan.applicationItemIdentifier)
duplicateRoot["TB Item Identifiers"] = duplicateIDs
duplicateRoot["TB Item Plists"] = duplicateRecords
let duplicateSnapshot = try ToolbarSnapshot(root: duplicateRoot)
let duplicatePlan = try plan(duplicateSnapshot)
expect(duplicatePlan.isNoOp && duplicatePlan.existingIndices.count == 2, "existing duplicates are not increased or silently deleted")
expect(duplicatePlan.after.data == duplicateSnapshot.data, "duplicate detection preserves original data")
var fileReferenceRoot = insertion.after.root
var fileReferenceRecords = try ToolbarLayout(fileReferenceRoot).records
fileReferenceRecords["3"] = ["_CFURLString": "file:///.file/id=fixture.own/", "_CFURLAliasData": Data([5, 6])]
fileReferenceRoot["TB Item Plists"] = fileReferenceRecords
expect(try plan(ToolbarSnapshot(root: fileReferenceRoot)).isNoOp, "resolve file-reference identity instead of substring path")
for badRoot: [String: Any] in [[:], ["TB Item Identifiers": "wrong"],
    ["TB Item Identifiers": ["one"], "TB Item Plists": ["9": oldReference]],
    ["TB Item Identifiers": ["one"], "TB Item Plists": ["00": oldReference]],
    ["TB Item Identifiers": [ToolbarPlan.applicationItemIdentifier]],
    ["TB Item Identifiers": [ToolbarPlan.applicationItemIdentifier], "TB Item Plists": ["0": ["opaque": Data([1])]]]] {
    rejects { _ = try plan(ToolbarSnapshot(root: badRoot)) }
}
rejects { _ = try ToolbarPlan.make(snapshot: before, helperURL: helper, reference: oldReference, resolve: resolveFixture) }

final class MemoryStore: ConditionalToolbarStore {
    var value: ToolbarSnapshot
    var writes = 0
    var calls = 0
    var beforeReplace: (() throws -> Void)?
    var result: ToolbarReplaceResult = .replaced
    var throwAfterWrite = false
    var readAfterWrite: ToolbarSnapshot?
    init(_ value: ToolbarSnapshot) { self.value = value }
    func read() throws -> ToolbarSnapshot { writes > 0 ? readAfterWrite ?? value : value }
    func replace(expectedDigest: String, with snapshot: ToolbarSnapshot) throws -> ToolbarReplaceResult {
        calls += 1
        let hook = beforeReplace; beforeReplace = nil
        try hook?()
        guard value.digest == expectedDigest else { return .conflict }
        switch result {
        case .conflict, .rejected: return result
        case .unknown: return .unknown
        case .replaced:
            value = snapshot; writes += 1
            if throwAfterWrite { throw TestFailure.injected }
            return .replaced
        }
    }
}
final class MemoryBackups: ToolbarBackupRepository {
    var values: [UUID: ToolbarBackup] = [:]
    var failSave = false
    var failMark = false
    func save(_ backup: ToolbarBackup) throws {
        if failSave { throw TestFailure.injected }
        _ = try backup.snapshots()
        values[backup.id] = backup
    }
    func load(_ id: UUID) throws -> ToolbarBackup { values[id]! }
    func mark(_ id: UUID, state: String) throws {
        if failMark { throw TestFailure.injected }
        values[id]?.state = state
    }
}
let memory = MemoryStore(before), backups = MemoryBackups()
let transaction = ToolbarTransaction(store: memory, backups: backups)
let applied = try transaction.apply(insertion)
expect(applied.status == .configurationWrittenPendingReload, "key write is never reported as visible toolbar success")
expect(memory.writes == 1 && backups.values.count == 1, "write has one prior backup")
let id = applied.backupID!
expect(backups.values[id]?.before == before.data, "backup retains original exact bytes")
let repeated = try transaction.apply(plan(memory.value))
expect(repeated.status == .alreadyConfigured && memory.writes == 1 && backups.values.count == 1, "idempotent apply writes no second item or backup")
let restored = try transaction.rollback(id)
expect(restored.status == .configurationRestoredPendingReload, "restore remains pending Finder reload")
expect(memory.value.data == before.data && memory.writes == 2, "rollback restores exact bytes")
expect(try transaction.rollback(id).status == .alreadyRestored && memory.writes == 2, "rollback is idempotent")

var changedRoot = root
changedRoot["Other User Change"] = true
let changed = try ToolbarSnapshot(root: changedRoot)
let conflict = MemoryStore(changed), conflictBackups = MemoryBackups()
rejects { _ = try ToolbarTransaction(store: conflict, backups: conflictBackups).apply(insertion) }
expect(conflict.writes == 0 && conflictBackups.values.isEmpty, "preflight conflict makes no write or backup")
let race = MemoryStore(before), raceBackups = MemoryBackups()
race.beforeReplace = { race.value = changed }
rejects { _ = try ToolbarTransaction(store: race, backups: raceBackups).apply(insertion) }
expect(race.writes == 0 && race.value.digest == changed.digest, "conditional write detects change during backup window")
let noBackup = MemoryStore(before), brokenBackups = MemoryBackups()
brokenBackups.failSave = true
rejects { _ = try ToolbarTransaction(store: noBackup, backups: brokenBackups).apply(insertion) }
expect(noBackup.calls == 0 && noBackup.writes == 0, "backup failure precedes any write attempt")

let rollbackConflict = MemoryStore(before), rollbackBackups = MemoryBackups()
let rollbackTx = ToolbarTransaction(store: rollbackConflict, backups: rollbackBackups)
let rollbackID = try rollbackTx.apply(insertion).backupID!
rollbackConflict.value = changed
rejects { _ = try rollbackTx.rollback(rollbackID) }
expect(rollbackConflict.value.digest == changed.digest && rollbackConflict.writes == 1, "rollback refuses to overwrite later user edits")
rollbackConflict.value = insertion.after
rollbackConflict.beforeReplace = { rollbackConflict.value = changed }
rejects { _ = try rollbackTx.rollback(rollbackID) }
expect(rollbackConflict.value.digest == changed.digest && rollbackConflict.writes == 1, "rollback also guards the final write condition")

let uncertain = MemoryStore(before), uncertainBackups = MemoryBackups()
uncertain.result = .unknown
let uncertainReport = try ToolbarTransaction(store: uncertain, backups: uncertainBackups).apply(insertion)
expect(uncertainReport.status == .unknown && uncertain.calls == 1, "unknown outcome is not automatically retried")
expect(uncertain.writes == 0 && uncertainBackups.values.count == 1, "unknown result retains recovery material")
let thrown = MemoryStore(before), thrownBackups = MemoryBackups()
thrown.throwAfterWrite = true
let thrownReport = try ToolbarTransaction(store: thrown, backups: thrownBackups).apply(insertion)
expect(thrownReport.status == .unknown && thrown.calls == 1 && thrown.writes == 1, "exception after write is not called failure-with-no-write")
thrown.throwAfterWrite = false
expect(try ToolbarTransaction(store: thrown, backups: thrownBackups).rollback(thrownReport.backupID!).status == .configurationRestoredPendingReload, "unknown result can be explicitly restored only after exact after-state match")
let mismatch = MemoryStore(before), mismatchBackups = MemoryBackups()
mismatch.readAfterWrite = changed
let mismatchReport = try ToolbarTransaction(store: mismatch, backups: mismatchBackups).apply(insertion)
expect(mismatchReport.status == .unknown && mismatch.writes == 1, "readback mismatch is not claimed successful or blindly undone")
let journal = MemoryStore(before), journalBackups = MemoryBackups()
journalBackups.failMark = true
let journalReport = try ToolbarTransaction(store: journal, backups: journalBackups).apply(insertion)
expect(journalReport.status == .configurationWrittenPendingReload && journalReport.warning != nil, "journal failure preserves known write outcome and reports warning")
expect(journalBackups.values[journalReport.backupID!] != nil, "original backup still exists when journal update fails")
let blocked = try BlockedFinderToolbarStore().replace(expectedDigest: before.digest, with: insertion.after)
if case .rejected = blocked { assertions += 1 } else { fatalError("Real Finder write must stay blocked") }

guard let testRoot = ProcessInfo.processInfo.environment["FOLDERTERM_TEST_ROOT"] else { fatalError("Project test root required") }
let directory = URL(fileURLWithPath: testRoot).appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
final class FixtureFileStore: ConditionalToolbarStore {
    let url: URL
    init(_ url: URL, snapshot: ToolbarSnapshot) throws { self.url = url; try snapshot.data.write(to: url) }
    func read() throws -> ToolbarSnapshot { try ToolbarSnapshot(data: Data(contentsOf: url)) }
    func replace(expectedDigest: String, with snapshot: ToolbarSnapshot) throws -> ToolbarReplaceResult {
        guard try read().digest == expectedDigest else { return .conflict }
        try snapshot.data.write(to: url, options: .atomic)
        return .replaced
    }
}
let fixture = try FixtureFileStore(directory.appendingPathComponent("fixture.plist"), snapshot: before)
let fileBackups = FileToolbarBackupRepository(directory: directory.appendingPathComponent("backups"))
let diskTx = ToolbarTransaction(store: fixture, backups: fileBackups)
let diskReport = try diskTx.apply(insertion)
let diskID = diskReport.backupID!
expect(try fixture.read().digest == insertion.after.digest, "real fixture file commit")
expect(try fileBackups.load(diskID).before == before.data, "durable backup has exact before data")
let mode = try FileManager.default.attributesOfItem(atPath: fileBackups.url(for: diskID).path)[.posixPermissions] as? Int
expect(mode == 0o600, "backup file mode is private")
_ = try diskTx.rollback(diskID)
expect(try Data(contentsOf: fixture.url) == before.data, "disk rollback preserves original serialized bytes")
let validBackupData = try Data(contentsOf: fileBackups.url(for: diskID))
var corrupt = try PropertyListSerialization.propertyList(from: Data(contentsOf: fileBackups.url(for: diskID)), format: nil) as! [String: Any]
corrupt["beforeDigest"] = "wrong"
try PropertyListSerialization.data(fromPropertyList: corrupt, format: .binary, options: 0).write(to: fileBackups.url(for: diskID))
rejects { _ = try diskTx.rollback(diskID) }
expect(try Data(contentsOf: fixture.url) == before.data, "corrupt backup cannot change fixture")
for (field, replacement) in [("schema", 2 as Any), ("domain", "wrong.domain" as Any), ("key", "other preference" as Any)] {
    var invalid = try PropertyListSerialization.propertyList(from: validBackupData, format: nil) as! [String: Any]
    invalid[field] = replacement
    try PropertyListSerialization.data(fromPropertyList: invalid, format: .binary, options: 0).write(to: fileBackups.url(for: diskID))
    rejects { _ = try diskTx.rollback(diskID) }
    expect(try Data(contentsOf: fixture.url) == before.data, "wrong backup scope never writes")
}

// A real native reference is created only for this project-local fake bundle,
// without reading or writing Finder preferences or launching an application.
let nativeHelper = directory.appendingPathComponent("中文 O'Reilly FolderTermToolbar.app")
try FileManager.default.createDirectory(at: nativeHelper.appendingPathComponent("Contents"), withIntermediateDirectories: true)
let nativeInfo = ["CFBundleIdentifier": "app.folderterm.FolderTerm.Toolbar", "CFBundlePackageType": "APPL", "CFBundleName": "Fixture"]
try PropertyListSerialization.data(fromPropertyList: nativeInfo, format: .xml, options: 0).write(to: nativeHelper.appendingPathComponent("Contents/Info.plist"))
let nativeReference = try ToolbarReference.make(for: nativeHelper)
expect((nativeReference["_CFURLAliasData"] as? Data)?.isEmpty == false, "native alias data is independently created")
expect(try ToolbarReference.resolve(nativeReference).map(ToolbarPlan.canonicalPath) == ToolbarPlan.canonicalPath(nativeHelper), "native alias round trips Unicode and quote path")
let nativePlan = try ToolbarPlan.make(snapshot: before, helperURL: nativeHelper, reference: nativeReference, resolve: ToolbarReference.resolve)
expect(try ToolbarPlan.make(snapshot: nativePlan.after, helperURL: nativeHelper, reference: nativeReference, resolve: ToolbarReference.resolve).isNoOp, "real file-reference URL detects duplicate")
let otherNativeHelper = directory.appendingPathComponent("Different Toolbar.app")
try FileManager.default.copyItem(at: nativeHelper, to: otherNativeHelper)
let otherNativeReference = try ToolbarReference.make(for: otherNativeHelper)
var mismatchedReference = nativeReference
mismatchedReference["_CFURLAliasData"] = otherNativeReference["_CFURLAliasData"]
rejects { _ = try ToolbarPlan.make(snapshot: before, helperURL: nativeHelper, reference: mismatchedReference, resolve: ToolbarReference.resolve) }

for length in 0...40 {
    var ids = (0..<length).map { $0 % 3 == 0 ? "NSToolbarSpaceItem" : "vendor.\($0)" }
    let search = length / 2
    ids.insert("com.apple.finder.SRCH", at: search)
    var records: [String: Any] = [:]
    for index in ids.indices where index % 2 == 1 { records[String(index)] = ["opaque": Data([UInt8(index)]), "keep": true] }
    let value: [String: Any] = ["TB Item Identifiers": ids, "TB Item Plists": records, "Future": ["int": length, "blob": Data([7, 8])]]
    let snapshot = try ToolbarSnapshot(root: value)
    let p = try plan(snapshot)
    expect(p.insertionIndex == search, "generated insertion index")
    expect(try ToolbarPlan.removingInsertion(from: p.after, at: search, originallyHadRecords: true).digest == snapshot.digest, "generated exact inverse")
}
let absentRecords = try ToolbarSnapshot(root: ["TB Item Identifiers": ["one", "two"], "Future": 9])
let p = try plan(absentRecords)
expect(p.insertionIndex == 2, "append when search absent")
expect(try ToolbarPlan.removingInsertion(from: p.after, at: 2, originallyHadRecords: false).digest == absentRecords.digest, "rollback restores absence of record key")
final class PreferenceSpy: FinderToolbarPreferenceIO {
    var value: Any?
    var synchronizations = 0
    var setters = 0
    var syncResults: [Bool] = []
    var onSync: ((Int) -> Void)?
    var throwOnSet = false
    init(_ value: Any?) { self.value = value }
    func synchronize() -> Bool {
        synchronizations += 1
        onSync?(synchronizations)
        return syncResults.isEmpty ? true : syncResults.removeFirst()
    }
    func copyValue() -> Any? { value }
    func setValue(_ value: [String: Any]) throws {
        setters += 1
        self.value = value
        if throwOnSet { throw TestFailure.injected }
    }
}
let io = PreferenceSpy(root), writeLatch = ToolbarWriteLatch()
let liveBoundary = FinderToolbarStore(io: io, latch: writeLatch)
expect(try liveBoundary.read().digest == before.digest && io.synchronizations == 1, "adapter refreshes before initial read")
expect(try liveBoundary.replace(expectedDigest: before.digest, with: insertion.after) == .replaced, "adapter accepts guarded single-key proposal")
expect(io.setters == 1 && io.synchronizations == 3, "one setter surrounded by fresh sync and persisted sync")
expect(try ToolbarSnapshot(root: io.value as! [String: Any]).digest == insertion.after.digest, "adapter exact post-write value")
let changedIO = PreferenceSpy(root)
changedIO.onSync = { _ in changedIO.value = changedRoot }
let changedBoundary = FinderToolbarStore(io: changedIO, latch: ToolbarWriteLatch())
expect(try changedBoundary.replace(expectedDigest: before.digest, with: insertion.after) == .conflict && changedIO.setters == 0, "adapter last-moment change preserves concurrent value")
let unreadableIO = PreferenceSpy(root)
unreadableIO.syncResults = [false]
expect(try FinderToolbarStore(io: unreadableIO, latch: ToolbarWriteLatch()).replace(expectedDigest: before.digest, with: insertion.after) == .rejected && unreadableIO.setters == 0, "pre-write synchronization failure makes no setter call")
let uncertainIO = PreferenceSpy(root), uncertainLatch = ToolbarWriteLatch()
uncertainIO.syncResults = [true, false]
let uncertainBoundary = FinderToolbarStore(io: uncertainIO, latch: uncertainLatch)
expect(try uncertainBoundary.replace(expectedDigest: before.digest, with: insertion.after) == .unknown, "post-write sync failure is unknown")
let syncCount = uncertainIO.synchronizations
rejects { _ = try uncertainBoundary.read() }
expect(uncertainIO.synchronizations == syncCount, "unknown write cannot be flushed by a later read")
expect(try FinderToolbarStore(io: uncertainIO, latch: uncertainLatch).replace(expectedDigest: before.digest, with: insertion.after) == .rejected && uncertainIO.setters == 1, "shared latch survives a new store instance")
let mismatchIO = PreferenceSpy(root)
mismatchIO.onSync = { n in if n == 2 { mismatchIO.value = changedRoot } }
let mismatchBoundary = FinderToolbarStore(io: mismatchIO, latch: ToolbarWriteLatch())
expect(try mismatchBoundary.replace(expectedDigest: before.digest, with: insertion.after) == .unknown, "adapter post-sync mismatch is not called success")
let throwingIO = PreferenceSpy(root), throwingLatch = ToolbarWriteLatch()
throwingIO.throwOnSet = true
expect(try FinderToolbarStore(io: throwingIO, latch: throwingLatch).replace(expectedDigest: before.digest, with: insertion.after) == .unknown && throwingLatch.suspended, "setter exception suspends uncertain pending state")
let serviceIO = PreferenceSpy(root), serviceBackups = MemoryBackups()
let service = ToolbarInstaller(store: FinderToolbarStore(io: serviceIO, latch: ToolbarWriteLatch()), backups: serviceBackups,
                               reference: { _ in newReference }, resolve: resolveFixture)
expect(try service.add(helperURL: helper).status == .configurationWrittenPendingReload, "installed button service commits to injected store")
expect(try service.add(helperURL: helper).status == .alreadyConfigured, "button service is idempotent")
expect(serviceIO.setters == 1 && serviceBackups.values.count == 1, "repeated click makes one setter and one backup")
expect(ToolbarInstaller.message(for: ToolbarTransactionReport(status: .alreadyConfigured, backupID: nil, warning: nil)).contains("未重复添加"), "already-configured message describes actual scope")
let reentrantIO = PreferenceSpy(root), reentrantBackups = MemoryBackups()
var reentrant: ToolbarInstaller!
var reentryStopped = 0
reentrant = ToolbarInstaller(store: FinderToolbarStore(io: reentrantIO, latch: ToolbarWriteLatch()), backups: reentrantBackups,
                             reference: { _ in
    do { _ = try reentrant.add(helperURL: helper) } catch { reentryStopped += 1 }
    return newReference
}, resolve: resolveFixture)
_ = try reentrant.add(helperURL: helper)
expect(reentryStopped == 1 && reentrantIO.setters == 1, "overlapping button callbacks are serialized")
print("PASS: \(assertions) toolbar assertions using fixtures and injected preference IO; no real Finder writes or reloads")
