//
//  Stats.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 10/09/2025.
//

import Foundation
import CoreData

enum Stats {
    static let london: TimeZone = TimeZone(identifier: "Europe/London") ?? .current

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = london
        return c
    }

    /// Sum of minutes this week (Mon–Sun in Europe/London).
    static func minutesThisWeek(sessions: [Session]) -> Int {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        let secs = sessions
            .lazy
            .filter { s in
                guard let ts = s.timestamp else { return false }
                return interval.contains(ts)
            }
            .map { Int($0.durationSeconds) }
            .reduce(0, +)
        return secs / 60
    }

    /// Current streak up to *today* (Europe/London). Counts consecutive days with ≥1 session.
    static func currentStreakDays(sessions: [Session]) -> Int {
        let dayKeys = dayKeySet(sessions: sessions)
        guard !dayKeys.isEmpty else { return 0 }
        let todayKey = dayKey(for: Date())
        var streak = 0
        var cursor = todayKey
        while dayKeys.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Best (longest) streak across all history.
    static func bestStreakDays(sessions: [Session]) -> Int {
        let keys = dayKeySet(sessions: sessions).sorted()
        guard !keys.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for i in 1..<keys.count {
            if let prev = cal.date(byAdding: .day, value: -1, to: keys[i]), prev == keys[i-1] {
                run += 1
            } else {
                if run > best { best = run }
                run = 1
            }
        }
        if run > best { best = run }
        return best
    }

    // MARK: - Helpers
    private static func dayKeySet(sessions: [Session]) -> Set<Date> {
        var keys = Set<Date>()
        for s in sessions {
            if let ts = s.timestamp {
                keys.insert(dayKey(for: ts))
            }
        }
        return keys
    }

    private static func dayKey(for date: Date) -> Date {
        cal.startOfDay(for: date)
    }
}
