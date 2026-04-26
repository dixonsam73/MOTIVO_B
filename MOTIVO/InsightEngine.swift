// CHANGE-ID: 20260426_211300_meview_practice_window
// SCOPE: Add local-only Practice window insight and polish interpretive insight copy. No UI, backend, Core Data schema, Theme, or analytics changes.
// SEARCH-TOKEN: 20260426_211300_meview_practice_window

import Foundation
import CoreData

struct MeViewInsights {
    var emergingThread: EmergingThreadInsight?
    var returnPattern: ReturnPatternInsight
    var practiceWindow: PracticeWindowInsight
    var sessionShape: SessionShapeInsight
}

struct EmergingThreadInsight: Equatable {
    let name: String
}

enum ReturnPatternInsight: Equatable {
    case everyDay
    case every1to2Days
    case every2to3Days
    case everyFewDays
    case varies
    case insufficientData

    var valueText: String {
        switch self {
        case .everyDay:
            return "Every day"
        case .every1to2Days:
            return "Every 1–2 days"
        case .every2to3Days:
            return "Every 2–3 days"
        case .everyFewDays:
            return "Every few days"
        case .varies:
            return "Varies week to week"
        case .insufficientData:
            return "No clear rhythm yet"
        }
    }
}
enum PracticeWindowInsight: Equatable {
    case mornings
    case afternoons
    case evenings
    case spreadThroughDay
    case insufficientData

    var valueText: String {
        switch self {
        case .mornings:
            return "Mornings"
        case .afternoons:
            return "Afternoons"
        case .evenings:
            return "Evenings"
        case .spreadThroughDay:
            return "Spread throughout the day"
        case .insufficientData:
            return ""
        }
    }
}


enum SessionShapeInsight: Equatable {
    case consistent
    case mostlyConsistent
    case mixed
    case wideRanging
    case insufficientData

    var valueText: String {
        switch self {
        case .consistent:
            return "Consistent"
        case .mostlyConsistent:
            return "Mostly consistent"
        case .mixed:
            return "Mixed"
        case .wideRanging:
            return "Wide-ranging"
        case .insufficientData:
            return "Not enough data yet"
        }
    }

    var subtitleText: String? {
        switch self {
        case .consistent:
            return "Similar session lengths"
        case .mostlyConsistent:
            return "Mostly similar session lengths"
        case .mixed:
            return "A mix of shorter and longer sessions"
        case .wideRanging:
            return "Wide range of session lengths"
        case .insufficientData:
            return nil
        }
    }
}

enum InsightEngine {
    static func insights(from sessions: [Session]) -> MeViewInsights {
        let datedSessions = sessions.compactMap { session -> DatedSession? in
            guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
            return DatedSession(
                date: date,
                durationSeconds: durationSeconds(for: session),
                threadLabel: threadLabel(for: session)
            )
        }
        .sorted { $0.date > $1.date }

        return MeViewInsights(
            emergingThread: emergingThread(from: datedSessions),
            returnPattern: returnPattern(from: datedSessions),
            practiceWindow: practiceWindow(from: datedSessions),
            sessionShape: sessionShape(from: datedSessions)
        )
    }
}

private struct DatedSession {
    let date: Date
    let durationSeconds: Double
    let threadLabel: String?
}

private enum PracticeWindowBucket: Hashable {
    case morning
    case afternoon
    case evening

    init(hour: Int) {
        switch hour {
        case 5..<12:
            self = .morning
        case 12..<17:
            self = .afternoon
        default:
            self = .evening
        }
    }

    var sortOrder: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 1
        case .evening: return 2
        }
    }

    var insight: PracticeWindowInsight {
        switch self {
        case .morning: return .mornings
        case .afternoon: return .afternoons
        case .evening: return .evenings
        }
    }
}

private extension InsightEngine {
    static func emergingThread(from sessions: [DatedSession]) -> EmergingThreadInsight? {
        let threaded = sessions.filter { ($0.threadLabel?.isEmpty == false) }
        guard threaded.count >= 5 else { return nil }

        let recentCount = min(8, max(3, threaded.count / 3))
        let recent = Array(threaded.prefix(recentCount))
        let older = Array(threaded.dropFirst(recentCount))
        guard recent.count >= 3 else { return nil }

        let recentCounts = countsByThread(in: recent)
        guard recentCounts.isEmpty == false else { return nil }

        let olderCounts = countsByThread(in: older)
        let recentTotal = max(1, recent.count)
        let olderTotal = max(1, older.count)

        let candidates = recentCounts.compactMap { entry -> (name: String, recentCount: Int, recentShare: Double, olderShare: Double)? in
            let recentShare = Double(entry.value) / Double(recentTotal)
            let olderShare = Double(olderCounts[entry.key, default: 0]) / Double(olderTotal)
            guard entry.value >= 2 else { return nil }
            guard recentShare >= 0.35 else { return nil }
            guard older.isEmpty || olderCounts[entry.key, default: 0] == 0 || recentShare >= olderShare + 0.20 else { return nil }
            return (entry.key, entry.value, recentShare, olderShare)
        }

        let winner = candidates.sorted { lhs, rhs in
            if lhs.recentCount != rhs.recentCount { return lhs.recentCount > rhs.recentCount }
            if lhs.recentShare != rhs.recentShare { return lhs.recentShare > rhs.recentShare }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.first

        guard let winner else { return nil }
        return EmergingThreadInsight(name: winner.name)
    }

    static func returnPattern(from sessions: [DatedSession]) -> ReturnPatternInsight {
        let practiceDays = uniquePracticeDays(from: sessions)
        guard practiceDays.count >= 3 else { return .insufficientData }

        let gaps = zip(practiceDays.dropFirst(), practiceDays).compactMap { later, earlier -> Double? in
            Calendar.current.dateComponents([.day], from: earlier, to: later).day.map(Double.init)
        }
        .filter { $0 > 0 }

        guard gaps.count >= 2 else { return .insufficientData }

        let medianGap = median(gaps)
        let meanGap = mean(gaps)
        let standardDeviation = standardDeviation(gaps, mean: meanGap)
        let maxGap = gaps.max() ?? medianGap

        if gaps.count >= 4, standardDeviation >= 2.0, maxGap >= medianGap + 3.0 {
            return .varies
        }

        if medianGap <= 1.05 {
            return .everyDay
        } else if medianGap <= 2.0 {
            return .every1to2Days
        } else if medianGap <= 3.0 {
            return .every2to3Days
        } else if medianGap <= 5.0 {
            return .everyFewDays
        } else {
            return .varies
        }
    }

static func practiceWindow(from sessions: [DatedSession]) -> PracticeWindowInsight {
    guard sessions.count >= 6 else { return .insufficientData }

    var counts: [PracticeWindowBucket: Int] = [:]
    for session in sessions {
        let hour = Calendar.current.component(.hour, from: session.date)
        counts[PracticeWindowBucket(hour: hour), default: 0] += 1
    }

    let total = counts.values.reduce(0, +)
    guard total >= 6 else { return .insufficientData }

    let orderedCounts = counts.sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key.sortOrder < rhs.key.sortOrder
    }
    guard let top = orderedCounts.first else { return .insufficientData }

    let topShare = Double(top.value) / Double(total)
    if top.value >= 4, topShare >= 0.55 {
        return top.key.insight
    }

    let meaningfulBuckets = counts.filter { _, count in
        Double(count) / Double(total) >= 0.25
    }

    if total >= 8, meaningfulBuckets.count >= 2, topShare <= 0.50 {
        return .spreadThroughDay
    }

    return .insufficientData
}

    static func sessionShape(from sessions: [DatedSession]) -> SessionShapeInsight {
        let durations = sessions.map(\.durationSeconds).filter { $0 > 0 }
        guard durations.count >= 4 else { return .insufficientData }

        let avg = mean(durations)
        guard avg > 0 else { return .insufficientData }

        let sorted = durations.sorted()
        let minDuration = sorted.first ?? 0
        let maxDuration = sorted.last ?? 0
        let cv = standardDeviation(durations, mean: avg) / avg
        let rangeRatio = minDuration > 0 ? maxDuration / minDuration : Double.greatestFiniteMagnitude

        if cv <= 0.18, rangeRatio <= 1.5 {
            return .consistent
        } else if cv <= 0.35, rangeRatio <= 2.25 {
            return .mostlyConsistent
        } else if cv <= 0.65 {
            return .mixed
        } else {
            return .wideRanging
        }
    }

    static func countsByThread(in sessions: [DatedSession]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for session in sessions {
            guard let label = session.threadLabel else { continue }
            counts[label, default: 0] += 1
        }
        return counts
    }

    static func uniquePracticeDays(from sessions: [DatedSession]) -> [Date] {
        let calendar = Calendar.current
        return Array(Set(sessions.map { calendar.startOfDay(for: $0.date) })).sorted()
    }

    static func threadLabel(for session: Session) -> String? {
        let raw = session.value(forKey: "threadLabel") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func durationSeconds(for session: Session) -> Double {
        if let n = session.value(forKey: "durationSeconds") as? NSNumber { return max(0.0, n.doubleValue) }
        if let i = session.value(forKey: "durationSeconds") as? Int { return max(0.0, Double(i)) }
        if let d = session.value(forKey: "durationSeconds") as? Double { return max(0.0, d) }
        if let i16 = session.value(forKey: "durationSeconds") as? Int16 { return max(0.0, Double(i16)) }
        if let i32 = session.value(forKey: "durationSeconds") as? Int32 { return max(0.0, Double(i32)) }
        if let i64 = session.value(forKey: "durationSeconds") as? Int64 { return max(0.0, Double(i64)) }
        return 0.0
    }

    static func mean(_ values: [Double]) -> Double {
        guard values.isEmpty == false else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard sorted.isEmpty == false else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        } else {
            return sorted[middle]
        }
    }

    static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count >= 2 else { return 0 }
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(values.count)
        return sqrt(variance)
    }
}
