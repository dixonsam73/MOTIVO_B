// CHANGE-ID: 20260601_181500_PracticeInsightPendingDelivery
// SCOPE: Practice Insight pending-delivery support — expose ordered candidates so suppressed insights can be delayed, not destroyed. No UI/copy/threshold/archive logic changes.
// SEARCH-TOKEN: 20260601_181500_PracticeInsightPendingDelivery

import Foundation
import CoreData

enum PracticeInsightSelector {
    private static let focusWindowSize = 10
    private static let minimumFocusLeaderCount = 5
    private static let minimumFocusLeaderMargin = 2

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

        let candidates: [PracticeInsight?] = [
            archiveInsight(for: session, sessions: sessions),
            threadInsight(for: session, sessions: sessions),
            instrumentInsight(for: session, sessions: sessions),
            activityInsight(for: session, sessions: sessions)
        ]

        return candidates
            .compactMap { $0 }
            .filter { $0.collapsedText != excludedKey }
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
                expandedText: "The \(label) thread has appeared again",
                collapsedText: "\(label) thread appeared again"
            )

        case 3:
            return PracticeInsight(
                kind: .thread,
                expandedText: "The \(label) thread is becoming more regular",
                collapsedText: "\(label) thread becoming more regular"
            )

        case 10:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged ten sessions in the \(label) thread",
                collapsedText: "\(label) thread reached ten sessions"
            )

        case 25:
            return PracticeInsight(
                kind: .thread,
                expandedText: "The \(label) thread has become a substantial part of your journal",
                collapsedText: "\(label) thread has grown"
            )

        case 50:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged fifty sessions in the \(label) thread",
                collapsedText: "\(label) thread reached fifty sessions"
            )

        case 100:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged one hundred sessions in the \(label) thread",
                collapsedText: "\(label) thread reached one hundred sessions"
            )

        case 200:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged two hundred sessions in the \(label) thread",
                collapsedText: "\(label) thread reached two hundred sessions"
            )

        case 300:
            return PracticeInsight(
                kind: .thread,
                expandedText: "You've logged three hundred sessions in the \(label) thread",
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
                    expanded: "You've been spending more time practicing lately",
                    collapsed: "Spending more time practicing recently"
                ),
                (
                    expanded: "Practice has become a greater focus recently",
                    collapsed: "Focusing more on practice lately"
                ),
                (
                    expanded: "You've been practicing more recently",
                    collapsed: "Practicing more lately"
                )
            ]

        case "rehearsal":
            variants = [
                (
                    expanded: "You've been spending more time rehearsing lately",
                    collapsed: "Spending more time rehearsing recently"
                ),
                (
                    expanded: "Rehearsal has become a greater focus recently",
                    collapsed: "Focusing more on rehearsal lately"
                ),
                (
                    expanded: "You've been rehearsing more recently",
                    collapsed: "Rehearsing more lately"
                )
            ]

        case "recording":
            variants = [
                (
                    expanded: "You've been spending more time recording lately",
                    collapsed: "Spending more time recording recently"
                ),
                (
                    expanded: "Recording has become a greater focus recently",
                    collapsed: "Focusing more on recording lately"
                ),
                (
                    expanded: "You've been recording more recently",
                    collapsed: "Recording more lately"
                )
            ]

        case "lesson":
            variants = [
                (
                    expanded: "You've been spending more time taking lessons lately",
                    collapsed: "Spending more time taking lessons recently"
                ),
                (
                    expanded: "Lessons have become a greater focus recently",
                    collapsed: "Focusing more on lessons lately"
                ),
                (
                    expanded: "You've been taking more lessons recently",
                    collapsed: "Taking more lessons lately"
                )
            ]

        case "performance":
            variants = [
                (
                    expanded: "You've been spending more time performing lately",
                    collapsed: "Spending more time performing recently"
                ),
                (
                    expanded: "Performance has become a greater focus recently",
                    collapsed: "Focusing more on performance lately"
                ),
                (
                    expanded: "You've been performing more recently",
                    collapsed: "Performing more lately"
                )
            ]

        case "writing":
            variants = [
                (
                    expanded: "You've been spending more time writing lately",
                    collapsed: "Spending more time writing recently"
                ),
                (
                    expanded: "Writing has become a greater focus recently",
                    collapsed: "Focusing more on writing lately"
                ),
                (
                    expanded: "You've been writing more recently",
                    collapsed: "Writing more lately"
                )
            ]

        default:
            variants = [
                (
                    expanded: "You've been spending more time on \(label) lately",
                    collapsed: "Spending more time on \(label) recently"
                ),
                (
                    expanded: "\(label) has become a greater focus recently",
                    collapsed: "Focusing more on \(label) lately"
                ),
                (
                    expanded: "You've been doing more \(label) recently",
                    collapsed: "Doing more \(label) lately"
                )
            ]
        }

        return variants.randomElement() ?? variants[0]
    }

    private static func archiveInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        if let firstThreadInsight = firstThreadMilestone(for: session, sessions: sessions) {
            return firstThreadInsight
        }

        let count = sessions.count

        if count == 1 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "Your practice journal has begun",
                collapsedText: "Practice journal begun"
            )
        }

        if count == 5 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged five sessions",
                collapsedText: "Five sessions logged"
            )
        }

        if count == 10 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "You've logged ten sessions",
                collapsedText: "Ten sessions logged"
            )
        }

        if count == 25 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "Your practice journal now contains twenty-five sessions",
                collapsedText: "Twenty-five sessions logged"
            )
        }

        if count == 50 {
            return PracticeInsight(
                kind: .archive,
                expandedText: "Fifty sessions are now part of your practice journal",
                collapsedText: "Fifty sessions logged"
            )
        }

        return nil
    }

    private static func firstThreadMilestone(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard normalized(session.value(forKey: "threadLabel") as? String) != nil else { return nil }

        let threadTaggedSessions = sessions.filter {
            normalized($0.value(forKey: "threadLabel") as? String) != nil
        }

        guard threadTaggedSessions.count == 1 else { return nil }

        return PracticeInsight(
            kind: .archive,
            expandedText: "You've started your first thread",
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
