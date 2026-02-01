// AudioServices.swift
// CHANGE-ID: 20260201_214600_AudioSessionPolicyStable_7b1c1a
// SCOPE: Centralize AVAudioSession policy (recording vs playback) with deterministic preferred input selection (USB > built-in; never BT HFP).
//        Adds a recorder-preview playback context that keeps AirPods/headphones output but defaults to speaker when no headphones,
//        without switching away from playAndRecord (avoids capture-session churn).
// SEARCH-TOKEN: 20260201_214600_AudioSessionPolicyStable
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

    // MARK: - Policy

    enum SessionContext {
        /// Recording contexts (AudioRecorderView + VideoRecorderView).
        /// - Category: playAndRecord
        /// - Options: allowBluetoothA2DP (output only), NO allowBluetooth (prevents HFP mic)
        /// - Preferred input: USB > built-in
        case recording

        /// General playback (PracticeTimerView, AudioRecorderView preview, AttachmentViewerView).
        /// - Category: playback
        /// - Options: allowBluetoothA2DP (keep AirPods/headphones if present)
        case playback

        /// Preview playback inside VideoRecorderView *before saving*.
        /// Keep category as playAndRecord (to avoid capture-session conflicts), but default to speaker when no headphones.
        /// - Category: playAndRecord
        /// - Options: allowBluetoothA2DP + defaultToSpeaker
        case videoPreviewPlayback
    }

    func configureSession(for context: SessionContext) {
        // Avoid re-entrant configuration loops (routeChange -> configure -> categoryChange -> routeChange...).
        guard !isConfiguring else { return }
        isConfiguring = true
        defer { isConfiguring = false }

        let desiredCategory: AVAudioSession.Category
        let desiredMode: AVAudioSession.Mode = .default
        let desiredOptions: AVAudioSession.CategoryOptions

        switch context {
        case .recording:
            desiredCategory = .playAndRecord
            desiredOptions = [.allowBluetoothA2DP]

        case .playback:
            desiredCategory = .playback
            desiredOptions = [.allowBluetoothA2DP]

        case .videoPreviewPlayback:
            desiredCategory = .playAndRecord
            desiredOptions = [.allowBluetoothA2DP, .defaultToSpeaker]
        }

        do {
            // Only setCategory if something actually differs; redundant calls can trigger route churn.
            if session.category != desiredCategory || session.mode != desiredMode || session.categoryOptions != desiredOptions {
                try session.setCategory(desiredCategory, mode: desiredMode, options: desiredOptions)
            }

            // Keep the session active while we're using it.
            // notifyOthersOnDeactivation only matters when deactivating; harmless here.
            try session.setActive(true)

            if context == .recording {
                applyPreferredInputForRecording()
            }

        } catch {
            #if DEBUG
            print("[AudioServices] configureSession FAILED context=\(context): \(error)")
            #endif
        }
    }

    /// Deterministically pick the best input for recording:
    /// 1) USB mic, 2) built-in mic, 3) otherwise keep system default.
    /// Never selects Bluetooth HFP mic.
    func applyPreferredInputForRecording() {
        guard let inputs = session.availableInputs, !inputs.isEmpty else { return }

        // Preferred: USB
        if let usb = inputs.first(where: { $0.portType == .usbAudio }) {
            setPreferredInputIfNeeded(usb, label: "USB")
            return
        }

        // Next: built-in mic
        if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
            setPreferredInputIfNeeded(builtIn, label: "BuiltIn")
            return
        }
    }

    private func setPreferredInputIfNeeded(_ input: AVAudioSessionPortDescription, label: String) {
        if session.preferredInput?.uid == input.uid {
            return
        }

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

    // MARK: - Debug

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
