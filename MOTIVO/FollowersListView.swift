// CHANGE-ID: 20260117_090800_10B_FollowersList_PlaceholderAlign
// SCOPE: FollowersListView — remove duplicate in-body title; match Following list style; placeholder only.

import SwiftUI

struct FollowersListView: View {
    var body: some View {
        List {
            Text("Coming soon.")
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.inline)
    }
}
