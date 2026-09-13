import Foundation

enum MetronomeBeatUnit: Equatable, Sendable { case crotchet, dottedCrotchet, quaver }

enum MetronomeMeter: Equatable, Hashable, Sendable {
    case simple(Int), simpleEighth(Int), compound(Int), asymmetric(Int)

    static let standard: [Self] = [.simple(2), .simple(3), .simple(4), .simple(5), .simple(6), .simple(7),
                                  .simpleEighth(2), .simpleEighth(3), .simpleEighth(4),
                                  .asymmetric(5), .compound(6), .asymmetric(7), .asymmetric(8),
                                  .compound(9), .asymmetric(10), .asymmetric(11), .compound(12)]
    var numerator: Int {
        switch self { case .simple(let n), .simpleEighth(let n), .compound(let n), .asymmetric(let n): return n }
    }
    var isCompound: Bool { if case .compound = self { return true }; return false }
    var beatUnit: MetronomeBeatUnit {
        switch self { case .simple: return .crotchet; case .compound: return .dottedCrotchet; case .simpleEighth, .asymmetric: return .quaver }
    }
    var beats: Int { min(15, max(1, isCompound ? numerator / 3 : numerator)) }
    var denominator: Int { beatUnit == .crotchet ? 4 : 8 }
    var label: String { "\(numerator)/\(denominator)" }
    var beatLabel: String {
        switch beatUnit { case .crotchet: return "Crotchet"; case .dottedCrotchet: return "Dotted crotchet"; case .quaver: return "Quaver" }
    }
    // Different written meters can have the same beat count. Preserve their identity at handoff.
    var code: Int { (isCompound ? 16 : beatUnit == .quaver ? 32 : 0) + beats }
}

enum MetronomeSubdivision: Int, CaseIterable, Sendable {
    case beat, quavers, triplets, semiquavers
    func count(in meter: MetronomeMeter) -> Int {
        switch self {
        case .beat: return 1
        case .quavers: return meter.isCompound ? 3 : 2
        case .triplets: return 3
        case .semiquavers: return meter.isCompound ? 6 : 4
        }
    }
    func label(in meter: MetronomeMeter) -> String {
        switch self {
        case .beat: return meter.beatLabel + " beats"
        case .quavers: return meter.beatUnit == .quaver ? "Semiquavers" : "Quavers"
        case .triplets: return meter.beatUnit == .quaver ? "Semiquaver triplets" : "Quaver triplets"
        case .semiquavers: return meter.beatUnit == .quaver ? "Demisemiquavers" : "Semiquavers"
        }
    }
    static func choices(in meter: MetronomeMeter) -> [Self] {
        meter.isCompound ? [.beat, .quavers, .semiquavers] : allCases
    }
}

struct MetronomeSettings: Equatable, Sendable {
    var bpm = 80
    var meter: MetronomeMeter = .simple(4)
    var accent = false
    var subdivision: MetronomeSubdivision = .beat
    var volume = 0.7
    private(set) var rememberedGroupings: [String: [Int]] = [:]

    var grouping: MetronomeGrouping {
        let value = MetronomeGrouping(parts: rememberedGroupings[meter.label] ?? [])
        return meter.groupingChoices.contains(value) ? value : .even
    }
    mutating func selectGrouping(_ value: MetronomeGrouping) {
        guard meter.groupingChoices.contains(value) else { return }
        if value == .even { rememberedGroupings.removeValue(forKey: meter.label) }
        else { rememberedGroupings[meter.label] = value.parts }
    }
    mutating func restoreGroupings(from data: Data) {
        let stored = (try? JSONDecoder().decode([String: [Int]].self, from: data)) ?? [:]
        rememberedGroupings = [:]
        for meter in MetronomeMeter.standard {
            guard let parts = stored[meter.label], !parts.isEmpty,
                  meter.groupingChoices.contains(MetronomeGrouping(parts: parts)) else { continue }
            rememberedGroupings[meter.label] = parts
        }
    }
    func encodedGroupings() -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(rememberedGroupings)) ?? Data()
    }

    mutating func selectMeter(_ value: MetronomeMeter) {
        meter = value
        if value.isCompound && subdivision == .triplets { subdivision = .beat }
    }

    /// One atomic word carries a coherent configuration. No pointer ownership crosses threads.
    func command(running: Bool) -> UInt64 {
        let level = volume.isFinite ? Int((min(1, max(0, volume)) * 1000).rounded()) : 0
        return UInt64(min(400, max(20, bpm)))
            | UInt64(meter.beats) << 9
            | UInt64(subdivision.count(in: meter)) << 13
            | UInt64(accent ? 1 : 0) << 16
            | UInt64(level) << 19
            | UInt64(meter.code) << 29
            | UInt64(grouping.startMask) << 35
            | (running ? 1 << 63 : 0)
    }
}

struct MetronomeRenderSettings: Equatable, Sendable {
    let bpm: Double
    let beats: Int
    let divisions: Int
    let accent: Bool
    let volume: Float
    let meterCode: Int
    let groupStartMask: UInt16
    let running: Bool
    init(command: UInt64) {
        bpm = Double(max(20, min(400, command & 511)))
        beats = max(1, Int((command >> 9) & 15))
        divisions = max(1, min(6, Int((command >> 13) & 7)))
        accent = (command >> 16) & 1 == 1
        volume = Float(min(1000, (command >> 19) & 1023)) / 1000
        meterCode = Int((command >> 29) & 63)
        let mask = UInt16((command >> 35) & 0x7FFF)
        groupStartMask = mask & 1 == 1 ? mask & UInt16((1 << beats) - 1) : 0
        running = command >> 63 == 1
    }
}

/// Monotonic tap history. A three-second beat at 20 BPM remains valid; stale sequences expire.
struct MetronomeTapTempo {
    private var taps: [Double] = []
    mutating func reset() { taps.removeAll(keepingCapacity: true) }
    mutating func tap(at time: Double) -> Int? {
        guard time.isFinite else { return nil }
        if let last = taps.last {
            let interval = time - last
            if interval <= 0 { return nil }
            if interval < 0.08 { return nil } // accidental double tap
            if interval > 3.5 { reset() }
        }
        taps.append(time)
        if taps.count > 5 { taps.removeFirst(taps.count - 5) }
        guard taps.count >= 2, let first = taps.first else { return nil }
        return min(400, max(20, Int((60 * Double(taps.count - 1) / (time - first)).rounded())))
    }
}
