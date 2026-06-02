// CHANGE-ID: 20260602_194500_PracticeInsightSuppressionKey
// SCOPE: Practice Insight identity hardening — add explicit suppression key while preserving collapsed text compatibility. No UI/backend/schema changes.
// SEARCH-TOKEN: 20260602_194500_PracticeInsightSuppressionKey

import Foundation

enum PracticeInsightKind: String, Equatable {
    case thread
    case instrument
    case activity
    case archive
}

struct PracticeInsight: Identifiable, Equatable {
    let id: UUID
    let kind: PracticeInsightKind
    let title: String
    let expandedText: String
    let collapsedText: String
    let suppressionKey: String

    init(
        id: UUID = UUID(),
        kind: PracticeInsightKind,
        title: String = "Practice Insight",
        expandedText: String,
        collapsedText: String,
        suppressionKey: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.expandedText = expandedText
        self.collapsedText = collapsedText
        self.suppressionKey = suppressionKey ?? collapsedText
    }
}
