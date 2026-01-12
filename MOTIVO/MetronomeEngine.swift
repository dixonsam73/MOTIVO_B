// MetronomeEngine.swift
// Sample-based click generator with optional accent-every-N-beats.
//
// Public API (file-scope):
//   let engine = MetronomeEngine()
//   engine.start(bpm: 80, accentEvery: 4, volume: 0.7)
//   engine.update(bpm: 96, accentEvery: 3, volume: 0.8)
//   engine.stop()

import Foundation
import AVFoundation

final class MetronomeEngine {

    // Ensure only one metronome instance is ever “actively clicking”.
    // Strong reference so the active engine survives view teardown / background.
    private static var activeInstance: MetronomeEngine?

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

    /// Preloaded click samples for normal and accented beats.
    private var normalClickBuffer: AVAudioPCMBuffer?
    private var accentClickBuffer: AVAudioPCMBuffer?

    // MARK: - State (control)

    private var bpm: Double = 80
    private var accentEvery: Int = 0   // 0 = no accent
    private var volume: Double = 0.7   // 0–1

    private(set) var isRunning: Bool = false

    /// Optional UI callback fired whenever a new beat starts.
    /// Called on the main queue; `isAccent` is true for accented beats.
    var onBeat: ((Bool) -> Void)?

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
        // Hand off from any previous active instance.
        if let other = MetronomeEngine.activeInstance, other !== self {
            other.hardStop()
        }
        MetronomeEngine.activeInstance = self

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

    /// Update tempo/accent (and optionally volume) while running. Safe to call even if stopped.
    func update(bpm: Int, accentEvery: Int, volume: Double) {
        let oldBPM = self.bpm

        self.bpm = max(30, Double(bpm))
        self.accentEvery = max(0, accentEvery)
        self.volume = max(0, min(1, volume))

        // Only recompute timing if BPM actually changed.
        if self.bpm != oldBPM {
            updateTiming()
        }
    }

    /// Update volume only (does not touch tempo/timing).
    func updateVolume(_ volume: Double) {
        self.volume = max(0, min(1, volume))
        // Intentionally do NOT call updateTiming()
    }

    /// Stop the metronome.
    func stop() {
        isRunning = false
        // We deliberately leave the AVAudioEngine running; the
        // source node will just output silence when isRunning == false.
        if MetronomeEngine.activeInstance === self {
            MetronomeEngine.activeInstance = nil
        }
    }

    // MARK: - Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // If a recorder has already put us into a record-capable mode, don’t touch it.
            if session.category == .playAndRecord {
                return
            }

            // Prefer playback for click-only operation (louder, speaker-friendly).
            try session.setCategory(.playback,
                                    mode: .default,
                                    options: [.mixWithOthers])
            try session.setPreferredSampleRate(44_100)
            try session.setActive(true)
        } catch {
            print("[MetronomeEngine] Audio Session error: \(error)")
        }
    }

    // MARK: - Click buffers (sample-based)

    /// Prepare short click samples whose channel count / sample rate can differ from the mixer.
    private func prepareClickBuffersIfNeeded() {
        if normalClickBuffer != nil && accentClickBuffer != nil { return }

        normalClickBuffer = loadClickBuffer(named: "metronome_click_normal")
        accentClickBuffer = loadClickBuffer(named: "metronome_click_accent")

        if normalClickBuffer == nil || accentClickBuffer == nil {
            print("[MetronomeEngine] Warning: Failed to load one or both metronome samples.")
        }
    }

    private func loadClickBuffer(named name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            print("[MetronomeEngine] Missing resource: \(name).wav")
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("[MetronomeEngine] Failed to create buffer for \(name)")
                return nil
            }

            try file.read(into: buffer)
            return buffer
        } catch {
            print("[MetronomeEngine] Error loading \(name): \(error)")
            return nil
        }
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

                // Notify UI on the main queue (lightweight, once per beat).
                if let beatCallback = onBeat {
                    let accentFlag = isAccent
                    DispatchQueue.main.async {
                        beatCallback(accentFlag)
                    }
                }
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

    // MARK: - Hard stop helper

    /// Used when handing off between instances: stop immediately and tear down node.
    private func hardStop() {
        isRunning = false
        engine.pause()
        if engine.attachedNodes.contains(sourceNode) {
            engine.detach(sourceNode)
        }
        normalClickBuffer = nil
        accentClickBuffer = nil
    }
}
