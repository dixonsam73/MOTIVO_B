import AVFoundation

/// AVAudioRecorder retains its delegate weakly. The view owns this bridge for one take
/// and invalidates it before an intentional stop, preventing late callbacks changing a new take.
final class AudioRecorderEvents: NSObject, AVAudioRecorderDelegate {
    var onEnd: (@MainActor (AVAudioRecorder, String?) -> Void)?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        deliver(recorder, message: flag ? nil : "Recording stopped unexpectedly. Check the saved take before keeping it.")
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        deliver(recorder, message: "Recording stopped because audio could not be saved. Check the existing take before keeping it.")
    }

    private func deliver(_ recorder: AVAudioRecorder, message: String?) {
        DispatchQueue.main.async { [weak self] in self?.onEnd?(recorder, message) }
    }
}
