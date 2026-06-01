// CHANGE-ID: 20260530_201500_PracticeInsightV1
// SCOPE: Practice Insight v1 — select one calm post-save reflection biased toward the newly saved session. No thought/note/attachment interpretation.
// SEARCH-TOKEN: 20260530_201500_PracticeInsightV1

import Foundation
import CoreData

enum PracticeInsightSelector {
    static func select(
        forNewlySavedSession session: Session,
        in context: NSManagedObjectContext,
        excludingInsightKey excludedKey: String?
    ) -> PracticeInsight? {

        guard isEligiblePracticeSession(session) else { return nil }

        let ownerUserID = normalized(session.value(forKey: "ownerUserID") as? String)
        let sessions = fetchEligibleSessions(in: context, ownerUserID: ownerUserID)
        guard sessions.isEmpty == false else { return nil }

        let candidates: [PracticeInsight?] = [
            threadInsight(for: session, sessions: sessions),
            instrumentInsight(for: session, sessions: sessions),
            activityInsight(for: session, sessions: sessions),
            archiveInsight(for: session, sessions: sessions)
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if candidate.collapsedText != excludedKey {
                return candidate
            }
        }

        return nil
    }

    private static func threadInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard let label = normalized(session.value(forKey: "threadLabel") as? String) else { return nil }
        let count = sessions.filter { normalized($0.value(forKey: "threadLabel") as? String)?.caseInsensitiveCompare(label) == .orderedSame }.count

        if count >= 3 {
            return PracticeInsight(
                kind: .thread,
                expandedText: "The \(label) thread is becoming more regular",
                collapsedText: "\(label) becoming more regular"
            )
        }

        if count == 2 {
            return PracticeInsight(
                kind: .thread,
                expandedText: "\(label) has appeared again",
                collapsedText: "\(label) appeared again"
            )
        }

        if count == 1 {
            return nil
        }

        return nil
    }

    private static func instrumentInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard let label = instrumentLabel(for: session) else { return nil }
        let count = sessions.filter { instrumentLabel(for: $0)?.caseInsensitiveCompare(label) == .orderedSame }.count
        guard count >= 3 else { return nil }

        return PracticeInsight(
            kind: .instrument,
            expandedText: "\(label) has featured more recently",
            collapsedText: "\(label) featured more recently"
        )
    }

    private static func activityInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
        guard let label = activityLabel(for: session) else { return nil }
        let count = sessions.filter { activityLabel(for: $0)?.caseInsensitiveCompare(label) == .orderedSame }.count
        guard count >= 3 else { return nil }

        return PracticeInsight(
            kind: .activity,
            expandedText: "\(label) has appeared more frequently recently",
            collapsedText: "\(label) appearing more frequently"
        )
    }

    private static func archiveInsight(for session: Session, sessions: [Session]) -> PracticeInsight? {
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

        return nil
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

    private static func normalized(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.isEmpty ? nil : value
    }
}
