//
//  ConnectedTrialReminderCard.swift
//  MOTIVO
//
//  FOUNDING 500 — the in-feed reminder card.
//
//  Styling is `PracticeInsightCard`'s, deliberately and not approximately: the
//  same accent wash, radius, card surface, and the same meta-weight title over
//  body copy. Samuel asked for subtle and elegant, and the app already has a
//  quiet way of saying something in the feed.
//

import SwiftUI

struct ConnectedTrialReminderCard: View {
    let periodEnd: Date
    let onManage: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(ConnectedTrialReminder.title)
                    .font(Theme.Text.meta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        // A small glyph needs a real target: 44×44, without
                        // enlarging the mark itself. An earlier version said 44
                        // and set 28 — the comment was aspirational.
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ConnectedTrialReminder.dismissActionLabel)
            }

            Text(ConnectedTrialReminder.message(periodEnd: periodEnd))
                .font(Theme.Text.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onManage) {
                Text(ConnectedTrialReminder.manageActionTitle)
                    .font(Theme.Text.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.primaryAction)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.card)
        .padding(.vertical, PracticeInsightCardTuning.verticalPadding)
        .background(Theme.Colors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .cardSurface(padding: 0)
        .accessibilityElement(children: .contain)
    }
}
