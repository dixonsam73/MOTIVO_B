// DroneEngine.swift
// Extracted from PracticeTimerView (drone audio engine & waveform).
// No logic changes.

import Foundation
import AVFoundation
// === DRONE ENGINE (soft sine-ish tone with smoothing) ===
final class DroneEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private let sampleRate: Double
    private var phase: Double = 0
    private let twoPi = 2.0 * Double.pi

    private var currentFrequency: Double = 440
    private var targetFrequency: Double = 440

    private var currentVolume: Double = 0
    private var targetVolume: Double = 0

    // Small smoothing factor to avoid clicks when changing freq/volume
    private let smoothingFactor: Double = 0.002

    init() {
        let session = AVAudioSession.sharedInstance()
        let sr = session.sampleRate
        sampleRate = sr > 0 ? sr : 44_100
    }

    // MARK: - Public API

    func start(frequency: Double, volume: Double) {
        targetFrequency = frequency
        targetVolume = volume

        configureSession()

        if sourceNode == nil {
            createSourceNode()
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[DroneEngine] Failed to start engine: \(error)")
            }
        }

        // Fade in from silence
        currentFrequency = targetFrequency
        currentVolume = 0.0
        targetVolume = volume
    }

    func stop() {
        // Smooth fade-out
        targetVolume = 0.0

        // After a short delay, pause engine + detach node to save CPU
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if self.currentVolume <= 0.0001 {
                self.engine.pause()
                if let node = self.sourceNode {
                    self.engine.detach(node)
                    self.sourceNode = nil
                }
            }
        }
    }

    func update(frequency: Double) {
        targetFrequency = max(20, min(20_000, frequency))
    }

    func updateVolume(_ volume: Double) {
        targetVolume = max(0, min(1, volume))
    }

    // Map "A4", "Bb3" etc. → Hz using an arbitrary A4 reference
        static func frequency(for note: String, baseA4: Double = 440) -> Double {
            guard note.count >= 2 else { return baseA4 }

            let chars = Array(note)
            var namePart = ""
            var octavePart = ""

            // Split into pitch name + octave (e.g. "Bb" + "4")
            for c in chars {
                if c.isNumber {
                    octavePart.append(c)
                } else if octavePart.isEmpty {
                    namePart.append(c)
                }
            }

            let noteName = namePart
            let octave = Int(octavePart) ?? 4

            // Semitone offsets within an octave relative to C
            let semitoneMap: [String: Int] = [
                "C": 0, "C#": 1, "Db": 1,
                "D": 2, "D#": 3, "Eb": 3,
                "E": 4,
                "F": 5, "F#": 6, "Gb": 6,
                "G": 7, "G#": 8, "Ab": 8,
                "A": 9, "A#": 10, "Bb": 10,
                "B": 11
            ]

            guard let semitone = semitoneMap[noteName] else { return baseA4 }

            // MIDI note number: C-1 = 0 → A4 = 69
            let midi = (octave + 1) * 12 + semitone

            // Standard equal temperament using arbitrary A4 reference
            let freq = baseA4 * pow(2.0, Double(midi - 69) / 12.0)
            return freq
        }

        // Convenience: compute using default A=440
        static func frequency(for note: String) -> Int {
            Int(frequency(for: note, baseA4: 440).rounded())
        }
    // MARK: - Internal

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[DroneEngine] Audio Session error: \(error)")
        }
    }

    private func createSourceNode() {
        let format = engine.outputNode.inputFormat(forBus: 0)

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            if ablPointer.isEmpty { return noErr }

            let frames = Int(frameCount)
            let dt = 1.0 / self.sampleRate

            func smooth(_ current: Double, _ target: Double) -> Double {
                current + (target - current) * self.smoothingFactor
            }

            for frame in 0..<frames {
                self.currentFrequency = smooth(self.currentFrequency, self.targetFrequency)
                self.currentVolume = smooth(self.currentVolume, self.targetVolume)

                let phaseIncrement = self.twoPi * self.currentFrequency * dt
                self.phase += phaseIncrement
                if self.phase > self.twoPi {
                    self.phase -= self.twoPi
                }

                // Soft-ish waveform (sine with tiny second harmonic)
                let sample = Float(
                    sin(self.phase) * self.currentVolume * 0.9 +
                    sin(2 * self.phase) * self.currentVolume * 0.1
                )

                for buffer in ablPointer {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = sample
                }
            }

            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }
}

