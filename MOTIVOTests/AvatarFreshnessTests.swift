//
//  AvatarFreshnessTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-I / C-34 — THE VERSION SIGNAL MUST ACTUALLY ARRIVE.
//
//  Phase 4 made the image cache version-aware, but the version travels in a
//  directory row, and that row was cached for the whole process: other members'
//  devices only saw a replacement after relaunch (R1). And the owner's own
//  second device never saw it at all — a local file won before the backend was
//  consulted, keyed on an avatar key that never changes (R2).
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`). Each assertion is
//  scoped to the function or struct it is about: `DirectoryAccount` already
//  decodes `avatar_version`, so a file-wide search would pass on nothing.
//

import XCTest
import UIKit
@testable import Etudes

/// A flag two threads may touch in the marker race test.
private final class RaceFlags: @unchecked Sendable {
    var markerFinishedWhileClearWasInside = false
    var cleared = false
}

final class AvatarFreshnessTests: XCTestCase {

    private func code(_ file: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(file)"), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ file: String, from start: String, length: Int) -> String? {
        let s = code(file)
        guard let r = s.range(of: start) else { return nil }
        return String(s[r.lowerBound...].prefix(length))
    }

    // MARK: - R1

    /// Directory rows expire, so a new `avatar_version` reaches every site.
    func testDirectoryCacheExpires() {
        let s = code("AccountDirectoryService.swift")
        XCTAssertTrue(s.contains("directoryCacheTTL"), "the directory cache needs an expiry")
        guard let body = slice("AccountDirectoryService.swift", from: "func resolveAccounts(", length: 2500) else {
            return XCTFail("resolveAccounts not found")
        }
        XCTAssertTrue(body.contains("idsNeedingFetch("), "expired rows must be refetched, not only absent ones")
    }

    // MARK: - R2 / B1

    /// The owner's own row carries the version — scoped, because `DirectoryAccount`
    /// already decodes it.
    func testSelfRowReadsAvatarVersion() {
        guard let row = slice("AccountDirectoryService.swift", from: "public struct SelfDirectoryRow", length: 1200),
              let fetch = slice("AccountDirectoryService.swift", from: "func fetchSelfRow(", length: 700) else {
            return XCTFail("SelfDirectoryRow / fetchSelfRow not found")
        }
        XCTAssertTrue(row.contains("case avatarVersion = \"avatar_version\""), "the self row must decode avatar_version")
        XCTAssertTrue(fetch.contains("avatar_version"), "fetchSelfRow must select avatar_version")
    }

    /// Hydration hands the self row's version to the own-avatar sync — a CALL,
    /// not merely the declaration.
    func testHydrationSyncsOwnAvatarFromBackend() {
        let calls = code("AuthManager.swift").components(separatedBy: .newlines)
            .filter { $0.contains("syncOwnAvatarFromBackend(") && !$0.contains("func syncOwnAvatarFromBackend(") }
        XCTAssertFalse(calls.isEmpty, "self-row hydration must reconcile the owner's local avatar copy")
    }

    /// The Profile redraws when the local copy is replaced — its trigger used to
    /// be keyed only on an avatar key that never changes.
    func testProfileAvatarRedrawsWhenOwnAvatarIsReplaced() {
        guard let trigger = slice("ProfileView.swift", from: "private var avatarRefreshTrigger: String {", length: 400) else {
            return XCTFail("avatarRefreshTrigger not found")
        }
        XCTAssertTrue(trigger.contains("ownAvatarRevision"), "the Profile must redraw when the own avatar is replaced")
    }

    // MARK: - Behavioural

    /// Absent and expired rows are fetched; fresh rows are not; forcing fetches all.
    func testExpiredDirectoryRowsAreRefetched() {
        let now = Date()
        let ttl = AccountDirectoryService.directoryCacheTTL
        XCTAssertEqual(ttl, 20 * 60, "consistent with CommentPresenceStore's comparable cache")
        let fetchedAt: [String: Date] = [
            "fresh": now.addingTimeInterval(-(ttl - 60)),
            "expired": now.addingTimeInterval(-(ttl + 60))
        ]
        let requested = ["fresh", "expired", "absent"]
        XCTAssertEqual(AccountDirectoryService.idsNeedingFetch(requested: requested, fetchedAt: fetchedAt,
                                                               now: now, ttl: ttl, forceRefresh: false),
                       ["expired", "absent"])
        XCTAssertEqual(AccountDirectoryService.idsNeedingFetch(requested: requested, fetchedAt: fetchedAt,
                                                               now: now, ttl: ttl, forceRefresh: true),
                       requested)
    }

    /// B1's whole rule, row by row.
    func testOwnAvatarSyncDecisionTable() {
        typealias S = OwnAvatarSync
        // An unsynced local change is never overwritten, whatever the backend says.
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v2", backendHasAvatar: true, hasPendingLocalChange: true), .none)
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: nil, backendHasAvatar: false, hasPendingLocalChange: true), .none)
        // First sight: refresh a present avatar; never delete on an absent one.
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: "v1", backendHasAvatar: true, hasPendingLocalChange: false), .refresh)
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: nil, backendHasAvatar: true, hasPendingLocalChange: false), .refresh)
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: nil, backendHasAvatar: false, hasPendingLocalChange: false), .recordOnly)
        // Unchanged: nothing.
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v1", backendHasAvatar: true, hasPendingLocalChange: false), .none)
        XCTAssertEqual(S.decide(lastApplied: "", backendVersion: nil, backendHasAvatar: true, hasPendingLocalChange: false), .none)
        // Changed: follow the backend — replace, or remove if it was removed.
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v2", backendHasAvatar: true, hasPendingLocalChange: false), .refresh)
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v2", backendHasAvatar: false, hasPendingLocalChange: false), .remove)
    }

    // MARK: - C-192, second pass: echoes, real changes, and the marker race

    /// `avatar_version` as PostgREST prints it; the fraction has 0 to 6 digits.
    func testAvatarVersionsAreOrderedAsTheServersClock() throws {
        typealias S = OwnAvatarSync
        let a = try XCTUnwrap(S.date(ofVersion: "2026-11-11T19:41:42.302262+00:00"))
        let b = try XCTUnwrap(S.date(ofVersion: "2026-11-11T19:41:42.3+00:00"))
        let c = try XCTUnwrap(S.date(ofVersion: "2026-11-11T19:41:43+00:00"))
        XCTAssertEqual(a.timeIntervalSince(b), 0.002262, accuracy: 0.00001)
        XCTAssertEqual(c.timeIntervalSince(b), 0.7, accuracy: 0.00001)
        XCTAssertNotNil(S.date(ofVersion: "2026-11-11T19:41:42.302262Z"))
        XCTAssertNil(S.date(ofVersion: "")); XCTAssertNil(S.date(ofVersion: "v1"))
        XCTAssertTrue(S.isNewer("2026-11-11T19:41:43+00:00", than: "2026-11-11T19:41:42.302262+00:00"))
        XCTAssertFalse(S.isNewer("2026-11-11T19:41:42.3+00:00", than: "2026-11-11T19:41:42.302262+00:00"),
                       "a shorter fraction is not a later time (a text comparison says it is)")
        XCTAssertFalse(S.isNewer("2026-11-11T19:41:42.302262+00:00", than: "2026-11-11T19:41:42.302262+00:00"))
        XCTAssertTrue(S.isNewer("2026-11-11T19:41:42+00:00", than: ""), "a first version follows none")
        XCTAssertFalse(S.isNewer("", than: "2026-11-11T19:41:42+00:00"), "a version is never unset")
    }

    /// A row read before this device's own publication must not undo it: the
    /// device records the version its publication produced, and only a NEWER
    /// version is followed. Without this the stale "no avatar" row below
    /// removed the photo the member had just chosen.
    func testAnOlderBackendVersionIsNeverFollowed() {
        typealias S = OwnAvatarSync
        let own = "2026-11-11T19:41:42.302262+00:00", stale = "2026-11-11T19:36:13.811987+00:00", later = "2026-11-11T19:50:00+00:00"
        XCTAssertEqual(S.decide(lastApplied: own, backendVersion: stale, backendHasAvatar: false, hasPendingLocalChange: false), .none)
        XCTAssertEqual(S.decide(lastApplied: own, backendVersion: stale, backendHasAvatar: true, hasPendingLocalChange: false), .none)
        XCTAssertEqual(S.decide(lastApplied: own, backendVersion: own, backendHasAvatar: true, hasPendingLocalChange: false), .none,
                       "its own publication is not read back")
        XCTAssertEqual(S.decide(lastApplied: own, backendVersion: later, backendHasAvatar: true, hasPendingLocalChange: false), .refresh)
        XCTAssertEqual(S.decide(lastApplied: own, backendVersion: later, backendHasAvatar: false, hasPendingLocalChange: false), .remove)
        // The record never moves backwards.
        let uid = "c192-" + UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "profile.\(uid).ownAvatarAppliedVersion_v1") }
        ProfileStore.noteOwnAvatarPublished(version: own, for: uid)
        ProfileStore.noteOwnAvatarPublished(version: stale, for: uid)
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: uid), own)
        ProfileStore.noteOwnAvatarPublished(version: later, for: uid)
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: uid), later)
        ProfileStore.noteOwnAvatarPublished(version: nil, for: uid)
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: uid), later)
    }

    /// A real change must stand before a sync-on device applies it.
    func testABackendChangeSettlesOnlyAfterStandingForTheInterval() {
        typealias S = OwnAvatarSync
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = S.settle(seen: nil, version: "v1", now: t0)
        XCTAssertFalse(first.settled); XCTAssertEqual(first.seen, S.Seen(version: "v1", at: t0))
        XCTAssertFalse(S.settle(seen: first.seen, version: "v1", now: t0.addingTimeInterval(119)).settled)
        XCTAssertTrue(S.settle(seen: first.seen, version: "v1", now: t0.addingTimeInterval(120)).settled)
        // A different version starts the wait again (the sibling published the newer state meanwhile).
        let changed = S.settle(seen: first.seen, version: "v2", now: t0.addingTimeInterval(500))
        XCTAssertFalse(changed.settled); XCTAssertEqual(changed.seen.version, "v2")
        // A clock set back starts it again too.
        XCTAssertFalse(S.settle(seen: first.seen, version: "v1", now: t0.addingTimeInterval(-10)).settled)
        XCTAssertEqual(S.settleInterval, 120)
    }

    private func picture(seed: UInt64, side: CGFloat = 256) -> UIImage {
        var state = seed
        func next() -> CGFloat { state = state &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((state >> 33) % 1000) / 1000 }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            UIColor(red: next(), green: next(), blue: next(), alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            for _ in 0..<24 {
                UIColor(red: next(), green: next(), blue: next(), alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: next() * side, y: next() * side, width: next() * side / 2, height: next() * side / 2))
            }
        }
    }

    /// The echo test: what this device publishes (a JPEG of its PNG) and what
    /// it would read back are the same picture; two photos are not.
    func testAPublishedCopyIsTheSamePictureAndADifferentPhotoIsNot() throws {
        let original = picture(seed: 1)
        let png = try XCTUnwrap(UIImage(data: try XCTUnwrap(original.pngData())))
        let published = try XCTUnwrap(UIImage(data: try XCTUnwrap(png.jpegData(compressionQuality: 0.9))))
        let readBack = try XCTUnwrap(UIImage(data: try XCTUnwrap(published.pngData())))
        let twice = try XCTUnwrap(UIImage(data: try XCTUnwrap(readBack.jpegData(compressionQuality: 0.9))))
        let echo = try XCTUnwrap(OwnAvatarSync.pictureDistance(png, published))
        XCTAssertLessThan(echo, 2, "JPEG loss disappears at this size")
        XCTAssertTrue(OwnAvatarSync.samePicture(png, published))
        XCTAssertTrue(OwnAvatarSync.samePicture(png, readBack))
        XCTAssertTrue(OwnAvatarSync.samePicture(png, twice), "a second generation is still the same picture")
        XCTAssertTrue(OwnAvatarSync.samePicture(png, picture(seed: 1, side: 1024)), "the editor's larger export of the same picture")
        for other in [UInt64(2), 3, 4, 5] {
            let distance = try XCTUnwrap(OwnAvatarSync.pictureDistance(png, picture(seed: other)))
            XCTAssertGreaterThan(distance, OwnAvatarSync.samePictureTolerance * 3, "a different photo is far outside the tolerance")
            XCTAssertFalse(OwnAvatarSync.samePicture(png, picture(seed: other)))
        }
    }

    /// The read-back no longer depends on whether sync is on to decide IF it
    /// looks, and every publication records the version it produced.
    func testTheReadBackIsNotBlanketSuppressedAndPublicationsRecordTheirVersion() throws {
        let auth = code("AuthManager.swift")
        let start = try XCTUnwrap(auth.range(of: "func syncOwnAvatarFromBackend("))
        let end = try XCTUnwrap(auth.range(of: "private func scheduleOwnAvatarRecheck("))
        let body = String(auth[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(body.contains("journalIsSource"), "the blanket suppression is gone")
        XCTAssertTrue(body.contains("OwnAvatarSync.samePicture("), "an echo is recognised by its picture")
        XCTAssertTrue(body.contains("OwnAvatarSync.settle("), "a real change waits with sync on")
        XCTAssertTrue(body.contains("== appliedAtStart"), "a publication during the download is not overwritten")
        XCTAssertEqual(auth.components(separatedBy: "ProfileStore.noteOwnAvatarPublished(").count - 1, 2, "the upload and the removal promotion")
        XCTAssertEqual(code("ProfileView.swift").components(separatedBy: "ProfileStore.noteOwnAvatarPublished(").count - 1, 1, "the Profile screen's own upload")
        XCTAssertEqual(AccountDirectoryService.avatarVersion(inPatchResponse: Data("[{\"user_id\":\"u\",\"avatar_version\":\"2026-11-11T19:41:42.302262+00:00\"}]".utf8)),
                       "2026-11-11T19:41:42.302262+00:00")
        XCTAssertNil(AccountDirectoryService.avatarVersion(inPatchResponse: Data("[]".utf8)))
    }

    private static let markerKey = "profile.__local_etudes_profile__.avatarSyncState_v1"

    /// THE RACE, with a controlled overlap. The checked clear has passed its
    /// check and has not yet removed the marker; a new marking arrives on
    /// another thread in exactly that window. Before the fix the number and the
    /// stored value changed in two steps, so the marking landed and the clear
    /// then removed it: the newer pending change was lost. Under one lock the
    /// marking waits for the clear, and is still there afterwards.
    func testAMarkingThatArrivesInsideACheckedClearIsNotLost() throws {
        let saved = UserDefaults.standard.object(forKey: Self.markerKey)
        defer {
            ProfileStore.testHookInsideCheckedAvatarClear = nil
            if let saved { UserDefaults.standard.set(saved, forKey: Self.markerKey) } else { UserDefaults.standard.removeObject(forKey: Self.markerKey) }
        }
        ProfileStore.deleteAvatar(for: nil)                                   // the older marking ("delete")
        let older = ProfileStore.pendingLocalAvatarSnapshot()
        XCTAssertEqual(older.state, "delete")

        let insideClear = DispatchSemaphore(value: 0)
        let markerDone = DispatchSemaphore(value: 0)
        let clearDone = DispatchSemaphore(value: 0)
        let flags = RaceFlags()
        ProfileStore.testHookInsideCheckedAvatarClear = {
            insideClear.signal()
            // Hold the window open: long enough for the other thread to mark if nothing stops it.
            flags.markerFinishedWhileClearWasInside = markerDone.wait(timeout: .now() + 0.4) == .success
        }
        let olderGeneration = older.generation
        DispatchQueue.global().async {                                          // the older upload completing
            flags.cleared = ProfileStore.clearPendingLocalAvatarSync(ifUnchangedSince: olderGeneration)
            clearDone.signal()
        }
        XCTAssertEqual(insideClear.wait(timeout: .now() + 5), .success, "the clear reached its window")
        let raceUser = "c192-race-\(UUID().uuidString)"
        DispatchQueue.global().async {                                          // the newer change being marked
            ProfileStore.removeSyncedAvatar(for: raceUser)
            markerDone.signal()
        }
        XCTAssertEqual(clearDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(markerDone.wait(timeout: .now() + 5), .success)
        ProfileStore.testHookInsideCheckedAvatarClear = nil

        XCTAssertTrue(flags.cleared, "the older clear was entitled to clear its own marking")
        XCTAssertFalse(flags.markerFinishedWhileClearWasInside, "the marking could not land between the check and the removal")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion(), "the newer pending change survives the older completion")
        XCTAssertEqual(ProfileStore.pendingLocalAvatarSnapshot().generation, older.generation + 1)
        // And in the other order (marked first): the clear refuses.
        let newer = ProfileStore.pendingLocalAvatarSnapshot()
        ProfileStore.deleteAvatar(for: nil)
        XCTAssertFalse(ProfileStore.clearPendingLocalAvatarSync(ifUnchangedSince: newer.generation))
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarSync())
    }

    /// The promotion of a removal must not delete an image the sync wrote after
    /// the promotion read its marker.
    func testARemovalPromotionDoesNotDeleteAnImageMarkedSinceItStarted() throws {
        let saved = UserDefaults.standard.object(forKey: Self.markerKey)
        let uid = "c192-del-" + UUID().uuidString
        defer {
            ProfileStore.removeSyncedAvatar(for: uid)
            if let saved { UserDefaults.standard.set(saved, forKey: Self.markerKey) } else { UserDefaults.standard.removeObject(forKey: Self.markerKey) }
        }
        ProfileStore.removeSyncedAvatar(for: uid)                               // a removal arrives: marked "delete"
        let removal = ProfileStore.pendingLocalAvatarSnapshot()
        XCTAssertEqual(removal.state, "delete")
        let png = try XCTUnwrap(picture(seed: 9).pngData())
        XCTAssertTrue(ProfileStore.writeSyncedAvatar(pngData: png, for: uid, modifiedAt: Date()))   // then the new image
        XCTAssertFalse(ProfileStore.deleteAvatarForPendingDeletion(for: uid, ifUnchangedSince: removal.generation))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(ProfileStore.avatarDerivedURL(for: uid))), png, "the new image is untouched")
        XCTAssertEqual(ProfileStore.pendingLocalAvatarSnapshot().state, "upload")
        // With nothing marked since, the removal does drop the identity's copy.
        let current = ProfileStore.pendingLocalAvatarSnapshot()
        XCTAssertTrue(ProfileStore.deleteAvatarForPendingDeletion(for: uid, ifUnchangedSince: current.generation))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(ProfileStore.avatarDerivedURL(for: uid)).path))
    }

    /// C-192, device rerun 2026-11-11. At a first join the pending avatar was
    /// promoted before the first directory row existed: the object went up, the
    /// key PATCH matched no row and still read as success, and the marker was
    /// cleared with nothing pointing at the object.
    func testAnAvatarKeyPatchThatMatchedNoRowIsNotASuccess() throws {
        XCTAssertFalse(AccountDirectoryService.avatarKeyPatchMatchedARow(Data("[]".utf8)), "no row: keep the marker")
        XCTAssertFalse(AccountDirectoryService.avatarKeyPatchMatchedARow(Data()), "the old `return=minimal` empty body")
        XCTAssertFalse(AccountDirectoryService.avatarKeyPatchMatchedARow(Data("{\"message\":\"x\"}".utf8)))
        XCTAssertTrue(AccountDirectoryService.avatarKeyPatchMatchedARow(Data("[{\"user_id\":\"u\"}]".utf8)))
        let service = code("AccountDirectoryService.swift")
        let start = try XCTUnwrap(service.range(of: "public func updateSelfAvatarKey("))
        let body = String(service[start.lowerBound...].prefix(1_600))
        XCTAssertTrue(body.contains("return=representation") && body.contains("avatarKeyPatchMatchedARow"),
                      "the patch must ask for the row back and require it")
        XCTAssertFalse(body.contains("return=minimal"))
        // And the photo is attached when ANY write evidences the row: the three
        // writers of the own row all go through one function, which says so.
        let applied = try XCTUnwrap(service.range(of: "if case .applied(let receipt) = outcome {"))
        XCTAssertTrue(String(service[applied.lowerBound...].prefix(700)).contains("Self.ownRowAppliedNotification"),
                      "an evidenced own-row write is announced")
        let auth = code("AuthManager.swift")
        XCTAssertTrue(auth.contains("forName: AccountDirectoryService.ownRowAppliedNotification"), "and the account listens")
        let handler = try XCTUnwrap(auth.range(of: "func directoryRowWasEvidenced(owner: String?) async {"))
        XCTAssertTrue(String(auth[handler.lowerBound...].prefix(600)).contains("afterFirstRow: true"),
                      "the row is evidenced, so the no-row skip does not apply")
    }

    /// C-192. A marking made while a promotion is in flight is not cleared by it.
    func testAPromotionClearsOnlyTheMarkingItStartedFrom() {
        let key = "profile.__local_etudes_profile__.avatarSyncState_v1"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        ProfileStore.deleteAvatar(for: nil)                       // marks "delete"
        let removal = ProfileStore.pendingLocalAvatarGeneration   // a promotion starts here
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion())
        ProfileStore.deleteAvatar(for: nil)                       // marked again meanwhile
        XCTAssertFalse(ProfileStore.clearPendingLocalAvatarSync(ifUnchangedSince: removal), "the later marking survives")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarSync())
        XCTAssertTrue(ProfileStore.clearPendingLocalAvatarSync(ifUnchangedSince: ProfileStore.pendingLocalAvatarGeneration))
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())
    }
}
