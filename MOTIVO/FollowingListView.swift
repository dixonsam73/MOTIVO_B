//
//  FollowingListView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 16/01/2026.
//
import SwiftUI

/// Phase 10B — Following list
/// Shows users the viewer is following. No counts. Calm list.
/// Tapping a row opens ProfilePeek.
struct FollowingListView: View {

    @ObservedObject private var followStore = FollowStore.shared

    var body: some View {
        List {
            let ids = Array(followStore.following).sorted()
            if ids.isEmpty {
                Text("You’re not following anyone yet.")
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.vertical, Theme.Spacing.l)
            } else {
                ForEach(ids, id: \.self) { userID in
                    PeopleUserRow(userID: userID) {
                        ProfilePeekView(ownerID: userID)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Following")
        .task {
            await followStore.refreshFromBackendIfPossible()
        }
    }
}
