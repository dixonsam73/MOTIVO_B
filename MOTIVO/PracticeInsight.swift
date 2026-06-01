// CHANGE-ID: 20260530_201500_PracticeInsightV1
// SCOPE: Practice Insight v1 — lightweight post-save reflection model. Text-first, session-only, no backend/schema changes.
// SEARCH-TOKEN: 20260530_201500_PracticeInsightV1

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

    init(
        id: UUID = UUID(),
        kind: PracticeInsightKind,
        title: String = "Practice Insight",
        expandedText: String,
        collapsedText: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.expandedText = expandedText
        self.collapsedText = collapsedText
    }
}
