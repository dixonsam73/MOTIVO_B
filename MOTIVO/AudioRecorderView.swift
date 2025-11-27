// AudioRecorderView.swift
// CHANGE-ID: 20251127_ContinuousModeToggle
// SCOPE: Add RecordingMode state + segmented picker UI; no call-site, storage, or audio logic changes.

// Motivo
// Created by Assistant on 2025-10-20

import SwiftUI
import AVFoundation
import AVKit

/// A lightweight, self-contained audio recorder view using AVAudioRecorder.
/// Stores audio files in the app's Documents directory and returns the saved URL via `onSave`.
struct AudioRecorderView: View {
    // MARK: - Public API
    var onSave: (URL) -> Void
    @EnvironmentObject private var stagingStore: StagingStoreObject
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State
    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var recordingURL: URL?
    @State private var playbackPosition: TimeInterval = 0
    @State private var displayTime: TimeInterval = 0

    @State private var state: RecordingState = .idle
    @State private var errorMessage: String?
    @State private var recordingMode: RecordingMode = .standard
    
    @State private var stagedID: UUID? = nil

    private let ephemeralMediaFlagKey = "ephemeralSessionHasMedia_v1"

    // Timer for elapsed recording time
    @State private var startTime: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var accumulatedRecordedTime: TimeInterval = 0
    @State private var finalRecordedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var playbackTimer: Timer?

    // MARK: - Waveform state (for current recording or playback)
    @State private var renderBars: [CGFloat] = []
    @State private var frozenRenderBars: [CGFloat]? = nil
    @State private var waveformSamples: [Float] = []
    @State private var waveformWriteIndex: Int = 0
    @State private var waveformHasWrapped: Bool = false
    private let waveformSampleRate: TimeInterval = 1.0 / 30.0 // ~30 Hz
    private let waveformDuration: TimeInterval = 8.0 // seconds of history
    
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
                    .accessibilityLabel("Elapsed time \(timeString)")
            }
            .frame(maxWidth: .infinity)
            // Recording mode
            HStack(spacing: 12) {
                Text("Mode")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Recording mode", selection: $recordingMode) {
                    Text("Standard").tag(RecordingMode.standard)
                    Text("Continuous").tag(RecordingMode.continuous)
                }
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording mode")
            .accessibilityValue(recordingMode == .standard ? "Standard" : "Continuous")
            

            // Controls
            let tintRecord = Color(red: 0.92, green: 0.30, blue: 0.28)       // soft coral/red
            let tintStopDelete = Color(red: 0.72, green: 0.42, blue: 0.40)   // muted clay / gray-red
            let tintPlay = Color(red: 0.36, green: 0.60, blue: 0.52)         // desaturated mint / slate green
            let tintConfirm = Color(red: 0.38, green: 0.48, blue: 0.62)      // slate blue-gray

            HStack(spacing: 20) {
                // Delete
                ControlButton(systemName: "trash", tint: tintStopDelete, role: .destructive, isEnabled: recordingURL != nil && state.isIdleLike) {
                    deleteRecording()
                }
                .accessibilityLabel("Delete recording")

                // Record / Pause (recording)
                ControlButton(
                    systemName: (state == .recording) ? "pause.circle.fill" : "record.circle.fill",
                    tint: tintRecord,
                    isEnabled: state.canRecord || state == .recording
                ) {
                    Task {
                        if state == .recording {
                            pauseRecording()
                        } else if state == .pausedRecording {
                            resumeRecording()
                        } else {
                            await startRecording()
                        }
                    }
                }
                .accessibilityLabel(state == .recording ? "Pause recording" :
                                    (state == .pausedRecording ? "Resume recording" : "Start recording"))

                // Stop
                ControlButton(systemName: "stop.circle.fill", tint: tintStopDelete, isEnabled: state.canStop) {
                    stopAll()
                }
                .accessibilityLabel("Stop")

                // Play / Pause
                ControlButton(systemName: (state == .playing || state == .paused) ? "pause.circle.fill" : "play.circle.fill",
                              tint: tintPlay,
                              isEnabled: recordingURL != nil && state.canPlayToggle) {
                    togglePlayback()
                }
                .accessibilityLabel(state == .playing ? "Pause" : "Play")

                // Save
                ControlButton(systemName: "checkmark.circle.fill", tint: tintConfirm, isEnabled: recordingURL != nil && state.isIdleLike) {
                    saveRecording()
                }
                .accessibilityLabel("Save recording")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Waveform
            WaveformView(
                samples: frozenRenderBars ?? renderBars,
                isRecording: state == .recording,
                isPlaying: state == .playing
            )
            .frame(height: 80)
            .padding(.top, 8)
            .accessibilityHidden(true)

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
            Theme.Colors.surface(colorScheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 10)
        .padding()
        .onAppear {
            setupWaveformBuffer()
            installObserversIfNeeded()
        }
        .onDisappear {
            stopAll()
            stopElapsedTimer()
            cleanupWaveform()
            removeObservers()
        }
    }

    // MARK: - Public Helpers

    func documentsDirectory() -> URL {
        // Using temporaryDirectory per your existing implementation
        FileManager.default.temporaryDirectory
    }

    func newRecordingURL() -> URL {
        let filename = "motivo_rec_\(UUID().uuidString).m4a"
        return documentsDirectory().appendingPathComponent(filename)
    }

    // MARK: - Recording State / Title

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
    enum RecordingMode: String, CaseIterable {
        case standard
        case continuous
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
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Recording Logic

    func ensureRecordPermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    session.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func configureSessionIfNeeded() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true, options: [])
        } catch {
            setError("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    func startRecording() async {
        // Start a new recording (fresh). Only allowed when not currently recording or pausedRecording.
        guard state != .recording && state != .pausedRecording else { return }
        let hasPermission = await ensureRecordPermission()
        guard hasPermission else {
            setError("Microphone permission is required to record.")
            return
        }
        await configureSessionIfNeeded()
        
        let fileURL = newRecordingURL() // ensure .m4a extension

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        stopAll()
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
                startWaveform()
                state = .recording
                errorMessage = nil
                UserDefaults.standard.set(true, forKey: ephemeralMediaFlagKey)
                #if DEBUG
                print("[AudioRecorder] Ephemeral flag set true (recording started, mode=\(recordingMode.rawValue))")
                #endif
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
        stopElapsedTimer()
        state = .pausedRecording
    }

    func resumeRecording() {
        guard state == .pausedRecording else { return }
        recorder?.record()
        startElapsedTimer()
        state = .recording
    }

    func stopRecording() {
        guard state == .recording || state == .pausedRecording else { return }
        recorder?.stop()
        recorder = nil
        stopElapsedTimer()
        stopWaveformAndFreeze()
        finalRecordedTime = accumulatedRecordedTime
        displayTime = finalRecordedTime
        state = .idle
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        stopPlaybackTimer()
        stopWaveformAndFreeze()
        displayTime = finalRecordedTime
        state = .idle
    }

    func stopAll() {
        if state == .recording || state == .pausedRecording {
            stopRecording()
        }
        if state == .playing || state == .paused {
            stopPlayback()
        }
        state = .idle
    }

    func saveRecording() {
        guard let url = recordingURL else {
            setError("No recording to save.")
            return
        }

        stopAll()

        // Reset ephemeral flag once we hand the file off to the caller / staging
        UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
        #if DEBUG
        print("[AudioRecorder] Ephemeral flag reset false (saveRecording)")
        #endif

        onSave(url)
    }

    func deleteRecording() {
        stopAll()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        displayTime = 0
        accumulatedRecordedTime = 0
        finalRecordedTime = 0
        state = .idle
        errorMessage = nil
        clearWaveform()
    }

    func togglePlayback() {
        guard let url = recordingURL else { return }

        switch state {
        case .playing:
            player?.pause()
            stopPlaybackTimer()
            state = .paused
        case .paused:
            player?.play()
            startPlaybackTimer()
            state = .playing
        case .idle, .pausedRecording, .recording:
            do {
                stopAll()
                player = try AVAudioPlayer(contentsOf: url)
                player?.isMeteringEnabled = true
                player?.prepareToPlay()
                player?.play()
                displayTime = 0 // playback starts at zero
                startPlaybackTimer()
                startWaveform()
                state = .playing
            } catch {
                setError("Playback error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Elapsed Time Timer

    func startElapsedTimer() {
        stopElapsedTimer()
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let startTime else { return }
            let now = Date()
            elapsed = now.timeIntervalSince(startTime)
            displayTime = accumulatedRecordedTime + elapsed
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopElapsedTimer() {
        accumulatedRecordedTime += elapsed
        elapsed = 0
        startTime = nil
        timer?.invalidate()
        timer = nil
        displayTime = accumulatedRecordedTime
    }

    // MARK: - Playback Timer

    func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackPosition = 0
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let player else { return }
            self.playbackPosition = player.currentTime
            self.displayTime = player.currentTime
            if !player.isPlaying {
                self.stopPlayback()
            }
        }
        if let playbackTimer {
            RunLoop.main.add(playbackTimer, forMode: .common)
        }
    }

    func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Error Handling

    func setError(_ message: String) {
        withAnimation {
            errorMessage = message
        }
    }

    // MARK: - Waveform Helpers (Recording + Playback)

    func setupWaveformBuffer() {
        let sampleCount = Int(waveformDuration / waveformSampleRate)
        waveformSamples = Array(repeating: 0, count: sampleCount)
        waveformWriteIndex = 0
        waveformHasWrapped = false
        updateRenderBarsFromSamples()
    }

    func cleanupWaveform() {
        waveformSamples.removeAll()
        renderBars.removeAll()
        frozenRenderBars = nil
    }

    func clearWaveform() {
        let sampleCount = Int(waveformDuration / waveformSampleRate)
        waveformSamples = Array(repeating: 0, count: sampleCount)
        waveformWriteIndex = 0
        waveformHasWrapped = false
        frozenRenderBars = nil
        updateRenderBarsFromSamples()
    }

    func startWaveform() {
        frozenRenderBars = nil
        startMeteringTimer()
    }

    func stopWaveformAndFreeze() {
        stopMeteringTimer()
        frozenRenderBars = renderBars
    }

    @State private var meteringTimer: Timer?

    func startMeteringTimer() {
        stopMeteringTimer()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: waveformSampleRate, repeats: true) { _ in
            sampleWaveform()
        }
        if let meteringTimer {
            RunLoop.main.add(meteringTimer, forMode: .common)
        }
    }

    func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    func sampleWaveform() {
        // If recording, sample from recorder
        if let recorder, state == .recording {
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            let normalized = normalizedPower(level)
            writeWaveformSample(normalized)
        }
        // If playing, sample from player
        else if let player, (state == .playing || state == .paused) {
            player.updateMeters()
            let level = player.averagePower(forChannel: 0)
            let normalized = normalizedPower(level)
            writeWaveformSample(normalized)
        }
        // Otherwise, gently decay toward zero
        else {
            writeWaveformSample(0.0)
        }
    }

    func normalizedPower(_ decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        let minDb: Float = -60
        if decibels <= minDb {
            return 0
        }
        let normalized = (decibels - minDb) / -minDb
        return max(0, min(1, normalized))
    }

    func writeWaveformSample(_ sample: Float) {
        guard !waveformSamples.isEmpty else { return }
        waveformSamples[waveformWriteIndex] = sample
        waveformWriteIndex += 1
        if waveformWriteIndex >= waveformSamples.count {
            waveformWriteIndex = 0
            waveformHasWrapped = true
        }
        updateRenderBarsFromSamples()
    }

    func updateRenderBarsFromSamples() {
        guard !waveformSamples.isEmpty else { return }
        let orderedSamples: [Float]
        if waveformHasWrapped {
            let head = waveformSamples[waveformWriteIndex..<waveformSamples.count]
            let tail = waveformSamples[0..<waveformWriteIndex]
            orderedSamples = Array(head + tail)
        } else {
            orderedSamples = waveformSamples
        }

        // Map floats [0,1] to CGFloat heights
        let bars = orderedSamples.map { sample -> CGFloat in
            let minHeight: CGFloat = 0.1
            let height = CGFloat(sample)
            return max(minHeight, height)
        }
        renderBars = bars
    }

    // MARK: - Interruption Handling

    func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleInterruption(notification: notification)
        }

        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleRouteChange(notification: notification)
        }
    }

    func removeObservers() {
        guard observersInstalled else { return }
        observersInstalled = false
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
    }

    func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            wasRecordingBeforeInterruption = (state == .recording)
            wasPlayingBeforeInterruption = (state == .playing)
            if wasRecordingBeforeInterruption {
                pauseRecording()
            }
            if wasPlayingBeforeInterruption {
                togglePlayback()
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // We don't auto-resume; user must explicitly resume
                }
            }
        @unknown default:
            break
        }
    }

    func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable, .categoryChange, .override, .wakeFromSleep, .noSuitableRouteForCategory, .routeConfigurationChange:
            if state == .playing {
                togglePlayback()
            }
        default:
            break
        }
    }
}

// MARK: - ControlButton

private struct ControlButton: View {
    let systemName: String
    let tint: Color
    var role: ButtonRole? = nil
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(role: role == .destructive ? .destructive : nil) {
            if isEnabled {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 36, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isEnabled ? tint : tint.opacity(0.3))
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 4, y: 2)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - WaveformView

private struct WaveformView: View {
    let samples: [CGFloat]
    let isRecording: Bool
    let isPlaying: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(samples.count, 1)
            let barWidth = max(width / CGFloat(count), 1)

            HStack(alignment: .center, spacing: 0) {
                ForEach(samples.indices, id: \.self) { index in
                    let sample = samples[index]
                    Capsule()
                        .frame(width: barWidth, height: max(height * sample, 2))
                        .foregroundStyle(color(for: index))
                }
            }
        }
    }

    func color(for index: Int) -> Color {
        if isRecording {
            return Color.red.opacity(0.8)
        } else if isPlaying {
            return Color.blue.opacity(0.8)
        } else {
            return Color.secondary.opacity(0.4)
        }
    }
}

// MARK: - Preview

struct AudioRecorderView_Previews: PreviewProvider {
    static var previews: some View {
        AudioRecorderView { url in
            print("Saved: \(url)")
        }
        .environmentObject(StagingStoreObject())
        .padding()
        .background(Color.black.opacity(0.1))
        .previewLayout(.sizeThatFits)
    }
}

