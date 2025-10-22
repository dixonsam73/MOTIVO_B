// AudioRecorderView.swift
// Motivo
// Created by Assistant on 2025-10-20

import SwiftUI
import AVFoundation

/// A lightweight, self-contained audio recorder view using AVAudioRecorder.
/// Stores audio files in the app's Documents directory and returns the saved URL via `onSave`.
struct AudioRecorderView: View {
    // MARK: - Public API
    var onSave: (URL) -> Void

    // MARK: - State
    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var recordingURL: URL?
    @State private var playbackPosition: TimeInterval = 0

    @State private var state: RecordingState = .idle
    @State private var errorMessage: String?

    // Timer for elapsed recording time
    @State private var startTime: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var accumulatedRecordedTime: TimeInterval = 0
    @State private var finalRecordedTime: TimeInterval = 0
    @State private var timer: Timer?

    // MARK: - Body
    var body: some View {
        VStack(spacing: 24) {
            // Status
            VStack(spacing: 8) {
                Text(titleForState)
                    .font(.title3).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(timeString)
                    .monospacedDigit()
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .foregroundStyle(state == .recording ? .red : .secondary)
                    .accessibilityLabel("Elapsed time")
            }
            .frame(maxWidth: .infinity)

            // Controls
            HStack(spacing: 28) {
                // Delete
                ControlButton(systemName: "trash", tint: .secondary, role: .destructive, isEnabled: recordingURL != nil && state.isIdleLike) {
                    deleteRecording()
                }
                .accessibilityLabel("Delete recording")

                // Record / Pause (recording)
                ControlButton(
                    systemName: (state == .recording) ? "pause.circle.fill" : "record.circle.fill",
                    tint: .red,
                    isEnabled: state.canRecord || state == .recording
                ) {
                    Task {
                        if state == .recording {
                            pauseRecording()
                        } else if state == .pausedRecording {
                            await resumeRecording()
                        } else {
                            await startRecording()
                        }
                    }
                }
                .accessibilityLabel(state == .recording ? "Pause recording" : (state == .pausedRecording ? "Resume recording" : "Start recording"))

                // Stop
                ControlButton(systemName: "stop.fill", tint: .primary, isEnabled: state.canStop) {
                    stopAllAndFinalizeRecording()
                }
                .accessibilityLabel("Stop")

                // Play / Pause
                ControlButton(systemName: (state == .playing) ? "pause.fill" : "play.fill", tint: .primary, isEnabled: recordingURL != nil && state.canPlayToggle) {
                    togglePlayback()
                }
                .accessibilityLabel(state == .playing ? "Pause" : "Play")

                // Save
                ControlButton(systemName: "checkmark.circle.fill", tint: .green, isEnabled: recordingURL != nil && state.isIdleLike) {
                    saveRecording()
                }
                .accessibilityLabel("Save recording")
            }
            .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onDisappear { cleanup() }
        .task { await configureSessionIfNeeded() }
        #if DEBUG
        .animation(.default, value: state)
        #endif
    }
}

// MARK: - Private helpers
private extension AudioRecorderView {
    enum RecordingState: Equatable {
        case idle
        case recording
        case pausedRecording
        case playing
        case paused

        var isIdleLike: Bool { self == .idle || self == .paused || self == .pausedRecording }
        var canRecord: Bool { self != .recording }
        var canStop: Bool { self == .recording || self == .playing || self == .paused || self == .pausedRecording }
        var canPlayToggle: Bool { self != .recording && self != .pausedRecording }
    }

    var titleForState: String {
        switch state {
        case .idle: return "Ready"
        case .recording: return "Recording…"
        case .pausedRecording: return "Paused"
        case .playing: return "Playing…"
        case .paused: return "Paused"
        }
    }

    var timeString: String {
        let total: TimeInterval
        switch state {
        case .recording:
            total = accumulatedRecordedTime + elapsed
        case .pausedRecording, .idle:
            // When paused recording or stopped, show the accumulated total (frozen)
            total = accumulatedRecordedTime > 0 ? accumulatedRecordedTime : finalRecordedTime
        case .playing, .paused:
            total = player?.currentTime ?? 0
        }
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let fraction = Int((total - floor(total)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, fraction)
    }

    func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func newRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "motivo_rec_\(formatter.string(from: Date())).m4a"
        return documentsDirectory().appendingPathComponent(name)
    }

    func recordingSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC as NSNumber,
            AVSampleRateKey: 44_100 as NSNumber,
            AVNumberOfChannelsKey: 1 as NSNumber,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue as NSNumber
        ]
    }

    func configureSessionIfNeeded() async {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            setError("Audio session error: \(error.localizedDescription)")
        }
    }

    func startRecording() async {
        // Start a new recording (fresh). Only allowed when not currently recording or pausedRecording.
        guard state != .recording && state != .pausedRecording else { return }
        await configureSessionIfNeeded()
        let url = newRecordingURL()

        do {
            recorder = try AVAudioRecorder(url: url, settings: recordingSettings())
            recorder?.isMeteringEnabled = true
            recorder?.prepareToRecord()

            if recorder?.record() == true {
                recordingURL = url
                // Reset accumulated time because this is a new file
                accumulatedRecordedTime = 0
                finalRecordedTime = 0
                startElapsedTimer()
                state = .recording
                errorMessage = nil
            } else {
                setError("Failed to start recording.")
            }
        } catch {
            setError("Recorder error: \(error.localizedDescription)")
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        recorder?.pause()
        // Add the elapsed chunk to accumulated time and stop the timer
        accumulatedRecordedTime += elapsed
        stopElapsedTimer()
        // Reset per-chunk elapsed
        elapsed = 0
        state = .pausedRecording
    }

    func resumeRecording() async {
        guard state == .pausedRecording else { return }
        do {
            // Ensure session is active
            await configureSessionIfNeeded()
            if recorder?.record() == true {
                startElapsedTimer()
                state = .recording
            } else {
                setError("Failed to resume recording.")
            }
        }
    }

    func stopAll() {
        if recorder?.isRecording == true {
            recorder?.stop()
        } else if state == .pausedRecording {
            recorder?.stop()
        }
        if player?.isPlaying == true {
            player?.stop()
        }
        player?.currentTime = 0
        playbackPosition = 0
        stopElapsedTimer()
        // Do not change accumulatedRecordedTime here; let finalization compute total
    }

    func stopAllAndFinalizeRecording() {
        let wasRecording = (state == .recording) || (state == .pausedRecording)
        stopAll()
        if wasRecording {
            // If we were in active or paused recording, compute total recorded time
            let total = accumulatedRecordedTime + ((state == .recording) ? elapsed : 0)
            finalRecordedTime = max(total, accumulatedRecordedTime)
            // Reset per-chunk elapsed
            elapsed = 0
        }
        state = .idle
    }

    func togglePlayback() {
        guard let url = recordingURL else { return }
        // If currently recording or paused recording, ignore play toggles
        guard state != .recording && state != .pausedRecording else { return }

        switch state {
        case .playing:
            // Pause and store current time
            playbackPosition = player?.currentTime ?? playbackPosition
            player?.pause()
            state = .paused

        case .paused, .idle:
            do {
                if player == nil || player?.url != url {
                    player = try AVAudioPlayer(contentsOf: url)
                    player?.delegate = AudioPlayerDelegate(onFinish: {
                        DispatchQueue.main.async {
                            // Reset to idle and clear position when finished
                            state = .idle
                            playbackPosition = 0
                        }
                    })
                    player?.prepareToPlay()
                }
                // Resume from last position if available
                player?.currentTime = playbackPosition
                player?.play()
                state = .playing
            } catch {
                setError("Playback error: \(error.localizedDescription)")
            }

        case .recording, .pausedRecording:
            break
        }
    }

    func deleteRecording() {
        stopAll()
        guard let url = recordingURL else { return }
        do {
            try FileManager.default.removeItem(at: url)
            recordingURL = nil
            playbackPosition = 0
            accumulatedRecordedTime = 0
            finalRecordedTime = 0
            elapsed = 0
            state = .idle
        } catch {
            setError("Delete failed: \(error.localizedDescription)")
        }
    }

    func saveRecording() {
        stopAllAndFinalizeRecording()
        guard let url = recordingURL else {
            setError("No recording to save.")
            return
        }
        onSave(url)
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func startElapsedTimer() {
        startTime = Date()
        elapsed = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let start = startTime {
                elapsed = Date().timeIntervalSince(start)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopElapsedTimer() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }

    func cleanup() {
        stopAll()
        recorder = nil
        player = nil
        accumulatedRecordedTime = 0
        finalRecordedTime = 0
        elapsed = 0
    }
}

// MARK: - Minimal AVAudioPlayer delegate bridge
private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}

// MARK: - Control Button
private struct ControlButton: View {
    var systemName: String
    var tint: Color
    var role: ButtonRole? = nil
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(role: role) { action() } label: {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 32, weight: .regular))
                .frame(width: 56, height: 56)
                .contentShape(.rect)
        }
        .tint(tint)
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .background(
            Circle()
                .fill(Color(.tertiarySystemBackground))
                .frame(width: 72, height: 72)
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("")
    }
}

// MARK: - Preview
#Preview("Audio Recorder") {
    AudioRecorderView { url in
        print("Saved to: \(url)")
    }
    .padding()
}
