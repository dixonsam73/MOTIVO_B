// CHANGE-ID: 20260602_222800_PracticeInsightCopyPolish
// SCOPE: Practice Insight copy polish — refine visible insight language for milestones, observations, thread focus, leadership, and activity recurrence. No selection, suppression, UI, backend, schema, or persistence changes.
// SEARCH-TOKEN: 20260602_222800_PracticeInsightCopyPolish

import Foundation
import CoreData

enum PracticeInsightSelector {
    private static let focusWindowSize = 10
    private static let minimumFocusLeaderCount = 5
    private static let minimumFocusLeaderMargin = 2
    private static let totalHourThresholds = [10, 25, 50, 100, 250, 500, 1000]
    private static let observationWindowSize = 8
    private static let minimumPracticeWindowObservationSessions = 6
    private static let minimumSessionShapeObservationSessions = 6

    static func select(
        forNewlySavedSession session: Session,
        in context: NSManagedObjectContext,
        excludingInsightKey excludedKey: String?
    ) -> PracticeInsight? {
        selectCandidates(
            forNewlySavedSession: session,
            in: context,
            excludingInsightKey: excludedKey
        ).first
    }

    static func selectCandidates(
        forNewlySavedSession session: Session,
        in context: NSManagedObjectContext,
        excludingInsightKey excludedKey: String?
    ) -> [PracticeInsight] {

        guard isEligiblePracticeSession(session) else { return [] }

        let ownerUserID = normalized(session.value(forKey: "ownerUserID") as? String)
        let sessions = fetchEligibleSessions(in: context, ownerUserID: ownerUserID)
        guard sessions.isEmpty == false else { return [] }

        let candidates: [PracticeInsight] =
            archiveInsights(for: session, sessions: sessions) +
            observationInsights(for: session, sessions: sessions) +
            [
                threadInsight(for: session, sessions: sessions),
                instrumentInsight(for: session, sessions: sessions),
                activityInsight(for: session, sessions: sessions)
            ].compactMap { $0 }

        return candidates
            .filter { $0.suppressionKey != excludedKey }
    }


    private static func observationInsights(for session: Session, sessions: [Session]) -> [PracticeInsight] {
        var insights: [PracticeInsight] = []

        if let practiceWindow = practiceWindowObservation(for: session, sessions: sessions) {
            insights.append(practiceWindow)
        }

        if let sessionShape = sessionShapeObservation(for: session, sessions: sessions) {
            insights.append(sessionShape)
        }

        return insights
    }

    private static func practiceWindowObservation(for session: Session, sessions: [Session]) -> PracticeInsight? {
        let recentSessions = Array(sessions.prefix(observationWindowSize))
        guard recentSessions.count >= minimumPracticeWindowObservationSessions else { return nil }
        guard recentSessions.contains(where: { $0.objectID == session.objectID }) else { return nil }

        let previousRecentSessions = Array(
            sessions
                .filter { $0.objectID != session.objectID }
                .prefix(observationWindowSize)
        )

        let currentWindow = InsightEngine.insights(from: recentSessions).practiceWindow
        let previousWindow = previousRecentSessions.count >= minimumPracticeWindowObservationSessions
            ? InsightEngine.insights(from: previousRecentSessions).practiceWindow
            : PracticeWindowInsight.insufficientData

        guard currentWindow != previousWindow else { return nil }

        switch currentWindow {
        case .mornings:
            return PracticeInsight(
                kind: .observation,
                expandedText: randomText([
                    "You've been more active in the mornings recently.",
                    "More of your recent activity has been happening in the mornings."
                ]),
                collapsedText: "Morning activity emerging",
                suppressionKey: "observation.practiceWindow.morning"
            )

        case .afternoons:
            return PracticeInsight(
                kind: .observation,
                expandedText: randomText([
                    "Afternoon activity has been happening more often lately.",
                    "You've been spending more time working in the afternoons recently."
                ]),
                collapsedText: "Afternoon activity emerging",
                suppressionKey: "observation.practiceWindow.afternoon"
            )

        case .evenings:
            return PracticeInsight(
                kind: .observation,
                expandedText: randomText([
                    "You've been more active in the evenings recently.",
                    "More of your recent activity has been happening in the evenings."
                ]),
                collapsedText: "Evening activity emerging",
                suppressionKey: "observation.practiceWindow.evening"
            )

        case .spreadThroughDay, .insufficientData:
            return nil
        }
    }

    private static func sessionShapeObservation(for session: Session, sessions: [Session]) -> PracticeInsight? {
        let recentSessions = Array(sessions.prefix(observationWindowSize))
        guard recentSessions.count >= minimumSessionShapeObservationSessions else { return nil }
        guard recentSessions.contains(where: { $0.objectID == session.objectID }) else { return nil }

        let recentSessionsWithDuration = recentSessions.filter { Int($0.durationSeconds) > 0 }
        guard recentSessionsWithDuration.count >= minimumSessionShapeObservationSessions else { return nil }

        let previousRecentSessions = Array(
            sessions
                .filter { $0.objectID != session.objectID }
                .prefix(observationWindowSize)
        )
        let previousRecentSessionsWithDuration = previousRecentSessions.filter { Int($0.durationSeconds) > 0 }

        let currentShape = InsightEngine.insights(from: recentSessions).sessionShape
        let previousShape = previousRecentSessionsWithDuration.count >= minimumSessionShapeObservationSessions
            ? InsightEngine.insights(from: previousRecentSessions).sessionShape
            : SessionShapeInsight.insufficientData

        guard currentShape == .consistent else { return nil }
        guard previousShape != .consistent else { return nil }

        return PracticeInsight(
            kind: .observation,
            expandedText: "Recent sessions have settled into a similar length",
            collapsedText: "Session lengths becoming consistent",
            suppressionKey: "observation.sessionShape.consistent"
        )
    }

    private static func threadInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard let label = normalized(session.value(forKey: "threadLabel") as? String) else { return nil }
        let count = sessions.filter {
            normalized($0.value(forKey: "threadLabel") as? String)?.caseInsensitiveCompare(label) == .orderedSame
        }.count

        switch count {
        case 2:
            return PracticeInsight(
                kind: .thread,
                expandedText: randomText(["You've returned to the \(label) thread.", "You've been working on the \(label) thread again."]),
                collapsedText: "\(label) thread appeared again"
            )

        case 3:
            return PracticeInsight(
                kind: .thread,
                expandedText: randomText(["You've been spending more time on the \(label) thread lately.", "The \(label) thread has been a regular focus recently."]),
                collapsedText: "\(label) thread becoming more regular"
            )

        case 10:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged ten entries in the \(label) thread.",
                collapsedText: "\(label) thread reached ten sessions"
            )

        case 25:
            return PracticeInsight(
                kind: .thread,
                expandedText: randomText(["More of your recent activity has centred on the \(label) thread.", "You've been spending a lot of time on the \(label) thread lately."]),
                collapsedText: "\(label) thread has grown"
            )

        case 50:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged fifty entries in the \(label) thread.",
                collapsedText: "\(label) thread reached fifty sessions"
            )

        case 100:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged one hundred entries in the \(label) thread.",
                collapsedText: "\(label) thread reached one hundred sessions"
            )

        case 200:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged two hundred entries in the \(label) thread.",
                collapsedText: "\(label) thread reached two hundred sessions"
            )

        case 300:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged three hundred entries in the \(label) thread.",
                collapsedText: "\(label) thread reached three hundred sessions"
            )

        default:
            return nil
        }
    }

    private static func instrumentInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard let shift = focusShift(in: sessions, labelFor: instrumentLabel(for:)) else { return nil }
        let text = instrumentInsightText(for: shift.displayLabel)

        return PracticeInsight(
            kind: .instrument,
            expandedText: text.expanded,
            collapsedText: text.collapsed
        )
    }

    private static func activityInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard let shift = focusShift(in: sessions, labelFor: activityLabel(for:)) else { return nil }
        let text = activityInsightText(for: shift.displayLabel)

        return PracticeInsight(
            kind: .activity,
            expandedText: text.expanded,
            collapsedText: text.collapsed
        )
    }

    private static func instrumentInsightText(for label: String) -> (expanded: String, collapsed: String) {
        let variants: [(expanded: String, collapsed: String)] = [
            (
                expanded: "You've been spending more time on \(label) lately",
                collapsed: "Spending more time on \(label) recently"
            ),
            (
                expanded: "\(label) has become a greater focus recently",
                collapsed: "More focus on \(label) lately"
            ),
            (
                expanded: "You've been playing more \(label) recently",
                collapsed: "Playing more \(label) lately"
            )
        ]

        return variants.randomElement() ?? variants[0]
    }

    private static func activityInsightText(for label: String) -> (expanded: String, collapsed: String) {
        let variants: [(expanded: String, collapsed: String)]

        switch normalizedKey(label) {
        case "practice":
            variants = [
                (
                    expanded: "You've been practicing more lately",
                    collapsed: "Practicing more lately"
                ),
                (
                    expanded: "You've been spending more time practicing recently",
                    collapsed: "Spending more time practicing recently"
                )
            ]

        case "rehearsal":
            variants = [
                (
                    expanded: "You've been rehearsing more lately",
                    collapsed: "Rehearsing more lately"
                ),
                (
                    expanded: "You've been spending more time rehearsing recently",
                    collapsed: "Spending more time rehearsing recently"
                )
            ]

        case "recording":
            variants = [
                (
                    expanded: "You've been recording more lately",
                    collapsed: "Recording more lately"
                ),
                (
                    expanded: "You've been spending more time recording recently",
                    collapsed: "Spending more time recording recently"
                )
            ]

        case "lesson":
            variants = [
                (
                    expanded: "You've been having more lessons recently",
                    collapsed: "Having more lessons recently"
                ),
                (
                    expanded: "You've been logging more lessons lately",
                    collapsed: "Logging more lessons lately"
                )
            ]

        case "performance":
            variants = [
                (
                    expanded: "You've been performing more lately",
                    collapsed: "Performing more lately"
                ),
                (
                    expanded: "You've been spending more time performing recently",
                    collapsed: "Spending more time performing recently"
                )
            ]

        case "writing":
            variants = [
                (
                    expanded: "You've been writing more lately",
                    collapsed: "Writing more lately"
                ),
                (
                    expanded: "You've been spending more time writing recently",
                    collapsed: "Spending more time writing recently"
                )
            ]

        default:
            variants = [
                (
                    expanded: "You've been spending more time on \(label) lately",
                    collapsed: "Spending more time on \(label) recently"
                ),
                (
                    expanded: "You've been logging more \(label) recently",
                    collapsed: "Logging more \(label) recently"
                )
            ]
        }

        return variants.randomElement() ?? variants[0]
    }

    private static func archiveInsights(for session: Session, sessions: [Session]) -> [PracticeInsight] {
        var insights: [PracticeInsight] = []

        if let existingArchive = archiveInsight(for: session, sessions: sessions) {
            insights.append(existingArchive)
        }

        if let longestSession = longestSessionMilestone(for: session, sessions: sessions) {
            insights.append(longestSession)
        }

        insights.append(contentsOf: totalHoursMilestones(for: session, sessions: sessions))

     

        if let instrumentLeader = durationLeadershipMilestone(
            for: session,
            sessions: sessions,
            labelFor: instrumentLabel(for:),
            family: .instrument
        ) {
            insights.append(instrumentLeader)
        }

        if let activityLeader = durationLeadershipMilestone(
            for: session,
            sessions: sessions,
            labelFor: activityLabel(for:),
            family: .activity
        ) {
            insights.append(activityLeader)
        }

        return insights
    }

    private static func archiveInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        if let firstThreadInsight = firstThreadMilestone(for: session, sessions: sessions) {
            return firstThreadInsight
        }

        let count = sessions.count

        if count == 1 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "Your practice journal has begun.",
                collapsedText: "Practice journal begun"
            )
        }

        if count == 5 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged five entries in your journal.",
                collapsedText: "Five sessions logged"
            )
        }

        if count == 10 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged ten entries in your journal.",
                collapsedText: "Ten sessions logged"
            )
        }

        if count == 25 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged twenty-five entries in your journal.",
                collapsedText: "Twenty-five sessions logged"
            )
        }

        if count == 50 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged fifty entries in your journal.",
                collapsedText: "Fifty sessions logged"
            )
        }

        return nil
    }

    private static func longestSessionMilestone(for session: Session, sessions: [Session]) -> PracticeInsight? {
        let currentDuration = Int(session.durationSeconds)
        guard currentDuration > 0 else { return nil }

        let previousLongest = sessions
            .filter { $0.objectID != session.objectID }
            .map { Int($0.durationSeconds) }
            .max() ?? 0

        guard previousLongest > 0 else { return nil }
        guard currentDuration > previousLongest else { return nil }

        return PracticeInsight(
            kind: .archive,
            expandedText: "This was your longest session so far.",
            collapsedText: "Longest session so far",
            suppressionKey: "archive.longestSession.\(currentDuration)"
        )
    }

    private static func totalHoursMilestones(for session: Session, sessions: [Session]) -> [PracticeInsight] {
        let currentDuration = Int(session.durationSeconds)
        guard currentDuration > 0 else { return [] }

        let totalSeconds = sessions.reduce(0) { $0 + max(0, Int($1.durationSeconds)) }
        let previousTotalSeconds = max(0, totalSeconds - currentDuration)

        return totalHourThresholds.compactMap { threshold in
            let thresholdSeconds = threshold * 60 * 60
            guard previousTotalSeconds < thresholdSeconds,
                  totalSeconds >= thresholdSeconds else {
                return nil
            }

            return totalHoursMilestone(for: threshold)
        }
    }

    private static func totalHoursMilestone(for threshold: Int) -> PracticeInsight {
        switch threshold {
        case 10:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged ten hours of activity.",
                collapsedText: "Ten hours of activity logged",
                suppressionKey: "archive.totalHours.10"
            )

        case 25:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged twenty-five hours of activity.",
                collapsedText: "Twenty-five hours of activity logged",
                suppressionKey: "archive.totalHours.25"
            )

        case 50:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged fifty hours of activity.",
                collapsedText: "Fifty hours of activity logged",
                suppressionKey: "archive.totalHours.50"
            )

        case 100:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged one hundred hours of activity.",
                collapsedText: "One hundred hours of activity logged",
                suppressionKey: "archive.totalHours.100"
            )

        case 250:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged two hundred and fifty hours of activity.",
                collapsedText: "Two hundred and fifty hours of activity logged",
                suppressionKey: "archive.totalHours.250"
            )

        case 500:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged five hundred hours of activity.",
                collapsedText: "Five hundred hours of activity logged",
                suppressionKey: "archive.totalHours.500"
            )

        case 1000:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged one thousand hours of activity.",
                collapsedText: "One thousand hours of activity logged",
                suppressionKey: "archive.totalHours.1000"
            )

        default:
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged \(threshold) hours of activity.",
                collapsedText: "\(threshold) hours of activity logged",
                suppressionKey: "archive.totalHours.\(threshold)"
            )
        }
    }

   

    private enum DurationLeadershipFamily {
        case instrument
        case activity
    }

    private static func durationLeadershipMilestone(
        for session: Session,
        sessions: [Session],
        labelFor: (Session) -> String?,
        family: DurationLeadershipFamily
    ) -> PracticeInsight? {
        let previousSessions = sessions.filter { $0.objectID != session.objectID }

        guard let currentLeader = durationLeader(in: sessions, labelFor: labelFor),
              let previousLeader = durationLeader(in: previousSessions, labelFor: labelFor),
              currentLeader.key != previousLeader.key else {
            return nil
        }

        switch family {
        case .instrument:
            return PracticeInsight(
                kind: .archive,
                expandedText: instrumentLeadershipText(for: currentLeader.displayLabel),
                collapsedText: "\(currentLeader.displayLabel) became leading instrument",
                suppressionKey: "archive.instrumentLeader.\(currentLeader.key).\(currentLeader.seconds)"
            )

        case .activity:
            return PracticeInsight(
                kind: .archive,
                expandedText: activityLeadershipText(for: currentLeader.displayLabel),
                collapsedText: "\(currentLeader.displayLabel) became leading activity",
                suppressionKey: "archive.activityLeader.\(currentLeader.key).\(currentLeader.seconds)"
            )
        }
    }

    private static func instrumentLeadershipText(for label: String) -> String {
        randomText([
            "You've spent more time playing \(label) than any other instrument.",
            "More of your time has been spent playing \(label) than any other instrument."
        ])
    }

    private static func activityLeadershipText(for label: String) -> String {
        let phrase = activityLeadershipPhrase(for: label)
        return randomText([
            "You've spent more time \(phrase) than any other activity.",
            "More of your time has been spent \(phrase) than any other activity."
        ])
    }

    private static func activityLeadershipPhrase(for label: String) -> String {
        switch normalizedKey(label) {
        case "practice": return "practicing"
        case "rehearsal": return "rehearsing"
        case "recording": return "recording"
        case "lesson": return "having lessons"
        case "performance": return "performing"
        case "writing": return "writing"
        default: return "on \(label)"
        }
    }

    private struct DurationLeader {
        let key: String
        let displayLabel: String
        let seconds: Int
    }

    private static func durationLeader(in sessions: [Session], labelFor: (Session) -> String?) -> DurationLeader? {
        var totals: [String: (displayLabel: String, seconds: Int)] = [:]

        for session in sessions {
            guard let label = normalized(labelFor(session)),
                  let key = normalizedKey(label) else {
                continue
            }

            let seconds = max(0, Int(session.durationSeconds))
            guard seconds > 0 else { continue }

            if let existing = totals[key] {
                totals[key] = (displayLabel: existing.displayLabel, seconds: existing.seconds + seconds)
            } else {
                totals[key] = (displayLabel: label, seconds: seconds)
            }
        }

        return totals
            .map { key, value in
                DurationLeader(
                    key: key,
                    displayLabel: value.displayLabel,
                    seconds: value.seconds
                )
            }
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds {
                    return lhs.seconds > rhs.seconds
                }

                return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
            }
            .first
    }

    private static func firstThreadMilestone(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard normalized(session.value(forKey: "threadLabel") as? String) != nil else { return nil }

        let threadTaggedSessions = sessions.filter {
            normalized($0.value(forKey: "threadLabel") as? String) != nil
        }

        guard threadTaggedSessions.count == 1 else { return nil }

        return PracticeInsight(
            kind: .archive,
            expandedText: "You've started your first thread.",
            collapsedText: "First thread created"
        )
    }

    private struct FocusLeader {
        let key: String
        let displayLabel: String
        let count: Int
    }

    private static func focusShift(in sessions: [Session], labelFor: (Session) -> String?) -> FocusLeader? {
        guard let currentShift = focusShiftSnapshot(in: sessions, labelFor: labelFor) else { return nil }

        let priorSessions = Array(sessions.dropFirst())
        if let priorShift = focusShiftSnapshot(in: priorSessions, labelFor: labelFor),
           priorShift.key == currentShift.key {
            return nil
        }

        return currentShift
    }

    private static func focusShiftSnapshot(in sessions: [Session], labelFor: (Session) -> String?) -> FocusLeader? {
        guard sessions.count > focusWindowSize else { return nil }

        let currentWindow = Array(sessions.prefix(focusWindowSize))
        let historicalWindow = Array(sessions.dropFirst(focusWindowSize))

        guard currentWindow.count == focusWindowSize,
              historicalWindow.isEmpty == false else {
            return nil
        }

        guard let currentLeader = focusLeader(in: currentWindow, labelFor: labelFor),
              let historicalLeader = focusLeader(in: historicalWindow, labelFor: labelFor) else {
            return nil
        }

        guard currentLeader.key != historicalLeader.key else { return nil }

        return currentLeader
    }

    private static func focusLeader(in window: [Session], labelFor: (Session) -> String?) -> FocusLeader? {
        var counts: [String: (displayLabel: String, count: Int)] = [:]

        for session in window {
            guard let label = normalized(labelFor(session)),
                  let key = normalizedKey(label) else {
                continue
            }

            if let existing = counts[key] {
                counts[key] = (displayLabel: existing.displayLabel, count: existing.count + 1)
            } else {
                counts[key] = (displayLabel: label, count: 1)
            }
        }

        let ranked: [(key: String, displayLabel: String, count: Int)] = counts.map { key, value in
            (key: key, displayLabel: value.displayLabel, count: value.count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }

            return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
        }

        guard let leader = ranked.first else { return nil }

        let secondPlaceCount = ranked.dropFirst().first?.count ?? 0

        guard leader.count >= minimumFocusLeaderCount else { return nil }
        guard leader.count - secondPlaceCount >= minimumFocusLeaderMargin else { return nil }

        return FocusLeader(
            key: leader.key,
            displayLabel: leader.displayLabel,
            count: leader.count
        )
    }

    private static func fetchEligibleSessions(in context: NSManagedObjectContext, ownerUserID: String?) -> [Session] {
        let request: NSFetchRequest<Session> = Session.fetchRequest()
        request.fetchLimit = 500
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        if let ownerUserID {
            request.predicate = NSPredicate(format: "ownerUserID == %@", ownerUserID)
        }

        do {
            return try context.fetch(request).filter { isEligiblePracticeSession($0) }
        } catch {
            return []
        }
    }

    private static func isEligiblePracticeSession(_ session: Session) -> Bool {
        if let title = session.value(forKey: "title") as? String,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Int(session.durationSeconds) == 0 {
            return false
        }

        if let activityDetail = session.value(forKey: "activityDetail") as? String,
           activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Int(session.durationSeconds) == 0 {
            return false
        }

        return Int(session.durationSeconds) > 0
    }

    private static func instrumentLabel(for session: Session) -> String? {
        if let local = normalized(session.value(forKey: "userInstrumentLabel") as? String) {
            return local
        }
        return normalized(session.instrument?.name)
    }

    private static func activityLabel(for session: Session) -> String? {
        if let custom = normalized(session.value(forKey: "userActivityLabel") as? String) {
            return custom
        }

        if let raw = session.value(forKey: "activityType") as? Int16 {
            return activityName(for: raw)
        }

        if let number = session.value(forKey: "activityType") as? NSNumber {
            return activityName(for: number.int16Value)
        }

        return nil
    }

    private static func activityName(for raw: Int16) -> String? {
        switch raw {
        case 0: return "Practice"
        case 1: return "Rehearsal"
        case 2: return "Recording"
        case 3: return "Lesson"
        case 4: return "Performance"
        default: return nil
        }
    }

    private static func randomText(_ variants: [String]) -> String {
        variants.randomElement() ?? variants.first ?? ""
    }

    private static func normalizedKey(_ value: String?) -> String? {
        normalized(value)?.lowercased()
    }

    private static func normalized(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.isEmpty ? nil : value
    }
}
