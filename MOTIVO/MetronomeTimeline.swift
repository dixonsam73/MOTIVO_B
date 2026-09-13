import Foundation

enum MetronomeClickRole: Int, Sendable {
    case downbeat, beat, subdivision, groupInterior, groupAccent
    // Group interiors reuse the full Dry regular recording at a quieter level.
    var sampleIndex: Int {
        switch self {
        case .groupInterior: return Self.beat.rawValue
        case .groupAccent: return 3
        default: return rawValue
        }
    }
    var gain: Float {
        switch self { case .downbeat: return 0.7079458; case .beat, .groupAccent: return 0.35
        case .groupInterior: return 0.22; case .subdivision: return 0.14 }
    }
}
struct MetronomeTick: Equatable, Sendable {
    let role: MetronomeClickRole
    let beatInBar: Int
    var isPrimary: Bool { role != .subdivision }
}

/// Render-thread owned. Fractional sample positions avoid repeated interval-rounding drift.
struct MetronomeTimeline {
    let sampleRate: Double
    private(set) var frame: Int64 = 0
    private var beatStart = 0.0
    private var samplesPerBeat: Double
    private var nextDivision = 0
    private var beatInBar = 0
    private var active: MetronomeRenderSettings
    private var pending: MetronomeRenderSettings

    init(sampleRate: Double, settings: MetronomeRenderSettings) {
        self.sampleRate = sampleRate
        active = settings
        pending = settings
        samplesPerBeat = sampleRate * 60 / settings.bpm
    }

    mutating func update(_ settings: MetronomeRenderSettings) {
        if settings.bpm != pending.bpm {
            let elapsedFraction = (Double(frame) - beatStart) / samplesPerBeat
            samplesPerBeat = sampleRate * 60 / settings.bpm
            beatStart = Double(frame) - elapsedFraction * samplesPerBeat
        }
        pending = settings
    }

    mutating func nextFrame() -> MetronomeTick? {
        defer { frame += 1 }
        let due = beatStart + Double(nextDivision) * samplesPerBeat / Double(active.divisions)
        guard Double(frame) + 0.5 >= due else { return nil }
        if nextDivision == 0 || nextDivision == active.divisions {
            if nextDivision != 0 { beatStart += samplesPerBeat }
            if pending.meterCode != active.meterCode || pending.groupStartMask != active.groupStartMask { beatInBar = 0 }
            active = pending
            let index = beatInBar
            let isGroupInterior = active.groupStartMask != 0 && active.groupStartMask & (1 << index) == 0
            let role: MetronomeClickRole
            if active.accent && index == 0 { role = .downbeat }
            else if active.groupStartMask == 0 { role = .beat }
            else { role = isGroupInterior ? .groupInterior : .groupAccent }
            beatInBar = (index + 1) % active.beats
            nextDivision = 1
            return MetronomeTick(role: role, beatInBar: index)
        }
        nextDivision += 1
        return MetronomeTick(role: .subdivision, beatInBar: (beatInBar + active.beats - 1) % active.beats)
    }
}
