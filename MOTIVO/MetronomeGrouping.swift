import Foundation

/// Presets are UI-owned arrays; only the fixed-width start mask enters the audio thread.
struct MetronomeGrouping: Equatable, Hashable, Sendable {
    let parts: [Int]
    static let even = Self(parts: [])
    var label: String { parts.isEmpty ? "Even" : parts.map(String.init).joined(separator: "+") }
    var accessibilityLabel: String {
        parts.isEmpty ? "Even" : parts.map(String.init).joined(separator: " plus ")
    }
    var startMask: UInt16 {
        guard !parts.isEmpty, parts.allSatisfy({ $0 == 2 || $0 == 3 }), parts.reduce(0, +) <= 15 else { return 0 }
        var position = 0, mask: UInt16 = 0
        for length in parts { mask |= 1 << position; position += length }
        return mask
    }
}

extension MetronomeMeter {
    var groupingChoices: [MetronomeGrouping] {
        guard case .asymmetric = self else { return [.even] }
        let patterns: [[Int]]
        switch numerator {
        case 5: patterns = [[2,3], [3,2]]
        case 7: patterns = [[2,2,3], [2,3,2], [3,2,2]]
        case 8: patterns = [[3,3,2], [3,2,3], [2,3,3], [2,2,2,2]]
        case 10: patterns = [[3,3,2,2], [3,2,3,2], [3,2,2,3], [2,3,3,2], [2,3,2,3], [2,2,3,3], [2,2,2,2,2]]
        case 11: patterns = [[3,3,3,2], [3,3,2,3], [3,2,3,3], [2,3,3,3],
                             [3,2,2,2,2], [2,3,2,2,2], [2,2,3,2,2], [2,2,2,3,2], [2,2,2,2,3]]
        default: patterns = []
        }
        return [.even] + patterns.map { MetronomeGrouping(parts: $0) }
    }
    var supportsGrouping: Bool { groupingChoices.count > 1 }
}
