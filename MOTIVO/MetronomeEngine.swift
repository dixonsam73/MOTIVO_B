// MetronomeEngine.swift
// Simple click generator with optional accent-every-N-beats.
//
// Public API (file-scope):
//   let engine = MetronomeEngine()
//   engine.start(bpm: 80, accentEvery: 4, volume: 0.7)
//   engine.update(bpm: 96, accentEvery: 3, volume: 0.8)
//   engine.stop()

import Foundation
import AVFoundation

final class MetronomeEngine {

    // MARK: - Audio

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?

    // MARK: - Timer

    private let timerQueue = DispatchQueue(label: "MetronomeEngine.Timer")
    private var timer: DispatchSourceTimer?

    // MARK: - State

    private var bpm: Double = 80
    private var accentEvery: Int = 0   // 0 = no accent
    private var volume: Double = 0.7   // 0–1

    private var beatIndex: Int = 0
    private(set) var isRunning: Bool = false

    // MARK: - Init

    init() {
        // Attach + connect player once up-front using the mixer’s format
        engine.attach(player)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        prepareClickBufferIfNeeded()
    }

    // MARK: - Public API

    /// Start the metronome with the given parameters.
    func start(bpm: Int, accentEvery: Int, volume: Double) {
        self.bpm = max(30, Double(bpm))
        self.accentEvery = max(0, accentEvery)
        self.volume = max(0, min(1, volume))

        configureSession()
        prepareClickBufferIfNeeded()

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[MetronomeEngine] Failed to start engine: \(error)")
            }
        }

        player.play()
        beatIndex = 0
        startTimer()
    }

    /// Update parameters while running. Safe to call even if stopped.
    func update(bpm: Int, accentEvery: Int, volume: Double) {
        self.bpm = max(30, Double(bpm))
        self.accentEvery = max(0, accentEvery)
        self.volume = max(0, min(1, volume))

        if isRunning {
            restartTimer()
        }
    }

    /// Stop the metronome.
    func stop() {
        stopTimer()
        player.stop()
        isRunning = false
    }

    // MARK: - Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[MetronomeEngine] Audio Session error: \(error)")
        }
    }

    // MARK: - Click buffer

    /// Prepare a short click sample whose channel count matches the mixer/output.
    private func prepareClickBufferIfNeeded() {
        if clickBuffer != nil { return }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let clickLengthSeconds = 0.03  // ~30 ms
        let frameCount = AVAudioFrameCount(sampleRate * clickLengthSeconds)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("[MetronomeEngine] Failed to create click buffer")
            return
        }

        buffer.frameLength = frameCount
        let channels = Int(format.channelCount)

        for channel in 0..<channels {
            guard let ptr = buffer.floatChannelData?[channel] else { continue }

            for i in 0..<Int(frameCount) {
                let t = Double(i)
                let total = Double(frameCount)

                // Simple attack / decay envelope
                let progress = t / total
                let attack = min(1.0, progress / 0.15)
                let release = min(1.0, (1.0 - progress) / 0.4)
                let envelope = max(0.0, min(1.0, min(attack, release)))

                // White-ish noise with some bright tone for a neutral click
                let noise = Double.random(in: -1.0...1.0)
                let tone = sin(2.0 * Double.pi * 2000.0 * (t / sampleRate))
                let sample = Float((noise * 0.25 + tone * 0.75) * envelope)

                ptr[i] = sample
            }
        }

        clickBuffer = buffer
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()

        guard bpm > 0 else { return }
        let interval = max(0.03, 60.0 / bpm) // floor to avoid pathological values

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }

        self.timer = timer
        isRunning = true
        timer.resume()
    }

    private func restartTimer() {
        guard isRunning else { return }
        startTimer()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Tick

    private func tick() {
        guard let buffer = clickBuffer else { return }

        // Decide if this beat is accented BEFORE incrementing the counter.
        let isAccent: Bool
        if accentEvery <= 0 {
            isAccent = false
        } else {
            isAccent = (beatIndex % accentEvery == 0)
        }
        beatIndex &+= 1

        // Apply relative gain for accent vs normal beat.
        let base = max(0.0, min(1.0, volume))
        let gain = Float(base * (isAccent ? 1.25 : 0.8))  // gently louder accent
        player.volume = gain

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[MetronomeEngine] Restart failed: \(error)")
            }
        }
    }
}
