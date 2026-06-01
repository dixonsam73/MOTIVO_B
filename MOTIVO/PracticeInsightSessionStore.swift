// CHANGE-ID: 20260601_181500_PracticeInsightPendingDelivery
// SCOPE: Practice Insight pending-delivery support — hold at most one suppressed insight for one future save. No UI/copy/threshold/archive logic changes.
// SEARCH-TOKEN: 20260601_181500_PracticeInsightPendingDelivery

import Foundation
import CoreData

@MainActor
final class PracticeInsightSessionStore: ObservableObject {
    enum DisplayState: Equatable {
        case expanded
        case collapsed
    }

    static let shared = PracticeInsightSessionStore()

    @Published private(set) var currentInsight: PracticeInsight?
    @Published private(set) var displayState: DisplayState = .collapsed

    private var collapseTask: Task<Void, Never>?
    private var lastInsightKey: String?
    private var pendingInsight: PracticeInsight?

    private init() {}

    func generateInsight(forNewlySavedSession session: Session, in context: NSManagedObjectContext) {
        collapseTask?.cancel()

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
            displayState = .collapsed
            return
        }

        currentInsight = insight
        displayState = .expanded
        lastInsightKey = insight.collapsedText

        collapseTask = Task { [weak self] in
            let nanoseconds = UInt64(PracticeInsightCardTuning.expandedDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.displayState = .collapsed
            }
        }
    }

    func clear() {
        collapseTask?.cancel()
        collapseTask = nil
        currentInsight = nil
        displayState = .collapsed
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
