//
//  SyncTestTransferGateTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage J: media over mobile data. The gate rule, the per-device option, the
//  held-media bookkeeping and the status text.
//

#if SYNCTEST
import XCTest
@testable import Etudes

final class SyncTestTransferGateTests: XCTestCase {

    func testOnlyAMeteredLinkWithoutTheOptionWaits() {
        XCTAssertFalse(JournalMediaGate.isMetered(cellular: false, expensive: false, constrained: false))
        XCTAssertTrue(JournalMediaGate.isMetered(cellular: true, expensive: false, constrained: false))
        XCTAssertTrue(JournalMediaGate.isMetered(cellular: false, expensive: true, constrained: false), "a hotspot counts as mobile data")
        XCTAssertTrue(JournalMediaGate.isMetered(cellular: false, expensive: false, constrained: true), "Low Data Mode counts as mobile data")
        XCTAssertTrue(JournalMediaGate.waitsForWiFi(metered: true, allowCellular: false))
        XCTAssertFalse(JournalMediaGate.waitsForWiFi(metered: true, allowCellular: true))
        XCTAssertFalse(JournalMediaGate.waitsForWiFi(metered: false, allowCellular: false))
    }

    func testTheOptionIsPerDeviceAndOffByDefault() {
        let defaults = UserDefaults(suiteName: "synctest-gate-\(UUID().uuidString)")!
        XCTAssertFalse(JournalMediaPreference.allowsCellular(defaults: defaults))
        let posted = expectation(forNotification: JournalMediaPreference.changedNotification, object: nil)
        JournalMediaPreference.setAllowsCellular(true, defaults: defaults)
        wait(for: [posted], timeout: 1)
        XCTAssertTrue(JournalMediaPreference.allowsCellular(defaults: defaults))
        XCTAssertFalse(JournalSettingKey.all.contains(JournalMediaPreference.defaultsKey), "never synced")
    }

    func testHeldNamesAreUniqueAndTheStatusTextSaysWhatWaits() {
        let held = JournalMediaHold.adding(["a", "b", "a"], to: ["b"])
        XCTAssertEqual(held, ["b", "a"])
        XCTAssertNil(JournalMediaHold.summary(uploads: [:], downloads: []))
        XCTAssertEqual(JournalMediaHold.summary(uploads: ["x": 1_000_000], downloads: ["y", "z"]),
                       "Media waiting for Wi-Fi: 1 to send (1 MB), 2 to receive")
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
