// CHANGE-ID: 20260530_201500_PracticeInsightV1
// SCOPE: Practice Insight v1 — memory-only post-save insight lifecycle. One active insight, replaced by next save, cleared on relaunch.
// SEARCH-TOKEN: 20260530_201500_PracticeInsightV1

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

    private init() {}

    func generateInsight(forNewlySavedSession session: Session, in context: NSManagedObjectContext) {
        collapseTask?.cancel()

        guard let insight = PracticeInsightSelector.select(
            forNewlySavedSession: session,
            in: context,
            excludingInsightKey: lastInsightKey
        ) else {
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
    }
}
