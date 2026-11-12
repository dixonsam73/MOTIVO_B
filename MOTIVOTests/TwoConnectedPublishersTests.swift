//
//  TwoConnectedPublishersTests.swift
//  MOTIVOTests
//
//  C-192 — TWO CONNECTED DEVICES OF ONE OWNER, BOTH WITH THE PRIVATE SYNC ON,
//  SETTLE: no repeated publication, no unintended removal.
//
//  **Two physical Connected devices were NOT tested** (2026-11-11): the
//  simulator cannot pass Apple's age check, so it cannot be Connected, and no
//  second device on the disposable Apple Account was set up. This is the cover
//  there is for the pair.
//
//  WHAT THIS IS: a model. Two devices, one iCloud journal record and one
//  backend avatar are plain values; every DECISION is the app's own pure
//  function (`OwnAvatarSync.decide`, `.settle`, `AvatarRemovalGuard.decide`,
//  `JournalProfileMerge.decideAvatar`), wired in the order `AuthManager` and
//  the sync engine wire them: import → mark → publish (a removal only past
//  the guard) → record the version; hydrate → echo, wait or apply, clocked
//  just after the state displaced. A FILE is a picture plus an encoding: an import copies the file
//  byte for byte, a read-back from the backend is a NEW encoding of the same
//  picture (that is what makes a read-back a new edit to the sync, and the
//  loop possible). "The same picture" is the picture number; the picture
//  measure itself is tested in `AvatarFreshnessTests`, and one device's real
//  wiring in `SyncTestConnectedIsolationTests`.
//
//  WHAT IT DOES NOT SHOW: the real wiring on two devices, CloudKit, the
//  network, or timing finer than the model's one-minute rounds.
//

import XCTest
@testable import Etudes

final class TwoConnectedPublishersTests: XCTestCase {

    /// What the journal and a device hold: the picture and which encoding of it.
    private struct File: Equatable {
        var picture: Int?
        var encoding = 0
        var hash: String { picture.map { "\($0).\(encoding)" } ?? "" }
    }
    private struct Journal {
        var file: File; var stamp: Date
        var picture: Int? { file.picture }
        init(picture: Int?, stamp: Date) { file = File(picture: picture); self.stamp = stamp }
        init(file: File, stamp: Date) { self.file = file; self.stamp = stamp }
    }
    private struct Backend {
        var picture: Int?
        var count = 0
        /// The server's `now()`: strictly increasing, in the format PostgREST prints.
        var version: String { count == 0 ? "" : String(format: "2026-11-11T19:%02d:%02d+00:00", count / 60, count % 60) }
        mutating func write(_ picture: Int?) -> String { self.picture = picture; count += 1; return version }
    }
    private struct Device {
        var name: String
        var file: File
        var picture: Int? { file.picture }
        var stamp: Date                 // the journal clock of what it holds
        var knownJournalStamp: Date     // what it last exchanged with the journal
        var applied: String?
        var marker = false
        var seen: OwnAvatarSync.Seen?
        var publications = 0
        var removalsApplied = 0
        var readBacksApplied = 0
        /// The picture this device last removed (`ProfileStore.removedAvatarThumbnail`).
        var removedPicture: Int?
        /// A device whose iCloud is behind: it reaches the backend, not the journal.
        var journalPaused = false
    }

    private var journal = Journal(picture: 1, stamp: Date(timeIntervalSince1970: 1_000))
    private var backend = Backend(picture: 1)
    private var devices: [Device] = []
    private var now = Date(timeIntervalSince1970: 10_000)
    private var encodings = 0
    private func newEncoding(of picture: Int?) -> File { encodings += 1; return File(picture: picture, encoding: encodings) }
    /// Off = the first pass's danger: every newer version is applied as a change.
    private var echoRule = true
    private var settleRule = true
    /// Off = a change read back is clocked "now" (before the third pass).
    private var displacedClockRule = true
    /// Off = a waiting removal is published whatever the profile shows (before the third pass).
    private var removalGuardRule = true
    private var photoEverMissingFromBackend = false

    override func setUp() {
        super.setUp()
        journal = Journal(picture: 1, stamp: Date(timeIntervalSince1970: 1_000))
        backend = Backend(picture: 1); backend.count = 1
        devices = ["D1", "D2"].map {
            Device(name: $0, file: journal.file, stamp: journal.stamp, knownJournalStamp: journal.stamp, applied: backend.version)
        }
        now = Date(timeIntervalSince1970: 10_000); encodings = 0
        echoRule = true; settleRule = true; displacedClockRule = true; removalGuardRule = true
        photoEverMissingFromBackend = false
    }

    // MARK: The three steps a device takes, in the app's order

    /// The sync engine: fetch the avatar record, or send this device's.
    private func exchange(_ i: Int) {
        var d = devices[i]
        defer { devices[i] = d }
        guard !d.journalPaused else { return }
        guard d.knownJournalStamp != journal.stamp || d.stamp != journal.stamp || d.file != journal.file else { return }
        switch JournalProfileMerge.decideAvatar(localHash: d.file.hash, localStamp: d.stamp, localPending: false,
                                                serverHash: journal.file.hash, serverStamp: journal.stamp) {
        case .nothing: break
        case .takeServer:                       // an import: written byte for byte, and MARKED for the Connected profile
            if journal.file.picture == nil { d.removedPicture = d.picture }
            d.file = journal.file; d.stamp = journal.stamp; d.marker = true
        case .keepLocalAndSend:                 // this device's is newer: it goes up
            journal = Journal(file: d.file, stamp: d.stamp)
        }
        d.knownJournalStamp = journal.stamp
    }

    /// The promotion: publish what is marked, and record the version it produced.
    /// A removal goes through `AvatarRemovalGuard` first.
    private func publish(_ i: Int) {
        guard devices[i].marker else { return }
        if devices[i].picture == nil, removalGuardRule {
            let shows: Bool? = devices[i].removedPicture.map { $0 == backend.picture }
            switch AvatarRemovalGuard.decide(backendHasAvatar: backend.picture != nil, backendShowsTheRemovedPicture: shows) {
            case .publish: break
            case .alreadyRemoved:
                devices[i].applied = backend.version; devices[i].marker = false
                return
            case .yieldToBackend:
                devices[i].marker = false
                hydrate(i)                      // the profile's photo comes here instead
                return
            }
        }
        devices[i].applied = backend.write(devices[i].picture)
        if backend.picture == nil { photoEverMissingFromBackend = true }
        devices[i].marker = false
        devices[i].publications += 1
    }

    /// The journal clock a change read back from the backend gets.
    private func clockForAReadBack(displacing stamp: Date) -> Date {
        displacedClockRule ? stamp.addingTimeInterval(0.001) : now
    }

    /// The hydration read-back, as `AuthManager.syncOwnAvatarFromBackend` orders it.
    private func hydrate(_ i: Int) {
        var d = devices[i]
        defer { devices[i] = d }
        let incoming = backend.version
        func settled() -> Bool {
            guard settleRule else { return true }
            let result = OwnAvatarSync.settle(seen: d.seen, version: incoming, now: now)
            d.seen = result.seen
            return result.settled
        }
        func record() { d.applied = incoming; d.seen = nil }
        switch OwnAvatarSync.decide(lastApplied: d.applied, backendVersion: incoming,
                                    backendHasAvatar: backend.picture != nil, hasPendingLocalChange: d.marker) {
        case .none: return
        case .recordOnly: record()
        case .remove:
            guard d.picture != nil else { record(); return }
            guard settled() else { return }
            d.removedPicture = d.picture
            d.file = File(picture: nil); d.stamp = clockForAReadBack(displacing: d.stamp); d.removalsApplied += 1
            record()
        case .refresh:
            if echoRule, d.picture == backend.picture { record(); return }
            if d.picture != nil { guard settled() else { return } }
            d.file = newEncoding(of: backend.picture); d.stamp = clockForAReadBack(displacing: d.stamp); d.readBacksApplied += 1   // a re-encoded copy
            record()
        }
    }

    private var fingerprint: String {
        "\(journal.file.hash)@\(journal.stamp.timeIntervalSince1970)|\(backend.picture ?? -1)#\(backend.count)|"
            + devices.map { "\($0.file.hash)/\($0.applied ?? "nil")/\($0.marker)/\($0.seen?.version ?? "-")" }.joined(separator: ",")
    }

    /// One-minute rounds until five in a row change nothing. Returns false if it never rests.
    @discardableResult
    private func run(maxRounds: Int = 60, order: [Int] = [0, 1]) -> Bool {
        var quiet = 0
        for _ in 0..<maxRounds {
            let before = fingerprint
            for i in order { exchange(i); publish(i); hydrate(i) }
            now.addTimeInterval(60)
            quiet = fingerprint == before ? quiet + 1 : 0
            if quiet >= 5 { return true }
        }
        return false
    }

    private func assertSettled(on picture: Int?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(devices.map(\.picture), [picture, picture], "both devices hold it", file: file, line: line)
        XCTAssertEqual(devices.map(\.file), [journal.file, journal.file], "the same file, byte for byte", file: file, line: line)
        XCTAssertEqual(journal.picture, picture, "the journal holds it", file: file, line: line)
        XCTAssertEqual(backend.picture, picture, "the Connected profile shows it", file: file, line: line)
        XCTAssertEqual(devices.map(\.marker), [false, false], file: file, line: line)
        XCTAssertEqual(devices.map(\.applied), [backend.version, backend.version], "both know the standing version", file: file, line: line)
    }

    // MARK: The cases

    /// A photo chosen on a Solo device reaches both through iCloud.
    func testAnImportedPhotoIsPublishedOnceByEachDeviceAndThenNothingMoves() {
        journal = Journal(picture: 2, stamp: now)
        XCTAssertTrue(run(), "the pair comes to rest")
        assertSettled(on: 2)
        XCTAssertEqual(devices.map(\.publications), [1, 1], "once each: the second is the same picture again, not a loop")
        XCTAssertEqual(devices.map(\.readBacksApplied), [0, 0], "each read the other's publication back as an echo")
        XCTAssertEqual(devices.map(\.removalsApplied), [0, 0])
        let publicationsAtRest = backend.count
        XCTAssertTrue(run()); XCTAssertEqual(backend.count, publicationsAtRest, "and it stays at rest")
    }

    /// A photo chosen on one of the two.
    func testAPhotoChosenOnOneDeviceSettlesWithOnePublicationEach() {
        devices[0].file = newEncoding(of: 3); devices[0].stamp = now; devices[0].marker = true   // the editor's writes
        XCTAssertTrue(run())
        assertSettled(on: 3)
        XCTAssertEqual(devices.map(\.publications), [1, 1])
        XCTAssertEqual(devices.map(\.readBacksApplied), [0, 0])
    }

    /// C-194 with the holder Connected. D1 chooses photo 4 and publishes it. The
    /// journal carries a REMOVAL first and the image later; D2 imports the
    /// removal and has it waiting. The profile shows photo 4, which that
    /// removal is not about, so D2 does not publish it.
    func testARemovalThatIsNotAboutTheProfilesPhotoIsNeverPublished() {
        devices[0].file = newEncoding(of: 4); devices[0].stamp = now; devices[0].marker = true   // D1 chooses photo 4
        publish(0)                                                                    // and publishes it
        let chosen = devices[0].file
        journal = Journal(picture: nil, stamp: now.addingTimeInterval(-1))            // the removal reaches the journal first
        devices[0].journalPaused = true                                               // (D1's image is still to be sent)
        exchange(1); publish(1)                                                       // D2 imports the removal; the guard looks
        XCTAssertEqual(backend.picture, 4, "the removal of photo 1 is not published over photo 4")
        XCTAssertEqual(devices[1].picture, 4, "D2 takes the profile's photo instead")
        // Hours later, far beyond any wait, D1's image reaches the journal.
        now.addTimeInterval(4 * 3_600)
        devices[0].journalPaused = false
        journal = Journal(file: chosen, stamp: devices[0].stamp)
        XCTAssertTrue(run())
        assertSettled(on: 4)
        XCTAssertFalse(photoEverMissingFromBackend, "the Connected profile never lost the photo")
        XCTAssertEqual(devices.map(\.removalsApplied), [0, 0], "no unintended removal")
    }

    /// The same sequence WITHOUT the guard and with a read-back clocked "now":
    /// the photo is removed everywhere, for good. What the third pass is for.
    func testWithoutTheGuardAndTheClockThatSequenceIsALastingDeletion() {
        removalGuardRule = false; displacedClockRule = false
        devices[0].file = newEncoding(of: 4); devices[0].stamp = now; devices[0].marker = true
        publish(0)
        let chosen = devices[0].file
        journal = Journal(picture: nil, stamp: now.addingTimeInterval(-1))
        devices[0].journalPaused = true
        exchange(1); publish(1)                                                       // D2 publishes the stale removal
        XCTAssertNil(backend.picture)
        for _ in 0..<4 { hydrate(0); now.addTimeInterval(60) }                        // D1 sees it stand past the wait
        XCTAssertNil(devices[0].picture, "D1 has applied the removal to the photo it chose")
        devices[0].journalPaused = false
        journal = Journal(file: chosen, stamp: Date(timeIntervalSince1970: 10_000))   // the image, with its own (older) clock
        XCTAssertTrue(run())
        XCTAssertEqual(devices.map(\.picture), [nil, nil], "gone from both devices")
        XCTAssertNil(journal.picture, "gone from the journal")
        XCTAssertNil(backend.picture, "and gone from the profile")
    }

    /// CODEX'S CASE. A removal the journal really carried is published by D2.
    /// D1's iCloud is behind, so it still holds the old photo and only sees the
    /// backend. The replacement was chosen meanwhile but reaches the journal
    /// LATE, after D1's two-minute wait has run out and D1 has applied the
    /// removal. It must still win everywhere.
    func testAReplacementDelayedBeyondTheWaitIsNotALastingDeletion() {
        devices[0].journalPaused = true
        journal = Journal(picture: nil, stamp: now)                                   // the removal, in the journal
        exchange(1); publish(1)                                                       // D2 imports and publishes it
        XCTAssertNil(backend.picture)
        let replacement = Journal(file: newEncoding(of: 5), stamp: now.addingTimeInterval(30))   // chosen half a minute later...
        for _ in 0..<4 { hydrate(0); now.addTimeInterval(60) }                        // ...but D1 only sees the backend, for four minutes
        XCTAssertNil(devices[0].picture, "D1 has applied the removal once it had stood")
        XCTAssertEqual(devices[0].removalsApplied, 1)
        journal = replacement                                                         // the replacement finally arrives
        devices[0].journalPaused = false
        XCTAssertTrue(run())
        assertSettled(on: 5)
    }

    /// The same case with the read-back clocked "now": D1's removal outranks the
    /// replacement, and the photo is gone from every device.
    func testWithAReadBackClockedNowThatDelayIsALastingDeletion() {
        displacedClockRule = false
        devices[0].journalPaused = true
        journal = Journal(picture: nil, stamp: now)
        exchange(1); publish(1)
        let replacement = Journal(file: newEncoding(of: 5), stamp: now.addingTimeInterval(30))
        for _ in 0..<4 { hydrate(0); now.addTimeInterval(60) }
        XCTAssertNil(devices[0].picture)
        journal = replacement
        devices[0].journalPaused = false
        XCTAssertTrue(run())
        XCTAssertEqual(devices.map(\.picture), [nil, nil], "the replacement lost to a removal applied four minutes after it was chosen")
        XCTAssertNil(journal.picture); XCTAssertNil(backend.picture)
    }

    /// A real replacement, and a real removal, made on a Connected device whose
    /// sync is OFF (so the backend changes and the journal does not).
    func testARealChangeFromASyncOffDeviceReachesBothAndSettles() {
        _ = backend.write(5)                                                          // the sync-off device's upload and key patch
        XCTAssertTrue(run())
        assertSettled(on: 5)
        // Both waits end together here, so both apply it; one copy wins in the
        // journal and the other device imports that and publishes it once.
        XCTAssertTrue((1...2).contains(devices.map(\.readBacksApplied).reduce(0, +)))
        XCTAssertLessThanOrEqual(devices.map(\.publications).reduce(0, +), 1, "at most the importer publishes it once more")
        let before = devices.map(\.publications)
        _ = backend.write(nil)                                                        // then that device removes the photo
        XCTAssertTrue(run())
        assertSettled(on: nil)
        XCTAssertTrue((1...2).contains(devices.map(\.removalsApplied).reduce(0, +)))
        XCTAssertLessThanOrEqual(zip(devices.map(\.publications), before).map { $0 - $1 }.reduce(0, +), 1)
        let atRest = backend.count
        XCTAssertTrue(run()); XCTAssertEqual(backend.count, atRest, "and nothing moves afterwards")
    }

    /// The loop the echo rule exists to stop: without it the pair never rests.
    func testWithoutTheEchoRuleThePairPublishesWithoutEnd() {
        echoRule = false; settleRule = false
        journal = Journal(picture: 2, stamp: now)
        XCTAssertFalse(run(), "each read-back is a new edit, which the other device publishes again")
        XCTAssertGreaterThan(backend.count, 20)
    }

    /// Either device going first gives the same rest state.
    func testTheOrderOfTheTwoDevicesDoesNotMatter() {
        journal = Journal(picture: 2, stamp: now)
        XCTAssertTrue(run(order: [1, 0]))
        assertSettled(on: 2)
        XCTAssertEqual(devices.map(\.publications), [1, 1])
    }
}
