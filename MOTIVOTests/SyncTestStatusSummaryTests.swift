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
@testable import Etudes

final class SyncTestStatusSummaryTests: XCTestCase {

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
