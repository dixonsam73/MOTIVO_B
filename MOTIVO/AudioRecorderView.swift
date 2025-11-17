// AudioRecorderView.swift
// CHANGE-ID: 20251110_161547-AudioRecorderView-freezeInitialZoom
// SCOPE: Freeze initial progressive zoom as constant waveform density; add samplesPerSecond param; timers on .common; no other logic changes.

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
    
    @State private var stagedID: UUID? = nil

    private let ephemeralMediaFlagKey = "ephemeralSessionHasMedia_v1"

    // Timer for elapsed recording time
    @State private var startTime: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var accumulatedRecordedTime: TimeInterval = 0
    @State private var finalRecordedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var playbackTimer: Timer?

    // Waveform metering
    @State private var waveformTimer: Timer?
    @State private var waveformSamples: [CGFloat] = []
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
                            await resumeRecording()
                        } else {
                            await startRecording()
                        }
                    }
                }
                .accessibilityLabel(state == .recording ? "Pause recording" : (state == .pausedRecording ? "Resume recording" : "Start recording"))

                // Stop
                ControlButton(systemName: "stop.fill", tint: tintStopDelete, isEnabled: state.canStop) {
                    stopAllAndFinalizeRecording()
                }
                .accessibilityLabel("Stop")

                // Play / Pause
                ControlButton(systemName: (state == .playing) ? "pause.fill" : "play.fill", tint: tintPlay, isEnabled: recordingURL != nil && state.canPlayToggle) {
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
            .cardSurface(padding: 12)

            // Decorative waveform indicator
            WaveformIndicatorView(
                samples: waveformSamples,
                color: Color(red: 0.36, green: 0.60, blue: 0.52), // align with media accents
                background: Theme.Colors.surface(colorScheme),
                writeIndex: waveformWriteIndex,
                hasWrapped: waveformHasWrapped,
                samplesPerSecond: 1.0 / waveformSampleRate
            )
            .frame(height: 44)
            .opacity(state == .recording ? 1 : (waveformSamples.isEmpty ? 0 : ((state == .paused || state == .pausedRecording) ? 0.6 : 0.85)))
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.cardStroke(colorScheme), lineWidth: 1)
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
            Task { try? await StagingStore.bootstrap() }
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

    func ensureRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                continuation.resume(returning: true)
            case .denied:
                continuation.resume(returning: false)
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            @unknown default:
                continuation.resume(returning: false)
            }
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
                startWaveform()
                state = .recording
                errorMessage = nil
                UserDefaults.standard.set(true, forKey: ephemeralMediaFlagKey)
                #if DEBUG
                print("[AudioRecorder] Ephemeral flag set true (recording started)")
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
        // Add the elapsed chunk to accumulated time and stop the timer
        accumulatedRecordedTime += elapsed
        stopElapsedTimer()
        // Reset per-chunk elapsed
        elapsed = 0
        displayTime = accumulatedRecordedTime
        state = .pausedRecording
        stopWaveformTimer()
    }

    func resumeRecording() async {
        guard state == .pausedRecording else { return }
        do {
            // Ensure session is active
            await configureSessionIfNeeded()
            if recorder?.record() == true {
                recorder?.isMeteringEnabled = true
                startElapsedTimer()
                startWaveform()
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
        stopWaveformTimer()
        clearWaveform()
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
                // Reset state for a clean slate
                recordingURL = nil
                playbackPosition = 0
                accumulatedRecordedTime = 0
                finalRecordedTime = 0
                elapsed = 0
                displayTime = 0
                state = .idle
                UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
                return
            } else {
                // Optional: confirm format consistency
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
            stopWaveformTimer()
            clearWaveform()
            state = .idle
            UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
            #if DEBUG
            print("[AudioRecorder] Deleted recording; ephemeral flag reset false")
            #endif
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
        // Mirror VideoRecorderView staging flow - additive only
        Task {
            try? await StagingStore.bootstrap()
            let originalURL = url
            let computedDuration: TimeInterval = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    var duration: TimeInterval = 0
                    if finalRecordedTime > 0 {
                        duration = finalRecordedTime
                    } else if let player = try? AVAudioPlayer(contentsOf: originalURL) {
                        duration = player.duration
                    }
                    continuation.resume(returning: duration)
                }
            }
            do {
                let ref = try await StagingStore.saveNew(
                    from: originalURL,
                    kind: .audio,
                    suggestedName: originalURL.deletingPathExtension().lastPathComponent,
                    duration: computedDuration,
                    poster: nil
                )
                await MainActor.run { self.stagedID = ref.id }
                // Best-effort cleanup of the original temporary audio file after successful staging
                let fm = FileManager.default
                if fm.fileExists(atPath: originalURL.path) {
                    do { try fm.removeItem(at: originalURL) } catch { print("[AudioRecorder] Cleanup original audio failed: \(error)") }
                }
                UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
                #if DEBUG
                print("[AudioRecorder] Saved and cleaned original; ephemeral flag reset false")
                #endif
                // If the audio recorder had any additional temp artefacts on disk for this save, delete them here (none by default)
            } catch {
                // Staging failed — keep original files; no further action.
                #if DEBUG
                print("[AudioRecorder] Staging failed, keeping original: \(error)")
                #endif
            }
        }
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func startElapsedTimer() {
        startTime = Date()
        elapsed = 0
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
                if let start = startTime {
                    elapsed = Date().timeIntervalSince(start)
                    displayTime = accumulatedRecordedTime + elapsed
                }
            }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
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
            DispatchQueue.main.async {
                if state == .playing {
                    let current = player?.currentTime ?? playbackPosition
                    playbackPosition = current
                    displayTime = current
                }
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
        stopWaveformTimer()
        clearWaveform()
        recorder = nil
        player = nil
        accumulatedRecordedTime = 0
        finalRecordedTime = 0
        elapsed = 0
        displayTime = 0
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
        #if DEBUG
        print("[AudioRecorder] Cleanup on disappear; ephemeral flag reset false")
        #endif
    }
    
    func clearAllStagedAudio() {
        Task {
            try? await StagingStore.bootstrap()
            let refs = StagingStore.list().filter { $0.kind == .audio }
            for ref in refs { StagingStore.remove(ref) }
        }
    }
    
    // MARK: - Waveform metering
    func startWaveform() {
        if waveformTimer != nil { return }
        // Prepare buffer size based on duration and sample rate
        let capacity = max(1, Int((waveformDuration / waveformSampleRate).rounded()))
        if waveformSamples.count != capacity {
            // Prefill with a small visible baseline so we render a stable window from frame 0.
            let baseline: CGFloat = 0.02
            waveformSamples = Array(repeating: baseline, count: capacity)
            waveformWriteIndex = 0
            waveformHasWrapped = false
        }
        stopWaveformTimer()
        let newTimer = Timer.scheduledTimer(withTimeInterval: waveformSampleRate, repeats: true) { _ in
            DispatchQueue.main.async {
                guard state == .recording else { return }
                recorder?.updateMeters()
                let db = recorder?.averagePower(forChannel: 0) ?? -160
                // Convert dBFS to linear 0...1 and ensure a minimum visible amplitude
                let linear = max(0, min(1, pow(10.0, 0.06 * CGFloat(db))))
                let visible = max(linear, 0.01)
                // Less damping so early frames move more
                let count = waveformSamples.count
                let prevIndex = count > 0 ? (waveformWriteIndex - 1 + count) % count : 0
                let previous = count > 0 ? waveformSamples[prevIndex] : 0
                let smoothedRaw = previous * 0.5 + visible * 0.5
                // Ensure a very small but visible baseline for quiet rooms
                let smoothed = max(smoothedRaw, 0.015)
                writeWaveformSample(smoothed)
            }
        }
        waveformTimer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func stopWaveformTimer() {
        waveformTimer?.invalidate()
        waveformTimer = nil
    }

    func writeWaveformSample(_ value: CGFloat) {
        if waveformSamples.isEmpty { return }
        waveformSamples[waveformWriteIndex] = value
        let nextIndex = (waveformWriteIndex + 1) % waveformSamples.count
        // If next index wraps to 0, we've completed at least one full window
        if nextIndex == 0 { waveformHasWrapped = true }
        waveformWriteIndex = nextIndex
    }

    func clearWaveform() {
        waveformSamples.removeAll(keepingCapacity: false)
        waveformWriteIndex = 0
        waveformHasWrapped = false
    }
    
    // MARK: - Audio session observers
    func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            handleAudioInterruption(note)
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            handleRouteChange(note)
        }
    }

    func removeObserversIfNeeded() {
        guard observersInstalled else { return }
        observersInstalled = false
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }

    func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Remember what we were doing
            wasRecordingBeforeInterruption = (state == .recording || state == .pausedRecording)
            wasPlayingBeforeInterruption = (state == .playing)
            // Pause ongoing work
            if state == .recording { pauseRecording() }
            if state == .playing { togglePlayback() } // will transition to .paused
        case .ended:
            // Optionally resume if the system allows
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
            let shouldResume = optionsValue.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            if shouldResume {
                Task { @MainActor in
                    if wasRecordingBeforeInterruption && state == .pausedRecording {
                        await resumeRecording()
                    } else if wasPlayingBeforeInterruption && state == .paused {
                        togglePlayback()
                    }
                    wasRecordingBeforeInterruption = false
                    wasPlayingBeforeInterruption = false
                }
            }
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
            // Headphones unplugged etc. Pause playback to avoid blasting speaker unexpectedly
            if state == .playing {
                togglePlayback()
            }
        default:
            break
        }
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

// MARK: - WaveformIndicatorView
private struct WaveformIndicatorView: View {
    @Environment(\.colorScheme) private var colorScheme

    var samples: [CGFloat]
    var color: Color
    var background: Color
    var writeIndex: Int = 0
    var hasWrapped: Bool = false
    var samplesPerSecond: Double = 30.0

    @State private var frozenRenderBars: Int? = nil
    private let freezeSeconds: Double = 3.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                Canvas { context, size in
                    // Draw using a stable, locked density/stride. No state mutations here.
                    guard !samples.isEmpty else { return }

                    let barCount = samples.count              // ring buffer capacity
                    let barSpacing: CGFloat = 2
                    let minPixel = max(1.0 / UIScreen.main.scale, 1.0)
                    let availableWidth = size.width
                    let midY = size.height / 2
                    let maxHeight = size.height

                    // How many samples are actually written so far.
                    let writtenCount: Int = {
                        if hasWrapped { return barCount }
                        return max(0, min(barCount, writeIndex))
                    }()
                    guard writtenCount > 0 else { return }

                    // Determine target bars from frozen value or a sensible default.
                    let defaultTarget = max(1, Int((freezeSeconds * samplesPerSecond).rounded()))
                    let targetBars = max(1, min(frozenRenderBars ?? defaultTarget, barCount))
                    let renderBars = max(1, min(targetBars, writtenCount))

                    // Lock stride based on capacity so speed/density are stable from frame 0.
                    let stride = max(1, barCount / max(1, targetBars))

                    // Bar width derived from renderBars so bars stay readable.
                    let rawBarWidth = (availableWidth - CGFloat(renderBars - 1) * barSpacing) / CGFloat(renderBars)
                    let barWidth = max(minPixel, floor(rawBarWidth))
                    let step = barWidth + barSpacing

                    // Index math: newest sample index in the circular buffer.
                    let newest = (writeIndex - 1 + barCount) % barCount

                    // Draw oldest -> newest across full width using downsampling with locked stride.
                    for i in 0..<renderBars {
                        let idxBack = (renderBars - 1 - i) * stride
                        let srcIdx = (newest - idxBack + barCount) % barCount
                        let v = samples[srcIdx]
                        let clamped = max(0, min(1, v))
                        let h = clamped * maxHeight
                        let x = CGFloat(i) * step
                        let rect = CGRect(x: x, y: midY - h/2, width: barWidth, height: h)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: barWidth / 2),
                            with: .color(color.opacity(0.95))
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.cardStroke(colorScheme), lineWidth: 1)
            )
            .onChange(of: writeIndex) { _ in
                // Defensive re-freeze if needed on late rotations etc.
                if frozenRenderBars == nil {
                    let threshold = max(1, Int(freezeSeconds * samplesPerSecond))
                    let written = hasWrapped ? samples.count : max(0, writeIndex)
                    if written >= threshold {
                        DispatchQueue.main.async {
                            frozenRenderBars = threshold
                        }
                    }
                }
            }
            .onAppear {
                if frozenRenderBars == nil {
                    let threshold = max(1, Int(freezeSeconds * samplesPerSecond))
                    DispatchQueue.main.async {
                        frozenRenderBars = threshold
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview
#Preview("Audio Recorder") {
    AudioRecorderView { url in
    }
    .padding()
}

