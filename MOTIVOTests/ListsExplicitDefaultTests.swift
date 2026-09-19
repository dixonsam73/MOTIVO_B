import XCTest
@testable import Etudes

/// Lists default: explicit per (instrument, activity), whatever the number of
/// instruments; nothing inherited, assigned or transferred.
///
/// What catches what, plainly:
/// - BEHAVIOUR tests use the production helper `ListsDefaultContext` that BOTH the
///   Lists manager and the practice timer call (keys, resolution, explicit writes,
///   which instrument the manager shows), on an isolated suite with synthetic ids.
/// - The timer's "no fall-through to the activity-only context" and the manager's
///   "reads write nothing" are STRUCTURAL assertions on the callers. The helper tests
///   cannot catch a fall-through re-added in the timer; only the structural test can.
///   No SwiftUI view or timer session is exercised.
@MainActor
final class ListsExplicitDefaultTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let owner = "lists-explicit-" + UUID().uuidString
    private let practice = "core:0"
    private let scales = "core:1"
    private let bass = UUID(), piano = UUID()

    override func setUpWithError() throws {
        suite = "ListsExplicitDefault." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func context(_ instrument: UUID?, _ activity: String? = nil) -> ListsDefaultContext {
        ListsDefaultContext(ownerScope: owner, activityRef: activity ?? practice, instrumentID: instrument)
    }

    private func list(_ name: String, _ items: [String]) -> SavedList {
        SavedList(id: UUID(), name: name, items: items.map { SavedListLine(text: $0) })
    }

    private func choose(_ list: SavedList?, in context: ListsDefaultContext) throws {
        let preset = try JSONEncoder().encode((list?.items ?? []).map { ["text": $0.text, "type": $0.type.rawValue] })
        context.recordExplicitChoice(listID: list?.id, presetData: preset, defaults: defaults)
    }

    private func snapshot() -> NSDictionary { (defaults.persistentDomain(forName: suite) ?? [:]) as NSDictionary }

    // MARK: - Independent combinations

    func testContextsAreDistinctAndIndependentOfInstrumentCount() {
        let keys = [context(bass).tasksKey, context(piano).tasksKey, context(bass, scales).tasksKey, context(nil).tasksKey]
        XCTAssertEqual(Set(keys).count, 4)
        XCTAssertEqual(context(bass).tasksKey, "practiceTasks_v1::\(owner)::\(practice)::inst:\(bass.uuidString)")
        XCTAssertEqual(context(nil).autofillKey, "practiceTasks_autofill_enabled::\(owner)::\(practice)")
    }

    func testAnExplicitChoiceBelongsToExactlyOneCombination() throws {
        let etudes = list("Etudes", ["No. 1"]), arps = list("Arpeggios", ["C"])
        try choose(etudes, in: context(bass))
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: [etudes, arps]), .list(etudes))
        XCTAssertEqual(context(piano).resolve(defaults: defaults, lists: [etudes, arps]), .none)
        XCTAssertEqual(context(bass, scales).resolve(defaults: defaults, lists: [etudes, arps]), .none)
        XCTAssertEqual(context(nil).resolve(defaults: defaults, lists: [etudes, arps]), .none)

        try choose(arps, in: context(piano))
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: [etudes, arps]), .list(etudes), "Bass keeps its own")
        XCTAssertEqual(context(piano).resolve(defaults: defaults, lists: [etudes, arps]), .list(arps))
    }

    func testDeselectingOneCombinationLeavesTheOthers() throws {
        let etudes = list("Etudes", ["No. 1"])
        try choose(etudes, in: context(bass))
        try choose(etudes, in: context(piano))
        try choose(nil, in: context(bass))
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: [etudes]), .off)
        XCTAssertEqual(context(piano).resolve(defaults: defaults, lists: [etudes]), .list(etudes))
    }

    // MARK: - Legacy activity-only data

    func testActivityOnlyDataIsNeverAppliedOrCopiedToAnInstrument() throws {
        let etudes = list("Etudes", ["No. 1"])
        try choose(etudes, in: context(nil))               // e.g. chosen while one instrument was keyed by activity
        defaults.set(try JSONSerialization.data(withJSONObject: [["text": "Old"]]), forKey: context(nil).tasksKey)
        let before = snapshot()
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: [etudes]), .none)
        XCTAssertEqual(context(piano).resolve(defaults: defaults, lists: [etudes]), .none)
        XCTAssertEqual(snapshot(), before, "nothing copied to an instrument by a read")
        XCTAssertEqual(context(nil).resolve(defaults: defaults, lists: [etudes]), .list(etudes),
                       "kept, and still used with no instrument")
    }

    // MARK: - Order and formats within ONE context

    func testExplicitOffWinsOverAStoredDefaultSoNoBadgeIsShown() throws {
        let etudes = list("Etudes", ["No. 1"])
        defaults.set(etudes.id.uuidString, forKey: context(bass).defaultIDKey)
        defaults.set(false, forKey: context(bass).autofillKey)
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: [etudes]), .off)
    }

    func testWithinAContextDanglingOrBlankDefaultsFallToItsOwnPreset() throws {
        let blank = list("Blank", ["  "])
        let own = try JSONSerialization.data(withJSONObject: [["text": "Own preset"]])
        defaults.set(own, forKey: context(bass).tasksKey)
        for raw in [UUID().uuidString, "not-a-uuid", blank.id.uuidString] {
            defaults.set(raw, forKey: context(bass).defaultIDKey)
            guard case .typed(let lines) = context(bass).resolve(defaults: defaults, lists: [blank]) else {
                return XCTFail("expected the context's own preset for \(raw)")
            }
            XCTAssertEqual(lines.map(\.text), ["Own preset"])
        }
    }

    func testPresetFormatsMatchTheTimersContract() throws {
        let key = context(bass).tasksKey
        defaults.set(try JSONSerialization.data(withJSONObject: []), forKey: key)
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: []), .none, "empty data")
        defaults.set(try JSONSerialization.data(withJSONObject: [["text": "A", "type": NSNull()]]), forKey: key)
        if case .typed(let lines) = context(bass).resolve(defaults: defaults, lists: []) {
            XCTAssertEqual(lines.map(\.type), [.task], "null type is a task")
        } else { XCTFail("null type decodes") }
        defaults.set(try JSONSerialization.data(withJSONObject: [["text": "A", "type": "bogus"]]), forKey: key)
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: []), .none, "unknown type fails the decode")
        defaults.set([String](), forKey: key)
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: []), .legacyArray([]), "legacy array, even empty")
    }

    func testResolvingWritesNothingAndLeavesTheListLibraryBytes() throws {
        let etudes = list("Etudes", ["No. 1"])
        try SavedListLibrary.commit(snapshot: [], updated: [etudes], ownerScope: owner, defaults: defaults)
        let libraryBytes = defaults.data(forKey: SavedListLibrary.key(ownerScope: owner))
        try choose(etudes, in: context(bass))
        let before = snapshot()
        for c in [context(bass), context(piano), context(nil), context(bass, scales)] {
            _ = c.resolve(defaults: defaults, lists: [etudes])
        }
        XCTAssertEqual(snapshot(), before, "reads write nothing")
        try choose(nil, in: context(bass))
        try choose(etudes, in: context(piano))
        XCTAssertEqual(defaults.data(forKey: SavedListLibrary.key(ownerScope: owner)), libraryBytes,
                       "explicit choices never touch the List library")
    }

    // MARK: - Which instrument the manager shows (one → two → one), and renaming

    func testManagerContextAcrossOneTwoOneTransitionsAndRename() throws {
        let etudes = list("Etudes", ["No. 1"])
        // One instrument: the manager shows Bass, and a choice is Bass's.
        var shown = ListsDefaultContext.effectiveInstrument(selected: nil, available: [(bass, "Bass")], primaryName: "Bass")
        XCTAssertEqual(shown, bass)
        try choose(etudes, in: context(shown))
        // Add Piano (sorted Bass, Piano; primary still Bass): Bass keeps it, Piano has none.
        let two: [(id: UUID, name: String)] = [(bass, "Bass"), (piano, "Piano")]
        shown = ListsDefaultContext.effectiveInstrument(selected: shown, available: two, primaryName: "Bass")
        XCTAssertEqual(shown, bass)
        XCTAssertEqual(context(bass).resolve(defaults: defaults, lists: [etudes]), .list(etudes))
        XCTAssertEqual(context(piano).resolve(defaults: defaults, lists: [etudes]), .none)
        // Explicitly view Piano, then remove it: back to the primary, Bass unchanged.
        shown = ListsDefaultContext.effectiveInstrument(selected: piano, available: two, primaryName: "Bass")
        XCTAssertEqual(shown, piano)
        shown = ListsDefaultContext.effectiveInstrument(selected: piano, available: [(bass, "Bass")], primaryName: "Bass")
        XCTAssertEqual(shown, bass)
        XCTAssertEqual(context(shown).resolve(defaults: defaults, lists: [etudes]), .list(etudes))
        // Renaming the original instrument keeps its UUID, so its context and choice.
        XCTAssertEqual(context(bass).tasksKey, ListsDefaultContext(ownerScope: owner, activityRef: practice,
                                                                  instrumentID: bass).tasksKey)
        XCTAssertEqual(ListsDefaultContext.effectiveInstrument(selected: nil, available: [(bass, "Bass Guitar"), (piano, "Piano")],
                                                               primaryName: "Bass Guitar"), bass)
    }

    func testManagerPicksPrimaryThenFirstAndNeverNilWhileInstrumentsExist() {
        let two: [(id: UUID, name: String)] = [(bass, "Bass"), (piano, "Piano")]
        XCTAssertEqual(ListsDefaultContext.effectiveInstrument(selected: nil, available: two, primaryName: "  piano "), piano)
        XCTAssertEqual(ListsDefaultContext.effectiveInstrument(selected: nil, available: two, primaryName: ""), bass)
        XCTAssertEqual(ListsDefaultContext.effectiveInstrument(selected: nil, available: two, primaryName: "Cello"), bass)
        XCTAssertEqual(ListsDefaultContext.effectiveInstrument(selected: UUID(), available: two, primaryName: nil), bass, "stale id")
        XCTAssertNil(ListsDefaultContext.effectiveInstrument(selected: bass, available: [], primaryName: "Bass"))
    }

    // MARK: - Structural (executable code only)

    private func raw(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO/" + file)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func code(_ file: String) throws -> String { stripComments(try raw(file)) }

    private func stripComments(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { return "" }
                if let r = line.range(of: " //") { return String(line[..<r.lowerBound]) }
                return String(line)
            }.joined(separator: "\n")
    }

    private func region(_ source: String, from start: String, to end: String) throws -> String {
        let a = try XCTUnwrap(source.range(of: start))
        let b = try XCTUnwrap(source[a.upperBound...].range(of: end))
        return String(source[a.lowerBound..<b.lowerBound])
    }

    /// The ONLY guard against a timer fall-through to the activity-only context.
    func testTimerResolvesOnlyTheSessionsOwnContext() throws {
        // The end marker is itself a comment, so the region is cut from the raw file first.
        let loader = stripComments(try region(try raw("PracticeTimerView.swift"),
                                              from: "private func loadPracticeDefaultsIfNeeded()",
                                              to: "// END TASKS DEFAULTS PATCH"))
        XCTAssertEqual(loader.components(separatedBy: "ListsDefaultContext(").count - 1, 1, "one context, the session's own")
        XCTAssertTrue(loader.contains("instrumentID: instrument?.id)"))
        XCTAssertTrue(loader.contains("case .none:\n        guard context.instrumentID == nil else { return }"))
        XCTAssertFalse(loader.contains("::inst:\\(inst)"), "no hand-built instrument keys")
        XCTAssertFalse(loader.contains("applyDefaultTaskSetIfAvailable"))
        // Session-pad preservation still precedes any default.
        let guardRange = try XCTUnwrap(loader.range(of: "guard taskLines.isEmpty, !clearedForSameContext else { return }"))
        let contextRange = try XCTUnwrap(loader.range(of: "ListsDefaultContext("))
        XCTAssertLessThan(guardRange.lowerBound, contextRange.lowerBound)
    }

    func testManagerReadsWriteNothingAndUseTheSharedContext() throws {
        let source = try code("TasksManagerView.swift")
        let loadAll = try region(source, from: "private func loadAll()", to: "\n    private func ")
        for write in ["defaults.set(", "removeObject(", "recordExplicitChoice(", "saveTaskSetSelectionAndItems(", "syncAutofill"] {
            XCTAssertFalse(loadAll.contains(write), "loadAll must not write: \(write)")
        }
        XCTAssertTrue(loadAll.contains("listsContext.resolve(defaults: defaults, lists: savedTaskSets)"))
        XCTAssertTrue(loadAll.contains("listsContext.instrumentID == nil"), "legacy practice display only without an instrument")
        XCTAssertTrue(source.contains("ListsDefaultContext.effectiveInstrument("))
        XCTAssertFalse(source.contains("currentInstrumentKeySuffix"), "no count-based key switching")
        let save = try region(source, from: "private func saveTaskSetSelectionAndItems()", to: "\n    private func ")
        XCTAssertTrue(save.contains("listsContext.recordExplicitChoice("))
    }
}
