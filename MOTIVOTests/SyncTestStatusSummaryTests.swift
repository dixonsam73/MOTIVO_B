//
//  SyncTestStatusSummaryTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  The person-facing status (`JournalSyncStatusSummary`), derived from the
//  state file's fields and the live facts: restoring with progress, what
//  waits to upload, offline, held media, the actionable states (signed out, a
//  different account, storage full, Low Data Mode), and the one rule that
//  "Up to date" is never said while anything waits.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestStatusSummaryTests: XCTestCase {

    // MARK: the status object through the engine's own paths (C-183)

    private var tempDir: URL?

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func openStore(at url: URL) throws -> NSPersistentContainer {
        let c = NSPersistentContainer(name: "MOTIVO")
        let d = NSPersistentStoreDescription(url: url)
        d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        d.shouldAddStoreAsynchronously = false
        c.persistentStoreDescriptions = [d]
        var loadError: Error?
        c.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil, "store failed to load: \(String(describing: loadError))")
        return c
    }

    /// Waits for the main-actor publish that `refreshCounts` schedules.
    private func summary(of status: JournalSyncStatus, becomes kind: JournalSyncStatusSummary.Kind, within seconds: Double = 3) async -> JournalSyncStatusSummary {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            let current = await MainActor.run { status.summary }
            if current.kind == kind || Date() > deadline { return current }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Codex, 2026-11-05: the pure summary was right, but a later failed
    /// fetch or an incomplete import updated the state file and the log
    /// without reliably refreshing the DISPLAYED summary. This drives the
    /// real engine paths — the records-only catch-up against CloudKit (which
    /// fails here: the simulator has no iCloud account) and the import half
    /// of a batch whose write failed — and reads the status object itself,
    /// starting from "Up to date".
    @MainActor
    func testTheDisplayedSummaryIsRefreshedAfterAFailedFetchAndAnIncompleteImport() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("state"), withIntermediateDirectories: true)
        tempDir = dir
        let container = try openStore(at: dir.appendingPathComponent("store.sqlite"))
        let store = JournalSyncStateStore(fileURL: dir.appendingPathComponent("state/JournalSyncState.json"))
        let upToDate = "Catch-up (poll): 0 changed record(s), 0 deletion(s), 0 file(s) fetched"
        XCTAssertTrue(store.update { st in
            st.boundUserRecordName = "_user"
            st.initialFetchComplete = true
            st.lastCatchUp = upToDate
        })
        let status = JournalSyncStatus()
        let engine = JournalSyncEngine(containerIdentifier: JournalSyncCoordinator.containerIdentifier, persistence: container,
                                       store: store, status: status, customOwner: nil)
        engine.importer.log = { [store] in store.log($0) }
        engine.assumeCurrentUserForTesting("_user")

        // Seeded from the state file: nothing waits, the last check completed.
        engine.refreshCounts()
        var shown = await summary(of: status, becomes: .upToDate)
        XCTAssertEqual(shown.kind, .upToDate, "\(shown)")

        // 1. The import half of a batch whose write failed: the token is
        //    kept, the state file says "incomplete, fetched again", and the
        //    status must follow without any engine event.
        let before = store.writeFailures
        let complete = await engine.applyFetchedBatch(modified: [], deleted: [], newToken: nil, assetsFetched: 0,
                                                      generation: engine.generationForTesting(), reason: "test",
                                                      writeFailuresBefore: before - 1)   // "a write failed during this batch"
        XCTAssertFalse(complete)
        XCTAssertTrue(store.state.lastCatchUp?.hasSuffix(JournalSyncStatusSummary.catchUpIncompleteMarker) == true, store.state.lastCatchUp ?? "nil")
        shown = await summary(of: status, becomes: .retrying)
        XCTAssertEqual(shown.kind, .retrying, "\(shown)")
        XCTAssertEqual(shown.headline, "Finishing an import")

        // Back to up to date (a later complete batch), then
        XCTAssertTrue(store.update { $0.lastCatchUp = upToDate })
        engine.refreshCounts()
        shown = await summary(of: status, becomes: .upToDate)
        XCTAssertEqual(shown.kind, .upToDate)

        // 2. A later records-only catch-up that fails at CloudKit (no account
        //    here): the state file records the failure and the status says so.
        let ran = await engine.deltaCatchUp(reason: "test")
        XCTAssertTrue(ran, "a transient failure keeps the token and returns true")
        XCTAssertTrue(store.state.lastCatchUp?.hasPrefix(JournalSyncStatusSummary.catchUpFailedMarker) == true, store.state.lastCatchUp ?? "nil")
        shown = await summary(of: status, becomes: .retrying)
        XCTAssertEqual(shown.kind, .retrying, "\(shown)")
        XCTAssertEqual(shown.headline, "Last check failed")
        XCTAssertNotEqual(shown.headline, "Up to date")
    }

    private func change(_ name: String, _ type: String, op: JournalSyncPendingChange.Op = .save, assetFree: Bool = false) -> JournalSyncPendingChange {
        JournalSyncPendingChange(recordName: name, recordType: type, op: op, metadataOnly: assetFree)
    }

    func testPendingCountsReadTheOutboxTheWayAPersonDoes() {
        let outbox = [change("s1", JournalSyncRecordType.session), change("s2", JournalSyncRecordType.session),
                      change("a1", JournalSyncRecordType.attachment), change("a2", JournalSyncRecordType.attachment),
                      change("a2-meta", JournalSyncRecordType.attachmentMeta),
                      change("a3", JournalSyncRecordType.attachment, assetFree: true),   // a metadata edit never carries the file
                      change("score-x", JournalSyncRecordType.score),
                      change("setting-tintMode", JournalSyncRecordType.setting),
                      change("gone", JournalSyncRecordType.session, op: .delete)]
        let counts = JournalSyncPendingCounts.count(outbox: outbox, mediaWaitingUpload: ["a1": 10_000_000],
                                                    fileStampCache: ["a2": "5000000|1700000000|abc", "score-x": "250000|1|def"])
        XCTAssertEqual(counts.entries, 2)
        XCTAssertEqual(counts.files, 3, "two attachment files and a score; the asset-free edit is a change, not a file")
        XCTAssertEqual(counts.otherChanges, 3, "the meta record, the asset-free edit and the setting")
        XCTAssertEqual(counts.deletions, 1)
        XCTAssertEqual(counts.bytes, 15_250_000, "held bytes plus the hashed sizes")
        XCTAssertEqual(counts.text, "2 entries, 3 files (15.3 MB), 3 other changes and 1 deletion")

        let unknown = JournalSyncPendingCounts.count(outbox: [change("a9", JournalSyncRecordType.attachment)], mediaWaitingUpload: [:], fileStampCache: [:])
        XCTAssertNil(unknown.bytes, "a file never hashed has no size on record, so no figure is shown")
        XCTAssertEqual(unknown.text, "1 file")
        XCTAssertTrue(JournalSyncPendingCounts.count(outbox: [], mediaWaitingUpload: [:], fileStampCache: [:]).isEmpty)
    }

    func testUpToDateIsSaidOnlyWhenNothingWaits() {
        var facts = JournalSyncStatusFacts()
        facts.lastFetchAt = nil
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .upToDate)
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).headline, "Up to date")

        var pending = facts
        pending.outbox = [change("s1", JournalSyncRecordType.session)]
        let uploading = JournalSyncStatusSummary.derive(pending)
        XCTAssertEqual(uploading.kind, .uploading)
        XCTAssertEqual(uploading.headline, "Uploading")
        XCTAssertEqual(uploading.detail, "Still to upload: 1 entry.")

        var failing = pending
        failing.lastTransientFailure = "The Internet connection appears to be offline."
        XCTAssertEqual(JournalSyncStatusSummary.derive(failing).detail,
                       "Still to upload: 1 entry. Last attempt failed (The Internet connection appears to be offline.); trying again.")
        XCTAssertNotEqual(JournalSyncStatusSummary.derive(failing).headline, "Up to date", "a running engine with failing sends never reads as done")

        var receiving = facts
        receiving.awaitingMedia = ["a1", "a2"]
        XCTAssertEqual(JournalSyncStatusSummary.derive(receiving).kind, .downloading)
        XCTAssertEqual(JournalSyncStatusSummary.derive(receiving).detail, "2 files still to receive.")

        var checking = facts
        checking.phase = "Checking iCloud account"
        XCTAssertEqual(JournalSyncStatusSummary.derive(checking).kind, .checking)
    }

    func testOfflineSaysWhatWaitsAndThatItIsSentLater() {
        var facts = JournalSyncStatusFacts()
        facts.online = false
        facts.phase = "Running"   // the engine's phase stays "Running" offline; the status must not
        let idle = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(idle.kind, .offline)
        XCTAssertEqual(idle.headline, "Offline")
        XCTAssertEqual(idle.detail, "Everything on this device is in iCloud. Changes you make now are sent when the connection returns.")

        facts.outbox = [change("s1", JournalSyncRecordType.session), change("a1", JournalSyncRecordType.attachment)]
        facts.fileStampCache = ["a1": "2000000|1|h"]
        let busy = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(busy.headline, "Offline")
        XCTAssertEqual(busy.detail, "Still to upload: 1 entry and 1 file (2 MB). Sent when the connection returns.")
    }

    func testRestoringShowsRecordsThenFilesThenApplying() {
        var facts = JournalSyncStatusFacts()
        facts.initialFetchComplete = false
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).headline, "Restoring from iCloud")
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail, "Reading your journal: 0 records so far")
        facts.restore = JournalRestoreProgress(recordsFetched: 275)
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail, "Reading your journal: 275 records so far")
        facts.restore = JournalRestoreProgress(recordsFetched: 339, filesFetched: 12, filesTotal: 91)
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail, "Downloading files: 12 of 91")
        facts.restore = JournalRestoreProgress(recordsFetched: 339, filesFetched: 0, filesTotal: 0)
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail, "339 records read; no files to download")
        facts.restore = JournalRestoreProgress(recordsFetched: 339, filesFetched: 91, filesTotal: 91, applying: true)
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail, "Adding 339 records to this device…")

        facts.online = false
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail,
                       "Waiting for a connection. Restoring continues when iCloud is reachable; you can keep using Études meanwhile.")
        facts.online = true
        facts.restore = nil
        facts.lastCatchUp = "Delta catch-up failed: The request timed out."
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail, "Delta catch-up failed: The request timed out. It is tried again automatically.")
        // Restoring outranks pending uploads: a receiver re-sending its lists is still restoring.
        facts.outbox = [change("list", JournalSyncRecordType.savedList)]
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .restoring)
    }

    func testActionableStatesNameWhatThePersonCanDo() {
        var facts = JournalSyncStatusFacts()
        facts.pausedReason = "Signed out of iCloud, or iCloud is off for this app; journal and pending changes kept"
        let signedOut = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(signedOut.kind, .attention)
        XCTAssertEqual(signedOut.headline, "Signed out of iCloud")
        XCTAssertEqual(signedOut.action, "Sign in to iCloud in Settings, and check that Études is allowed to use iCloud.")

        facts.pausedReason = "This journal is linked to a different iCloud account. Nothing is uploaded, downloaded or imported."
        let other = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(other.kind, .attention)
        XCTAssertEqual(other.headline, "Linked to a different iCloud account")
        XCTAssertEqual(other.action, "Sign in to that iCloud account in Settings to continue syncing.")

        facts.pausedReason = "Waiting for iCloud; journal and pending changes kept"
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .waiting)
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).headline, "Waiting for iCloud")

        facts.pausedReason = "Server zone deleted for a trial reset; uninstall this app next"
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .paused)
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).detail, facts.pausedReason)

        // The guard's reasons are the engine's own words: the summary must recognise them.
        let bound = JournalAccountGuard.decide(bound: "A", current: "B", unlinked: false, localRemovalInProgress: false, localCopyRemoved: false)
        XCTAssertTrue(bound.reason!.contains(JournalSyncStatusSummary.differentAccountMarker))
        let out = JournalAccountGuard.decide(bound: "A", current: nil, unlinked: false, localRemovalInProgress: false, localCopyRemoved: false)
        XCTAssertTrue(out.reason!.hasPrefix(JournalSyncStatusSummary.signedOutMarker))
        let waiting = JournalAccountGuard.decide(bound: nil, current: nil, unlinked: false, localRemovalInProgress: false, localCopyRemoved: false)
        XCTAssertTrue(waiting.reason!.hasPrefix(JournalSyncStatusSummary.waitingMarker))

        facts.pausedReason = nil
        facts.storageFullSummary = "iCloud storage is full (since 14:02): 7 changes waiting, 2 with media. They are sent when space is available; nothing is removed from this device."
        let full = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(full.kind, .attention)
        XCTAssertEqual(full.headline, "iCloud storage is full")
        XCTAssertEqual(full.detail, facts.storageFullSummary)
        XCTAssertEqual(full.action, "Free up iCloud storage, or buy more in Settings. Nothing is removed from this device.")
        // A paused state outranks storage full: the person must sign in first.
        facts.pausedReason = "Signed out of iCloud, or iCloud is off for this app; journal and pending changes kept"
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).headline, "Signed out of iCloud")
    }

    func testHeldMediaSaysWhyAndWhatToDo() {
        var facts = JournalSyncStatusFacts()
        facts.mediaHold = .mobileData
        facts.outbox = [change("a1", JournalSyncRecordType.attachment), change("s1", JournalSyncRecordType.session)]
        facts.mediaWaitingUpload = ["a1": 35_000_000]
        facts.awaitingMedia = ["b1"]
        let wifi = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(wifi.kind, .mediaHeld)
        XCTAssertEqual(wifi.headline, "Waiting for Wi-Fi")
        XCTAssertEqual(wifi.detail, "1 file (35 MB) to send, 1 to receive. Text and settings still sync.")
        XCTAssertEqual(wifi.action, "Turn on Media over mobile data below to send and receive them now.")

        facts.mediaHold = .lowDataMode
        let low = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(low.headline, "Media paused by Low Data Mode")
        XCTAssertEqual(low.action, "Turn off Low Data Mode in Settings to continue.")

        // A hold with no media waiting is not a status of its own: text still syncs.
        facts.outbox = [change("s1", JournalSyncRecordType.session)]
        facts.awaitingMedia = []
        facts.mediaWaitingUpload = [:]
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .uploading)
        facts.outbox = []
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .upToDate)
    }

    /// Codex, 2026-11-05: a later check that failed, an import that did not
    /// finish, or records held for data that has not arrived are not "Up to
    /// date" either, whatever the engine's phase says.
    func testNoUpToDateAfterAFailedOrIncompleteLaterCheckOrWhileRecordsAreHeld() {
        var facts = JournalSyncStatusFacts()
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .upToDate)

        var failed = facts
        failed.lastCatchUp = "Delta catch-up failed: The request timed out."
        let f = JournalSyncStatusSummary.derive(failed)
        XCTAssertEqual(f.kind, .retrying)
        XCTAssertEqual(f.headline, "Last check failed")
        XCTAssertEqual(f.detail, "Delta catch-up failed: The request timed out. It is tried again automatically.")

        var incomplete = facts
        incomplete.lastCatchUp = "Catch-up (push): 7 changed record(s), 0 deletion(s), 1 file(s) fetched — incomplete, fetched again"
        let i = JournalSyncStatusSummary.derive(incomplete)
        XCTAssertEqual(i.kind, .retrying)
        XCTAssertEqual(i.headline, "Finishing an import")
        // The engine's own wording for both, so the summary stays in step with it.
        XCTAssertTrue(incomplete.lastCatchUp!.hasSuffix(JournalSyncStatusSummary.catchUpIncompleteMarker))
        XCTAssertTrue(failed.lastCatchUp!.hasPrefix(JournalSyncStatusSummary.catchUpFailedMarker))

        var ok = facts
        ok.lastCatchUp = "Catch-up (poll): 1 changed record(s), 0 deletion(s), 0 file(s) fetched"
        XCTAssertEqual(JournalSyncStatusSummary.derive(ok).kind, .upToDate, "a completed later check is up to date")

        var held = facts
        held.heldRecords = 3
        let h = JournalSyncStatusSummary.derive(held)
        XCTAssertEqual(h.kind, .downloading)
        XCTAssertEqual(h.detail, "3 items waiting for the rest of their data from iCloud.")
        held.heldRecords = 1
        XCTAssertEqual(JournalSyncStatusSummary.derive(held).detail, "1 item waiting for the rest of its data from iCloud.")

        // Order: something to upload is said before a failed check; a hold
        // before a failed check; offline before all of them.
        var both = failed
        both.outbox = [change("s1", JournalSyncRecordType.session)]
        XCTAssertEqual(JournalSyncStatusSummary.derive(both).kind, .uploading)
        both.outbox = []
        both.heldRecords = 2
        XCTAssertEqual(JournalSyncStatusSummary.derive(both).kind, .downloading)
        both.online = false
        XCTAssertEqual(JournalSyncStatusSummary.derive(both).kind, .offline)
    }

    func testOffAndRemovingComeFirst() {
        var facts = JournalSyncStatusFacts()
        facts.inUse = false
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .off)
        facts.inUse = true
        facts.unlinked = true
        facts.outbox = [change("s1", JournalSyncRecordType.session)]
        let off = JournalSyncStatusSummary.derive(facts)
        XCTAssertEqual(off.kind, .off)
        XCTAssertEqual(off.headline, "Off")
        facts.localRemovalInProgress = true
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts).kind, .removing)
    }

    func testUpToDateNamesTheLastCheck() {
        var facts = JournalSyncStatusFacts()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        facts.lastFetchAt = now.addingTimeInterval(-120)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        XCTAssertEqual(JournalSyncStatusSummary.derive(facts, now: now).detail,
                       "Everything on this device is in iCloud. Last checked \(f.string(from: facts.lastFetchAt!)).")
    }
}
#endif
