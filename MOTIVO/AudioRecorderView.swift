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
    @State private var displayTime: TimeInterval = 0

    @State private var state: RecordingState = .idle
    @State private var errorMessage: String?

    // Timer for elapsed recording time
    @State private var startTime: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var accumulatedRecordedTime: TimeInterval = 0
    @State private var finalRecordedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var playbackTimer: Timer?
    
    @State private var wasRecordingBeforeInterruption: Bool = false
    @State private var wasPlayingBeforeInterruption: Bool = false
    @State private var observersInstalled: Bool = false

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
            HStack(spacing: 20) {
                // Delete
                ControlButton(systemName: "trash", tint: .red, role: .destructive, isEnabled: recordingURL != nil && state.isIdleLike) {
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
                ControlButton(systemName: "stop.fill", tint: .red, isEnabled: state.canStop) {
                    stopAllAndFinalizeRecording()
                }
                .accessibilityLabel("Stop")

                // Play / Pause
                ControlButton(systemName: (state == .playing) ? "pause.fill" : "play.fill", tint: .green, isEnabled: recordingURL != nil && state.canPlayToggle) {
                    togglePlayback()
                }
                .accessibilityLabel(state == .playing ? "Pause" : "Play")

                // Save
                ControlButton(systemName: "checkmark.circle.fill", tint: .blue, isEnabled: recordingURL != nil && state.isIdleLike) {
                    saveRecording()
                }
                .accessibilityLabel("Save recording")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )

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
        .onAppear {
            installObserversIfNeeded()
            // Sync display to current state on appear
            switch state {
            case .recording:
                displayTime = accumulatedRecordedTime + elapsed
            case .pausedRecording:
                displayTime = accumulatedRecordedTime
            case .playing, .paused:
                displayTime = playbackPosition
            case .idle:
                displayTime = finalRecordedTime
            }
        }
        .onDisappear {
            removeObserversIfNeeded()
            cleanup()
        }
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
        let clamped = max(0, displayTime)
        let totalTenths = Int((clamped * 10).rounded(.down))
        let wholeSeconds = totalTenths / 10
        let minutes = wholeSeconds / 60
        let seconds = wholeSeconds % 60
        let fraction = totalTenths % 10
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
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            setError("Audio session error: \(error.localizedDescription)")
        }
    }

    func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            handleInterruption(note)
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            handleRouteChange(note)
        }
        #if canImport(UIKit)
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            handleAppWillResignActive()
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            handleAppDidBecomeActive()
        }
        #endif
        observersInstalled = true
    }

    func removeObserversIfNeeded() {
        guard observersInstalled else { return }
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        nc.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        #if canImport(UIKit)
        nc.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        nc.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
        observersInstalled = false
    }

    func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            // Pause recording or playback and mark flags
            wasRecordingBeforeInterruption = (state == .recording || state == .pausedRecording)
            wasPlayingBeforeInterruption = (state == .playing)
            if state == .recording { pauseRecording() }
            if state == .playing {
                playbackPosition = player?.currentTime ?? playbackPosition
                displayTime = playbackPosition
                player?.pause()
                state = .paused
                stopPlaybackTimer()
            }
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            // Try to resume if system suggests
            if options.contains(.shouldResume) {
                if wasRecordingBeforeInterruption {
                    Task { await resumeRecording() }
                } else if wasPlayingBeforeInterruption {
                    // Only resume playback if not recording
                    if state != .recording && state != .pausedRecording {
                        player?.play()
                        state = .playing
                        startPlaybackTimer()
                    }
                }
            }
            wasRecordingBeforeInterruption = false
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged or BT lost
            if state == .recording { pauseRecording() }
            if state == .playing {
                playbackPosition = player?.currentTime ?? playbackPosition
                displayTime = playbackPosition
                player?.pause()
                state = .paused
                stopPlaybackTimer()
            }
        case .newDeviceAvailable, .categoryChange, .override, .wakeFromSleep, .noSuitableRouteForCategory, .routeConfigurationChange, .unknown:
            // Do not auto-resume recording; optionally resume playback if it was playing before
            if wasPlayingBeforeInterruption && state != .recording && state != .pausedRecording {
                // Validate there is at least one output route
                let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
                if let _ = outputs.first {
                    player?.play()
                    state = .playing
                    startPlaybackTimer()
                }
                wasPlayingBeforeInterruption = false
            }
        @unknown default:
            break
        }
    }

    func handleAppWillResignActive() {
        // Mirror interruption began
        wasRecordingBeforeInterruption = (state == .recording || state == .pausedRecording)
        wasPlayingBeforeInterruption = (state == .playing)
        if state == .recording { pauseRecording() }
        if state == .playing {
            playbackPosition = player?.currentTime ?? playbackPosition
            displayTime = playbackPosition
            player?.pause()
            state = .paused
            stopPlaybackTimer()
        }
    }

    func handleAppDidBecomeActive() {
        // Mirror interruption ended: do not force resume unless we had been playing and not recording
        if wasRecordingBeforeInterruption {
            // Allow user to resume manually; if system indicates shouldResume we'd handle in interruption handler
        }
        if wasPlayingBeforeInterruption && state != .recording && state != .pausedRecording {
            player?.play()
            state = .playing
            startPlaybackTimer()
        }
        wasRecordingBeforeInterruption = false
        wasPlayingBeforeInterruption = false
    }

    func startRecording() async {
        // Start a new recording (fresh). Only allowed when not currently recording or pausedRecording.
        guard state != .recording && state != .pausedRecording else { return }
        await configureSessionIfNeeded()
        
        let fileURL = newRecordingURL() // ensure .m4a extension

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.prepareToRecord()

            if recorder?.record() == true {
                recordingURL = fileURL
                // Reset accumulated time because this is a new file
                accumulatedRecordedTime = 0
                finalRecordedTime = 0
                displayTime = 0
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
        displayTime = accumulatedRecordedTime
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
        stopPlaybackTimer()
        // Do not change accumulatedRecordedTime here; let finalization compute total
    }

    func stopAllAndFinalizeRecording() {
        let wasRecording = (state == .recording) || (state == .pausedRecording)
        stopAll()

        // Junk Clip Suppression: discard very short accidental taps
        if let fileURL = recordingURL {
            // Measure finalized file duration using AVAudioPlayer for reliability
            var duration: TimeInterval = 0
            if let p = try? AVAudioPlayer(contentsOf: fileURL) {
                duration = p.duration
            } else {
                // Fallback: use recorder's last known currentTime if available
                duration = recorder?.currentTime ?? 0
            }

            if duration < 0.5 {
                recorder?.deleteRecording()
                try? FileManager.default.removeItem(at: fileURL)
                recorder = nil
                print("Discarded junk recording (<0.5s)")
                // Reset state for a clean slate
                recordingURL = nil
                playbackPosition = 0
                accumulatedRecordedTime = 0
                finalRecordedTime = 0
                elapsed = 0
                displayTime = 0
                state = .idle
                return
            } else {
                // Optional: confirm format consistency
                print("Saved audio: 44.1kHz AAC Mono, duration: \(duration)s")
            }
        }

        if wasRecording {
            // If we were in active or paused recording, compute total recorded time
            let total = accumulatedRecordedTime + ((state == .recording) ? elapsed : 0)
            finalRecordedTime = max(total, accumulatedRecordedTime)
            // Reset per-chunk elapsed
            elapsed = 0
            displayTime = finalRecordedTime
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
            displayTime = playbackPosition
            player?.pause()
            state = .paused
            stopPlaybackTimer()

        case .paused, .idle:
            do {
                if player == nil || player?.url != url {
                    player = try AVAudioPlayer(contentsOf: url)
                    player?.delegate = AudioPlayerDelegate(onFinish: {
                        DispatchQueue.main.async {
                            // Reset to idle and clear position when finished
                            state = .idle
                            playbackPosition = 0
                            displayTime = 0
                        }
                    })
                    player?.prepareToPlay()
                }
                // Resume from last position if available
                player?.currentTime = playbackPosition
                displayTime = player?.currentTime ?? playbackPosition
                player?.play()
                state = .playing
                startPlaybackTimer()
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
            displayTime = 0
            stopPlaybackTimer()
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
                displayTime = accumulatedRecordedTime + elapsed
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopElapsedTimer() {
        timer?.invalidate()
        timer = nil
        startTime = nil
    }

    func startPlaybackTimer() {
        // Avoid duplicating timers
        if playbackTimer != nil { return }
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if state == .playing {
                let current = player?.currentTime ?? playbackPosition
                playbackPosition = current
                displayTime = current
            }
        }
        if let t = playbackTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func cleanup() {
        stopAll()
        removeObserversIfNeeded()
        stopPlaybackTimer()
        recorder = nil
        player = nil
        accumulatedRecordedTime = 0
        finalRecordedTime = 0
        elapsed = 0
        displayTime = 0
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
                .font(.system(size: 32))
                .foregroundColor(tint.opacity(isEnabled ? 1 : 0.4))
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color(.systemGray6)).frame(width: 60, height: 60))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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

