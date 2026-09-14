import AVFoundation

struct RecordingInputPort: Equatable {
    let id: String
    let type: AVAudioSession.Port
}

/// The adapter is intentionally separate from video's established session startup.
@MainActor
protocol RecordingInputSession {
    var inputs: [RecordingInputPort] { get }
    var currentInputs: [RecordingInputPort] { get }
    var preferredInputID: String? { get }
    func configureForAudioRecording() throws
    func prefer(_ input: RecordingInputPort) throws
}

enum RecordingInputFailure: LocalizedError {
    case unavailable, selection, start
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Connect a USB microphone or use the phone microphone, then try again."
        case .selection: return "The recording microphone could not be selected. Check the connection and try again."
        case .start: return "Recording could not start. Check the microphone connection and try again."
        }
    }
}

enum RecordingInputPolicy {
    static func preferred(in inputs: [RecordingInputPort]) -> RecordingInputPort? {
        inputs.first { $0.type == .usbAudio } ?? inputs.first { $0.type == .builtInMic }
    }

    @MainActor
    static func verify(_ session: any RecordingInputSession) throws {
        guard let desired = preferred(in: session.inputs) else { throw RecordingInputFailure.unavailable }
        guard session.currentInputs == [desired] else { throw RecordingInputFailure.selection }
    }

    @MainActor
    static func applyAndVerify(_ session: any RecordingInputSession) throws {
        guard let desired = preferred(in: session.inputs) else { throw RecordingInputFailure.unavailable }
        // Matching preference AND current route avoids a self-induced route-notification loop.
        if session.preferredInputID != desired.id || session.currentInputs != [desired] {
            try session.prefer(desired)
        }
        try verify(session)
    }
}

@MainActor
struct SystemRecordingInputSession: RecordingInputSession {
    private var session: AVAudioSession { .sharedInstance() }
    var inputs: [RecordingInputPort] {
        (session.availableInputs ?? []).map { RecordingInputPort(id: $0.uid, type: $0.portType) }
    }
    var currentInputs: [RecordingInputPort] {
        session.currentRoute.inputs.map { RecordingInputPort(id: $0.uid, type: $0.portType) }
    }
    var preferredInputID: String? { session.preferredInput?.uid }

    func configureForAudioRecording() throws {
        let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
        if session.category != .playAndRecord || session.mode != .default || session.categoryOptions != options {
            try session.setCategory(.playAndRecord, mode: .default, options: options)
        }
        try session.setActive(true)
    }

    func prefer(_ input: RecordingInputPort) throws {
        guard let port = session.availableInputs?.first(where: { $0.uid == input.id }) else {
            throw RecordingInputFailure.unavailable
        }
        try session.setPreferredInput(port)
    }
}

/// Initial start and resume share the same success conditions. The view only advances
/// its recording state/timer after this succeeds; failures leave an existing take paused.
enum AudioRecordingAttempt {
    @MainActor
    static func begin(session: any RecordingInputSession,
                      record: () -> Bool, isRecording: () -> Bool, pause: () -> Void) throws {
        try session.configureForAudioRecording()
        try RecordingInputPolicy.applyAndVerify(session)
        guard record(), isRecording() else {
            pause()
            throw RecordingInputFailure.start
        }
        do { try RecordingInputPolicy.verify(session) }
        catch { pause(); throw error }
        #if DEBUG
        print("[RecordingAudio] verified input=\(session.currentInputs.map { $0.type.rawValue })")
        #endif
    }
}
