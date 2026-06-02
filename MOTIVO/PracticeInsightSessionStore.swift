// CHANGE-ID: 20260602_200800_PracticeInsightPendingStaleArchiveFix
// SCOPE: Practice Insight pending-delivery bug fix — prevent stale archive milestones from surfacing after unrelated saves. No UI/backend/schema changes.
// SEARCH-TOKEN: 20260602_200800_PracticeInsightPendingStaleArchiveFix

import Foundation
import CoreData

@MainActor
final class PracticeInsightSessionStore: ObservableObject {
    static let shared = PracticeInsightSessionStore()

    @Published private(set) var currentInsight: PracticeInsight?
    private var lastInsightKey: String?
    private var pendingInsights: [PracticeInsight] = []

    private init() {}

    func generateInsight(forNewlySavedSession session: Session, in context: NSManagedObjectContext) {
        let freshInsights = PracticeInsightSelector.selectCandidates(
            forNewlySavedSession: session,
            in: context,
            excludingInsightKey: lastInsightKey
        )

        let carriedPendingInsights = pendingInsights.filter {
            $0.kind != .archive && $0.suppressionKey != lastInsightKey
        }

        let orderedFreshInsights = ordered(
            deduplicated(freshInsights, excludingInsightKey: lastInsightKey)
        )

        if let insight = orderedFreshInsights.first {
            currentInsight = insight
            lastInsightKey = insight.suppressionKey

            let remainingFreshInsights = Array(orderedFreshInsights.dropFirst()).filter { $0.kind != .archive }
            pendingInsights = ordered(
                deduplicated(
                    remainingFreshInsights + carriedPendingInsights,
                    excludingInsightKey: lastInsightKey
                )
            )
            return
        }

        let orderedPendingInsights = ordered(
            deduplicated(carriedPendingInsights, excludingInsightKey: lastInsightKey)
        )

        guard let insight = orderedPendingInsights.first else {
            currentInsight = nil
            pendingInsights = []
            return
        }

        currentInsight = insight
        lastInsightKey = insight.suppressionKey
        pendingInsights = Array(orderedPendingInsights.dropFirst())
    }

    func clearCurrentInsight() {
        currentInsight = nil
    }

    func clear() {
        currentInsight = nil
        pendingInsights = []
    }


    private func deduplicated(
        _ insights: [PracticeInsight],
        excludingInsightKey excludedKey: String?
    ) -> [PracticeInsight] {
        var seenKeys = Set<String>()
        var result: [PracticeInsight] = []

        for insight in insights {
            let key = insight.suppressionKey
            guard key != excludedKey else { continue }
            guard seenKeys.contains(key) == false else { continue }

            seenKeys.insert(key)
            result.append(insight)
        }

        return result
    }


    private func ordered(_ insights: [PracticeInsight]) -> [PracticeInsight] {
        insights
            .enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: lhs.element.kind)
                let rhsPriority = priority(for: rhs.element.kind)

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return lhs.offset < rhs.offset
            }
            .map { $0.element }
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
