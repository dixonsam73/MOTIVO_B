import XCTest
@testable import Etudes

/// P6-I-04 (an unreadable library is never overwritten) and F-1 (a deleted List
/// never comes back from a legacy per-context key). Isolated suites and synthetic
/// owner scopes only; no real preferences are read or written.
@MainActor
final class P6I04ListsPersistenceTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "P6I04Lists." + UUID().uuidString
        suites.append(suite)
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    /// Unique per test so nothing outside the suite can match the owner prefix.
    private func owner(_ tag: String = "o") -> String { "p6i04-\(tag)-" + UUID().uuidString }

    private func legacyKey(_ owner: String, _ context: String) -> String {
        "practiceTasks_v1::" + owner + "::" + context + "::saved_sets_v1"
    }

    private func list(_ name: String, _ items: [String], source: UUID? = nil) -> SavedList {
        SavedList(id: UUID(), name: name, items: items.map { SavedListLine(text: $0) }, sourceSendID: source)
    }

    private func write(_ lists: [SavedList], _ key: String, _ defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(lists), forKey: key)
    }

    private func lists(_ owner: String, _ defaults: UserDefaults) throws -> [SavedList] {
        guard case .lists(let lists) = SavedListLibrary.load(ownerScope: owner, defaults: defaults) else {
            XCTFail("library unexpectedly damaged"); return []
        }
        return lists
    }

    // MARK: - Shared read paths

    private func stored(_ owner: String, _ defaults: UserDefaults) -> SavedListLibrary.Stored {
        SavedListLibrary.stored(ownerScope: owner, defaults: defaults)
    }

    func testAbsentLibraryIsEmptyAndRecordsMigrationInTheLibraryValue() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        XCTAssertEqual(stored(o, defaults), .absent)
        XCTAssertEqual(SavedListLibrary.load(ownerScope: o, defaults: defaults), .lists([]))
        XCTAssertEqual(stored(o, defaults), .migrated([]))
    }

    func testValidLibraryIsReturnedVerbatimIncludingDuplicates() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        let a = list("Warm-up", ["Scales"]), b = list("Warm-up", ["Scales"])   // intentional duplicate
        let adopted = list("Warm-up", ["Scales"], source: UUID())
        let key = SavedListLibrary.key(ownerScope: o)
        try write([a, b, adopted], key, defaults)
        XCTAssertEqual(stored(o, defaults), .unmigrated([a, b, adopted]))
        XCTAssertEqual(try lists(o, defaults), [a, b, adopted])
        XCTAssertEqual(stored(o, defaults), .migrated([a, b, adopted]))
        XCTAssertEqual(try lists(o, defaults), [a, b, adopted])
    }

    func testLegacyShapeCanonicalValueIsRead() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        let old = LegacySavedList(id: UUID(), name: "Old", items: ["A", "B"])
        defaults.set(try JSONEncoder().encode([old]), forKey: SavedListLibrary.key(ownerScope: o))
        let read = try lists(o, defaults)
        XCTAssertEqual(read.map(\.id), [old.id])
        XCTAssertEqual(read.first?.items.map(\.text), ["A", "B"])
    }

    func testDamagedCanonicalValueIsNeverReplaced() throws {
        let futureEnvelope = try JSONEncoder().encode(SavedListLibrary.Envelope(version: 99, lists: []))
        let bad: [Any] = [Data("not json".utf8), "wrong storage type", 42, futureEnvelope]
        for value in bad {
            let (defaults, _) = try makeDefaults()
            let o = owner()
            let key = SavedListLibrary.key(ownerScope: o)
            try write([list("Legacy only", ["X"])], legacyKey(o, "activity"), defaults)
            defaults.set(value, forKey: key)
            let snapshot = defaults.object(forKey: key) as? NSObject

            XCTAssertEqual(SavedListLibrary.load(ownerScope: o, defaults: defaults), .damaged)
            XCTAssertThrowsError(try SavedListLibrary.commit(snapshot: [], updated: [list("New", ["Y"])],
                                                             ownerScope: o, defaults: defaults))
            XCTAssertThrowsError(try SavedListLibrary.adopt(ConnectedListPayload(list: list("Sent", ["Z"])),
                                                            sourceSendID: UUID(), ownerScope: o, defaults: defaults))
            XCTAssertThrowsError(try SavedListLibrary.read(ownerScope: o, defaults: defaults))

            XCTAssertEqual(defaults.object(forKey: key) as? NSObject, snapshot, "bytes changed for \(value)")
            XCTAssertEqual(stored(o, defaults), .damaged)
        }
    }

    // MARK: - One-time owner-wide migration

    func testLegacyOnlyContextsMigrateOnceKeepingUniqueContent() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        let shared = list("Etudes", ["No. 1", "No. 2"])
        let sameContent = SavedList(id: UUID(), name: " etudes ", items: [SavedListLine(text: "no. 1 "), SavedListLine(text: "No. 2")])
        let unique = list("Sight-reading", ["Bach"])
        let adoptedInLegacy = list("Adopted", ["Q"], source: UUID())
        let k1 = legacyKey(o, "activityA"), k2 = legacyKey(o, "activityB::inst:" + UUID().uuidString)
        try write([shared, adoptedInLegacy], k1, defaults)
        try write([sameContent, unique], k2, defaults)
        let legacyBytes = [defaults.data(forKey: k1), defaults.data(forKey: k2)]

        let migrated = try lists(o, defaults)
        XCTAssertEqual(migrated.map(\.id), [shared.id, unique.id])
        XCTAssertEqual(stored(o, defaults), .migrated(migrated))
        XCTAssertEqual([defaults.data(forKey: k1), defaults.data(forKey: k2)], legacyBytes, "legacy originals are kept")

        // A value written to a legacy key after the marker (for example by an older
        // build) is ignored rather than merged.
        try write([list("Late", ["L"])], legacyKey(o, "activityC"), defaults)
        XCTAssertEqual(try lists(o, defaults).map(\.id), [shared.id, unique.id])
    }

    func testDamagedLegacyValueBlocksMigrationAlongsideValidCanonical() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        let key = SavedListLibrary.key(ownerScope: o)
        try write([list("Kept", ["A"])], key, defaults)
        try write([list("Readable legacy", ["B"])], legacyKey(o, "good"), defaults)
        defaults.set(Data("corrupt".utf8), forKey: legacyKey(o, "bad"))
        let canonicalBytes = defaults.data(forKey: key)

        XCTAssertEqual(SavedListLibrary.load(ownerScope: o, defaults: defaults), .damaged)
        XCTAssertEqual(defaults.data(forKey: key), canonicalBytes)
        XCTAssertEqual(defaults.data(forKey: legacyKey(o, "bad")), Data("corrupt".utf8))
        guard case .unmigrated = stored(o, defaults) else { return XCTFail("migration was recorded") }
        XCTAssertThrowsError(try SavedListLibrary.commit(snapshot: [], updated: [], ownerScope: o, defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: key), canonicalBytes)
    }

    func testDamagedLegacyValueBlocksMigrationWithNoCanonical() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        defaults.set("wrong type", forKey: legacyKey(o, "bad"))
        XCTAssertEqual(SavedListLibrary.load(ownerScope: o, defaults: defaults), .damaged)
        XCTAssertNil(defaults.object(forKey: SavedListLibrary.key(ownerScope: o)))
        XCTAssertEqual(defaults.string(forKey: legacyKey(o, "bad")), "wrong type")
        XCTAssertEqual(stored(o, defaults), .absent)
    }

    func testMigratedStateAndListsAreOneWrite() throws {
        let suite = "P6I04Lists." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: suite))
        let o = owner()
        try write([list("Legacy", ["A"])], legacyKey(o, "ctx"), defaults)
        defaults.writes = []
        _ = SavedListLibrary.load(ownerScope: o, defaults: defaults)
        // No separate marker exists that could be lost, or land, apart from the data.
        XCTAssertEqual(Set(defaults.writes), [SavedListLibrary.key(ownerScope: o)])
        guard case .migrated(let lists) = stored(o, defaults) else { return XCTFail("not recorded as migrated") }
        XCTAssertEqual(lists.map(\.name), ["Legacy"])
    }

    func testOwnersAreIsolatedAtTheKeyBoundary() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner("x")
        let other = o + "0"   // shares o as a string prefix, but not the "::" boundary
        try write([list("Mine", ["A"])], legacyKey(o, "ctx"), defaults)
        try write([list("Theirs", ["B"])], legacyKey(other, "ctx"), defaults)
        XCTAssertEqual(try lists(o, defaults).map(\.name), ["Mine"])
        XCTAssertEqual(try lists(other, defaults).map(\.name), ["Theirs"])
    }

    // MARK: - F-1 and stale screens

    func testDeletedListDoesNotReturnFromAnyLegacyContext() throws {
        let (defaults, suite) = try makeDefaults()
        let o = owner()
        let doomed = list("Delete me", ["A"]), keep = list("Keep", ["B"])
        for ctx in ["activityA", "activityB", "activityA::inst:" + UUID().uuidString] {
            try write([doomed, keep], legacyKey(o, ctx), defaults)
        }
        let loaded = try lists(o, defaults)
        XCTAssertEqual(Set(loaded.map(\.id)), [doomed.id, keep.id])
        try SavedListLibrary.commit(snapshot: loaded, updated: loaded.filter { $0.id != doomed.id }, ownerScope: o, defaults: defaults)

        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(try lists(o, reopened).map(\.id), [keep.id])
        XCTAssertEqual(try SavedListLibrary.read(ownerScope: o, defaults: reopened).map(\.id), [keep.id])
    }

    func testStaleSnapshotCannotResurrectADeletionOrDropAnAdoption() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        let x = list("X", ["1"]), y = list("Y", ["2"])
        try SavedListLibrary.commit(snapshot: [], updated: [x, y], ownerScope: o, defaults: defaults)
        let staleScreen = try lists(o, defaults)

        // Another surface deletes Y, and a received List is adopted.
        let other = try lists(o, defaults)
        try SavedListLibrary.commit(snapshot: other, updated: other.filter { $0.id != y.id }, ownerScope: o, defaults: defaults)
        let adopted = try SavedListLibrary.adopt(ConnectedListPayload(list: list("Sent", ["S"])), sourceSendID: UUID(),
                                                 ownerScope: o, defaults: defaults)

        // The stale screen saves its whole array plus a new List.
        let z = list("Z", ["3"])
        let result = try SavedListLibrary.commit(snapshot: staleScreen, updated: staleScreen + [z], ownerScope: o, defaults: defaults)
        XCTAssertEqual(result.map(\.id), [x.id, z.id, adopted.id])
        XCTAssertEqual(try lists(o, defaults).map(\.id), [x.id, z.id, adopted.id])
    }

    func testStaleScreenAddingAListKeepsANewerEditElsewhere() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        let x = list("X", ["1"])
        try SavedListLibrary.commit(snapshot: [], updated: [x], ownerScope: o, defaults: defaults)
        let staleScreen = try lists(o, defaults)

        var edited = try lists(o, defaults)
        edited[0].name = "X renamed"
        edited[0].items.append(SavedListLine(text: "2"))
        try SavedListLibrary.commit(snapshot: try lists(o, defaults), updated: edited, ownerScope: o, defaults: defaults)

        let z = list("Z", ["3"])
        try SavedListLibrary.commit(snapshot: staleScreen, updated: staleScreen + [z], ownerScope: o, defaults: defaults)
        XCTAssertEqual(try lists(o, defaults), [edited[0], z])

        // A List this screen DID change is still written as the screen has it.
        var mine = try lists(o, defaults)
        mine[0].name = "Mine"
        XCTAssertEqual(try SavedListLibrary.commit(snapshot: try lists(o, defaults), updated: mine, ownerScope: o,
                                                   defaults: defaults).first?.name, "Mine")
    }

    func testCommitKeepsDuplicateSavesAndSeparateAdoptions() throws {
        let (defaults, _) = try makeDefaults()
        let o = owner()
        let first = list("Set", ["A"]), second = list("Set 2", ["A"])
        try SavedListLibrary.commit(snapshot: [], updated: [first], ownerScope: o, defaults: defaults)
        try SavedListLibrary.commit(snapshot: [first], updated: [first, second], ownerScope: o, defaults: defaults)
        let payload = ConnectedListPayload(list: first)
        let a = try SavedListLibrary.adopt(payload, sourceSendID: UUID(), ownerScope: o, defaults: defaults)
        let b = try SavedListLibrary.adopt(payload, sourceSendID: UUID(), ownerScope: o, defaults: defaults)
        XCTAssertEqual(try lists(o, defaults).map(\.id), [first.id, second.id, a.id, b.id])
    }

    // MARK: - Structural (executable code only)

    func testEverySurfaceUsesTheSharedLibraryAndNothingWritesLegacyKeys() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 10)
        for file in files where file.lastPathComponent != "SavedList.swift" {
            let code = Self.executableCode(try String(contentsOf: file, encoding: .utf8))
            XCTAssertFalse(code.contains("saved_sets_v1"), "\(file.lastPathComponent) names a legacy List key")
            XCTAssertFalse(code.contains("practiceTasks_saved_sets_v2"), "\(file.lastPathComponent) bypasses SavedListLibrary")
            XCTAssertFalse(code.contains("SavedListLibrary.key("), "\(file.lastPathComponent) addresses the library key directly")
        }
        let readers: [String: Int] = ["TasksManagerView.swift": 1, "PracticeTimerView.swift": 2, "PracticeTimerView+Sheets.swift": 1]
        for (name, minimum) in readers {
            let code = Self.executableCode(try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8))
            XCTAssertGreaterThanOrEqual(code.components(separatedBy: "SavedListLibrary.load(").count - 1, minimum, name)
            XCTAssertFalse(code.contains("dictionaryRepresentation()"), "\(name) scans defaults for Lists itself")
        }
    }

    private static func executableCode(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { return "" }
            if let range = line.range(of: " //") { return String(line[..<range.lowerBound]) }
            return String(line)
        }.joined(separator: "\n")
    }
}

/// Records the order of writes so the marker can be shown not to outrun the data.
private final class RecordingDefaults: UserDefaults {
    var writes: [String] = []
    override func set(_ value: Any?, forKey defaultName: String) {
        writes.append(defaultName)
        super.set(value, forKey: defaultName)
    }
    override func set(_ value: Bool, forKey defaultName: String) {
        writes.append(defaultName)
        super.set(value, forKey: defaultName)
    }
}
