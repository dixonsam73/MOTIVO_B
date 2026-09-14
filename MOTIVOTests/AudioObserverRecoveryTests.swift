import XCTest
import AVFoundation
@testable import Etudes

@MainActor
final class AudioObserverRecoveryTests: XCTestCase {
    func testRemoveActuallyStopsFoundationDelivery() {
        let center = NotificationCenter()
        let observers = AudioNotificationObservers(center: center)
        let name = Notification.Name("recording-route-test")
        var calls = 0
        observers.observe(name) { _ in calls += 1 }
        center.post(name: name, object: nil)
        observers.removeAll()
        center.post(name: name, object: nil)
        XCTAssertEqual(calls, 1)
    }
    func testRepeatedInstallationAndRemovalNeverDuplicatesListeners() {
        let center = NotificationCenter()
        let observers = AudioNotificationObservers(center: center)
        let name = Notification.Name("recording-cycle-test")
        var calls = 0
        for cycle in 1...20 {
            observers.observe(name) { _ in calls += 1 }
            observers.observe(name) { _ in XCTFail("Duplicate listener installed") }
            center.post(name: name, object: nil)
            XCTAssertEqual(calls, cycle)
            observers.removeAll()
            observers.removeAll()
            center.post(name: name, object: nil)
            XCTAssertEqual(calls, cycle)
        }
    }
    func testIndependentEventTypesAndObjectFiltering() {
        let center = NotificationCenter()
        let observers = AudioNotificationObservers(center: center)
        let object = NSObject()
        var routeCalls = 0
        var resetCalls = 0
        observers.observe(.init("route"), object: object) { _ in routeCalls += 1 }
        observers.observe(.init("reset")) { _ in resetCalls += 1 }
        center.post(name: .init("route"), object: NSObject())
        center.post(name: .init("route"), object: object)
        center.post(name: .init("reset"), object: nil)
        XCTAssertEqual(routeCalls, 1)
        XCTAssertEqual(resetCalls, 1)
        observers.removeAll()
    }
    func testRecorderErrorAndCompletionAreDeliveredOnMainActor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
        let bridge = AudioRecorderEvents()
        let completed = expectation(description: "Recorder delegate completion")
        bridge.onEnd = { value, message in
            XCTAssertTrue(value === recorder)
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNotNil(message)
            completed.fulfill()
        }
        bridge.audioRecorderEncodeErrorDidOccur(recorder, error: nil)
        await fulfillment(of: [completed], timeout: 1)
        let ended = expectation(description: "Recorder unexpected finish")
        bridge.onEnd = { _, message in XCTAssertNil(message); ended.fulfill() }
        bridge.audioRecorderDidFinishRecording(recorder, successfully: true)
        await fulfillment(of: [ended], timeout: 1)
    }
    func testIntentionalStopInvalidatesAlreadyQueuedDelegateCallback() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
        let bridge = AudioRecorderEvents()
        bridge.onEnd = { _, _ in XCTFail("A stopped/old take delivered a callback") }
        bridge.audioRecorderDidFinishRecording(recorder, successfully: false)
        bridge.onEnd = nil
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 1)
    }
}
