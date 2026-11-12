//
//  AvatarUniqueNameTests.swift
//  MOTIVOTests
//
//  A name per avatar upload (2026-11-12, with B-48): a delete names one image,
//  so however late it arrives it cannot reach a newer photo; and what this
//  device deletes is decided by a record that never gives up an image whose
//  reference write is pending or of unknown outcome.
//
//  Every interleaving here is an ordered script against the backend in memory
//  (`FakeAvatarBackend`): requests are held at gates, answers are lost, a write
//  is delivered late. Nothing depends on timing. The removal's own cases, which
//  need a signed-in account, are in `SyncTestConnectedIsolationTests`.
//

import XCTest
import UIKit
@testable import Etudes

/// The record's file, refusing writes when a test says so.
private final class FlakyDisk {
    var refuses: (Data) -> Bool = { _ in false }
    private(set) var refused = 0
    func write(_ data: Data, to url: URL) throws {
        if refuses(data) { refused += 1; throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: url, options: .atomic)
    }
    /// The record of a reference write (an entry with the version it is conditional on).
    static func holdsAReferenceWrite(_ data: Data) -> Bool { String(decoding: data, as: UTF8.self).contains("writeExpected") }
}

@MainActor
final class AvatarUniqueNameTests: XCTestCase {
    private let uid = "fake"
    private var files: [URL] = []

    override func tearDown() async throws {
        for url in files { try? FileManager.default.removeItem(at: url) }
        files = []
    }

    private func photo(_ seed: Int) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { context in
            UIColor(hue: CGFloat(seed % 10) / 10, saturation: 0.9, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: CGFloat(seed * 5 % 50), y: 8, width: 10, height: 40))
        }
    }
    private func jpeg(_ seed: Int) -> Data { photo(seed).jpegData(compressionQuality: 0.9)! }
    private func memoryLedger() -> AvatarWorkLedger { AvatarWorkLedger(userID: uid, fileURL: nil) }
    private func ledgerFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-work-\(UUID().uuidString).json")
        files.append(url)
        return url
    }
    private func publish(_ seed: Int, _ backend: FakeAvatarBackend, _ ledger: AvatarWorkLedger) async -> AvatarPublication.Outcome {
        await AvatarPublication.publish(jpeg: jpeg(seed), userID: uid, backend: backend, ledger: ledger)
    }
    /// What the first read of the row after a launch does.
    private func settleOnAFreshRead(_ backend: FakeAvatarBackend, _ ledger: AvatarWorkLedger) async {
        await ledger.settle(rowExists: backend.rowExists, key: backend.key, version: backend.version, backend: backend)
    }
    private func shows(_ backend: FakeAvatarBackend, _ seed: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let image = backend.referenced else { return XCTFail("the reference names no stored image", file: file, line: line) }
        XCTAssertTrue(OwnAvatarSync.samePicture(image, photo(seed)), "the profile does not show photo \(seed)", file: file, line: line)
    }

    // MARK: - Names

    func testOnlyTheTwoFormsInTheMembersOwnFolderAreAvatarNames() {
        let id = "0f33f6b8-704d-49e3-b94f-3de7dd82ba87"
        let made = AvatarObjectName.make(userID: id.uppercased() + " ")
        XCTAssertTrue(made.hasPrefix("users/\(id)/avatar-") && made.hasSuffix(".jpg") && made.count == "users/\(id)/avatar-".count + 32 + 4, made)
        XCTAssertTrue(AvatarObjectName.isPerUpload(made, userID: id))
        XCTAssertNotEqual(made, AvatarObjectName.make(userID: id), "a new name every time")
        XCTAssertTrue(AvatarObjectName.isOwn("users/\(id)/avatar.jpg", userID: id), "the old fixed name is still this member's avatar")
        let hex = "0123456789abcdef0123456789abcdef"
        for bad in ["users/other/avatar.jpg", "users/other/avatar-\(hex).jpg", "users/\(id)/other.jpg", "users/\(id)/avatar-\(hex.uppercased()).jpg",
                    "users/\(id)/avatar-\(hex.dropLast()).jpg", "users/\(id)/avatar-\(hex)0.jpg", "users/\(id)/avatar-\(hex).png",
                    "users/\(id)/x/avatar-\(hex).jpg", "users/\(id)/avatar-\(hex).jpg/../../other/avatar.jpg", "anything", ""] {
            XCTAssertFalse(AvatarObjectName.isOwn(bad, userID: id), bad)
        }
        XCTAssertFalse(AvatarObjectName.isOwn("users//avatar.jpg", userID: " "), "no member, no avatar")
    }

    func testAVersionIsNewerOnlyWhenItIsReadableAndStrictlyLater() {
        typealias L = AvatarWorkLedger
        XCTAssertTrue(L.isStrictlyNewer("2026-11-12T11:55:05.496452+00:00", than: "2026-11-12T11:55:05.496451+00:00"), "one microsecond is later")
        XCTAssertFalse(L.isStrictlyNewer("2026-11-12T11:55:05.496451+00:00", than: "2026-11-12T11:55:05.496451+00:00"), "the same version is not")
        XCTAssertFalse(L.isStrictlyNewer("2026-11-12T11:55:05.496451Z", than: "2026-11-12T11:55:05.496451+00:00"), "nor the same instant written another way")
        XCTAssertFalse(L.isStrictlyNewer("2026-11-12T11:55:05.496450+00:00", than: "2026-11-12T11:55:05.496451+00:00"), "an OLDER read never counts")
        XCTAssertTrue(L.isStrictlyNewer("2026-11-12T11:55:06+00:00", than: "2026-11-12T11:55:05.999999+00:00"))
        XCTAssertTrue(L.isStrictlyNewer("2026-11-12T11:55:05.5+00:00", than: "2026-11-12T11:55:05.49+00:00"), "a short fraction is read as a fraction")
        XCTAssertTrue(L.isStrictlyNewer("2026-11-12T11:55:05+00:00", than: ""), "any stamp is later than 'never stamped'")
        XCTAssertFalse(L.isStrictlyNewer(nil, than: ""), "no stamp is not")
        XCTAssertFalse(L.isStrictlyNewer("garbage", than: "2026-11-12T11:55:05+00:00"), "an unreadable version deletes nothing")
        XCTAssertFalse(L.isStrictlyNewer("2026-11-12T11:55:05+00:00", than: "garbage"))
    }

    // MARK: - The delayed delete

    /// THE RACE THIS CHANGE CLOSES, for a replacement. This device publishes
    /// photo 2 over photo 1; the server accepts its reference write; its
    /// delete of photo 1's image is still on its way. Another of the owner's
    /// devices then publishes photo 3 completely. The delete arrives. With one
    /// fixed name it would have removed photo 3. Now it names photo 1's image.
    func testAReplacementsDeleteThatArrivesAfterANewerPublicationDeletesOnlyTheOldImage() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        guard case .published(let first, _) = await publish(1, backend, ledger) else { return XCTFail() }
        let held = AvatarTestGate()
        backend.gates["this.deleteObject"] = held
        let replacing = Task { @MainActor in await self.publish(2, backend, ledger) }
        await held.waitUntilArrived()                                  // reference -> photo 2, accepted; the delete of photo 1 is in flight
        let second = try XCTUnwrap(backend.key)
        guard case .published(let third, _) = await backend.otherDevicePublishes(photo(3)) else { return XCTFail() }
        XCTAssertEqual(backend.key, third); shows(backend, 3)
        XCTAssertEqual(backend.deletions.map(\.name), [second], "the other device deleted the image IT displaced (photo 2's)")
        XCTAssertNotNil(backend.objects[first], "photo 1's image is still there: its delete has not arrived")

        held.open()                                                    // the delayed delete arrives now
        guard case .published = await replacing.value else { return XCTFail() }

        XCTAssertEqual(backend.key, third, "the reference is untouched")
        shows(backend, 3)
        XCTAssertEqual(Array(backend.objects.keys), [third], "only the newest image is stored: the late delete took photo 1's and nothing else")
        XCTAssertEqual(backend.deletions.filter { $0.device == "this" }.map(\.name), [first], "this device deleted exactly the name it displaced")
    }

    /// The same with the other device's publication REFUSED ONCE AND REPEATED
    /// while this device's delete is in flight (the case a longer timeout or
    /// another read could not cover: the delete may be outstanding for as long
    /// as it likes).
    func testADelayedDeleteOutlastingAnotherDevicesRefusedAndRepeatedPublicationStillDeletesOnlyTheOldImage() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        guard case .published(let first, _) = await publish(1, backend, ledger) else { return XCTFail() }
        // The other device starts publishing photo 3: it reads the row, stores its image, and is held before its reference write.
        let otherHeld = AvatarTestGate()
        backend.gates["other.setKey"] = otherHeld
        let other = Task { @MainActor in await backend.otherDevicePublishes(self.photo(3)) }
        await otherHeld.waitUntilArrived()
        // This device replaces photo 1 with photo 2; its delete of photo 1's image is held in flight.
        let deleteHeld = AvatarTestGate()
        backend.gates["this.deleteObject"] = deleteHeld
        let replacing = Task { @MainActor in await self.publish(2, backend, ledger) }
        await deleteHeld.waitUntilArrived()
        // The other device's write is refused (the reference has been written), and it repeats: whole publication.
        otherHeld.open()
        guard case .published(let third, _) = await other.value else { return XCTFail() }
        XCTAssertEqual(backend.count("other: setKey REFUSED"), 1); XCTAssertEqual(backend.count("other: upload"), 2)
        XCTAssertNotNil(backend.objects[first], "this device's delete is still outstanding")

        deleteHeld.open()
        _ = await replacing.value

        XCTAssertEqual(backend.key, third); shows(backend, 3)
        XCTAssertEqual(Array(backend.objects.keys), [third])
        XCTAssertEqual(backend.deletions.filter { $0.device == "this" }.map(\.name), [first])
        XCTAssertFalse(backend.deletions.contains { $0.name == third }, "nobody ever deleted the newest photo")
    }

    // MARK: - Failed operations

    func testAFailedUploadStoresNothingAndTheNextAttemptPublishes() async throws {
        let backend = FakeAvatarBackend()
        let ledger = AvatarWorkLedger(userID: uid, fileURL: ledgerFile())
        backend.uploadsFail = true
        let failed = await publish(1, backend, ledger)
        XCTAssertEqual(failed, .uploadFailed)
        XCTAssertTrue(backend.objects.isEmpty); XCTAssertNil(backend.key)
        backend.uploadsFail = false
        guard case .published(let key, _) = await publish(1, backend, ledger) else { return XCTFail() }
        XCTAssertEqual(Array(backend.objects.keys), [key]); shows(backend, 1)
        XCTAssertEqual(ledger.entries.keys.sorted(), [key], "the name that was never stored is off the record once the server says it is not there")
    }

    /// The upload was stored and its answer lost: this device believes it
    /// failed. No reference write was ever sent for that image, so it is this
    /// device's abandoned upload, and the next attempt removes it.
    func testAnUploadStoredWithItsAnswerLostIsAbandonedAndRemoved() async throws {
        let backend = FakeAvatarBackend()
        let ledger = AvatarWorkLedger(userID: uid, fileURL: ledgerFile())
        backend.nextUploadLosesItsResponse = true
        let failed = await publish(1, backend, ledger)
        XCTAssertEqual(failed, .uploadFailed)
        let stranded = try XCTUnwrap(backend.unreferenced.first)
        XCTAssertNil(backend.key)
        guard case .published(let key, _) = await publish(1, backend, ledger) else { return XCTFail() }
        XCTAssertEqual(Array(backend.objects.keys), [key], "the abandoned image is gone")
        XCTAssertEqual(backend.deletions.map(\.name), [stranded])
    }

    /// CODEX'S CORRECTION 1. The reference write was sent and no answer came;
    /// it has NOT reached the server (it may yet). The image is neither
    /// published nor abandoned: it is kept, through any number of looks, until
    /// a read of the row settles it.
    func testAnImageWhoseReferenceWriteIsStillPendingIsNeverDeleted() async throws {
        let backend = FakeAvatarBackend(picture: photo(9))                 // an older build's photo is showing
        let ledger = AvatarWorkLedger(userID: uid, fileURL: ledgerFile())
        backend.nextSetKeyIsDelayed = true
        let unanswered = await publish(1, backend, ledger)
        XCTAssertEqual(unanswered, .referenceFailed)
        let pending = try XCTUnwrap(backend.unreferenced.first)
        for _ in 0..<3 { await settleOnAFreshRead(backend, ledger) }
        XCTAssertNotNil(backend.objects[pending], "a pending image survives every look while the version stands")
        XCTAssertTrue(backend.deletions.isEmpty, "and nothing at all was deleted: the old photo is not displaced either")
        // The same after a relaunch: the record is the file, and nothing is in flight.
        let relaunched = AvatarWorkLedger(userID: uid, fileURL: try XCTUnwrap(files.last))
        await settleOnAFreshRead(backend, relaunched)
        XCTAssertNotNil(backend.objects[pending]); XCTAssertTrue(backend.deletions.isEmpty)

        // The write arrives at last. The image is the profile's photo, and stays.
        backend.deliverTheDelayedWrite()
        XCTAssertEqual(backend.key, pending); shows(backend, 1)
        await settleOnAFreshRead(backend, relaunched)
        XCTAssertNotNil(backend.objects[pending], "the published image is not deleted")
        XCTAssertEqual(backend.deletions.map(\.name), [backend.legacyName], "the photo it displaced is, now that a read shows it displaced")
        // And the retry recognises its own publication: nothing is stored again.
        let uploads = backend.count("this: upload")
        guard case .published(let key, let version) = await publish(1, backend, relaunched) else { return XCTFail() }
        XCTAssertEqual(key, pending); XCTAssertEqual(version, backend.version)
        XCTAssertEqual(backend.count("this: upload"), uploads)
    }

    /// CODEX'S CORRECTION 1, the named case: SUCCESS WITH A LOST RESPONSE. The
    /// server made the write; this device was told nothing. The image is the
    /// profile's photo. It must not be deleted, by a clean-up or by the retry.
    func testAnImagePublishedWithItsAnswerLostIsNeverDeletedAndIsRecognisedOnTheRetry() async throws {
        let backend = FakeAvatarBackend(picture: photo(9))
        let ledger = AvatarWorkLedger(userID: uid, fileURL: ledgerFile())
        backend.nextSetKeyLosesItsResponse = true
        let unanswered = await publish(1, backend, ledger)
        XCTAssertEqual(unanswered, .referenceFailed, "this device does not know it was published")
        let published = try XCTUnwrap(backend.key)
        shows(backend, 1)
        XCTAssertTrue(backend.deletions.isEmpty, "nothing was deleted on an unknown outcome, not even the photo it replaced")
        // A relaunch, then the first read of the row.
        let relaunched = AvatarWorkLedger(userID: uid, fileURL: try XCTUnwrap(files.last))
        await settleOnAFreshRead(backend, relaunched)
        XCTAssertNotNil(backend.objects[published], "the published image survives the clean-up")
        XCTAssertEqual(backend.deletions.map(\.name), [backend.legacyName], "the read shows the old photo displaced: that one goes")
        // The retry (the pending marker is still set) publishes nothing new.
        let before = backend.log.filter { !$0.hasSuffix("probe") }.count
        guard case .published(let key, let version) = await publish(1, backend, relaunched) else { return XCTFail() }
        XCTAssertEqual(key, published); XCTAssertEqual(version, backend.version)
        XCTAssertEqual(backend.log.filter { !$0.hasSuffix("probe") }.count, before, "no upload, no write, no delete")
        shows(backend, 1)
    }

    /// The pending write and the retry race each other, both ways round. The
    /// retry is made first: the earlier image can then never be pointed at
    /// (the version its write needs has passed), so it is deleted, and the
    /// write that arrives late is refused by the server.
    func testARetryThatLandsBeforeTheEarlierWriteLeavesOneImageAndTheLateWriteIsRefused() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        backend.nextSetKeyIsDelayed = true
        let unanswered = await publish(1, backend, ledger)
        XCTAssertEqual(unanswered, .referenceFailed)
        let earlier = try XCTUnwrap(backend.unreferenced.first)
        guard case .published(let key, _) = await publish(1, backend, ledger) else { return XCTFail() }
        XCTAssertNotEqual(key, earlier, "a retry stores under a new name; a name is never pointed at twice")
        XCTAssertEqual(Array(backend.objects.keys), [key], "the earlier image is deleted once its write can no longer be accepted")
        backend.deliverTheDelayedWrite()
        XCTAssertEqual(backend.count("this: setKey REFUSED"), 1, "the late write is refused")
        XCTAssertEqual(backend.key, key); shows(backend, 1)
    }

    /// The other way round: the earlier write lands while the retry is between
    /// storing its image and writing the reference. The retry is refused, its
    /// own image is deleted, and it recognises the earlier image as published.
    func testAnEarlierWriteThatLandsDuringTheRetryIsThePublicationAndTheRetrysImageIsRemoved() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        backend.nextSetKeyIsDelayed = true
        let unanswered = await publish(1, backend, ledger)
        XCTAssertEqual(unanswered, .referenceFailed)
        let earlier = try XCTUnwrap(backend.unreferenced.first)
        let held = AvatarTestGate()
        backend.gates["this.setKey"] = held
        let retry = Task { @MainActor in await self.publish(1, backend, ledger) }
        await held.waitUntilArrived()                    // the retry's image is stored; its write is about to go
        backend.deliverTheDelayedWrite()                 // the earlier write arrives first
        XCTAssertEqual(backend.key, earlier)
        held.open()
        guard case .published(let key, _) = await retry.value else { return XCTFail() }
        XCTAssertEqual(key, earlier, "the earlier image is the publication")
        XCTAssertEqual(Array(backend.objects.keys), [earlier], "and the retry's refused image was deleted")
        XCTAssertEqual(backend.count("this: upload"), 2, "nothing was stored a third time")
        shows(backend, 1)
    }

    /// The image the publication displaced could not be deleted. The
    /// publication stands; the deletion stays on record, across a relaunch,
    /// and is made at the next look.
    func testAFailedDeleteOfTheDisplacedImageIsKeptOnRecordAndRetried() async throws {
        let backend = FakeAvatarBackend()
        let url = ledgerFile()
        let ledger = AvatarWorkLedger(userID: uid, fileURL: url)
        guard case .published(let first, _) = await publish(1, backend, ledger) else { return XCTFail() }
        backend.deletesFail = true
        guard case .published(let second, _) = await publish(2, backend, ledger) else { return XCTFail("a failed delete must not fail the publication") }
        XCTAssertEqual(backend.key, second); shows(backend, 2)
        XCTAssertEqual(backend.unreferenced, [first], "the old image is still stored")
        XCTAssertTrue(ledger.owesDeletion(of: first))
        let relaunched = AvatarWorkLedger(userID: uid, fileURL: url)
        XCTAssertTrue(relaunched.owesDeletion(of: first), "the owed deletion survives a relaunch")
        await settleOnAFreshRead(backend, relaunched)
        XCTAssertEqual(backend.unreferenced, [first], "still failing: still owed")
        XCTAssertTrue(relaunched.owesDeletion(of: first))
        backend.deletesFail = false
        await settleOnAFreshRead(backend, relaunched)
        XCTAssertEqual(Array(backend.objects.keys), [second])
        XCTAssertFalse(relaunched.owesDeletion)
        XCTAssertEqual(relaunched.entries.keys.sorted(), [second])
    }

    /// THE APP STOPS BETWEEN THE UPLOAD AND THE REFERENCE WRITE.
    func testAnInterruptedPublicationIsFinishedFromTheRecordAfterARelaunch() async throws {
        // 1. Stopped after the upload, before any write was recorded: no write
        //    was sent, so the image is this device's abandoned upload.
        var backend = FakeAvatarBackend(picture: photo(9))
        var url = ledgerFile()
        var ledger = AvatarWorkLedger(userID: uid, fileURL: url)
        var name = AvatarObjectName.make(userID: uid)
        XCTAssertTrue(ledger.begin(name: name, digest: AvatarWorkLedger.digest(jpeg(1))))
        _ = await backend.upload(jpeg: jpeg(1), key: name)
        // While the publication is still running in this process it is NOT touched.
        await settleOnAFreshRead(backend, ledger)
        XCTAssertNotNil(backend.objects[name], "an upload in progress is never cleaned up from under its own publication")
        var relaunched = AvatarWorkLedger(userID: uid, fileURL: url)          // the app stopped; a new process
        await settleOnAFreshRead(backend, relaunched)
        XCTAssertNil(backend.objects[name], "after a relaunch it is abandoned and removed")
        XCTAssertEqual(backend.key, backend.legacyName); shows(backend, 9)
        XCTAssertTrue(relaunched.entries.isEmpty)

        // 2. Stopped after the write was recorded. Whether it was sent is not
        //    known, so the image is kept...
        backend = FakeAvatarBackend(picture: photo(9)); url = ledgerFile()
        ledger = AvatarWorkLedger(userID: uid, fileURL: url)
        name = AvatarObjectName.make(userID: uid)
        XCTAssertTrue(ledger.begin(name: name, digest: AvatarWorkLedger.digest(jpeg(1))))
        _ = await backend.upload(jpeg: jpeg(1), key: name)
        XCTAssertNotNil(ledger.willWrite(pointingAt: name, displacing: backend.key, expected: backend.version ?? ""))
        relaunched = AvatarWorkLedger(userID: uid, fileURL: url)
        await settleOnAFreshRead(backend, relaunched)
        XCTAssertNotNil(backend.objects[name], "a write that may have been sent: the image is kept")
        XCTAssertTrue(backend.deletions.isEmpty)
        //    ...until the reference is written again by anyone. Here this
        //    device's own next publication: the stranded image can then never
        //    be pointed at, and goes with the photo that was displaced.
        guard case .published(let key, _) = await publish(2, backend, relaunched) else { return XCTFail() }
        XCTAssertEqual(Array(backend.objects.keys), [key]); shows(backend, 2)
        XCTAssertEqual(Set(backend.deletions.map(\.name)), [name, backend.legacyName])
    }

    // MARK: - The record comes first

    /// THE FINAL CORRECTION (2026-11-12). The record of a reference write could
    /// not be written to the file. Before the fix that failure was ignored and
    /// the write was sent anyway, with only the upload on record; after a
    /// restart the clean-up took the image for an upload no write was ever
    /// sent for and deleted it, while the reference request was still on its
    /// way. Now the request is not sent, in this attempt or any retry, and
    /// what the clean-up finds after a restart is the truth.
    func testAReferenceWriteThatCannotBeRecordedIsNeverSentAndNothingPendingIsDeletedAfterARestart() async throws {
        let backend = FakeAvatarBackend(picture: photo(9))                 // the profile shows an older build's photo
        let url = ledgerFile()
        let disk = FlakyDisk()
        let ledger = AvatarWorkLedger(userID: uid, fileURL: url)
        ledger.writer = disk.write
        disk.refuses = FlakyDisk.holdsAReferenceWrite                      // the upload can be recorded; the write cannot
        backend.nextSetKeyIsDelayed = true                                 // were a write sent, it would be left pending

        let outcome = await publish(1, backend, ledger)

        XCTAssertEqual(outcome, .recordFailed)
        XCTAssertEqual(disk.refused, 1, "precondition: the record of the write was refused by the disk")
        XCTAssertEqual(backend.entries(by: "this").filter { $0.contains("setKey") }, [], "NO UNRECORDED REFERENCE REQUEST WAS SENT")
        XCTAssertTrue(backend.nextSetKeyIsDelayed, "(the backend never saw one)")
        let stored = try XCTUnwrap(backend.unreferenced.first, "the image had been stored")
        XCTAssertEqual(ledger.entries[stored]?.writeExpected, nil, "memory holds no write either: it is never ahead of the file")
        XCTAssertNil(ledger.entries[backend.legacyName], "and nothing is on record as displaced")

        // A retry in the same process cannot get past the file.
        let again = await publish(1, backend, ledger)
        XCTAssertEqual(again, .recordFailed)
        XCTAssertEqual(disk.refused, 2)
        XCTAssertEqual(backend.entries(by: "this").filter { $0.contains("setKey") }, [], "the retry sent none either")
        XCTAssertNil(backend.objects[stored], "the first attempt's image, for which no write was sent, was cleared up on the way")
        let second = try XCTUnwrap(backend.unreferenced.first)

        // The app stops. A new process reads the file and clears up.
        let relaunched = AvatarWorkLedger(userID: uid, fileURL: url)
        XCTAssertEqual(relaunched.entries, ledger.entries, "the file holds exactly what the process believed")
        await settleOnAFreshRead(backend, relaunched)
        backend.deliverTheDelayedWrite()                                   // nothing was ever on its way
        XCTAssertEqual(backend.key, backend.legacyName, "the reference is untouched"); shows(backend, 9)
        XCTAssertNotNil(backend.objects[backend.legacyName], "the profile's photo was not deleted")
        XCTAssertEqual(backend.deletions.map(\.name), [stored, second], "only the two images no write was sent for")
        XCTAssertTrue(relaunched.entries.isEmpty)

        // The disk recovers. This time the write IS recorded, sent, and left
        // unanswered: a PENDING publication. Restart, clean up: it is kept.
        let healed = AvatarWorkLedger(userID: uid, fileURL: url)
        backend.nextSetKeyIsDelayed = true
        let pendingOutcome = await publish(1, backend, healed)
        XCTAssertEqual(pendingOutcome, .referenceFailed)
        XCTAssertEqual(backend.count("this: setKey SENT, NO ANSWER"), 1)
        let pending = try XCTUnwrap(backend.unreferenced.first)
        let afterRestart = AvatarWorkLedger(userID: uid, fileURL: url)
        XCTAssertNotNil(afterRestart.entries[pending]?.writeExpected, "the write is in the file")
        await settleOnAFreshRead(backend, afterRestart)
        XCTAssertNotNil(backend.objects[pending], "NO PENDING PUBLICATION IS DELETED")
        XCTAssertEqual(backend.deletions.count, 2, "nothing more was deleted")
        backend.deliverTheDelayedWrite()
        XCTAssertEqual(backend.key, pending); shows(backend, 1)
    }

    /// The same one step earlier: the upload cannot be recorded, so it is not
    /// sent. Nothing reaches the server but the read.
    func testAnUploadThatCannotBeRecordedIsNotSent() async throws {
        let backend = FakeAvatarBackend(picture: photo(9))
        let disk = FlakyDisk()
        let ledger = AvatarWorkLedger(userID: uid, fileURL: ledgerFile())
        ledger.writer = disk.write
        disk.refuses = { _ in true }
        for _ in 0..<2 {
            let outcome = await publish(1, backend, ledger)
            XCTAssertEqual(outcome, .recordFailed)
        }
        XCTAssertEqual(backend.log, ["this: probe", "this: probe"], "no upload, no write, no delete")
        XCTAssertTrue(ledger.entries.isEmpty, "and memory holds nothing the file does not")
        XCTAssertFalse(ledger.begin(name: AvatarObjectName.make(userID: uid), digest: "x"))
        XCTAssertNil(ledger.willWrite(pointingAt: nil, displacing: backend.legacyName, expected: backend.version ?? ""))
        disk.refuses = { _ in false }
        guard case .published(let key, _) = await publish(1, backend, ledger) else { return XCTFail() }
        XCTAssertEqual(Array(backend.objects.keys), [key]); shows(backend, 1)
    }

    /// A record that EXISTS AND CANNOT BE READ is not an empty record. Nothing
    /// is recorded (so nothing is sent) and nothing is deleted until it can be
    /// read, and it is not written over: the pending publication it holds is
    /// still there afterwards.
    func testARecordThatCannotBeReadStopsEverythingAndIsNotWrittenOver() async throws {
        let backend = FakeAvatarBackend(picture: photo(9))
        let url = ledgerFile()
        let first = AvatarWorkLedger(userID: uid, fileURL: url)
        backend.nextSetKeyIsDelayed = true
        let unanswered = await publish(1, backend, first)
        XCTAssertEqual(unanswered, .referenceFailed)
        let pending = try XCTUnwrap(backend.unreferenced.first)
        // The file is there and unreadable (here: something that is not a file).
        let aside = url.appendingPathExtension("aside"); files.append(aside)
        try FileManager.default.moveItem(at: url, to: aside)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let blocked = AvatarWorkLedger(userID: uid, fileURL: url)
        XCTAssertTrue(blocked.entries.isEmpty, "precondition: it could not be read")
        let outcome = await publish(2, backend, blocked)
        XCTAssertEqual(outcome, .recordFailed)
        await settleOnAFreshRead(backend, blocked)
        XCTAssertEqual(backend.entries(by: "this").filter { !$0.hasSuffix("probe") }, ["this: upload", "this: setKey SENT, NO ANSWER"],
                       "nothing was sent while the record could not be read")
        XCTAssertNotNil(backend.objects[pending])
        // It becomes readable again: the same object picks the record up, whole.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: aside, to: url)
        await settleOnAFreshRead(backend, blocked)
        XCTAssertNotNil(blocked.entries[pending]?.writeExpected, "the pending publication is still on record")
        XCTAssertNotNil(backend.objects[pending], "and still stored"); XCTAssertTrue(backend.deletions.isEmpty)
        backend.deliverTheDelayedWrite()
        XCTAssertEqual(backend.key, pending); shows(backend, 1)
    }

    // MARK: - Whose image it is

    /// This device deletes the exact image its own accepted write displaced,
    /// whoever stored it, and its own abandoned uploads. It never sweeps: an
    /// image another device has stored and not yet published is not touched.
    func testAnotherDevicesUnfinishedUploadIsNeverThisDevicesToDelete() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        guard case .published = await backend.otherDevicePublishes(photo(1)) else { return XCTFail() }
        let theirs = try XCTUnwrap(backend.key)
        // The other device is half way through publishing photo 3.
        let otherHeld = AvatarTestGate()
        backend.gates["other.setKey"] = otherHeld
        let other = Task { @MainActor in await backend.otherDevicePublishes(self.photo(3)) }
        await otherHeld.waitUntilArrived()
        let unfinished = try XCTUnwrap(backend.unreferenced.first)
        // This device publishes photo 2, and looks again afterwards.
        guard case .published(let mine, _) = await publish(2, backend, ledger) else { return XCTFail() }
        await settleOnAFreshRead(backend, ledger)
        XCTAssertEqual(backend.deletions.filter { $0.device == "this" }.map(\.name), [theirs],
                       "it deleted the image it displaced (stored by the other device), by name")
        XCTAssertNotNil(backend.objects[unfinished], "and not the other device's unfinished upload")
        otherHeld.open()
        guard case .published(let third, _) = await other.value else { return XCTFail() }
        XCTAssertEqual(Array(backend.objects.keys), [third], "each device cleared up after itself: one image, the one referenced")
        // (It also sent a delete for its own first image, which this device had
        // already removed when it displaced it: a delete of a name that is gone
        // is harmless, and neither device has to trust the other to clear up.)
        XCTAssertEqual(Set(backend.deletions.filter { $0.device == "other" }.map(\.name)), [unfinished, mine, theirs])
        XCTAssertFalse(backend.deletions.contains { $0.name == third }, "nobody deleted the photo that stands")
        shows(backend, 3)
    }

    /// B-48 seen from the device: a reference that names anything outside the
    /// member's own folder (possible only in a row written before the server
    /// check) is replaced, and NEVER followed with a delete.
    func testAReferenceOutsideTheMembersFolderIsNeverDeleted() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        backend.setReferenceForTesting("users/someone-else/avatar.jpg")
        guard case .published(let key, _) = await publish(1, backend, ledger) else { return XCTFail() }
        XCTAssertEqual(backend.key, key)
        XCTAssertTrue(backend.deletions.isEmpty, "no delete was sent for another member's image")
        XCTAssertEqual(backend.count("this: deleteObject REFUSED NAME"), 0)
        XCTAssertEqual(ledger.entries.keys.sorted(), [key])
    }

    /// An OUTDATED read of the row (an older version than the one a write was
    /// conditional on) decides nothing: it cannot make anything deletable.
    func testAnOutdatedReadOfTheRowDeletesNothing() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        guard case .published(let first, let v1) = await publish(1, backend, ledger) else { return XCTFail() }
        backend.deletesFail = true
        guard case .published(let second, _) = await publish(2, backend, ledger) else { return XCTFail() }
        backend.deletesFail = false
        let fresh = AvatarWorkLedger(userID: uid, fileURL: nil)
        // A device that only knows: "my image `second` has a write conditional on v1".
        XCTAssertTrue(fresh.begin(name: second, digest: "x"))
        XCTAssertNotNil(fresh.willWrite(pointingAt: second, displacing: first, expected: v1 ?? "")); fresh.end(name: second)
        // A stale read: the row as it was BEFORE that write (photo 1, version v1).
        await fresh.settle(rowExists: true, key: first, version: v1, backend: backend)
        XCTAssertNotNil(backend.objects[second], "the stale read does not condemn the published image")
        XCTAssertNotNil(backend.objects[first]); XCTAssertTrue(backend.deletions.isEmpty)
        // The true read: only the displaced image goes.
        await fresh.settle(rowExists: true, key: backend.key, version: backend.version, backend: backend)
        XCTAssertEqual(Array(backend.objects.keys), [second])
    }

    /// The last guard, whatever the record believes: an image the row names is
    /// not deleted. (Here the record was told the write was refused; the row
    /// says it was made. The row is right.)
    func testAnImageTheRowNamesIsNeverDeletedWhateverTheRecordSays() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        guard case .published(let key, _) = await publish(1, backend, ledger) else { return XCTFail() }
        ledger.writeWasRefused(pointingAt: key, recorded: nil)
        XCTAssertTrue(ledger.owesDeletion(of: key), "precondition: the record thinks it is to be deleted")
        await settleOnAFreshRead(backend, ledger)
        XCTAssertNotNil(backend.objects[key]); XCTAssertTrue(backend.deletions.isEmpty)
        XCTAssertFalse(ledger.owesDeletion, "and the record is corrected by the read")
        shows(backend, 1)
    }

    // MARK: - Older builds

    /// A photo an older build published under the fixed name is replaced by
    /// this build: the reference moves to a per-upload name and exactly the
    /// old name is deleted.
    func testAnOldBuildsPhotoIsReplacedAndItsFixedNameDeleted() async throws {
        let backend = FakeAvatarBackend(picture: photo(1))
        let ledger = memoryLedger()
        guard case .published(let key, _) = await publish(2, backend, ledger) else { return XCTFail() }
        XCTAssertTrue(AvatarObjectName.isPerUpload(key, userID: uid))
        XCTAssertEqual(backend.deletions.map(\.name), [backend.legacyName])
        XCTAssertEqual(Array(backend.objects.keys), [key]); shows(backend, 2)
    }

    /// An older build publishes (or removes) over this build's photo. It
    /// writes only the fixed name and deletes nothing else, so this build's
    /// image is left behind; the device that stored it removes it at its next
    /// look, and never touches the old build's photo.
    func testAnImageLeftBehindByAnOlderBuildIsRemovedByTheDeviceThatStoredIt() async throws {
        let backend = FakeAvatarBackend()
        let ledger = memoryLedger()
        guard case .published(let mine, _) = await publish(1, backend, ledger) else { return XCTFail() }
        backend.anOldBuildPublishes(photo(2))
        XCTAssertEqual(backend.unreferenced, [mine])
        await settleOnAFreshRead(backend, ledger)
        XCTAssertEqual(Array(backend.objects.keys), [backend.legacyName]); shows(backend, 2)
        XCTAssertEqual(backend.deletions.map(\.name), [mine])
        // The same when the older build removes the photo.
        guard case .published(let again, _) = await publish(3, backend, ledger) else { return XCTFail() }
        XCTAssertEqual(Array(backend.objects.keys), [again])
        backend.anOldBuildRemoves()
        XCTAssertNil(backend.key); XCTAssertEqual(backend.unreferenced, [again])
        await settleOnAFreshRead(backend, ledger)
        XCTAssertTrue(backend.objects.isEmpty)
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    /// The one name that CAN be pointed at again is the old fixed one, by an
    /// older build. A deletion of it that this device still owes is dropped
    /// the moment a read shows the reference naming it.
    func testAnOwedDeleteOfTheFixedNameIsDroppedWhenAnOlderBuildPublishesThereAgain() async throws {
        let backend = FakeAvatarBackend(picture: photo(1))
        let ledger = memoryLedger()
        backend.deletesFail = true
        guard case .published(let mine, _) = await publish(2, backend, ledger) else { return XCTFail() }
        XCTAssertTrue(ledger.owesDeletion(of: backend.legacyName))
        backend.deletesFail = false
        backend.anOldBuildPublishes(photo(3))                       // the fixed name holds a NEW photo, and the reference names it
        await settleOnAFreshRead(backend, ledger)
        XCTAssertNotNil(backend.objects[backend.legacyName], "the old build's new photo is not deleted")
        shows(backend, 3)
        XCTAssertFalse(ledger.owesDeletion(of: backend.legacyName), "the owed deletion is dropped, not kept for later")
        XCTAssertEqual(backend.deletions.map(\.name), [mine], "only this device's own displaced image went")
    }
}
