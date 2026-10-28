//
//  SyncTestTransferGateTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage J: media over mobile data. The hold rule (option covers mobile data
//  and hotspots; Low Data Mode always pauses), the per-device option, the
//  held-media bookkeeping and the status text.
//

#if SYNCTEST
import XCTest
@testable import Etudes

final class SyncTestTransferGateTests: XCTestCase {

    func testTheOptionCoversMobileDataAndHotspotsButNeverLowDataMode() {
        typealias L = JournalMediaGate.Link
        // Ordinary Wi-Fi (or wired): media moves whatever the option says.
        XCTAssertEqual(JournalMediaGate.hold(link: L(), allowMobileData: false), .none)
        XCTAssertEqual(JournalMediaGate.hold(link: L(), allowMobileData: true), .none)
        // Mobile data: waits for Wi-Fi with the option off, moves with it on.
        XCTAssertEqual(JournalMediaGate.hold(link: L(cellularOnly: true), allowMobileData: false), .mobileData)
        XCTAssertEqual(JournalMediaGate.hold(link: L(cellularOnly: true), allowMobileData: true), .none)
        // A personal hotspot (Wi-Fi that iOS reports as expensive) is mobile data.
        XCTAssertEqual(JournalMediaGate.hold(link: L(expensive: true), allowMobileData: false), .mobileData)
        XCTAssertEqual(JournalMediaGate.hold(link: L(expensive: true), allowMobileData: true), .none)
        // Low Data Mode pauses media on any link, and the option never overrides it.
        XCTAssertEqual(JournalMediaGate.hold(link: L(constrained: true), allowMobileData: false), .lowDataMode)
        XCTAssertEqual(JournalMediaGate.hold(link: L(constrained: true), allowMobileData: true), .lowDataMode)
        XCTAssertEqual(JournalMediaGate.hold(link: L(cellularOnly: true, constrained: true), allowMobileData: true), .lowDataMode)
    }

    func testOnlyAChangeBetweenHeldAndAllowedRebuildsTheEngine() {
        XCTAssertTrue(JournalMediaGate.rebuildNeeded(from: .none, to: .mobileData))
        XCTAssertTrue(JournalMediaGate.rebuildNeeded(from: .lowDataMode, to: .none))
        XCTAssertFalse(JournalMediaGate.rebuildNeeded(from: .mobileData, to: .lowDataMode), "a change of reason is a status change only")
        XCTAssertFalse(JournalMediaGate.rebuildNeeded(from: .none, to: .none))
    }

    func testTheOptionIsPerDeviceAndOffByDefault() {
        let defaults = UserDefaults(suiteName: "synctest-gate-\(UUID().uuidString)")!
        XCTAssertFalse(JournalMediaPreference.allowsMobileData(defaults: defaults))
        let posted = expectation(forNotification: JournalMediaPreference.changedNotification, object: nil)
        JournalMediaPreference.setAllowsMobileData(true, defaults: defaults)
        wait(for: [posted], timeout: 1)
        XCTAssertTrue(JournalMediaPreference.allowsMobileData(defaults: defaults))
        XCTAssertFalse(JournalSettingKey.all.contains(JournalMediaPreference.defaultsKey), "never synced")
    }

    func testHeldNamesAreUniqueAndTheStatusTextSaysWhatWaits() {
        let held = JournalMediaHold.adding(["a", "b", "a"], to: ["b"])
        XCTAssertEqual(held, ["b", "a"])
        XCTAssertNil(JournalMediaHold.summary(uploads: [:], downloads: []))
        XCTAssertEqual(JournalMediaHold.summary(uploads: ["x": 1_000_000], downloads: ["y", "z"], hold: .mobileData),
                       "Media waiting for Wi-Fi: 1 to send (1 MB), 2 to receive")
        XCTAssertEqual(JournalMediaHold.summary(uploads: [:], downloads: ["y"], hold: .lowDataMode),
                       "Media paused by Low Data Mode: 1 to receive")
        XCTAssertEqual(JournalMediaHold.summary(uploads: ["x": 10], downloads: [], hold: .none),
                       "Media still to transfer: 1 to send (10 bytes)")
    }

    func testStateFileKeepsWhatWaitsAcrossARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let store = JournalSyncStateStore(fileURL: url)
        store.update { $0.mediaWaitingUpload["att"] = 42; $0.awaitingMedia = ["score-1"]; $0.appSubscriptionSaved = true }
        let reloaded = JournalSyncStateStore(fileURL: url)
        XCTAssertEqual(reloaded.state.mediaWaitingUpload, ["att": 42])
        XCTAssertEqual(reloaded.state.awaitingMedia, ["score-1"])
        XCTAssertTrue(reloaded.state.appSubscriptionSaved)
    }
}
#endif
