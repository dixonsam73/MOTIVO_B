// CHANGE-ID: 20260602_213500_PracticeInsightObservations
// SCOPE: Practice Insights Pass 2 — add observational insight kind for practice-window and session-length pattern observations. No UI/backend/schema changes.
// SEARCH-TOKEN: 20260602_213500_PracticeInsightObservations

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
