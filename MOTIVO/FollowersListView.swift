// CHANGE-ID: 20260210_211128_P15_Avatars_PeopleLists
// SCOPE: FollowersListView: pass avatar_key into PeopleUserRow so follower rows can render remote avatars.
// SEARCH-TOKEN: 20260210_211128_P15_Avatars_PeopleLists

// CHANGE-ID: 20260117_090800_10B_FollowersList_PlaceholderAlign
// SCOPE: FollowersListView — remove duplicate in-body title; match Following list style; placeholder only.

// CHANGE-ID: 20260121_203420_Phase141_FollowersListView_DirectoryIdentityWiring
// SCOPE: Phase 14.1 — Resolve directory identity for list rows and pass into PeopleUserRow/ProfilePeek; avoid opaque ID fallback.
// SEARCH-TOKEN: 20260121_203420_Phase141_FollowersListView_DirectoryIdentityWiring

import SwiftUI

struct FollowersListView: View {

    @ObservedObject private var followStore = FollowStore.shared


    @State private var directory: [String: DirectoryAccount] = [:]
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
                    let acct = directory[userID]
                    PeopleUserRow(
                        userID: userID,
                        overrideDisplayName: acct?.displayName,
                        overrideSubtitle: acct?.accountID.map { "@\($0)" },
                        overrideAvatarKey: acct?.avatarKey
                    ) {
                        ProfilePeekView(
                            ownerID: userID,
                            directoryDisplayName: acct?.displayName,
                            directoryAccountID: acct?.accountID,
                            directoryLocation: acct?.location,
                            directoryAvatarKey: acct?.avatarKey,
                            directoryInstruments: acct?.instruments,
                        )
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appBackground()
        .task(id: userIDs) {
            let ids = userIDs
            guard !ids.isEmpty else {
                directory = [:]
                return
            }
            let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids)
            if case .success(let map) = result {
                directory = map
            }
        }
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.inline)
    }
}
