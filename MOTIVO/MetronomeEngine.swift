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

    /// Source node that generates the metronome click in a sample-accurate way.
    private lazy var sourceNode: AVAudioSourceNode = {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            return self.renderCallback(frameCount: frameCount, audioBufferList: audioBufferList)
        }
        return node
    }()

    /// Precomputed click sample matching the mixer/output format.
    private var clickBuffer: AVAudioPCMBuffer?

    // MARK: - State (control)

    private var bpm: Double = 80
    private var accentEvery: Int = 0   // 0 = no accent
    private var volume: Double = 0.7   // 0–1

    private(set) var isRunning: Bool = false

    // MARK: - State (audio-thread timing)

    /// Sample rate of the audio graph.
    private var sampleRate: Double = 44_100

    /// Number of samples between beats.
    private var samplesPerBeat: AVAudioFramePosition = 0

    /// Countdown to the next beat (in samples).
    private var samplesUntilNextBeat: AVAudioFramePosition = 0

    /// Current click playback position within clickBuffer (in samples), -1 = no click.
    private var currentClickSampleIndex: Int = -1

    /// Gain applied to the current click (includes volume + accent).
    private var currentClickGain: Float = 0.0

    /// Beat counter used for accent calculation.
    private var beatIndex: Int = 0

    /// Smoothed volume that chases the UI volume to avoid glitches.
    private var smoothedVolume: Double = 0.7

    // MARK: - Init

    init() {
        // Attach + connect source node once up-front using the mixer’s format.
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 44_100

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        prepareClickBufferIfNeeded()
        updateTiming()
    }

    // MARK: - Public API

    /// Start the metronome with the given parameters.
    func start(bpm: Int, accentEvery: Int, volume: Double) {
        self.bpm = max(30, Double(bpm))
        self.accentEvery = max(0, accentEvery)
        self.volume = max(0, min(1, volume))

        configureSession()
        prepareClickBufferIfNeeded()
        updateTiming()

        // Reset timing state for a clean start.
        beatIndex = 0
        samplesUntilNextBeat = 0   // fire on the next render callback
        currentClickSampleIndex = -1
        currentClickGain = 0.0
        smoothedVolume = self.volume

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[MetronomeEngine] Failed to start engine: \(error)")
            }
        }

        isRunning = true
    }

    /// Update parameters while running. Safe to call even if stopped.
    func update(bpm: Int, accentEvery: Int, volume: Double) {
        self.bpm = max(30, Double(bpm))
        self.accentEvery = max(0, accentEvery)
        self.volume = max(0, min(1, volume))

        // Update timing for new tempo; keep phase as-is.
        updateTiming()
    }

    /// Stop the metronome.
    func stop() {
        isRunning = false
        // We deliberately leave the AVAudioEngine running as before; the
        // source node will just output silence when isRunning == false.
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

    // MARK: - Timing helpers

    /// Recompute samplesPerBeat when BPM or sampleRate changes.
    private func updateTiming() {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sr = format.sampleRate > 0 ? format.sampleRate : sampleRate
        sampleRate = sr

        let raw = sr * 60.0 / max(bpm, 30.0)
        let spb = max(1, Int64(raw.rounded()))
        samplesPerBeat = AVAudioFramePosition(spb)

        // If we somehow ended up with no countdown, ensure we have something
        // sensible to avoid division by zero or runaway scheduling.
        if samplesUntilNextBeat <= 0 {
            samplesUntilNextBeat = 0
        }
    }

    // MARK: - Render callback

    /// Audio render callback for the source node.
    private func renderCallback(frameCount: AVAudioFrameCount,
                                audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {

        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let frameCountInt = Int(frameCount)

        // Ensure we have a click buffer; if not, output silence.
        guard let clickBuffer = clickBuffer,
              let clickChannelData = clickBuffer.floatChannelData else {
            // Zero output
            for bufferIndex in 0..<ablPointer.count {
                let buffer = ablPointer[bufferIndex]
                if let out = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    memset(out, 0, frameCountInt * MemoryLayout<Float>.size)
                }
            }
            return noErr
        }

        let clickFrameLength = Int(clickBuffer.frameLength)
        let clickChannelCount = Int(clickBuffer.format.channelCount)

        // Zero the output buffers first.
        for bufferIndex in 0..<ablPointer.count {
            let buffer = ablPointer[bufferIndex]
            if let out = buffer.mData?.assumingMemoryBound(to: Float.self) {
                memset(out, 0, frameCountInt * MemoryLayout<Float>.size)
            }
        }

        // Nothing to do if not running; we already wrote silence.
        if !isRunning {
            currentClickSampleIndex = -1
            currentClickGain = 0.0
            samplesUntilNextBeat = 0
            return noErr
        }

        // Process audio frame-by-frame for precise beat placement.
        for frame in 0..<frameCountInt {
            // Smooth volume towards target to avoid slider-induced glitches.
            let targetVolume = max(0.0, min(1.0, volume))
            let smoothingFactor = 0.002  // ~few ms time constant
            smoothedVolume += (targetVolume - smoothedVolume) * smoothingFactor
            let baseVolume = max(0.0, min(1.0, smoothedVolume))

            // Start a new beat (and click) when countdown reaches zero or below.
            if samplesUntilNextBeat <= 0 {
                // Decide if this beat is accented BEFORE incrementing the counter.
                let isAccent: Bool
                if accentEvery <= 0 {
                    isAccent = false
                } else {
                    isAccent = (beatIndex % accentEvery == 0)
                }
                beatIndex &+= 1

                // Accent: louder than normal; both scaled by smoothed volume.
                let gain = Float(baseVolume * (isAccent ? 1.25 : 0.8))
                currentClickGain = gain
                currentClickSampleIndex = 0
                samplesUntilNextBeat = samplesPerBeat
            }

            // Decrement countdown for next frame.
            samplesUntilNextBeat -= 1

            // If a click is currently playing, mix it into the output.
            if currentClickSampleIndex >= 0 && currentClickSampleIndex < clickFrameLength {
                for bufferIndex in 0..<ablPointer.count {
                    let buffer = ablPointer[bufferIndex]
                    guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }

                    // Use matching channel from clickBuffer; if fewer channels, reuse the last.
                    let srcChannelIndex = min(bufferIndex, clickChannelCount - 1)
                    let srcChannel = clickChannelData[srcChannelIndex]
                    let clickSample = srcChannel[currentClickSampleIndex]

                    out[frame] += clickSample * currentClickGain
                }

                currentClickSampleIndex += 1
                if currentClickSampleIndex >= clickFrameLength {
                    currentClickSampleIndex = -1
                    currentClickGain = 0.0
                }
            }
        }

        return noErr
    }
}
