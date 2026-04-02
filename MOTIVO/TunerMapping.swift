//
//  TunerMapping.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 02/04/2026.
//


import Foundation

struct TunerDisplayState: Equatable {
    let noteName: String?
    let cents: Int?
    let frequencyHz: Double?
    let hasSignal: Bool
    let isInTune: Bool
    let indicatorOffset: Double

    static let listening = TunerDisplayState(
        noteName: nil,
        cents: nil,
        frequencyHz: nil,
        hasSignal: false,
        isInTune: false,
        indicatorOffset: 0
    )
}

struct TunerMappingConfiguration {
    var amplitudeThreshold: Double = 0.02
    var smoothingWindowSize: Int = 5
    var noteLockReleaseCents: Double = 58
    var noteLockCaptureCents: Double = 32
    var holdDuration: TimeInterval = 0.40
    var inTuneThresholdCents: Double = 6
    var maxDisplayCents: Double = 50
}

final class TunerMapper {
    private let configuration: TunerMappingConfiguration

    private var smoothedMIDIBuffer: [Double] = []
    private var lockedMIDINote: Int?
    private var lastStableState: TunerDisplayState = .listening
    private var lastSignalTimestamp: TimeInterval?

    init(configuration: TunerMappingConfiguration = TunerMappingConfiguration()) {
        self.configuration = configuration
    }

    func reset() {
        smoothedMIDIBuffer.removeAll()
        lockedMIDINote = nil
        lastStableState = .listening
        lastSignalTimestamp = nil
    }

    func process(
        frequency: Double,
        amplitude: Double,
        timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> TunerDisplayState {
        guard frequency.isFinite, frequency > 0 else {
            return stateForNoSignal(at: timestamp)
        }

        guard amplitude.isFinite, amplitude >= configuration.amplitudeThreshold else {
            return stateForNoSignal(at: timestamp)
        }

        lastSignalTimestamp = timestamp

        let rawMIDI = Self.midiNoteValue(for: frequency)
        let smoothedMIDI = smoothedValue(for: rawMIDI)

        let targetMIDINote = resolvedLockedMIDINote(for: smoothedMIDI)
        let cents = Self.centsOffset(from: smoothedMIDI, toNearest: targetMIDINote)

        let noteName = Self.noteName(for: targetMIDINote)
        let clampedOffset = max(
            -1,
            min(1, cents / configuration.maxDisplayCents)
        )

        let state = TunerDisplayState(
            noteName: noteName,
            cents: Int(cents.rounded()),
            frequencyHz: frequency,
            hasSignal: true,
            isInTune: abs(cents) <= configuration.inTuneThresholdCents,
            indicatorOffset: clampedOffset
        )

        lastStableState = state
        return state
    }

    private func stateForNoSignal(at timestamp: TimeInterval) -> TunerDisplayState {
        guard
            let lastSignalTimestamp,
            timestamp - lastSignalTimestamp <= configuration.holdDuration
        else {
            resetLockedStatePreservingLastStable()
            return .listening
        }

        return TunerDisplayState(
            noteName: lastStableState.noteName,
            cents: lastStableState.cents,
            frequencyHz: lastStableState.frequencyHz,
            hasSignal: false,
            isInTune: lastStableState.isInTune,
            indicatorOffset: lastStableState.indicatorOffset
        )
    }

    private func resetLockedStatePreservingLastStable() {
        smoothedMIDIBuffer.removeAll()
        lockedMIDINote = nil
        lastSignalTimestamp = nil
    }

    private func smoothedValue(for midiValue: Double) -> Double {
        smoothedMIDIBuffer.append(midiValue)

        if smoothedMIDIBuffer.count > configuration.smoothingWindowSize {
            smoothedMIDIBuffer.removeFirst(smoothedMIDIBuffer.count - configuration.smoothingWindowSize)
        }

        let total = smoothedMIDIBuffer.reduce(0, +)
        return total / Double(smoothedMIDIBuffer.count)
    }

    private func resolvedLockedMIDINote(for smoothedMIDI: Double) -> Int {
        let nearest = Int(smoothedMIDI.rounded())

        guard let lockedMIDINote else {
            self.lockedMIDINote = nearest
            return nearest
        }

        let centsFromLocked = Self.centsOffset(from: smoothedMIDI, toNearest: lockedMIDINote)
        if abs(centsFromLocked) <= configuration.noteLockReleaseCents {
            return lockedMIDINote
        }

        let centsFromNearest = Self.centsOffset(from: smoothedMIDI, toNearest: nearest)
        if abs(centsFromNearest) <= configuration.noteLockCaptureCents {
            self.lockedMIDINote = nearest
            return nearest
        }

        return lockedMIDINote
    }

    private static func midiNoteValue(for frequency: Double) -> Double {
        69 + (12 * log2(frequency / 440.0))
    }

    private static func centsOffset(from midiValue: Double, toNearest midiNote: Int) -> Double {
        (midiValue - Double(midiNote)) * 100
    }

    private static func noteName(for midiNote: Int) -> String {
        let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let noteIndex = ((midiNote % 12) + 12) % 12
        let octave = (midiNote / 12) - 1
        return "\(noteNames[noteIndex])\(octave)"
    }
}
