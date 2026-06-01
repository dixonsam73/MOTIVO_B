// CHANGE-ID: 20260530_201500_PracticeInsightV1
// SCOPE: Practice Insight v1 — text-first post-save reflection card with centralised timing/layout tuning. Fade-only presentation.
// SEARCH-TOKEN: 20260530_201500_PracticeInsightV1

import SwiftUI

enum PracticeInsightCardTuning {
    static let expandedDuration: TimeInterval = 4.5
    static let expandFadeDuration: TimeInterval = 0.35
    static let collapseFadeDuration: TimeInterval = 0.35

    static let expandedMinHeight: CGFloat = 82
    static let collapsedMinHeight: CGFloat = 42
    static let expandedVerticalPadding: CGFloat = 12
    static let collapsedVerticalPadding: CGFloat = 9
}

struct PracticeInsightCard: View {
    @ObservedObject var store: PracticeInsightSessionStore

    var body: some View {
        Group {
            if let insight = store.currentInsight {
                content(for: insight)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: PracticeInsightCardTuning.expandFadeDuration), value: insight.id)
                    .animation(.easeInOut(duration: PracticeInsightCardTuning.collapseFadeDuration), value: store.displayState)
            }
        }
    }

    @ViewBuilder
    private func content(for insight: PracticeInsight) -> some View {
        let isExpanded = store.displayState == .expanded

        VStack(alignment: .leading, spacing: isExpanded ? 5 : 0) {
            if isExpanded {
                Text(insight.title)
                    .font(Theme.Text.meta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .transition(.opacity)
            }

            Text(isExpanded ? insight.expandedText : insight.collapsedText)
                .font(Theme.Text.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        .frame(minHeight: isExpanded ? PracticeInsightCardTuning.expandedMinHeight : PracticeInsightCardTuning.collapsedMinHeight)

        .padding(.horizontal, Theme.Spacing.card)

        .padding(.vertical, isExpanded ? PracticeInsightCardTuning.expandedVerticalPadding : PracticeInsightCardTuning.collapsedVerticalPadding)

        .background(

            Theme.Colors.accent.opacity(0.08)

        )

        .clipShape(

            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)

        )

        .cardSurface(padding: 0)
    }
}
