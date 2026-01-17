// CHANGE-ID: 20260117_101000_10B_Following_BGFix
// SCOPE: FollowingListView — remove white List canvas and match app background; preserve existing behavior.

import SwiftUI

struct FollowingListView: View {

    @ObservedObject private var followStore = FollowStore.shared

    private var userIDs: [String] {
        Array(followStore.following).sorted()
    }

    var body: some View {
        List {
            if userIDs.isEmpty {
                Text("You're not following anyone yet.")
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
        // Remove the default white List canvas so the app background shows through.
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.inline)
    }
}
