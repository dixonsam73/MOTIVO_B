//
//  SyncTestStorageFullTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  iCloud storage full (CKError.quotaExceeded): what a failed save means, the
//  episode that begins once and counts later refusals, the retry cadence (no
//  tight loop; a user-driven trigger waits only the floor), what ends an
//  episode, the person-facing line, the state file and the bounded
//  simulation window.
//

#if SYNCTEST
import XCTest
import CloudKit
@testable import Etudes

final class SyncTestStorageFullTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testEachFailedSaveHasOneDecisionAndOnlyQuotaExceededIsStorageFull() {
        XCTAssertEqual(JournalSendFailure.action(for: .serverRecordChanged), .resolveConflict)
        XCTAssertEqual(JournalSendFailure.action(for: .zoneNotFound), .recreateZone)
        XCTAssertEqual(JournalSendFailure.action(for: .unknownItem), .resendAsNew)
        XCTAssertEqual(JournalSendFailure.action(for: .quotaExceeded), .storageFull)
        for code: CKError.Code in [.networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
                                   .notAuthenticated, .accountTemporarilyUnavailable] {
            XCTAssertEqual(JournalSendFailure.action(for: code), .engineRetries, "\(code): the engine keeps the change and retries")
        }
        XCTAssertEqual(JournalSendFailure.action(for: .limitExceeded), .unexpected, "a batch too large is not a full account")
        XCTAssertEqual(JournalSendFailure.action(for: .permissionFailure), .unexpected)
        XCTAssertTrue(JournalStorageFull.isStorageFull(.quotaExceeded))
        XCTAssertFalse(JournalStorageFull.isStorageFull(.limitExceeded))
        XCTAssertFalse(JournalStorageFull.isStorageFull(.networkFailure))
    }

    func testAnEpisodeBeginsOnceAndLaterRefusalsAreCountedNotBegun() {
        let first = JournalStorageFull.noting(failureAt: t0, zone: false, simulated: false, in: nil)
        XCTAssertTrue(first.began, "the one moment the engine logs")
        XCTAssertEqual(first.episode.attempts, 1)
        XCTAssertEqual(first.episode.began, t0)
        XCTAssertFalse(first.episode.zoneSaveFailed)
        XCTAssertFalse(first.episode.simulated)

        let second = JournalStorageFull.noting(failureAt: t0 + 300, zone: true, simulated: true, in: first.episode)
        XCTAssertFalse(second.began, "logged once per episode, not per attempt")
        XCTAssertEqual(second.episode.attempts, 2)
        XCTAssertEqual(second.episode.began, t0, "the start is kept")
        XCTAssertEqual(second.episode.lastFailureAt, t0 + 300)
        XCTAssertTrue(second.episode.zoneSaveFailed, "a refused zone save sticks until the zone is saved")
        XCTAssertFalse(second.episode.simulated, "an episode the server began stays real")

        let third = JournalStorageFull.noting(failureAt: t0 + 900, zone: false, simulated: false, in: second.episode)
        XCTAssertTrue(third.episode.zoneSaveFailed, "and is not cleared by a later record-only refusal")
        XCTAssertEqual(third.episode.attempts, 3)

        let simulated = JournalStorageFull.noting(failureAt: t0, zone: false, simulated: true, in: nil)
        XCTAssertTrue(simulated.episode.simulated, "an episode the diagnostics switch began says so")
    }

    func testRetriesBackOffFromTwoMinutesAndNeverExceedFifteen() {
        XCTAssertEqual(JournalStorageFull.retryInterval(attempts: 1), 120)
        XCTAssertEqual(JournalStorageFull.retryInterval(attempts: 2), 240)
        XCTAssertEqual(JournalStorageFull.retryInterval(attempts: 3), 480)
        XCTAssertEqual(JournalStorageFull.retryInterval(attempts: 4), 900, "capped at fifteen minutes")
        XCTAssertEqual(JournalStorageFull.retryInterval(attempts: 40), 900)
        XCTAssertEqual(JournalStorageFull.retryInterval(attempts: 0), 120, "never below the floor")
        XCTAssertEqual(JournalStorageFull.minimumRetryInterval, 120)
        XCTAssertEqual(JournalStorageFull.maximumRetryInterval, 900)
    }

    func testNoAttemptBeforeItsTimeAndAUserDrivenTriggerWaitsOnlyTheFloor() {
        XCTAssertTrue(JournalStorageFull.retryDue(nil, now: t0, userDriven: false), "no episode: every send goes")
        let episode = JournalStorageFull.Episode(began: t0, attempts: 3, lastFailureAt: t0)
        // Three refusals: the backoff is 8 min for a push or poll; 2 min for a change, the foreground or activation.
        XCTAssertFalse(JournalStorageFull.retryDue(episode, now: t0 + 30, userDriven: false), "a poll 30 s later: no tight loop")
        XCTAssertFalse(JournalStorageFull.retryDue(episode, now: t0 + 30, userDriven: true), "nor a change 30 s later")
        XCTAssertFalse(JournalStorageFull.retryDue(episode, now: t0 + 119, userDriven: true))
        XCTAssertTrue(JournalStorageFull.retryDue(episode, now: t0 + 120, userDriven: true), "the foreground after the floor")
        XCTAssertFalse(JournalStorageFull.retryDue(episode, now: t0 + 120, userDriven: false), "a push waits the backoff")
        XCTAssertFalse(JournalStorageFull.retryDue(episode, now: t0 + 479, userDriven: false))
        XCTAssertTrue(JournalStorageFull.retryDue(episode, now: t0 + 480, userDriven: false))
        XCTAssertEqual(JournalStorageFull.nextRetryAt(episode, userDriven: false), t0 + 480)
        XCTAssertEqual(JournalStorageFull.nextRetryAt(episode, userDriven: true), t0 + 120)
        // The cadence is measured from the last REFUSAL, so a gated attempt
        // (one that did not run) does not push the next one out.
        let fresh = JournalStorageFull.Episode(began: t0, attempts: 1, lastFailureAt: t0)
        XCTAssertTrue(JournalStorageFull.retryDue(fresh, now: t0 + 120, userDriven: false))
    }

    func testAnEpisodeEndsOnAnAcceptedSaveOrWhenNothingIsLeftWaiting() {
        typealias F = JournalStorageFull
        XCTAssertTrue(F.recovered(savedRecords: 1, savedZones: 0, deletedRecords: 0, quotaFailures: 0, savesStillPending: 5), "one accepted save proves there is space")
        XCTAssertFalse(F.recovered(savedRecords: 1, savedZones: 0, deletedRecords: 0, quotaFailures: 2, savesStillPending: 2), "a batch with refusals in it keeps the episode")
        XCTAssertFalse(F.recovered(savedRecords: 0, savedZones: 0, deletedRecords: 3, quotaFailures: 0, savesStillPending: 2), "deletions can succeed while the storage is full")
        XCTAssertTrue(F.recovered(savedRecords: 0, savedZones: 0, deletedRecords: 3, quotaFailures: 0, savesStillPending: 0), "unless no save is left waiting")
        XCTAssertFalse(F.recovered(savedRecords: 0, savedZones: 1, deletedRecords: 0, quotaFailures: 0, savesStillPending: 4), "the zone is tiny; the records decide")
        XCTAssertTrue(F.recovered(savedRecords: 0, savedZones: 1, deletedRecords: 0, quotaFailures: 0, savesStillPending: 0))
        XCTAssertFalse(F.recovered(savedRecords: 0, savedZones: 0, deletedRecords: 0, quotaFailures: 0, savesStillPending: 0), "an empty event proves nothing")
    }

    func testTheStatusLineSaysWhatWaitsAndThatNothingIsRemoved() {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let began = Date().addingTimeInterval(-600)
        let episode = JournalStorageFull.Episode(began: began, attempts: 2, lastFailureAt: began)
        XCTAssertEqual(JournalStorageFull.summary(episode: episode, pendingSaves: 5, pendingDeletes: 2, mediaFiles: 2),
                       "iCloud storage is full (since \(f.string(from: began))): 7 changes waiting, 2 with media. They are sent when space is available; nothing is removed from this device.")
        XCTAssertEqual(JournalStorageFull.summary(episode: episode, pendingSaves: 1, pendingDeletes: 0, mediaFiles: 0),
                       "iCloud storage is full (since \(f.string(from: began))): 1 change waiting. It is sent when space is available; nothing is removed from this device.")
        XCTAssertEqual(JournalStorageFull.summary(episode: episode, pendingSaves: 0, pendingDeletes: 0, mediaFiles: 0),
                       "iCloud storage is full (since \(f.string(from: began))): nothing waiting.")
        var simulated = episode; simulated.simulated = true
        XCTAssertTrue(JournalStorageFull.summary(episode: simulated, pendingSaves: 1, pendingDeletes: 0, mediaFiles: 0).contains("(since \(f.string(from: began)), simulated)"))
        let yesterday = DateFormatter(); yesterday.dateFormat = "d MMM HH:mm"
        let old = JournalStorageFull.Episode(began: began.addingTimeInterval(-86_400 * 2), attempts: 1, lastFailureAt: began)
        XCTAssertTrue(JournalStorageFull.summary(episode: old, pendingSaves: 1, pendingDeletes: 0, mediaFiles: 0).contains(yesterday.string(from: old.began)), "an older episode shows its day")
    }

    func testTheEpisodeAndTheOutboxSurviveARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-quota-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let store = JournalSyncStateStore(fileURL: url)
        let episode = JournalStorageFull.Episode(began: t0, attempts: 2, lastFailureAt: t0 + 240, zoneSaveFailed: true, simulated: false)
        let pending = JournalSyncPendingChange(recordName: "att-1", recordType: JournalSyncRecordType.attachment, op: .save)
        store.update { $0.storageFull = episode; $0.storageFullEpisodes = 1; $0.outbox = [pending]; $0.mediaWaitingUpload["att-2"] = 7 }
        let reloaded = JournalSyncStateStore(fileURL: url)
        XCTAssertEqual(reloaded.state.storageFull, episode, "the status is right at the next launch")
        XCTAssertEqual(reloaded.state.storageFullEpisodes, 1)
        XCTAssertEqual(reloaded.state.outbox, [pending], "nothing is dropped from the outbox")
        XCTAssertEqual(reloaded.state.mediaWaitingUpload, ["att-2": 7], "held media keeps waiting")
        // A state file written before this field decodes with no episode.
        XCTAssertNil(JournalSyncPersistedState().storageFull)
    }

    func testTheSimulationIsBoundedInTime() {
        XCTAssertFalse(JournalStorageFull.simulationActive(until: nil, now: t0))
        XCTAssertTrue(JournalStorageFull.simulationActive(until: t0 + 600, now: t0))
        XCTAssertTrue(JournalStorageFull.simulationActive(until: t0 + 600, now: t0 + 599))
        XCTAssertFalse(JournalStorageFull.simulationActive(until: t0 + 600, now: t0 + 600), "then the next due attempt goes to the server")
    }
}
#endif
