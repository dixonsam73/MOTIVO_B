// CHANGE-ID: 20260921_R1_RecordingRouteObservation
// SCOPE: C-97 R1 — input-route observability for the video recorder. Read-only.
// SEARCH-TOKEN: 20260921_R1_RecordingRouteObservation

import Foundation
import os

/// Records which audio input the video recorder has at one moment.
///
/// **Observability, not a fix.** It repairs no defect and proves no soundtrack:
/// a matching route says the session reported the desired input then, not that
/// samples arrive afterwards. C-97's R2, R3 and R4 are untouched by it.
///
/// **A mismatch is an observation, never a diagnosis** — a route can legitimately
/// be in flight — so it never refuses, retries or warns the member.
enum RecordingRouteObservation {

    /// Which selection attempt the reading follows.
    ///
    /// **Both are deferred.** `VideoRecorderController` is not `@MainActor` while
    /// the verifier is, so every reading is taken on main after its selection
    /// attempt returns. Nothing blocks to make one atomic.
    enum Stage: String {
        case preactivationDeferred
        case preferenceAppliedDeferred
    }

    /// Port TYPES only — never a UID, a name, account data or recording content.
    enum Outcome: Equatable {
        case match(effective: String)
        case mismatch(desired: String, effective: [String])
        case unavailable
    }

    protocol Sink {
        func record(stage: Stage, outcome: Outcome)
    }

    /// Release-enabled and local: an `os.Logger` line carrying a stage and port
    /// types.
    ///
    /// **The honest claim is bounded.** This app neither uploads nor persists it,
    /// and puts nothing else in it. What the OS does with its own log store —
    /// retention, sysdiagnose, anything a device owner or a connected tool
    /// collects — is not something this code controls or can promise about.
    /// `privacy: .public` because every value is a port type from a fixed
    /// vocabulary, so there is nothing to redact.
    struct LogSink: Sink {
        private static let log = Logger(subsystem: "com.motivo.recorder", category: "route")
        init() {}
        func record(stage: Stage, outcome: Outcome) {
            switch outcome {
            case .match(let effective):
                Self.log.info("route stage=\(stage.rawValue, privacy: .public) outcome=match effective=\(effective, privacy: .public)")
            case .mismatch(let desired, let effective):
                Self.log.info("route stage=\(stage.rawValue, privacy: .public) outcome=mismatch desired=\(desired, privacy: .public) effective=\(effective.joined(separator: ","), privacy: .public)")
            case .unavailable:
                Self.log.info("route stage=\(stage.rawValue, privacy: .public) outcome=unavailable")
            }
        }
    }

    /// One reading of a session, taken once and then not re-read.
    ///
    /// **This is why it exists.** Classifying from live getters and then
    /// rendering from them again can describe two different routes in one
    /// record — a "match" whose named port is the one it did not match. Every
    /// value below comes from the same capture.
    ///
    /// **It is still NOT an atomic `AVAudioSession` snapshot:** the properties
    /// are read one after another, and the underlying route can move between
    /// them. It bounds the inconsistency to the capture; it does not remove it.
    private struct CapturedRoute: RecordingInputSession {
        let inputs: [RecordingInputPort]
        let currentInputs: [RecordingInputPort]
        let preferredInputID: String?

        init(_ session: any RecordingInputSession) {
            inputs = session.inputs
            currentInputs = session.currentInputs
            preferredInputID = session.preferredInputID
        }

        // Never called: `observe` classifies and renders only.
        func configureForAudioRecording() throws { throw RecordingInputFailure.selection }
        func prefer(_ input: RecordingInputPort) throws { throw RecordingInputFailure.selection }
    }

    /// Classify one capture and record it.
    ///
    /// The classification is `RecordingInputPolicy.verify`, reused rather than
    /// reimplemented, so it cannot drift from the audio path's rule. Read-only:
    /// nothing here writes a preference, category or activation.
    @MainActor
    @discardableResult
    static func observe(_ session: any RecordingInputSession,
                        stage: Stage,
                        sink: Sink = LogSink()) -> Outcome {
        let captured = CapturedRoute(session)
        let effective = captured.currentInputs.map { $0.type.rawValue }.sorted()

        let outcome: Outcome
        do {
            try RecordingInputPolicy.verify(captured)
            outcome = .match(effective: effective.joined(separator: ","))
        } catch RecordingInputFailure.unavailable {
            outcome = .unavailable
        } catch {
            let desired = RecordingInputPolicy.preferred(in: captured.inputs)?.type.rawValue ?? "none"
            outcome = .mismatch(desired: desired, effective: effective)
        }
        sink.record(stage: stage, outcome: outcome)
        return outcome
    }
}
