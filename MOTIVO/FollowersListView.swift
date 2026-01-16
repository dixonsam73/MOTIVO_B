//
//  FollowersListView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 16/01/2026.
//
import SwiftUI

/// Phase 10B — Followers list (placeholder)
/// Wiring deferred until backend/store exposes approved followers list.
/// No counts.
struct FollowersListView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Followers")
                .font(Theme.Text.pageTitle)
                .foregroundStyle(Color.primary)

            Text("Coming soon.")
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)

            Spacer()
        }
        .padding(Theme.Spacing.l)
        .appBackground()
        .navigationTitle("Followers")
    }
}
