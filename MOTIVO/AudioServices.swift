// AudioServices.swift
// CHANGE-ID: 20260201_230500_AudioSession_NoPlaybackCategory_9a1c7e
// SCOPE: Eliminate AVAudioSession.Category.playback switching to avoid OSStatus -50 during immediate post-record previews.
//        Playback uses playAndRecord with allowBluetoothA2DP + defaultToSpeaker (speaker when no
//        headphones; keeps AirPods if present).
//        Recording does not go through this type: the audio recorder's session and input policy
//        are RecordingInputPolicy / SystemRecordingInputSession; the video recorder configures
//        its own session in VideoRecorderView.
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
        /// General playback (PracticeTimerView, AttachmentViewerView, AudioRecorderView preview).
        /// NOTE: Uses playAndRecord to avoid post-record category-switch failures.
        case playback
    }

    func configureSession(for context: SessionContext) {
        guard !isConfiguring else { return }
        isConfiguring = true
        defer { isConfiguring = false }

        let desiredCategory: AVAudioSession.Category = .playAndRecord
        let desiredMode: AVAudioSession.Mode = .default

        // Speaker audible when no headphones; keeps AirPods if present.
        let desiredOptions: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .defaultToSpeaker]

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

        } catch {
            #if DEBUG
            print("[AudioServices] configureSession FAILED context=\(context): \(error)")
            logRouteSnapshot(prefix: "[AudioServices] route-after-configure-failed")
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
