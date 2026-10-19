//
//  C116OwnerStoreMigrationTests.swift
//  MOTIVOTests
//
//  C-116: stores made before the first sign-in move with the owner. Both
//  sides may hold content; the merge is a union by id or key, the owner's
//  own value wins on a clash, two Lists with the same name both survive, a
//  repeated or interrupted run neither loses nor duplicates anything, and a
//  List deleted after the merge is not brought back by the next sign-in.
//

import XCTest
@testable import Etudes

@MainActor
final class C116OwnerStoreMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private let owner = "001234.abcdef.5678"

    override func setUp() {
        suiteName = "c116-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func list(_ name: String, _ line: String) -> SavedList {
        SavedList(id: UUID(), name: name, items: [SavedListLine(text: line)])
    }

    func testBothSidesHaveListsUnionByIdAndSameNameSurvives() throws {
        let d1 = list("Warm-up", "Long tones"), d2 = list("Scales", "C major")
        let o1 = list("Warm-up", "Arpeggios"), o2 = list("Scales", "G major")
        try SavedListLibrary.commit(snapshot: [], updated: [d1, d2], ownerScope: "device", defaults: defaults)
        try SavedListLibrary.commit(snapshot: [], updated: [o1, o2], ownerScope: owner, defaults: defaults)

        LocalOwnerStoreMigration.mergeNoOwnerStores(into: owner, defaults: defaults)

        let merged = try SavedListLibrary.read(ownerScope: owner, defaults: defaults)
        XCTAssertEqual(Set(merged.map(\.id)), [d1.id, d2.id, o1.id, o2.id], "neither collection lost")
        XCTAssertEqual(merged.filter { $0.name == "Scales" }.count, 2, "same name, two lists")
        XCTAssertEqual(merged.first { $0.id == o1.id }?.items.first?.text, "Arpeggios", "owner's own entry untouched")
        XCTAssertEqual(try SavedListLibrary.read(ownerScope: "device", defaults: defaults).map(\.id), [d1.id, d2.id], "source kept")
    }

    func testOwnersValueWinsOnTheSameIdAndRepeatOrInterruptionIsHarmless() throws {
        let shared = UUID()
        let device = SavedList(id: shared, name: "Shared", items: [SavedListLine(text: "old")])
        let owned = SavedList(id: shared, name: "Shared", items: [SavedListLine(text: "newer")])
        let onlyDevice = list("Only here", "x")
        try SavedListLibrary.commit(snapshot: [], updated: [device, onlyDevice], ownerScope: "device", defaults: defaults)
        try SavedListLibrary.commit(snapshot: [], updated: [owned], ownerScope: owner, defaults: defaults)
        defaults.set(["a"], forKey: "practiceTasks_v1::device::core:0")
        defaults.set(["keep"], forKey: "practiceTasks_v1::\(owner)::core:1")
        defaults.set(["lose"], forKey: "practiceTasks_v1::device::core:1")
        defaults.set(try JSONEncoder().encode([Ensemble(id: "e1", name: "Quartet", memberUserIDs: ["x"])]),
                     forKey: "EnsembleStore.items::local-device")
        defaults.set(try JSONEncoder().encode([Ensemble(id: "e2", name: "Trio", memberUserIDs: ["y"])]),
                     forKey: "EnsembleStore.items::\(owner.lowercased())")
        defaults.set(["cello": 2, "viola": 4], forKey: "theme.instrumentTint.slotMap.v1.__anonymous__")
        defaults.set(["cello": 7], forKey: "theme.instrumentTint.slotMap.v1.\(owner.lowercased())")
        let saved = UUID()
        defaults.set(true, forKey: "feed.interact.v2.save.unknown.\(saved.uuidString)")

        // Three runs: the first "interrupted" before its marker, a repeat, then the gated form.
        LocalOwnerStoreMigration.mergeNoOwnerStores(into: owner, defaults: defaults)
        LocalOwnerStoreMigration.mergeNoOwnerStores(into: owner, defaults: defaults)
        XCTAssertFalse(LocalOwnerStoreMigration.mergeNoOwnerStoresIfNeeded(into: owner, defaults: defaults).contains("Already merged for this owner"))

        let merged = try SavedListLibrary.read(ownerScope: owner, defaults: defaults)
        XCTAssertEqual(merged.count, 2, "no duplicates after repeats")
        XCTAssertEqual(merged.first { $0.id == shared }?.items.first?.text, "newer", "owner's value wins on the same id")
        XCTAssertTrue(merged.contains { $0.id == onlyDevice.id })
        XCTAssertEqual(defaults.stringArray(forKey: "practiceTasks_v1::\(owner)::core:0"), ["a"])
        XCTAssertEqual(defaults.stringArray(forKey: "practiceTasks_v1::\(owner)::core:1"), ["keep"])
        let ensembles = try JSONDecoder().decode([Ensemble].self, from: XCTUnwrap(defaults.data(forKey: "EnsembleStore.items::\(owner.lowercased())")))
        XCTAssertEqual(Set(ensembles.map(\.id)), ["e1", "e2"])
        XCTAssertEqual(defaults.dictionary(forKey: "theme.instrumentTint.slotMap.v1.\(owner.lowercased())") as? [String: Int], ["cello": 7, "viola": 4])
        XCTAssertTrue(defaults.bool(forKey: "feed.interact.v2.save.\(LocalOwnerStoreMigration.safeSaveKeyPart(owner)).\(saved.uuidString)"))
        XCTAssertTrue(defaults.bool(forKey: LocalOwnerStoreMigration.markerKey(owner)))
    }

    func testAListDeletedAfterTheMergeIsNotBroughtBackByTheNextSignIn() throws {
        let l = list("Gone later", "x")
        try SavedListLibrary.commit(snapshot: [], updated: [l], ownerScope: "device", defaults: defaults)
        LocalOwnerStoreMigration.mergeNoOwnerStoresIfNeeded(into: owner, defaults: defaults)
        XCTAssertEqual(try SavedListLibrary.read(ownerScope: owner, defaults: defaults).map(\.id), [l.id])
        let current = try SavedListLibrary.read(ownerScope: owner, defaults: defaults)
        try SavedListLibrary.commit(snapshot: current, updated: [], ownerScope: owner, defaults: defaults)

        let notes = LocalOwnerStoreMigration.mergeNoOwnerStoresIfNeeded(into: owner, defaults: defaults)
        XCTAssertEqual(notes, ["Already merged for this owner"])
        XCTAssertTrue(try SavedListLibrary.read(ownerScope: owner, defaults: defaults).isEmpty)
    }

    func testProfileCopiesOnlyWhenAskedAndNeverOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("c116-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        defaults.set("Leeds", forKey: "profile.__local_etudes_profile__.location")
        try Data([1]).write(to: dir.appendingPathComponent("__local_etudes_profile__-avatar.png"))

        LocalOwnerStoreMigration.mergeNoOwnerStores(into: owner, defaults: defaults)
        XCTAssertNil(defaults.string(forKey: "profile.\(owner).location"), "the production sign-in leaves profile data to its own flows")

        LocalOwnerStoreMigration.mergeNoOwnerStores(into: owner, defaults: defaults, includeProfile: true, profilesDirectory: dir)
        XCTAssertEqual(defaults.string(forKey: "profile.\(owner).location"), "Leeds")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(owner)-avatar.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("__local_etudes_profile__-avatar.png").path))
    }
}
