// CHANGE-ID: 20260121_124000_P13F_FollowersListWire
// SCOPE: Phase 13F — Wire FollowersListView to FollowStore.followers (relationship-only).
// SEARCH-TOKEN: 20260121_124000_P13F_FollowersListWire

// CHANGE-ID: 20260117_090800_10B_FollowersList_PlaceholderAlign
// SCOPE: FollowersListView — remove duplicate in-body title; match Following list style; placeholder only.

import SwiftUI

struct FollowersListView: View {

    @ObservedObject private var followStore = FollowStore.shared

    private var userIDs: [String] {
        Array(followStore.followers).sorted()
    }

    var body: some View {
        List {
            if userIDs.isEmpty {
                Text("You don't have any followers yet.")
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(userIDs, id: \.self) { userID in
                    PeopleUserRow(userID: userID) {
                        ProfilePeekView(ownerID: userID)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.inline)
    }
}
