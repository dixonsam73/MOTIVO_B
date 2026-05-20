// CHANGE-ID: 20260520_223500_ContentViewJournalSectionBuilderPass2
// SCOPE: ContentView Pass 2 — extracted Journal section/date/model construction only. No UI, filtering, routing, backend, or state ownership changes.
// SEARCH-TOKEN: 20260520_223500_ContentViewJournalSectionBuilderPass2

import SwiftUI

struct JournalSection: Identifiable {
    let id: String
    let title: String
    let sessions: [Session]
}

struct JournalYearSectionModel: Identifiable {
    let id: String
    let year: Int
    let rows: [JournalYearMonthRowModel]
}

enum ContentViewJournalSectionBuilder {
    static var groupingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func weekStart(for date: Date) -> Date {
        let calendar = groupingCalendar
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func date(for session: Session) -> Date {
        (session.value(forKey: "timestamp") as? Date) ?? Date.distantPast
    }

    static func monthStart(for date: Date) -> Date {
        let calendar = groupingCalendar
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func yearStart(for date: Date) -> Date {
        let calendar = groupingCalendar
        let components = calendar.dateComponents([.year], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func weekHeaderTitle(for weekStart: Date) -> String {
        let calendar = groupingCalendar
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return weekDateRangeText(start: weekStart, end: weekEnd)
    }

    static func weekDateRangeText(start: Date, end: Date) -> String {
        let calendar = groupingCalendar

        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let startMonth = journalMonthFormatter.string(from: start)
        let endMonth = journalMonthFormatter.string(from: end)
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)

        if calendar.isDate(start, equalTo: end, toGranularity: .year),
           calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(startDay)–\(endDay) \(startMonth) \(startYear)"
        }

        if startYear == endYear {
            return "\(startDay) \(startMonth) – \(endDay) \(endMonth) \(startYear)"
        }

        return "\(startDay) \(startMonth) \(startYear) – \(endDay) \(endMonth) \(endYear)"
    }

    static func monthWeekRangeText(start: Date, end: Date) -> String {
        let calendar = groupingCalendar
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let month = journalMonthFormatter.string(from: start)
        return "\(startDay)–\(endDay) \(month)"
    }

    static func weekSections(sessions: [Session]) -> [JournalSection] {
        let sortedSessions = sessions.sorted { date(for: $0) > date(for: $1) }
        guard !sortedSessions.isEmpty else { return [] }

        let grouped = Dictionary(grouping: sortedSessions) { weekStart(for: date(for: $0)) }

        return grouped.keys
            .sorted(by: >)
            .compactMap { weekStart in
                guard let sessions = grouped[weekStart], !sessions.isEmpty else { return nil }
                return JournalSection(
                    id: journalWeekIDFormatter.string(from: weekStart),
                    title: weekHeaderTitle(for: weekStart),
                    sessions: sessions.sorted { date(for: $0) > date(for: $1) }
                )
            }
    }

    static func monthSections(sessions: [Session]) -> [JournalSection] {
        let sortedSessions = sessions.sorted { date(for: $0) > date(for: $1) }
        guard !sortedSessions.isEmpty else { return [] }

        let grouped = Dictionary(grouping: sortedSessions) { session in
            monthStart(for: date(for: session))
        }

        return grouped.keys
            .sorted(by: >)
            .compactMap { monthStart in
                guard let sessions = grouped[monthStart], !sessions.isEmpty else { return nil }
                return JournalSection(
                    id: "month-\(journalWeekIDFormatter.string(from: monthStart))",
                    title: journalMonthYearFormatter.string(from: monthStart),
                    sessions: sessions.sorted { date(for: $0) > date(for: $1) }
                )
            }
    }

    static func yearSections(sessions: [Session]) -> [JournalSection] {
        let sortedSessions = sessions.sorted { date(for: $0) > date(for: $1) }
        guard !sortedSessions.isEmpty else { return [] }

        let grouped = Dictionary(grouping: sortedSessions) { session in
            monthStart(for: date(for: session))
        }

        return grouped.keys
            .sorted(by: >)
            .compactMap { monthStart in
                guard let sessions = grouped[monthStart], !sessions.isEmpty else { return nil }
                return JournalSection(
                    id: "year-\(journalWeekIDFormatter.string(from: monthStart))",
                    title: journalMonthYearFormatter.string(from: monthStart),
                    sessions: sessions.sorted { date(for: $0) > date(for: $1) }
                )
            }
    }

    static func calendarYearSections(
        sessions: [Session],
        tintSource: Theme.ResolvedTintSource,
        fallbackOwnerUserID: String?
    ) -> [JournalYearSectionModel] {
        let calendar = groupingCalendar
        let now = Date()
        let currentMonthStart = monthStart(for: now)
        let currentYear = calendar.component(.year, from: now)

        let earliestSessionDate = sessions
            .map { date(for: $0) }
            .min() ?? now
        let earliestSessionYear = calendar.component(.year, from: earliestSessionDate)
        let earliestSessionMonth = calendar.component(.month, from: earliestSessionDate)

        guard earliestSessionYear <= currentYear else { return [] }

        let grouped = Dictionary(grouping: sessions) { session in
            monthStart(for: date(for: session))
        }

        let allMonthStarts: [Date] = stride(from: currentYear, through: earliestSessionYear, by: -1).flatMap { year in
            let months = stride(from: 12, through: 1, by: -1).filter { month in
                if year == earliestSessionYear {
                    return month >= earliestSessionMonth
                }
                return true
            }

            return months.compactMap { month in
                calendar.date(from: DateComponents(year: year, month: month, day: 1))
            }
        }

        let maxTotalSeconds = max(
            allMonthStarts.map { monthStart in
                grouped[monthStart, default: []].reduce(0) { $0 + durationSeconds(for: $1) }
            }.max() ?? 0,
            1
        )

        let maxSessionCount = max(
            allMonthStarts.map { grouped[$0, default: []].count }.max() ?? 0,
            1
        )

        let rows: [JournalYearMonthRowModel] = allMonthStarts.map { monthStart in
            let monthSessions = grouped[monthStart, default: []]
                .sorted { date(for: $0) > date(for: $1) }

            let totalSeconds = monthSessions.reduce(0) { $0 + durationSeconds(for: $1) }
            let sessionCount = monthSessions.count
            let dominantInstrument = yearDominantInstrument(
                for: monthSessions,
                totalSeconds: totalSeconds
            )
            let dominantActivity = yearDominantActivity(
                for: monthSessions,
                totalSeconds: totalSeconds
            )
            let dominantThread = yearDominantThread(
                for: monthSessions,
                totalSeconds: totalSeconds
            )
            let metadataText = yearMetadataText(
                for: monthSessions,
                totalSeconds: totalSeconds,
                sessionCount: sessionCount
            )
            let rowOwnerUserID = monthSessions
                .compactMap { session in
                    let ownerID = session.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (ownerID?.isEmpty == false) ? ownerID : nil
                }
                .first ?? fallbackOwnerUserID

            let rawWidthFraction = CGFloat(totalSeconds) / CGFloat(maxTotalSeconds)
            let widthFraction: CGFloat = totalSeconds > 0 ? min(max(rawWidthFraction, 0.08), 1.0) : 0.0

            let rawDensityFraction = CGFloat(sessionCount) / CGFloat(maxSessionCount)
            let densityFraction: CGFloat = sessionCount > 0
                ? min(rawDensityFraction, 1.0)
                : 0.0

            return JournalYearMonthRowModel(
                id: "calendar-year-\(journalWeekIDFormatter.string(from: monthStart))",
                monthStart: monthStart,
                year: calendar.component(.year, from: monthStart),
                monthLabel: journalMonthFormatter.string(from: monthStart),
                totalSeconds: totalSeconds,
                sessionCount: sessionCount,
                metadataText: metadataText,
                dominantInstrumentLabel: dominantInstrument?.label,
                dominantActivityLabel: dominantActivity?.label,
                dominantThreadLabel: dominantThread?.label,
                ownerUserID: rowOwnerUserID,
                tintSource: tintSource,
                widthFraction: widthFraction,
                densityFraction: densityFraction,
                isFutureMonth: calendar.component(.year, from: monthStart) == currentYear && monthStart > currentMonthStart,
                isCurrentMonth: calendar.isDate(monthStart, equalTo: currentMonthStart, toGranularity: .month)
            )
        }

        let sections = Dictionary(grouping: rows) { $0.year }

        return sections.keys
            .sorted(by: >)
            .compactMap { year in
                guard let rows = sections[year], !rows.isEmpty else { return nil }
                return JournalYearSectionModel(
                    id: "calendar-year-section-\(year)",
                    year: year,
                    rows: rows
                )
            }
    }

    static func currentMonthAnchorID(in sections: [JournalYearSectionModel]) -> String? {
        sections
            .flatMap { $0.rows }
            .first(where: { $0.isCurrentMonth })?
            .id
    }

    static func monthSectionAnchorID(for monthStart: Date) -> String {
        "journal-month-section-\(journalWeekIDFormatter.string(from: monthStart))"
    }

    static func monthSectionAnchorID(for section: JournalSection) -> String {
        let monthStartDate = section.sessions
            .map { date(for: $0) }
            .map { monthStart(for: $0) }
            .max() ?? Date.distantPast

        return monthSectionAnchorID(for: monthStartDate)
    }

    static func hasVisibleMonthSection(for monthStart: Date, in sessions: [Session]) -> Bool {
        yearSections(sessions: sessions)
            .contains { section in
                section.sessions.contains {
                    self.monthStart(for: date(for: $0)) == monthStart
                }
            }
    }

    static func durationSeconds(for session: Session) -> Int {
        let attrs = session.entity.attributesByName
        if attrs["durationSeconds"] != nil, let n = session.value(forKey: "durationSeconds") as? NSNumber {
            return max(0, n.intValue)
        } else if attrs["durationMinutes"] != nil, let n = session.value(forKey: "durationMinutes") as? NSNumber {
            return max(0, n.intValue * 60)
        } else if attrs["duration"] != nil, let n = session.value(forKey: "duration") as? NSNumber {
            return max(0, n.intValue * 60)
        } else if attrs["lengthMinutes"] != nil, let n = session.value(forKey: "lengthMinutes") as? NSNumber {
            return max(0, n.intValue * 60)
        }
        return 0
    }

    static func yearMaxDuration(for sessions: [Session]) -> Int {
        max(sessions.map(durationSeconds(for:)).max() ?? 0, 1)
    }

    static func yearSurfaceWidthFraction(for session: Session, maxDuration: Int) -> CGFloat {
        guard maxDuration > 0 else { return 0.05 }
        let raw = max(0, CGFloat(durationSeconds(for: session)) / CGFloat(maxDuration))
        let scaled = pow(raw, 0.75)
        return scaled
    }

    private struct JournalYearFacetSummary {
        let label: String
        let seconds: Int
        let distinctCount: Int
    }

    private static func yearMetadataText(
        for sessions: [Session],
        totalSeconds: Int,
        sessionCount: Int
    ) -> String? {
        guard sessionCount > 0, totalSeconds > 0 else { return nil }

        var parts: [String] = [
            StatsHelper.formatDuration(totalSeconds),
            sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        ]

        if let instrument = yearDominantInstrument(for: sessions, totalSeconds: totalSeconds) {
            parts.append("\(instrument.label) \(StatsHelper.formatDuration(instrument.seconds))")
        }

        if let activity = yearDominantActivity(for: sessions, totalSeconds: totalSeconds) {
            parts.append("\(activity.label) \(StatsHelper.formatDuration(activity.seconds))")
        }

        return parts.joined(separator: " • ")
    }

    private static func yearDominantInstrument(
        for sessions: [Session],
        totalSeconds: Int
    ) -> JournalYearFacetSummary? {
        yearDominantFacet(
            for: sessions,
            totalSeconds: totalSeconds,
            label: yearInstrumentLabel(for:)
        )
    }

    private static func yearDominantActivity(
        for sessions: [Session],
        totalSeconds: Int
    ) -> JournalYearFacetSummary? {
        yearDominantFacet(
            for: sessions,
            totalSeconds: totalSeconds,
            label: yearActivityLabel(for:)
        )
    }

    private static func yearDominantThread(
        for sessions: [Session],
        totalSeconds: Int
    ) -> JournalYearFacetSummary? {
        yearDominantFacet(
            for: sessions,
            totalSeconds: totalSeconds,
            label: yearThreadLabel(for:)
        )
    }

    private static func yearDominantFacet(
        for sessions: [Session],
        totalSeconds: Int,
        label: (Session) -> String?
    ) -> JournalYearFacetSummary? {
        let totals = sessions.reduce(into: [String: Int]()) { partial, session in
            guard let rawLabel = label(session) else { return }
            let trimmed = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            partial[trimmed, default: 0] += durationSeconds(for: session)
        }

        let sorted = totals.sorted {
            if $0.value == $1.value {
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            return $0.value > $1.value
        }

        guard let top = sorted.first, top.value > 0 else { return nil }

        let distinctCount = sorted.count
        // Always use the highest-duration instrument for the month
        return JournalYearFacetSummary(label: top.key, seconds: top.value, distinctCount: distinctCount)
    }

    private static func yearInstrumentLabel(for session: Session) -> String? {
        let directLabel = ((session.value(forKey: "userInstrumentLabel") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !directLabel.isEmpty { return directLabel }

        let relationshipLabel = session.instrument?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return relationshipLabel.isEmpty ? nil : relationshipLabel
    }

    private static func yearActivityLabel(for session: Session) -> String? {
        let directLabel = ((session.value(forKey: "userActivityLabel") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !directLabel.isEmpty { return directLabel }

        if let code = session.value(forKey: "activityType") as? Int16 {
            return (ActivityType(rawValue: code) ?? .practice).label
        }

        return nil
    }

    private static func yearThreadLabel(for session: Session) -> String? {
        let raw = ((session.value(forKey: "threadLabel") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sanitized = ThreadLabelSanitizer.sanitize(raw, maxLength: 32),
              !sanitized.isEmpty else {
            return nil
        }

        return sanitized
    }

    private static let journalMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MMMM"
        return f
    }()

    private static let journalWeekIDFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let journalMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
