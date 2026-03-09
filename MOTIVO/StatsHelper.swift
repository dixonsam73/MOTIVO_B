//
//  StatsHelper.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 13/10/2025.
//
// CHANGE-ID: 20251013_184800-v79C
// SCOPE: Add segmented stats header (Week/Month/Year/Total) to Your Sessions card

// CHANGE-ID: 20260202_181000_StatsOwnerScopeOptional
// SCOPE: Feed Stats Reactivity — Make ownerUserID predicate optional (default nil) to avoid breaking other call sites (e.g. MeView). When provided, stats are owner-scoped; no formula or date-range changes.
// SEARCH-TOKEN: 20260202_181000_StatsOwnerScopeOptional
// =============================================

// CHANGE-ID: 20260309_133200_BackendStatsParity_b712
// SCOPE: Add analytics-only backend-post stats helpers for connected owner second-device parity. Preserve existing Core Data stats path unchanged; do not merge backend data into Core Data; threads remain out of scope.
// SEARCH-TOKEN: 20260309_133200_BackendStatsParity_b712
// =============================================

import Foundation
import CoreData

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month, year, total
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .total: return "Total"
        }
    }
}

struct SessionStats {
    let count: Int
    let seconds: Int
}

struct BackendStatsBreakdownEntry: Identifiable, Hashable {
    let label: String
    let seconds: Int

    var id: String { label }
}

struct BackendStatsSnapshot {
    let stats: SessionStats
    let filteredPosts: [BackendPost]
    let longestPost: BackendPost?
    let firstPost: BackendPost?
    let averageEffort: Double?
    let activityDistribution: [BackendStatsBreakdownEntry]
    let instrumentDistribution: [BackendStatsBreakdownEntry]
    let currentStreakDays: Int
    let bestStreakDays: Int
}

enum StatsHelper {
    static func dateBounds(for range: StatsRange, now: Date = Date(), cal: Calendar = .current) -> (start: Date?, end: Date?) {
        switch range {
        case .week:
            var cal = cal
            cal.firstWeekday = 2              // Monday
            cal.minimumDaysInFirstWeek = 4    // ISO-8601 standard

            let startOfToday = cal.startOfDay(for: now)

            guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: startOfToday) else {
                return (startOfToday, startOfToday)
            }

            return (weekInterval.start, weekInterval.end)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        case .year:
            let comps = cal.dateComponents([.year], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        case .total:
            return (nil, nil)
        }
    }
    
    static func fetchStats(in ctx: NSManagedObjectContext, range: StatsRange, ownerUserID: String? = nil) throws -> SessionStats {
        let (start, end) = dateBounds(for: range)
        let req = NSFetchRequest<NSManagedObject>(entityName: "Session")
        var preds: [NSPredicate] = []
        if let s = start { preds.append(NSPredicate(format: "timestamp >= %@", s as NSDate)) }
        if let e = end { preds.append(NSPredicate(format: "timestamp < %@", e as NSDate)) }
        if let ownerUserID, ownerUserID.isEmpty == false {
            preds.append(NSPredicate(format: "ownerUserID == %@", ownerUserID))
        }
        if !preds.isEmpty { req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds) }
        let objs = try ctx.fetch(req)
        let count = objs.count
        let seconds = objs.reduce(0) { $0 + ( $1.value(forKey: "durationSeconds") as? Int ?? 0 ) }
        return SessionStats(count: count, seconds: seconds)
    }

    // MARK: - Backend analytics-only helpers

    static func fetchStatsFromBackendPosts(
        posts: [BackendPost],
        range: StatsRange,
        ownerUserID: String? = nil,
        now: Date = Date(),
        cal: Calendar = .current
    ) -> SessionStats {
        let filtered = filteredBackendPosts(posts, range: range, ownerUserID: ownerUserID, now: now, cal: cal)
        return SessionStats(
            count: filtered.count,
            seconds: filtered.reduce(0) { $0 + max(0, $1.durationSeconds ?? 0) }
        )
    }

    static func buildBackendStatsSnapshot(
        posts: [BackendPost],
        range: StatsRange,
        ownerUserID: String? = nil,
        now: Date = Date(),
        cal: Calendar = .current
    ) -> BackendStatsSnapshot {
        let filtered = filteredBackendPosts(posts, range: range, ownerUserID: ownerUserID, now: now, cal: cal)
        let stats = SessionStats(
            count: filtered.count,
            seconds: filtered.reduce(0) { $0 + max(0, $1.durationSeconds ?? 0) }
        )

        return BackendStatsSnapshot(
            stats: stats,
            filteredPosts: filtered,
            longestPost: backendLongestPost(from: filtered),
            firstPost: backendFirstPost(from: filtered),
            averageEffort: backendAverageEffort(from: filtered),
            activityDistribution: backendActivityDistribution(posts: filtered),
            instrumentDistribution: backendInstrumentDistribution(posts: filtered),
            currentStreakDays: backendCurrentStreakDays(from: filtered, now: now, cal: cal),
            bestStreakDays: backendBestStreakDays(from: filtered, cal: cal)
        )
    }

    static func filteredBackendPosts(
        _ posts: [BackendPost],
        range: StatsRange,
        ownerUserID: String? = nil,
        now: Date = Date(),
        cal: Calendar = .current
    ) -> [BackendPost] {
        let (start, end) = dateBounds(for: range, now: now, cal: cal)

        return posts.filter { post in
            if let ownerUserID, ownerUserID.isEmpty == false, post.ownerUserID != ownerUserID {
                return false
            }
            guard let date = analyticsDate(for: post) else { return false }
            if let start, date < start { return false }
            if let end, date >= end { return false }
            return true
        }
    }

    static func analyticsDate(for post: BackendPost) -> Date? {
        if let sessionTimestamp = post.sessionTimestamp,
           let parsedSessionTimestamp = parseBackendDate(sessionTimestamp) {
            return parsedSessionTimestamp
        }
        if let createdAt = post.createdAt,
           let parsedCreatedAt = parseBackendDate(createdAt) {
            return parsedCreatedAt
        }
        return nil
    }

    static func parseBackendDate(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter.fractional.date(from: raw) { return date }
        if let date = ISO8601DateFormatter.standard.date(from: raw) { return date }
        return nil
    }

    static func backendAverageEffort(from posts: [BackendPost]) -> Double? {
        let efforts = posts.compactMap { post -> Int? in
            guard let effort = post.effort else { return nil }
            return max(0, effort)
        }
        guard efforts.isEmpty == false else { return nil }
        let total = efforts.reduce(0, +)
        return Double(total) / Double(efforts.count)
    }

    static func backendLongestPost(from posts: [BackendPost]) -> BackendPost? {
        posts.max { lhs, rhs in
            let lhsDuration = max(0, lhs.durationSeconds ?? 0)
            let rhsDuration = max(0, rhs.durationSeconds ?? 0)
            if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
            return (analyticsDate(for: lhs) ?? .distantPast) < (analyticsDate(for: rhs) ?? .distantPast)
        }
    }

    static func backendFirstPost(from posts: [BackendPost]) -> BackendPost? {
        posts.min { lhs, rhs in
            (analyticsDate(for: lhs) ?? .distantFuture) < (analyticsDate(for: rhs) ?? .distantFuture)
        }
    }

    static func backendActivityDistribution(posts: [BackendPost]) -> [BackendStatsBreakdownEntry] {
        buildDistribution(posts: posts) { post in
            let type = normalizedDistributionLabel(post.activityType)
            if let type { return type }
            let label = normalizedDistributionLabel(post.activityLabel)
            if let label { return label }
            return "Unlabelled"
        }
    }

    static func backendInstrumentDistribution(posts: [BackendPost]) -> [BackendStatsBreakdownEntry] {
        buildDistribution(posts: posts) { post in
            normalizedDistributionLabel(post.instrumentLabel) ?? "Unlabelled"
        }
    }

    static func backendCurrentStreakDays(from posts: [BackendPost], now: Date = Date(), cal: Calendar = .current) -> Int {
        let days = distinctPracticeDays(from: posts, cal: cal)
        guard days.isEmpty == false else { return 0 }

        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let anchor: Date
        if days.contains(today) {
            anchor = today
        } else if days.contains(yesterday) {
            anchor = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = anchor
        while days.contains(cursor) {
            streak += 1
            guard let previousDay = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return streak
    }

    static func backendBestStreakDays(from posts: [BackendPost], cal: Calendar = .current) -> Int {
        let days = Array(distinctPracticeDays(from: posts, cal: cal)).sorted()
        guard days.isEmpty == false else { return 0 }

        var best = 1
        var current = 1

        for index in 1..<days.count {
            let previous = days[index - 1]
            let currentDay = days[index]
            let dayDelta = cal.dateComponents([.day], from: previous, to: currentDay).day ?? 0
            if dayDelta == 1 {
                current += 1
                best = max(best, current)
            } else if dayDelta > 1 {
                current = 1
            }
        }

        return best
    }
    
    static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: TimeInterval(seconds)) ?? "0m"
    }

    private static func buildDistribution(
        posts: [BackendPost],
        labelForPost: (BackendPost) -> String
    ) -> [BackendStatsBreakdownEntry] {
        guard posts.isEmpty == false else { return [] }

        var totals: [String: Int] = [:]
        for post in posts {
            let label = labelForPost(post)
            let seconds = max(0, post.durationSeconds ?? 0)
            totals[label, default: 0] += seconds
        }

        return totals
            .map { BackendStatsBreakdownEntry(label: $0.key, seconds: $0.value) }
            .sorted {
                if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
    }

    private static func normalizedDistributionLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func distinctPracticeDays(from posts: [BackendPost], cal: Calendar) -> Set<Date> {
        Set(posts.compactMap { post in
            guard let date = analyticsDate(for: post) else { return nil }
            return cal.startOfDay(for: date)
        })
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
