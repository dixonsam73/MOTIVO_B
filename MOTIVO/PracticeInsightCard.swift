// CHANGE-ID: 20260601_190500_PracticeInsightExpandedOnlyLifecycle
// SCOPE: Practice Insight card simplification — render expanded insight copy only. No selector, pending-delivery, copy, threshold, archive, or placement changes.
// SEARCH-TOKEN: 20260601_190500_PracticeInsightExpandedOnlyLifecycle

import SwiftUI

enum PracticeInsightCardTuning {
    static let presentationFadeDuration: TimeInterval = 0.35
    static let minHeight: CGFloat = 82
    static let verticalPadding: CGFloat = 12
}

struct PracticeInsightCard: View {
    @ObservedObject var store: PracticeInsightSessionStore

    var body: some View {
        Group {
            if let insight = store.currentInsight {
                content(for: insight)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: PracticeInsightCardTuning.presentationFadeDuration), value: insight.id)
            }
        }
    }

    @ViewBuilder
    private func content(for insight: PracticeInsight) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(insight.title)
                .font(Theme.Text.meta.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(insight.expandedText)
                .font(Theme.Text.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: PracticeInsightCardTuning.minHeight)
        .padding(.horizontal, Theme.Spacing.card)
        .padding(.vertical, PracticeInsightCardTuning.verticalPadding)
        .background(
            Theme.Colors.accent.opacity(0.08)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .cardSurface(padding: 0)
    }
}
