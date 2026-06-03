// CHANGE-ID: 20260603_115800_PracticeInsightExplicitSuppression
// SCOPE: Practice Insight cleanup — remove collapsedText from the model and require explicit suppression keys. No UI/backend/schema changes.
// SEARCH-TOKEN: 20260603_115800_PracticeInsightExplicitSuppression

import Foundation

enum PracticeInsightKind: String, Equatable {
    case thread
    case instrument
    case activity
    case archive
    case observation
}

struct PracticeInsight: Identifiable, Equatable {
    let id: UUID
    let kind: PracticeInsightKind
    let title: String
    let expandedText: String
    let suppressionKey: String

    init(
        id: UUID = UUID(),
        kind: PracticeInsightKind,
        title: String = "Practice Insight",
        expandedText: String,
        suppressionKey: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.expandedText = expandedText
        self.suppressionKey = suppressionKey
    }
}
