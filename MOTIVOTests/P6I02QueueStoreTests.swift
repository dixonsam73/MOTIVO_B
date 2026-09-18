//
//  P6I02QueueStoreTests.swift
//  MOTIVOTests
//
//  PHASE 6 · BATCH 2 · UNIT 2a — THE PRODUCTION STORE, on disposable roots.
//
//  These drive `SessionSyncQueueStore` itself, not a copy of its algorithm. Each
//  case builds a synthetic root under `tmp/`, writes real `PostPublishPayload`
//  values with their real fields — notes, privacy, session id and timestamp,
//  operation and omission consent — and the genuine legacy `[UUID]` shape, then
//  asserts what the store does.
//
//  The shipping queue's own file is never touched: every store here is
//  constructed with its own root.
//

import XCTest
import CryptoKit
@testable import Etudes

@MainActor
final class P6I02QueueStoreTests: XCTestCase {

    private let fm = FileManager.default
    private var root: URL!
    private var store: SessionSyncQueueStore!

    override func setUp() async throws {
        try await super.setUp()
        root = fm.temporaryDirectory.appendingPathComponent("P6I02-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        store = SessionSyncQueueStore(root: root)
    }

    override func tearDown() async throws {
        if let root, fm.fileExists(atPath: root.path) {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            let backups = root.appendingPathComponent("SessionSyncQueue_preserved")
            if fm.fileExists(atPath: backups.path) {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backups.path)
                for f in (try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? [] {
                    try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.path)
                }
            }
            try? fm.removeItem(at: root)
        }
        store = nil; root = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures with REAL fields

    /// A payload carrying every field that matters, so preservation is measured
    /// rather than assumed.
    private func richPayload(owner: String? = nil, isPublic: Bool = true) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: UUID(),
            sessionID: UUID(),
            sessionTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Scales and arpeggios",
            durationSeconds: 1800,
            activityType: "core:0",
            activityDetail: "Warm-up",
            instrumentLabel: "Cello",
            mood: 4,
            effort: 7,
            isPublic: isPublic,
            notes: "private thoughts",
            areNotesPrivate: true,
            authorisedOmissions: [UUID(), UUID()],
            ownerUserID: owner
        )
    }

    private func writeLegacy(_ payloads: [SessionSyncQueue.PostPublishPayload]) throws {
        try JSONEncoder().encode(payloads).write(to: store.legacyURL, options: .atomic)
    }
    private func writeLegacyRaw(_ raw: String) throws {
        try Data(raw.utf8).write(to: store.legacyURL, options: .atomic)
    }
    private var backupFiles: [URL] {
        ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
    }
    /// The decode chain the CURRENT shipping build uses, pinned here so "an older
    /// build gets nothing" is measured. A SHAPE replica: real historical files
    /// remain the stronger evidence and are not available to this test.
    private func legacyLoaderResult(_ url: URL) -> [SessionSyncQueue.PostPublishPayload] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder()
        if let new = try? d.decode([SessionSyncQueue.PostPublishPayload].self, from: data) { return new }
        if let old = try? d.decode([UUID].self, from: data) {
            return old.map { SessionSyncQueue.PostPublishPayload(id: $0, sessionID: nil, sessionTimestamp: nil,
                                                                 title: nil, durationSeconds: nil, activityType: nil,
                                                                 activityDetail: nil, instrumentLabel: nil,
                                                                 mood: nil, effort: nil) }
        }
        return []   // the shipping call site's `?? []`
    }

    // MARK: - Migration preserves the real payload

    func testLegacyMigrationQuarantinesAndPreservesEveryField() throws {
        let original = richPayload(isPublic: false)          // an UNSHARE, op derived
        try writeLegacy([original])

        let (state, envelope) = store.reconcile()
        XCTAssertEqual(state, .ok)
        let env = try XCTUnwrap(envelope)

        XCTAssertTrue(env.items.isEmpty, "legacy work has no provenance and must never be dispatchable")
        XCTAssertEqual(env.quarantined.count, 1)
        let held = try XCTUnwrap(env.quarantined.first)

        XCTAssertEqual(held.id, original.id)
        XCTAssertEqual(held.sessionID, original.sessionID)
        XCTAssertEqual(held.sessionTimestamp, original.sessionTimestamp)
        XCTAssertEqual(held.title, original.title)
        XCTAssertEqual(held.durationSeconds, original.durationSeconds)
        XCTAssertEqual(held.activityType, original.activityType)
        XCTAssertEqual(held.activityDetail, original.activityDetail)
        XCTAssertEqual(held.instrumentLabel, original.instrumentLabel)
        XCTAssertEqual(held.mood, original.mood)
        XCTAssertEqual(held.effort, original.effort)
        XCTAssertEqual(held.notes, original.notes)
        XCTAssertEqual(held.areNotesPrivate, original.areNotesPrivate)
        XCTAssertEqual(held.authorisedOmissions, original.authorisedOmissions,
                       "the member's Share Without It consent must survive migration")
        XCTAssertEqual(held.op, .unshare, "the operation must survive, derived from isPublic")
        XCTAssertNil(held.ownerUserID, "a legacy item has UNKNOWN provenance and must not acquire one")
    }

    func testHistoricalUUIDArrayShapeMigrates() throws {
        let ids = [UUID(), UUID()]
        try JSONEncoder().encode(ids).write(to: store.legacyURL, options: .atomic)
        let (state, envelope) = store.reconcile()
        XCTAssertEqual(state, .ok)
        XCTAssertEqual(Set((envelope?.quarantined ?? []).map(\.id)), Set(ids))
        XCTAssertTrue(envelope?.items.isEmpty == true)
    }

    func testMigrationNeutralisesTheLegacyFileSoAnOlderBuildDispatchesNothing() throws {
        try writeLegacy([richPayload(), richPayload()])
        _ = store.reconcile()
        XCTAssertTrue(legacyLoaderResult(store.legacyURL).isEmpty,
                      "the path an older build reads must be inert")
        XCTAssertTrue(legacyLoaderResult(store.currentURL).isEmpty,
                      "and the envelope is not an array, so it decodes to nothing either")
    }

    func testMigrationIsIdempotent() throws {
        try writeLegacy([richPayload()])
        _ = store.reconcile(); _ = store.reconcile(); _ = store.reconcile()
        let (_, env) = store.reconcile()
        XCTAssertEqual(env?.quarantined.count, 1)
        XCTAssertEqual(backupFiles.count, 1)
    }

    // MARK: - Refusals: VALIDATION halts mutate nothing

    func testUnsupportedVersionHaltsAndMutatesNothing() throws {
        let future = #"{"formatVersion":99,"items":[],"quarantined":[],"absorbed":[],"unreadableBackups":[]}"#
        try Data(future.utf8).write(to: store.currentURL, options: .atomic)
        try writeLegacy([richPayload()])
        let legacyBefore = try Data(contentsOf: store.legacyURL)
        let currentBefore = try Data(contentsOf: store.currentURL)

        let (state, envelope) = store.reconcile()
        XCTAssertEqual(state, .haltUnsupportedVersion(99))
        XCTAssertNil(envelope, "a halt yields no dispatchable envelope")
        XCTAssertEqual(try Data(contentsOf: store.legacyURL), legacyBefore, "validation refusal mutates nothing")
        XCTAssertEqual(try Data(contentsOf: store.currentURL), currentBefore)
        XCTAssertEqual(backupFiles.count, 0)
    }

    func testCorruptCurrentFileHaltsAndIsNotTreatedAsEmpty() throws {
        try Data(#"{"formatVersion":2,"items":["#.utf8).write(to: store.currentURL, options: .atomic)
        try writeLegacy([richPayload()])
        let legacyBefore = try Data(contentsOf: store.legacyURL)

        let (state, envelope) = store.reconcile()
        XCTAssertEqual(state, .haltCorruptV2)
        XCTAssertNil(envelope)
        XCTAssertEqual(try Data(contentsOf: store.legacyURL), legacyBefore)
        XCTAssertEqual(backupFiles.count, 0, "a halted run writes nothing")
    }

    func testTamperedBackupHaltsDuringBackupOnlyRecovery() throws {
        try writeLegacy([richPayload(), richPayload()])
        _ = store.reconcile()
        // Remove the envelope so recovery must come from the backup alone.
        try fm.removeItem(at: store.currentURL)
        let backup = try XCTUnwrap(backupFiles.first)
        try Data("[]".utf8).write(to: backup, options: .atomic)   // same name, different bytes

        let (state, envelope) = store.reconcile()
        guard case .haltBackupIntegrity = state else {
            return XCTFail("expected a backup-integrity halt, got \(state)")
        }
        XCTAssertNil(envelope)
        XCTAssertFalse(fm.fileExists(atPath: store.currentURL.path),
                       "no successful empty envelope may be written over a tampered backup")
    }

    func testUnusableBackupDirectoryHalts() throws {
        try writeLegacy([richPayload()])
        _ = store.reconcile()
        try fm.removeItem(at: store.currentURL)
        let preserved = root.appendingPathComponent("preserved-moved")
        try fm.moveItem(at: store.backupDirectory, to: preserved)
        try Data("not a directory".utf8).write(to: store.backupDirectory, options: .atomic)

        let (state, _) = store.reconcile()
        XCTAssertEqual(state, .haltBackupStoreUnusable)
        XCTAssertFalse(fm.fileExists(atPath: store.currentURL.path))

        // After repair the owed work still recovers.
        try fm.removeItem(at: store.backupDirectory)
        try fm.moveItem(at: preserved, to: store.backupDirectory)
        let (repaired, env) = store.reconcile()
        XCTAssertEqual(repaired, .ok)
        XCTAssertEqual(env?.quarantined.count, 1)
    }

    func testUnreadableBackupHalts() throws {
        try writeLegacy([richPayload()])
        _ = store.reconcile()
        let backup = try XCTUnwrap(backupFiles.first)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: backup.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backup.path) }

        let (state, _) = store.reconcile()
        guard case .haltBackupIntegrity = state else {
            return XCTFail("expected a backup-integrity halt, got \(state)")
        }
    }

    // MARK: - WRITE failure after neutralisation recovers from the backup

    func testWriteFailureAfterNeutralisationIsRecoveredFromTheBackup() throws {
        let items = [richPayload(), richPayload()]
        try writeLegacy(items)

        // Genuine I/O failure: the root is read-only, so the envelope cannot be
        // written. The backup and the neutralisation happen inside the backup
        // directory and the existing legacy file, which remain writable.
        _ = store.reconcile()                       // first run migrates cleanly
        try fm.removeItem(at: store.currentURL)     // model: the envelope is gone
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        let (state, _) = store.reconcile()
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)

        guard case .haltWriteFailed = state else {
            return XCTFail("expected a write failure, got \(state)")
        }
        XCTAssertFalse(fm.fileExists(atPath: store.currentURL.path), "no partial envelope")

        // THE ORDERING CLAIM: the legacy file is already empty, so the backup is
        // the only record — and it is enough.
        XCTAssertTrue(legacyLoaderResult(store.legacyURL).isEmpty)
        let (recovered, env) = store.reconcile()
        XCTAssertEqual(recovered, .ok)
        XCTAssertEqual(env?.quarantined.count, 2, "owed work recovered from the preserved copy alone")
    }

    // MARK: - Readback mismatch, via the deterministic seam

    func testReadbackMismatchIsDetected() throws {
        try writeLegacy([richPayload()])
        SessionSyncQueueStore.unitTestCorruptAfterWrite = { [currentURL = store.currentURL] in
            try? Data("{}".utf8).write(to: currentURL, options: .atomic)
        }
        defer { SessionSyncQueueStore.unitTestCorruptAfterWrite = nil }

        let (state, envelope) = store.reconcile()
        XCTAssertEqual(state, .haltReadbackMismatch,
                       "a file that changed between write and verify must not pass")
        XCTAssertNil(envelope)
    }

    // MARK: - Downgrade then re-upgrade

    func testWorkCreatedByAnOlderBuildAfterMigrationIsAbsorbedNotIgnored() throws {
        let original = richPayload()
        try writeLegacy([original])
        _ = store.reconcile()
        XCTAssertTrue(legacyLoaderResult(store.legacyURL).isEmpty)

        // An older build runs and writes its own work to the path it knows.
        let newWork = richPayload()
        try writeLegacy([newWork])

        let (state, env) = store.reconcile()
        XCTAssertEqual(state, .ok)
        XCTAssertEqual(Set((env?.quarantined ?? []).map(\.id)), Set([original.id, newWork.id]),
                       "an envelope already existing must not cause new legacy work to be ignored")
        XCTAssertTrue(env?.items.isEmpty == true)
        XCTAssertEqual(backupFiles.count, 2)
    }

    // MARK: - Unreadable legacy content is preserved, never run

    func testUnreadableLegacyContentIsPreservedAndNeverDispatchable() throws {
        try writeLegacyRaw("{ not json at all")
        let (state, env) = store.reconcile()
        XCTAssertEqual(state, .ok)
        XCTAssertEqual(backupFiles.count, 1, "the bytes are preserved verbatim")
        XCTAssertEqual(env?.unreadableBackups.count, 1)
        XCTAssertTrue(env?.items.isEmpty == true)
        XCTAssertTrue(env?.quarantined.isEmpty == true)
    }

    func testEmptyOrAbsentLegacyFileProducesNoBackup() throws {
        let (state, env) = store.reconcile()
        XCTAssertEqual(state, .ok)
        XCTAssertTrue(env?.quarantined.isEmpty == true)
        XCTAssertEqual(backupFiles.count, 0)
        try writeLegacyRaw("[]")
        _ = store.reconcile()
        XCTAssertEqual(backupFiles.count, 0)
    }
}
