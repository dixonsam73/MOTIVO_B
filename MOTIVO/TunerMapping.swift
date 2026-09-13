import Foundation

struct TunerDisplayState: Equatable, Sendable {
    let noteName: String?
    let cents: Int?
    let frequencyHz: Double?
    let hasSignal: Bool
    let isInTune: Bool
    let indicatorOffset: Double

    static let listening = TunerDisplayState(noteName: nil, cents: nil, frequencyHz: nil,
                                             hasSignal: false, isInTune: false, indicatorOffset: 0)

    var spokenNote: String? {
        noteName?.replacingOccurrences(of: "♯", with: " sharp ")
            .replacingOccurrences(of: "♭", with: " flat ")
            .replacingOccurrences(of: "([A-G])([0-9])", with: "$1 $2", options: .regularExpression)
    }
}

struct TunerMappingConfiguration {
    var amplitudeThreshold: Double = TunerSignalLevel.acquisition
    var continuationAmplitudeThreshold: Double = TunerSignalLevel.continuation
    var smoothingWindowSize: Int = 5
    var noteLockReleaseCents: Double = 58
    var holdDuration: TimeInterval = 0.90
    var inTuneThresholdCents: Double = 6
    var maxDisplayCents: Double = 50
}

/// Maps only estimates already qualified by TunerSignalAnalyzer. All state belongs to one tuner run.
final class TunerMapper {
    private let configuration: TunerMappingConfiguration
    private var referenceA4: Double = 440
    private var history: [Double] = []
    private var acceptedMIDI: Double?
    private var pendingMIDI: Double?
    private var lockedMIDINote: Int?
    private var lastStableState: TunerDisplayState = .listening
    private var lastSignalTimestamp: TimeInterval?
    private var canContinueQuietPitch = false

    init(configuration: TunerMappingConfiguration = TunerMappingConfiguration()) {
        self.configuration = configuration
    }

    func setReferenceA4(_ frequency: Double) {
        guard frequency.isFinite else { return }
        let value = min(460, max(392, frequency))
        guard referenceA4 != value else { return }
        referenceA4 = value
        reset()
    }

    func reset() {
        history.removeAll(keepingCapacity: true)
        acceptedMIDI = nil
        pendingMIDI = nil
        lockedMIDINote = nil
        lastStableState = .listening
        lastSignalTimestamp = nil
        canContinueQuietPitch = false
    }

    func process(frequency: Double, amplitude: Double,
                 timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TunerDisplayState {
        guard frequency.isFinite, frequency > 0, amplitude.isFinite,
              timestamp.isFinite else {
            pendingMIDI = nil
            return noSignal(at: timestamp)
        }
        let rawMIDI = 69 + 12 * log2(frequency / referenceA4)
        guard rawMIDI.isFinite, (-120...200).contains(rawMIDI) else {
            pendingMIDI = nil
            return noSignal(at: timestamp)
        }

        // Only a recent, continuously validated version of the same pitch can use the
        // lower release level. The longer neutral display hold does not extend this permission.
        let continuing: Bool
        if canContinueQuietPitch, let acceptedMIDI, let lastSignalTimestamp {
            continuing = timestamp >= lastSignalTimestamp && timestamp - lastSignalTimestamp <= 0.2
                && abs(rawMIDI - acceptedMIDI) <= 0.8
        } else {
            continuing = false
        }
        let threshold = continuing
            ? min(configuration.amplitudeThreshold, configuration.continuationAmplitudeThreshold)
            : configuration.amplitudeThreshold
        guard amplitude >= threshold else {
            pendingMIDI = nil
            return noSignal(at: timestamp)
        }

        // A large change needs corroboration, not an average through unrelated notes.
        // One bad octave frame is held neutrally; a sustained change is acquired on frame two.
        if let acceptedMIDI, abs(rawMIDI - acceptedMIDI) > 0.8 {
            if let pendingMIDI, abs(rawMIDI - pendingMIDI) <= 0.25 {
                history.removeAll(keepingCapacity: true)
                lockedMIDINote = nil
                self.pendingMIDI = nil
            } else {
                pendingMIDI = rawMIDI
                return noSignal(at: timestamp, preservePending: true)
            }
        } else {
            pendingMIDI = nil
        }

        history.append(rawMIDI)
        let window = max(1, configuration.smoothingWindowSize)
        if history.count > window { history.removeFirst(history.count - window) }
        let sorted = history.sorted()
        let middle = sorted.count / 2
        let estimate = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        acceptedMIDI = estimate
        let nearest = Int(estimate.rounded())
        let target: Int
        if let lockedMIDINote,
           abs((estimate - Double(lockedMIDINote)) * 100) <= configuration.noteLockReleaseCents {
            target = lockedMIDINote
        } else {
            target = nearest
            lockedMIDINote = nearest
        }
        let cents = (estimate - Double(target)) * 100
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let octave = Int(floor(Double(target) / 12)) - 1
        let state = TunerDisplayState(
            noteName: "\(names[((target % 12) + 12) % 12])\(octave)",
            cents: Int(cents.rounded()),
            frequencyHz: referenceA4 * pow(2, (estimate - 69) / 12),
            hasSignal: true,
            isInTune: abs(cents) <= configuration.inTuneThresholdCents,
            indicatorOffset: max(-1, min(1, cents / configuration.maxDisplayCents)))
        lastStableState = state
        lastSignalTimestamp = timestamp
        canContinueQuietPitch = true
        return state
    }

    /// Also called by the service watchdog when no fresh audio arrives.
    func noSignal(at timestamp: TimeInterval, preservePending: Bool = false) -> TunerDisplayState {
        canContinueQuietPitch = false
        guard timestamp.isFinite, let lastSignalTimestamp,
              timestamp >= lastSignalTimestamp,
              timestamp - lastSignalTimestamp <= configuration.holdDuration else {
            let pending = preservePending ? pendingMIDI : nil
            reset()
            pendingMIDI = pending
            return .listening
        }
        return TunerDisplayState(noteName: lastStableState.noteName, cents: lastStableState.cents,
                                 frequencyHz: lastStableState.frequencyHz, hasSignal: false,
                                 isInTune: false, indicatorOffset: lastStableState.indicatorOffset)
    }
}
