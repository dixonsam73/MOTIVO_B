// CHANGE-ID: 20260921_R1_RecordingRouteObservationTests
// SCOPE: C-97 R1 — the route diagnostic's production path, driven with a fake
// session and a recording sink, plus the wiring of both video call sites.
// SEARCH-TOKEN: 20260921_R1_RecordingRouteObservationTests

import AVFoundation
import XCTest
@testable import Etudes

/// **WHAT THESE CAN AND CANNOT SHOW.**
///
/// They drive the production classifier and the production sink protocol with a
/// fake session, so the OUTCOMES and the READ-ONLY property are measured. They
/// **cannot** show that real hardware routes as reported, that a real
/// `AVAudioSession` behaves like the fake, or that audio samples ever arrive —
/// the last of those is C-97 R4 and remains open.
@MainActor
final class RecordingRouteObservationTests: XCTestCase {

    private static let usb = RecordingInputPort(id: "usb-uid", type: .usbAudio)
    private static let builtIn = RecordingInputPort(id: "builtin-uid", type: .builtInMic)
    private static let bluetooth = RecordingInputPort(id: "bt-uid", type: .bluetoothHFP)

    /// Records every mutating call so a test can assert there were none, and
    /// counts reads so a test can assert the route is captured once.
    private final class FakeSession: RecordingInputSession {
        private let storedInputs: [RecordingInputPort]
        private let storedCurrent: [RecordingInputPort]
        private let storedPreferred: String?
        private(set) var configureCalls = 0
        private(set) var preferCalls: [RecordingInputPort] = []
        private(set) var currentInputsReads = 0
        private(set) var inputsReads = 0

        init(inputs: [RecordingInputPort], currentInputs: [RecordingInputPort],
             preferredInputID: String? = nil) {
            storedInputs = inputs
            storedCurrent = currentInputs
            storedPreferred = preferredInputID
        }

        var inputs: [RecordingInputPort] {
            inputsReads += 1
            return storedInputs
        }
        var currentInputs: [RecordingInputPort] {
            currentInputsReads += 1
            return storedCurrent
        }
        var preferredInputID: String? { storedPreferred }

        func configureForAudioRecording() throws { configureCalls += 1 }
        func prefer(_ input: RecordingInputPort) throws { preferCalls.append(input) }
    }

    /// A route that MOVES between reads — the condition the single capture
    /// exists for. Every read of `currentInputs` returns the next value.
    private final class ChangingRouteSession: RecordingInputSession {
        private let sequence: [[RecordingInputPort]]
        private(set) var currentInputsReads = 0
        let inputs: [RecordingInputPort]
        var preferredInputID: String? { nil }

        init(inputs: [RecordingInputPort], currentSequence: [[RecordingInputPort]]) {
            self.inputs = inputs
            self.sequence = currentSequence
        }

        var currentInputs: [RecordingInputPort] {
            defer { currentInputsReads += 1 }
            return sequence[min(currentInputsReads, sequence.count - 1)]
        }

        func configureForAudioRecording() throws {}
        func prefer(_ input: RecordingInputPort) throws {}
    }

    private final class RecordingSink: RecordingRouteObservation.Sink {
        private(set) var entries: [(RecordingRouteObservation.Stage, RecordingRouteObservation.Outcome)] = []
        func record(stage: RecordingRouteObservation.Stage,
                    outcome: RecordingRouteObservation.Outcome) {
            entries.append((stage, outcome))
        }
    }

    // MARK: - the three outcomes

    func testTheDesiredRouteIsAMatch() {
        let session = FakeSession(inputs: [Self.usb, Self.builtIn], currentInputs: [Self.usb])
        let sink = RecordingSink()
        let outcome = RecordingRouteObservation.observe(session, stage: .preferenceAppliedDeferred, sink: sink)

        XCTAssertEqual(outcome, .match(effective: "USBAudio"))
        XCTAssertEqual(sink.entries.count, 1)
        XCTAssertEqual(sink.entries[0].0, .preferenceAppliedDeferred)
    }

    /// The built-in microphone is the desired input when no USB one is offered —
    /// so this is a match, not a fallback to be reported as a problem.
    func testTheBuiltInMicrophoneIsAMatchWhenNoUSBIsOffered() {
        let session = FakeSession(inputs: [Self.builtIn], currentInputs: [Self.builtIn])
        let sink = RecordingSink()
        XCTAssertEqual(RecordingRouteObservation.observe(session, stage: .preactivationDeferred, sink: sink),
                       .match(effective: "MicrophoneBuiltIn"))
    }

    func testARouteThatIsNotTheDesiredOneIsAMismatchNamingBothTypes() {
        let session = FakeSession(inputs: [Self.usb, Self.builtIn], currentInputs: [Self.builtIn])
        let sink = RecordingSink()
        let outcome = RecordingRouteObservation.observe(session, stage: .preferenceAppliedDeferred, sink: sink)

        XCTAssertEqual(outcome, .mismatch(desired: "USBAudio", effective: ["MicrophoneBuiltIn"]))
        XCTAssertEqual(sink.entries.count, 1, "a mismatch is recorded, not swallowed")
    }

    /// Neither port offered. Bluetooth HFP is deliberately not a desired input,
    /// so a session offering only that is `unavailable`, not a match.
    func testNoPreferredInputIsUnavailable() {
        let session = FakeSession(inputs: [Self.bluetooth], currentInputs: [Self.bluetooth])
        let sink = RecordingSink()
        XCTAssertEqual(RecordingRouteObservation.observe(session, stage: .preactivationDeferred, sink: sink),
                       .unavailable)
        XCTAssertEqual(sink.entries.count, 1, "the no-input case is observed too, not skipped")
    }

    func testAnEmptySessionIsUnavailable() {
        let session = FakeSession(inputs: [], currentInputs: [])
        XCTAssertEqual(RecordingRouteObservation.observe(session, stage: .preactivationDeferred,
                                                         sink: RecordingSink()),
                       .unavailable)
    }

    // MARK: - one capture

    /// **THE DEFECT THIS UNIT WAS SENT BACK FOR.** Classifying from live getters
    /// and then rendering from them again can describe two different routes in
    /// one record: verification sees USB and passes, the route moves, and the
    /// rendered line reports a MATCH whose effective port is the built-in
    /// microphone — a record that contradicts itself.
    ///
    /// With one capture, the classification and the rendering are the same
    /// values, so the record is self-consistent whatever the route does next.
    func testAChangingRouteCannotProduceAContradictoryRecord() {
        let session = ChangingRouteSession(inputs: [Self.usb, Self.builtIn],
                                           currentSequence: [[Self.usb], [Self.builtIn]])
        let sink = RecordingSink()
        let outcome = RecordingRouteObservation.observe(session, stage: .preferenceAppliedDeferred,
                                                        sink: sink)

        XCTAssertEqual(outcome, .match(effective: "USBAudio"),
                       "a match must name the port it actually matched on")
        XCTAssertEqual(session.currentInputsReads, 1,
                       "the route is read ONCE; a second read is what admits the contradiction")
    }

    /// The same, the other way round: a mismatch must not be rendered with the
    /// values of a route that has since become correct.
    func testAMismatchIsRenderedFromTheValuesItWasClassifiedFrom() {
        let session = ChangingRouteSession(inputs: [Self.usb, Self.builtIn],
                                           currentSequence: [[Self.builtIn], [Self.usb]])
        let outcome = RecordingRouteObservation.observe(session, stage: .preactivationDeferred,
                                                        sink: RecordingSink())

        XCTAssertEqual(outcome, .mismatch(desired: "USBAudio", effective: ["MicrophoneBuiltIn"]))
        XCTAssertEqual(session.currentInputsReads, 1)
    }

    /// Capturing bounds the inconsistency to one reading. **It is not an atomic
    /// `AVAudioSession` snapshot** — the properties are read one after another —
    /// and this pins that the claim stays modest: available and current are read
    /// once each, not repeatedly.
    func testTheCaptureReadsEachPropertyOnce() {
        let session = FakeSession(inputs: [Self.usb, Self.builtIn], currentInputs: [Self.usb])
        _ = RecordingRouteObservation.observe(session, stage: .preferenceAppliedDeferred,
                                              sink: RecordingSink())
        XCTAssertEqual(session.currentInputsReads, 1)
        XCTAssertEqual(session.inputsReads, 1)
    }

    // MARK: - read-only

    /// **The property this unit rests on.** Observability must not become a
    /// second writer of the audio session: no preference, no category, no
    /// activation, on ANY outcome.
    func testNoOutcomeMutatesTheSession() {
        for (inputs, current) in [([Self.usb, Self.builtIn], [Self.usb]),
                                  ([Self.usb, Self.builtIn], [Self.builtIn]),
                                  ([Self.bluetooth], [Self.bluetooth]),
                                  ([], [])] as [([RecordingInputPort], [RecordingInputPort])] {
            let session = FakeSession(inputs: inputs, currentInputs: current)
            _ = RecordingRouteObservation.observe(session, stage: .preferenceAppliedDeferred,
                                                  sink: RecordingSink())
            XCTAssertEqual(session.configureCalls, 0, "no category or activation write")
            XCTAssertTrue(session.preferCalls.isEmpty, "no preference write")
            XCTAssertNil(session.preferredInputID, "no preference appears as a side effect")
        }
    }

    /// The classifier must be `RecordingInputPolicy.verify`, not a second
    /// implementation of the same rule that can drift from the audio path's.
    func testTheClassificationAgreesWithThePolicyItReuses() {
        let cases: [([RecordingInputPort], [RecordingInputPort])] = [
            ([Self.usb, Self.builtIn], [Self.usb]),
            ([Self.usb, Self.builtIn], [Self.builtIn]),
            ([Self.builtIn], [Self.builtIn]),
            ([Self.bluetooth], [Self.bluetooth]),
        ]
        for (inputs, current) in cases {
            let session = FakeSession(inputs: inputs, currentInputs: current)
            let policySaysMatch = (try? RecordingInputPolicy.verify(session)) != nil
            let observed = RecordingRouteObservation.observe(session, stage: .preactivationDeferred,
                                                             sink: RecordingSink())
            if case .match = observed {
                XCTAssertTrue(policySaysMatch, "observed a match the policy would reject")
            } else {
                XCTAssertFalse(policySaysMatch, "observed a non-match the policy would accept")
            }
        }
    }

    // MARK: - what the diagnostic may carry

    /// **Port TYPES only.** No UID, no device name, nothing from the recording
    /// or the account. Asserted against the fake's UIDs, which are distinctive.
    func testTheDiagnosticCarriesPortTypesAndNeverIdentifiers() {
        let session = FakeSession(inputs: [Self.usb, Self.builtIn], currentInputs: [Self.builtIn])
        let sink = RecordingSink()
        _ = RecordingRouteObservation.observe(session, stage: .preferenceAppliedDeferred, sink: sink)

        let rendered = String(describing: sink.entries)
        for identifier in ["usb-uid", "builtin-uid", "bt-uid"] {
            XCTAssertFalse(rendered.contains(identifier), "a device UID must never reach the diagnostic")
        }
        XCTAssertTrue(rendered.contains("USBAudio"))
        XCTAssertTrue(rendered.contains("MicrophoneBuiltIn"))
    }
}

// MARK: - wiring

/// Source-reading assertions: they prove the two call sites are WIRED and that
/// no write was introduced. They do not prove anything was rendered or routed.
///
/// The diagnostic is injected directly in the tests above; the controller keeps
/// no sink property, because nothing drove one.
final class RecordingRouteObservationWiringTests: XCTestCase {

    private func source() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("MOTIVO/VideoRecorderView.swift"),
                            encoding: .utf8)) ?? ""
    }

    private func code() -> String {
        source().split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
    }

    func testSourceWasFound() {
        XCTAssertFalse(source().isEmpty)
    }

    /// **BOTH production paths, once each.** Two observations, no more: the four
    /// `setPreferredInput` statements are two alternative branches in two paths,
    /// not four independent verification points.
    func testBothProductionPathsAreObservedExactlyOnce() {
        let s = code()
        XCTAssertEqual(s.components(separatedBy: "stage: .preactivationDeferred").count - 1, 1,
                       "the preactivation path is observed exactly once")
        XCTAssertEqual(s.components(separatedBy: ".preferenceAppliedDeferred").count - 1, 1,
                       "the preference path is observed exactly once")
        XCTAssertEqual(s.components(separatedBy: "RecordingRouteObservation.observe(").count - 1, 2,
                       "exactly two observation points in the controller")
    }

    /// **CORRECTED.** An earlier revision of this test said the early `return`
    /// skipped the NO-INPUT case. It did not: that case fell through to the end
    /// of the function. What the `return` after the USB branch would have
    /// skipped is the observation on the **USB path** — the one most worth
    /// observing. A single exit covers all three cases.
    func testThePreferencePathHasASingleExitSoTheUSBBranchIsObservedToo() {
        let s = code()
        guard let start = s.range(of: "private func applyPreferredRecordingInput() {") else {
            return XCTFail("not found")
        }
        let body = String(s[start.lowerBound...].prefix(900))
        XCTAssertTrue(body.contains("} else if let builtIn"),
                      "the branches must be alternatives, not an early-return pair")
        XCTAssertFalse(body.contains("            return\n"),
                       "an early return after the USB branch would skip its observation")
    }

    /// **NO NEW WRITER.** This unit must not have added a preference, category or
    /// activation write anywhere.
    func testTheObservationAddedNoSessionWrites() {
        let s = code()
        XCTAssertEqual(s.components(separatedBy: "setPreferredInput(").count - 1, 4,
                       "the same four selection statements as before, and no more")
        XCTAssertFalse(s.contains("applyAndVerify"),
                       "applyAndVerify mutates the preference and must not be used here")
        XCTAssertFalse(s.contains("configureForAudioRecording"),
                       "the audio-session category is not this unit's business")
        XCTAssertFalse(s.contains("automaticallyConfiguresApplicationAudioSession"),
                       "preserved deliberately; changing it needs its own proposal")
    }

    /// The hop to main must be `async`. A blocking hop would add a wait to
    /// capture setup to buy an atomicity this diagnostic does not claim.
    func testTheObservationNeverBlocks() {
        let s = code()
        guard let start = s.range(of: "private func observeRecordingRoute(") else {
            return XCTFail("not found")
        }
        let body = String(s[start.lowerBound...].prefix(500))
        XCTAssertTrue(body.contains("DispatchQueue.main.async"))
        XCTAssertFalse(body.contains("DispatchQueue.main.sync"), "must never block")
    }
}
