// CHANGE-ID: 20260601_190500_PracticeInsightExpandedOnlyLifecycle
// SCOPE: Practice Insight lifecycle simplification — keep insights expanded-only and remove collapse timer/display state. Preserve pending delivery, selector, copy, thresholds, archive logic, and UI styling intent.
// SEARCH-TOKEN: 20260601_190500_PracticeInsightExpandedOnlyLifecycle

import Foundation
import CoreData

@MainActor
final class PracticeInsightSessionStore: ObservableObject {
    static let shared = PracticeInsightSessionStore()

    @Published private(set) var currentInsight: PracticeInsight?
    private var lastInsightKey: String?
    private var pendingInsight: PracticeInsight?

    private init() {}

    func generateInsight(forNewlySavedSession session: Session, in context: NSManagedObjectContext) {
        let freshInsights = PracticeInsightSelector.selectCandidates(
            forNewlySavedSession: session,
            in: context,
            excludingInsightKey: lastInsightKey
        )

        let insightToShow: PracticeInsight?

        if let pendingInsight {
            if let freshInsight = freshInsights.first,
               priority(for: freshInsight.kind) < priority(for: pendingInsight.kind) {
                insightToShow = freshInsight
            } else {
                insightToShow = pendingInsight
            }

            self.pendingInsight = nil
        } else if let freshInsight = freshInsights.first {
            insightToShow = freshInsight
            pendingInsight = freshInsights.dropFirst().first
        } else {
            insightToShow = nil
        }

        guard let insight = insightToShow else {
            currentInsight = nil
            return
        }

        currentInsight = insight
        lastInsightKey = insight.collapsedText

    }

    func clearCurrentInsight() {
        currentInsight = nil
    }

    func clear() {
        currentInsight = nil
        pendingInsight = nil
    }

    private func priority(for kind: PracticeInsightKind) -> Int {
        switch kind {
        case .archive:
            return 0
        case .thread:
            return 1
        case .instrument:
            return 2
        case .activity:
            return 3
        }
    }
}
