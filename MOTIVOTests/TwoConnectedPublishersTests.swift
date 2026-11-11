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
//  function (`OwnAvatarSync.decide`, `.settle`, `JournalProfileMerge
//  .decideAvatar`), wired in the order `AuthManager` and the sync engine wire
//  them: import → mark → publish → record the version; hydrate → echo, wait
//  or apply. A FILE is a picture plus an encoding: an import copies the file
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

    override func setUp() {
        super.setUp()
        journal = Journal(picture: 1, stamp: Date(timeIntervalSince1970: 1_000))
        backend = Backend(picture: 1); backend.count = 1
        devices = ["D1", "D2"].map {
            Device(name: $0, file: journal.file, stamp: journal.stamp, knownJournalStamp: journal.stamp, applied: backend.version)
        }
        now = Date(timeIntervalSince1970: 10_000); encodings = 0
        echoRule = true; settleRule = true
    }

    // MARK: The three steps a device takes, in the app's order

    /// The sync engine: fetch the avatar record, or send this device's.
    private func exchange(_ i: Int) {
        var d = devices[i]
        defer { devices[i] = d }
        guard d.knownJournalStamp != journal.stamp || d.stamp != journal.stamp || d.file != journal.file else { return }
        switch JournalProfileMerge.decideAvatar(localHash: d.file.hash, localStamp: d.stamp, localPending: false,
                                                serverHash: journal.file.hash, serverStamp: journal.stamp) {
        case .nothing: break
        case .takeServer:                       // an import: written byte for byte, and MARKED for the Connected profile
            d.file = journal.file; d.stamp = journal.stamp; d.marker = true
        case .keepLocalAndSend:                 // this device's is newer: it goes up
            journal = Journal(file: d.file, stamp: d.stamp)
        }
        d.knownJournalStamp = journal.stamp
    }

    /// The promotion: publish what is marked, and record the version it produced.
    private func publish(_ i: Int) {
        guard devices[i].marker else { return }
        devices[i].applied = backend.write(devices[i].picture)
        devices[i].marker = false
        devices[i].publications += 1
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
            d.file = File(picture: nil); d.stamp = now; d.removalsApplied += 1      // a local removal: the sync sends it
            record()
        case .refresh:
            if echoRule, d.picture == backend.picture { record(); return }
            if d.picture != nil { guard settled() else { return } }
            d.file = newEncoding(of: backend.picture); d.stamp = now; d.readBacksApplied += 1   // a re-encoded copy: a new edit to the sync
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

    /// C-194: a photo change that reaches the other device as a REMOVAL and
    /// then the image. The other device publishes the removal first. The device
    /// that holds the photo looks at the backend in that window (a relaunch).
    func testASiblingsMomentaryRemovalNeverRemovesThePhoto() {
        devices[0].file = newEncoding(of: 4); devices[0].stamp = now; devices[0].marker = true   // D1 chooses photo 4
        publish(0)                                                                    // and publishes it
        let chosen = devices[0].file
        journal = Journal(picture: nil, stamp: now.addingTimeInterval(-1))            // the removal reaches the journal first
        exchange(1); publish(1)                                                       // D2 imports it and publishes the removal
        XCTAssertNil(backend.picture, "the Connected profile shows no photo for a moment")
        hydrate(0)                                                                    // D1 relaunches right now
        XCTAssertEqual(devices[0].picture, 4, "seen, waited on, not applied")
        XCTAssertNotNil(devices[0].seen)
        journal = Journal(file: chosen, stamp: now)                                   // then the image
        XCTAssertTrue(run())
        assertSettled(on: 4)
        XCTAssertEqual(devices.map(\.removalsApplied), [0, 0], "no unintended removal")
        XCTAssertEqual(devices[0].readBacksApplied, 0)
    }

    /// The same sequence WITHOUT the wait: the photo is removed everywhere.
    /// This is what the settle rule is for, and that this test would catch its loss.
    func testWithoutTheWaitThatRemovalWouldSpreadToEveryDevice() {
        settleRule = false
        devices[0].file = newEncoding(of: 4); devices[0].stamp = now; devices[0].marker = true
        publish(0)
        journal = Journal(picture: nil, stamp: now.addingTimeInterval(-1))
        exchange(1); publish(1)
        now.addTimeInterval(5)
        hydrate(0)
        XCTAssertNil(devices[0].picture, "applied at once")
        XCTAssertEqual(devices[0].removalsApplied, 1)
        exchange(0)
        XCTAssertNil(journal.picture, "and sent to the journal with a newer clock than the photo")
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
