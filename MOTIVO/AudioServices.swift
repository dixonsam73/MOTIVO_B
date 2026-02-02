// AudioServices.swift
// CHANGE-ID: 20260201_230500_AudioSession_NoPlaybackCategory_9a1c7e
// SCOPE: Eliminate AVAudioSession.Category.playback switching to avoid OSStatus -50 during immediate post-record previews.
//        Use playAndRecord for both recording and playback contexts, varying only options:
//          - recording: allowBluetoothA2DP (output), preferred input USB > built-in
//          - playback:  allowBluetoothA2DP + defaultToSpeaker (speaker when no headphones; keeps AirPods if present)
//          - videoPreviewPlayback: same as playback (kept for semantic clarity)
// SEARCH-TOKEN: 20260201_230500_AudioSession_NoPlaybackCategory
import Foundation
import AVFoundation

@MainActor
final class AudioServices: ObservableObject {
    static let shared = AudioServices()

    let droneEngine: DroneEngine
    let metronomeEngine: MetronomeEngine

    private let session = AVAudioSession.sharedInstance()
    private var isConfiguring: Bool = false

    private init() {
        self.droneEngine = DroneEngine()
        self.metronomeEngine = MetronomeEngine()
    }

    enum SessionContext {
        /// Recorder contexts (AudioRecorderView + VideoRecorderView).
        case recording

        /// General playback (PracticeTimerView, AttachmentViewerView, AudioRecorderView preview).
        /// NOTE: Uses playAndRecord to avoid post-record category-switch failures.
        case playback

        /// Preview playback inside VideoRecorderView *before saving*.
        case videoPreviewPlayback
    }

    func configureSession(for context: SessionContext) {
        guard !isConfiguring else { return }
        isConfiguring = true
        defer { isConfiguring = false }

        let desiredCategory: AVAudioSession.Category = .playAndRecord
        let desiredMode: AVAudioSession.Mode = .default

        let desiredOptions: AVAudioSession.CategoryOptions
        switch context {
        case .recording:
            // Output: allow AirPods (A2DP). Input: no Bluetooth HFP enabled.
            desiredOptions = [.allowBluetoothA2DP]

        case .playback, .videoPreviewPlayback:
            // Speaker audible when no headphones; keeps AirPods if present.
            desiredOptions = [.allowBluetoothA2DP, .defaultToSpeaker]
        }

        let needsChange =
            (session.category != desiredCategory) ||
            (session.mode != desiredMode) ||
            (session.categoryOptions != desiredOptions)

        do {
            if needsChange {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                try session.setCategory(desiredCategory, mode: desiredMode, options: desiredOptions)
            }

            try session.setActive(true)

            if context == .recording {
                applyPreferredInputForRecording()
            }

        } catch {
            #if DEBUG
            print("[AudioServices] configureSession FAILED context=\(context): \(error)")
            logRouteSnapshot(prefix: "[AudioServices] route-after-configure-failed")
            #endif
        }
    }

    /// Deterministically pick the best input for recording:
    /// 1) USB mic, 2) built-in mic, 3) otherwise keep system default.
    /// Never selects Bluetooth HFP mic (we do not enable .allowBluetooth).
    func applyPreferredInputForRecording() {
        guard let inputs = session.availableInputs, !inputs.isEmpty else { return }

        if let usb = inputs.first(where: { $0.portType == .usbAudio }) {
            setPreferredInputIfNeeded(usb, label: "USB")
            return
        }

        if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
            setPreferredInputIfNeeded(builtIn, label: "BuiltIn")
            return
        }
    }

    private func setPreferredInputIfNeeded(_ input: AVAudioSessionPortDescription, label: String) {
        if session.preferredInput?.uid == input.uid { return }

        do {
            try session.setPreferredInput(input)
            #if DEBUG
            logRouteSnapshot(prefix: "[AudioServices] preferredInput=\(label)")
            #endif
        } catch {
            #if DEBUG
            print("[AudioServices] setPreferredInput(\(label)) FAILED: \(error)")
            logRouteSnapshot(prefix: "[AudioServices] route-after-failedPreferredInput")
            #endif
        }
    }

    #if DEBUG
    func logRouteSnapshot(prefix: String) {
        let r = session.currentRoute
        let inPorts = r.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let outPorts = r.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let pref = session.preferredInput.map { "\($0.portType.rawValue):\($0.portName)" } ?? "nil"
        print("\(prefix) category=\(session.category.rawValue) mode=\(session.mode.rawValue) inputs=[\(inPorts)] outputs=[\(outPorts)] sr=\(session.sampleRate) buf=\(session.ioBufferDuration) prefIn=\(pref)")
    }
    #endif
}
