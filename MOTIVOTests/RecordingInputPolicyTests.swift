import XCTest
import AVFoundation
@testable import Etudes

@MainActor
final class RecordingInputPolicyTests: XCTestCase {
    private let phone = RecordingInputPort(id: "phone", type: .builtInMic)
    private let usb = RecordingInputPort(id: "usb", type: .usbAudio)
    private let bluetooth = RecordingInputPort(id: "airpods", type: .bluetoothHFP)
    private let wired = RecordingInputPort(id: "headset", type: .headsetMic)

    func testPhoneIsPreferredOverHeadsetInputs() {
        for accessory in [bluetooth, wired, RecordingInputPort(id: "le", type: .bluetoothLE)] {
            XCTAssertEqual(RecordingInputPolicy.preferred(in: [accessory, phone]), phone)
        }
    }
    func testUSBWinsRegardlessOfDeviceEnumerationOrder() {
        for ports in [[usb, phone, bluetooth], [bluetooth, phone, usb], [phone, usb], [usb]] {
            XCTAssertEqual(RecordingInputPolicy.preferred(in: ports), usb)
        }
    }
    func testNoDisallowedFallbackWhenPhoneAndUSBUnavailable() {
        XCTAssertNil(RecordingInputPolicy.preferred(in: [bluetooth, wired]))
        XCTAssertNil(RecordingInputPolicy.preferred(in: []))
    }
    func testUSBIsNotOverwrittenByPhoneWhenAirPodsAppear() throws {
        let session = FakeRecordingInputSession(inputs: [phone, bluetooth, usb], current: [usb])
        session.preferredInputID = usb.id
        try RecordingInputPolicy.applyAndVerify(session)
        XCTAssertEqual(session.currentInputs, [usb])
        XCTAssertTrue(session.requests.isEmpty)
    }
    func testUSBInsertionAndRemovalReapplyPriority() throws {
        let session = FakeRecordingInputSession(inputs: [phone], current: [phone])
        try RecordingInputPolicy.applyAndVerify(session)
        session.inputs = [phone, usb, bluetooth]
        try RecordingInputPolicy.applyAndVerify(session)
        XCTAssertEqual(session.currentInputs, [usb])
        session.inputs = [phone, bluetooth]
        session.currentInputs = [bluetooth]
        try RecordingInputPolicy.applyAndVerify(session)
        XCTAssertEqual(session.currentInputs, [phone])
    }
    func testPreferenceAloneDoesNotProveCorrectInput() {
        let session = FakeRecordingInputSession(inputs: [phone, bluetooth], current: [bluetooth])
        session.preferredInputID = phone.id
        session.honorsPreference = false
        XCTAssertThrowsError(try RecordingInputPolicy.applyAndVerify(session))
        XCTAssertEqual(session.requests, [phone])
    }
    func testRepeatedRouteNotificationDoesNotReconfigureAgain() throws {
        let session = FakeRecordingInputSession(inputs: [phone, usb], current: [phone])
        for _ in 0..<20 { try RecordingInputPolicy.applyAndVerify(session) }
        XCTAssertEqual(session.requests, [usb])
    }
    func testFailedSetupOrInputSelectionNeverCallsRecord() {
        for setupFailure in [true, false] {
            let session = FakeRecordingInputSession(inputs: [phone], current: [])
            session.failSetup = setupFailure
            session.failPreference = !setupFailure
            var calls = 0
            XCTAssertThrowsError(try AudioRecordingAttempt.begin(session: session, record: {
                calls += 1; return true
            }, isRecording: { true }, pause: {}))
            XCTAssertEqual(calls, 0)
        }
    }
    func testFailedResumeCannotReportSuccessAndLeavesTakePaused() {
        let session = FakeRecordingInputSession(inputs: [phone], current: [phone])
        var paused = false
        XCTAssertThrowsError(try AudioRecordingAttempt.begin(session: session,
            record: { false }, isRecording: { false }, pause: { paused = true }))
        XCTAssertTrue(paused)
    }
    func testTrueReturnWithInactiveRecorderStillFails() {
        let session = FakeRecordingInputSession(inputs: [phone], current: [phone])
        var paused = false
        XCTAssertThrowsError(try AudioRecordingAttempt.begin(session: session,
            record: { true }, isRecording: { false }, pause: { paused = true }))
        XCTAssertTrue(paused)
    }
    func testRouteChangedDuringStartPausesRatherThanReportingSuccess() {
        let session = FakeRecordingInputSession(inputs: [phone, bluetooth], current: [phone])
        var paused = false
        XCTAssertThrowsError(try AudioRecordingAttempt.begin(session: session, record: {
            session.currentInputs = [self.bluetooth]; return true
        }, isRecording: { true }, pause: { paused = true }))
        XCTAssertTrue(paused)
    }
    func testSuccessfulResumeUsesSameConfiguredAndVerifiedPolicy() throws {
        let session = FakeRecordingInputSession(inputs: [phone, usb], current: [phone])
        var recorded = false
        try AudioRecordingAttempt.begin(session: session, record: {
            XCTAssertEqual(session.currentInputs, [self.usb])
            recorded = true; return true
        }, isRecording: { recorded }, pause: { XCTFail("Successful recording was paused") })
        XCTAssertEqual(session.setupCalls, 1)
        XCTAssertTrue(recorded)
    }
}

@MainActor
private final class FakeRecordingInputSession: RecordingInputSession {
    var inputs: [RecordingInputPort]
    var currentInputs: [RecordingInputPort]
    var preferredInputID: String?
    var requests: [RecordingInputPort] = []
    var honorsPreference = true
    var failSetup = false
    var failPreference = false
    var setupCalls = 0
    init(inputs: [RecordingInputPort], current: [RecordingInputPort]) {
        self.inputs = inputs; currentInputs = current
    }
    func configureForAudioRecording() throws {
        setupCalls += 1
        if failSetup { throw RecordingInputFailure.unavailable }
    }
    func prefer(_ input: RecordingInputPort) throws {
        requests.append(input)
        if failPreference { throw RecordingInputFailure.selection }
        preferredInputID = input.id
        if honorsPreference { currentInputs = [input] }
    }
}
