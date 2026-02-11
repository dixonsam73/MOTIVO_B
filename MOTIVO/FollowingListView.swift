// CHANGE-ID: 20260210_211128_P15_Avatars_PeopleLists
// SCOPE: FollowingListView: pass avatar_key into PeopleUserRow so following rows can render remote avatars.
// SEARCH-TOKEN: 20260210_211128_P15_Avatars_PeopleLists

// CHANGE-ID: 20260121_203420_Phase141_FollowingListView_DirectoryIdentityWiring
// SCOPE: Phase 14.1 — Resolve directory identity for list rows and pass into PeopleUserRow/ProfilePeek; avoid opaque ID fallback.
// SEARCH-TOKEN: 20260121_203420_Phase141_FollowingListView_DirectoryIdentityWiring

import SwiftUI

struct FollowingListView: View {

    @ObservedObject private var followStore = FollowStore.shared


    @State private var directory: [String: DirectoryAccount] = [:]
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
        // Remove the default white List canvas so the app background shows through.
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
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.inline)
    }
}
