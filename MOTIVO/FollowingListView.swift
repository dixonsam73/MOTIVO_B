// CHANGE-ID: 20260401_183900_FollowLists_AlphabeticalDisplayNameSort
// SCOPE: View-only ordering update for FollowingListView — sort following alphabetically by resolved display name, using surname-first ordering when multiple name parts exist; fallback safely to userID; preserve all UI, loading, and navigation behavior.
// SEARCH-TOKEN: 20260401_183900_FollowLists_AlphabeticalDisplayNameSort

// CHANGE-ID: 20260318_165400_FollowLists_ProfileParity
// SCOPE: Visual-only parity pass for FollowingListView — replace plain List container with Profile-style section header + grouped card surface; preserve row content, async loading, and navigation behavior.
// SEARCH-TOKEN: 20260318_165400_FollowLists_ProfileParity

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

    private func alphabeticalSortKey(for userID: String) -> String {
        let fallback = userID.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard let rawName = directory[userID]?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return fallback
        }

        let parts = rawName
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !parts.isEmpty else { return fallback }

        if parts.count >= 2 {
            let surname = parts.last ?? ""
            let givenNames = parts.dropLast().joined(separator: " ")
            return "\(surname.localizedLowercase) \(givenNames.localizedLowercase)"
        } else {
            return parts[0].localizedLowercase
        }
    }

    private var userIDs: [String] {
        Array(followStore.following).sorted {
            let lhsKey = alphabeticalSortKey(for: $0)
            let rhsKey = alphabeticalSortKey(for: $1)
            if lhsKey == rhsKey {
                return $0.localizedLowercase < $1.localizedLowercase
            }
            return lhsKey < rhsKey
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Following")
                    .sectionHeader()

                Group {
                    if userIDs.isEmpty {
                        Text("You're not following anyone yet.")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(userIDs.enumerated()), id: \.element) { index, userID in
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

                                if index < userIDs.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
