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

    /// Precomputed click samples for normal and accented beats.
    private var normalClickBuffer: AVAudioPCMBuffer?
    private var accentClickBuffer: AVAudioPCMBuffer?

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

    /// Current click playback position within the active click buffer (in samples), -1 = no click.
    private var currentClickSampleIndex: Int = -1

    /// Gain applied to the current click (includes volume + accent).
    private var currentClickGain: Float = 0.0

    /// Beat counter used for accent calculation.
    private var beatIndex: Int = 0

    /// Smoothed volume that chases the UI volume to avoid glitches.
    private var smoothedVolume: Double = 0.7

    /// Whether the currently playing click (if any) is an accent.
    private var currentClickIsAccent: Bool = false

    // MARK: - Init

    init() {
        // Attach + connect source node once up-front using the mixer’s format.
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 44_100

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        prepareClickBuffersIfNeeded()
        updateTiming()
    }

    // MARK: - Public API

    /// Start the metronome with the given parameters.
    func start(bpm: Int, accentEvery: Int, volume: Double) {
        self.bpm = max(30, Double(bpm))
        self.accentEvery = max(0, accentEvery)
        self.volume = max(0, min(1, volume))

        configureSession()
        prepareClickBuffersIfNeeded()
        updateTiming()

        // Reset timing state for a clean start.
        beatIndex = 0
        samplesUntilNextBeat = 0   // fire on the next render callback
        currentClickSampleIndex = -1
        currentClickGain = 0.0
        smoothedVolume = self.volume
        currentClickIsAccent = false

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
        // We deliberately leave the AVAudioEngine running; the
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

    // MARK: - Click buffers

    /// Prepare short click samples whose channel count matches the mixer/output.
    private func prepareClickBuffersIfNeeded() {
        if normalClickBuffer != nil && accentClickBuffer != nil { return }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let clickLengthSeconds = 0.035  // ~35 ms, slightly rounder
        let frameCount = AVAudioFrameCount(sampleRate * clickLengthSeconds)

        func makeClickBuffer(frequency: Double) -> AVAudioPCMBuffer? {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("[MetronomeEngine] Failed to create click buffer")
                return nil
            }

            buffer.frameLength = frameCount
            let channels = Int(format.channelCount)
            let totalFrames = Int(frameCount)

            for channel in 0..<channels {
                guard let ptr = buffer.floatChannelData?[channel] else { continue }

                for i in 0..<totalFrames {
                    let t = Double(i)
                    let total = Double(totalFrames)
                    let progress = t / total

                    // Envelope: very quick attack, then smooth decay.
                    let attackPortion = 0.04
                    let attack = progress < attackPortion
                        ? (progress / attackPortion)
                        : 1.0

                    let decayPortion = max(0.0001, 1.0 - attackPortion)
                    let decayProgress = max(0.0, (progress - attackPortion) / decayPortion)
                    let decay = max(0.0, 1.0 - decayProgress)

                    let envelope = max(0.0, min(1.0, attack * decay))

                    // "Woodblock-ish": fundamental plus a couple of short harmonics.
                    let fundamental = sin(2.0 * Double.pi * frequency * (t / sampleRate))
                    let second = sin(2.0 * Double.pi * frequency * 2.0 * (t / sampleRate))
                    let third = sin(2.0 * Double.pi * frequency * 3.0 * (t / sampleRate))

                    let tone = fundamental * 0.8 + second * 0.35 + third * 0.2

                    // Global scale to keep headroom; per-beat gain handles loudness.
                    let sample = Float(tone * envelope * 0.7)

                    ptr[i] = sample
                }
            }

            return buffer
        }

        // Normal beat: lower, warmer tone.
        // Accent beat: slightly higher pitch, same envelope.
        normalClickBuffer = makeClickBuffer(frequency: 900.0)   // Hz
        accentClickBuffer = makeClickBuffer(frequency: 1350.0)  // Hz
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

        // Ensure we have click buffers; if not, output silence.
        guard let normalBuffer = normalClickBuffer,
              let normalChannelData = normalBuffer.floatChannelData,
              let accentBuffer = accentClickBuffer,
              let accentChannelData = accentBuffer.floatChannelData else {
            // Zero output
            for bufferIndex in 0..<ablPointer.count {
                let buffer = ablPointer[bufferIndex]
                if let out = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    memset(out, 0, frameCountInt * MemoryLayout<Float>.size)
                }
            }
            return noErr
        }

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
            currentClickIsAccent = false
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

                // Accent: full-volume; normal beats softer.
                let gain = Float(baseVolume * (isAccent ? 1.0 : 0.35))
                currentClickGain = gain
                currentClickSampleIndex = 0
                currentClickIsAccent = isAccent
                samplesUntilNextBeat = samplesPerBeat
            }

            // Decrement countdown for next frame.
            samplesUntilNextBeat -= 1

            // If a click is currently playing, mix it into the output.
            if currentClickSampleIndex >= 0 {
                // Pick the correct buffer for this click.
                let activeBuffer = currentClickIsAccent ? accentBuffer : normalBuffer
                let activeChannelData = currentClickIsAccent ? accentChannelData : normalChannelData
                let clickFrameLength = Int(activeBuffer.frameLength)
                let clickChannelCount = Int(activeBuffer.format.channelCount)

                if currentClickSampleIndex < clickFrameLength {
                    for bufferIndex in 0..<ablPointer.count {
                        let buffer = ablPointer[bufferIndex]
                        guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }

                        let srcChannelIndex = min(bufferIndex, clickChannelCount - 1)
                        let srcChannel = activeChannelData[srcChannelIndex]
                        let clickSample = srcChannel[currentClickSampleIndex]

                        out[frame] += clickSample * currentClickGain
                    }

                    currentClickSampleIndex += 1
                    if currentClickSampleIndex >= clickFrameLength {
                        currentClickSampleIndex = -1
                        currentClickGain = 0.0
                    }
                } else {
                    currentClickSampleIndex = -1
                    currentClickGain = 0.0
                }
            }
        }

        return noErr
    }
}
