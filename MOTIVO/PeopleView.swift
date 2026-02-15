// CHANGE-ID: 20260215_145500_PeopleView_ResponsesSection_FixBraces
// SCOPE: PeopleView — fix section helper scoping (close sharedWithYouSection, keep responsesSection at type scope). No UI/logic changes.
// SEARCH-TOKEN: 20260215_145500_PeopleView_ResponsesSection_FixBraces

// CHANGE-ID: 20260212_115900_OwnerShare_PeopleView_SharedWithYou
// SCOPE: PeopleView — add quiet 'Shared with you' section (recipient-side pointers) using Theme tokens. No other UI/layout changes.
// SEARCH-TOKEN: 20260212_115900_OwnerShare_PeopleView_SharedWithYou

// CHANGE-ID: 20260210_211128_P15_Avatars_PeopleLists
// SCOPE: PeopleView: plumb avatar_key into PeopleUserRow for directory search results + follow requests. No UI/layout changes.
// SEARCH-TOKEN: 20260210_211128_P15_Avatars_PeopleLists

//
//  PeopleView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 16/01/2026.
//
// CHANGE-ID: 20260120_113200_Phase12C_PeopleView_DirectorySearch
// SCOPE: Phase 12C — Wire People "Find" to backend account_directory RPC (search_account_directory). UI remains explicit-query only; no discovery.
// SEARCH-TOKEN: 20260120_113200_Phase12C_PeopleView_DirectorySearch

// CHANGE-ID: 20260117_122600_Phase10D_PeopleView_RequestFilter_LookupStyle
// SCOPE: Phase 10D.1 + 10D.3 — Defensive incoming-requests filtering and remove remaining system-default controls in PeopleView.
// SEARCH-TOKEN: 20260117_122600_Phase10D_PeopleView_RequestFilter_LookupStyle

// CHANGE-ID: 20260121_203420_Phase141_PeopleView_RequestIdentityWiring
// SCOPE: Phase 14.1 — Reuse directory batch resolver for Requests rows; avoid UI fallback to opaque user IDs.
// SEARCH-TOKEN: 20260121_203420_Phase141_PeopleView_RequestIdentityWiring

// CHANGE-ID: 20260205_065749_LocParity_d2c43ded
// SCOPE: Identity data parity — pass optional directory location into ProfilePeekView from People search results.
// SEARCH-TOKEN: 20260205_065749_LocParity_d2c43ded

import SwiftUI

/// Phase 10B — People Hub
/// Requests (conditional) · Intentional lookup (directory) · Connections
/// No counts. No discovery. Calm, ContentView-aligned UI.
struct PeopleView: View {

    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var unreadCommentsStore = UnreadCommentsStore.shared


    // Owner-Only Share — unread share pointers (recipient-side)
    @StateObject private var sharedWithYouStore = SharedWithYouStore()
    @State private var shareOwnerDirectory: [String: DirectoryAccount] = [:]

    @ObservedObject private var backendFeedStore: BackendFeedStore = BackendFeedStore.shared
    @EnvironmentObject private var auth: AuthManager


    @State private var searchText: String = ""
    @State private var searchResults: [DirectoryAccount] = []
    @State private var searchError: String? = nil
    @State private var requestDirectory: [String: DirectoryAccount] = [:]

    @State private var isSearching: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {

                Text("People")
                    .font(Theme.Text.sectionHeader)
                    .foregroundStyle(Theme.Colors.secondaryText)
                
                // Shared with you (quiet, conditional)
                if !sharedWithYouStore.unreadShares.isEmpty {
                    sharedWithYouSection
                }

                // Responses (unread private comments; quiet, conditional)
                if !unreadCommentsStore.unreadGroups.isEmpty {
                    responsesSection
                }

                // Incoming requests (defensive: never surface outgoing requests here)
                if !incomingRequestIDs.isEmpty {
                    requestsSection
                }

                // Intentional lookup (directory-backed)
                lookupSection

                // Connections
                connectionsSection
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
        }
        
        .appBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // In Backend Preview, this keeps requests/following fresh when opening People.
            await followStore.refreshFromBackendIfPossible()
        }
        .task {
            await unreadCommentsStore.refresh(force: true)
        }
        .task {
            await sharedWithYouStore.refreshUnreadShares()
        }
        .task(id: shareOwnerIDs) {
            let ids = shareOwnerIDs
            guard !ids.isEmpty else {
                shareOwnerDirectory = [:]
                return
            }
            let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids)
            if case .success(let map) = result {
                shareOwnerDirectory = map
            }
        }
        .task(id: incomingRequestIDs) {
            let ids = incomingRequestIDs
            guard !ids.isEmpty else {
                requestDirectory = [:]
                return
            }
            let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids)
            if case .success(let map) = result {
                requestDirectory = map
            }
        }
    }

    // MARK: - Sections

    /// Unread share pointers — we resolve owner identities for a calm, minimal label.
    private var shareOwnerIDs: [String] {
        Array(Set(sharedWithYouStore.unreadShares.map { $0.ownerUserID }))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }
    private var effectiveBackendUserID: String {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let o = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !o.isEmpty {
            return o.lowercased()
        }
        #endif

        return (auth.backendUserID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    private var sharedWithYouSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Shared with you").sectionHeader()

            ForEach(sharedWithYouStore.unreadShares.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { share in
                let acct = shareOwnerDirectory[share.ownerUserID]

                NavigationLink {
                    SharedPostDetailHost(
                        share: share,
                        viewerUserID: effectiveBackendUserID,
                        backendFeedStore: backendFeedStore
                    ) {
                        Task { await sharedWithYouStore.markViewed(shareID: share.id) }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(acct?.displayName ?? "Shared post")
                                .font(Theme.Text.body)
                                .foregroundStyle(Color.primary)

                            Text(share.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, Theme.Spacing.s)
                }
            }
        }
        .cardSurface()

    }

    private var responsesSection: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
        Text("Responses").sectionHeader()

        ForEach(unreadCommentsStore.unreadGroups.sorted(by: { $0.latestUnreadAt > $1.latestUnreadAt })) { group in
            NavigationLink {
                ResponsesPostDetailHost(
                    postID: group.postID,
                    viewerUserID: effectiveBackendUserID,
                    backendFeedStore: backendFeedStore
                ) {
                    Task { await unreadCommentsStore.markViewed(postID: group.postID) }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Session")
                            .font(Theme.Text.body)
                            .foregroundStyle(Color.primary)

                        Text((group.latestBody?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? group.latestBody! : "New comment")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(group.latestUnreadAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .contentShape(Rectangle())
                .padding(.vertical, Theme.Spacing.s)
            }
        }
    }
    .cardSurface()
    }




    /// Phase 10D.1: Incoming requests only (defensive filter).
    /// Requests UI must never surface outgoing requests.
    private var incomingRequestIDs: [String] {
        Array(followStore.requests.subtracting(followStore.outgoingRequests))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Requests").sectionHeader()

            ForEach(incomingRequestIDs, id: \.self) { userID in
                let acct = requestDirectory[userID]
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
                } trailing: {
                    HStack(spacing: Theme.Spacing.s) {
                        Button {
                            _ = followStore.approveFollow(from: userID)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.thinMaterial)
                                    .opacity(colorScheme == .dark ? 0.12 : 0.85)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accept follow request")

                        Button {
                            _ = followStore.declineFollow(from: userID)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.thinMaterial)
                                    .opacity(colorScheme == .dark ? 0.12 : 0.85)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)

                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decline follow request")
                    }
                    .frame(width: 96, alignment: .trailing)
                }
            }
        }
        .cardSurface()
    }

    private var lookupSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Find").sectionHeader()

            HStack(spacing: Theme.Spacing.s) {
                TextField("Search name or account ID", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Color.primary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.thinMaterial)
                            .opacity(colorScheme == .dark ? 0.12 : 0.85)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 0.7)
                    )

                Button {
                    Task { await performLookup() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.thinMaterial)
                            .opacity(colorScheme == .dark ? 0.12 : 0.85)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                        if isSearching {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSearching || searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                .accessibilityLabel("Lookup user")
            }

            if let err = searchError {
                Text(err)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } else {
                ForEach(searchResults, id: \.userID) { acct in
                    PeopleUserRow(
                        userID: acct.userID,
                        overrideDisplayName: acct.displayName,
                        overrideSubtitle: acct.accountID.map { "@\($0)" },
                        overrideAvatarKey: acct.avatarKey
                    ) {
                        ProfilePeekView(
                            ownerID: acct.userID,
                            directoryDisplayName: acct.displayName,
                            directoryAccountID: acct.accountID,
                            directoryLocation: acct.location,
                            directoryAvatarKey: acct.avatarKey,
                            directoryInstruments: acct.instruments,
                        )
                    }
                }
            }

            Text("Intentional lookup only — no browsing.")
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .cardSurface()
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Your connections").sectionHeader()

            NavigationLink {
                FollowingListView()
            } label: {
                rowLinkLabel("Following")
            }

            NavigationLink {
                FollowersListView()
            } label: {
                rowLinkLabel("Followers")
            }
        }
        .cardSurface()
    }

    // MARK: - Helpers

    private func performLookup() async {
        searchError = nil
        searchResults = []

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else {
            searchError = "Enter at least 3 characters."
            return
        }

        isSearching = true
        defer { isSearching = false }

        let result = await AccountDirectoryService.shared.search(query: q)
        switch result {
        case .success(let rows):
            searchResults = rows
            searchError = rows.isEmpty ? "No results." : nil
        case .failure:
            searchError = "Search unavailable."
        }
    }

    private func rowLinkLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Text.body)
                .foregroundStyle(Color.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .contentShape(Rectangle())
        .padding(.vertical, Theme.Spacing.s)
    }

    // MARK: - Derived

    /// Defensive: requests must be incoming-only.
    /// If local simulation or future wiring ever accidentally mixes sets, we still never show outgoing here.

}


// MARK: - Shared Post Detail Host (PeopleView navigation)

private struct SharedPostDetailHost: View {
    let share: BackendPostSharePointer
    let viewerUserID: String
    let backendFeedStore: BackendFeedStore
    let onMarkViewed: () -> Void

    @State private var didMarkViewed: Bool = false

    private var resolvedPost: BackendPost? {
        backendFeedStore.allPosts.first(where: { $0.id == share.postID })
        ?? backendFeedStore.minePosts.first(where: { $0.id == share.postID })
    }

    var body: some View {
        Group {
            if let post = resolvedPost {
                BackendSessionDetailView(
                    model: BackendSessionViewModel(
                        post: post,
                        currentUserID: viewerUserID
                    )
                )
            } else {
                VStack(spacing: Theme.Spacing.m) {
                    Text("Not available")
                        .font(Theme.Text.sectionHeader)
                        .foregroundStyle(Color.primary)

                    Text("This shared post isn’t available right now.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.l)
                .appBackground()
            }
        }
        .task {
            guard didMarkViewed == false else { return }
            didMarkViewed = true
            onMarkViewed()
        }
    }
}


private struct ResponsesPostDetailHost: View {
    let postID: UUID
    let viewerUserID: String
    let backendFeedStore: BackendFeedStore
    let onMarkViewed: () -> Void

    @State private var didMarkViewed: Bool = false

    private var resolvedPost: BackendPost? {
        backendFeedStore.allPosts.first(where: { $0.id == postID })
        ?? backendFeedStore.minePosts.first(where: { $0.id == postID })
    }

    var body: some View {
        Group {
            if let post = resolvedPost {
                BackendSessionDetailView(
                    model: BackendSessionViewModel(
                        post: post,
                        currentUserID: viewerUserID
                    )
                )
            } else {
                VStack(spacing: Theme.Spacing.m) {
                    Text("Not available")
                        .font(Theme.Text.sectionHeader)
                        .foregroundStyle(Color.primary)

                    Text("This session isn’t available right now.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.l)
                .appBackground()
            }
        }
        .task {
            guard didMarkViewed == false else { return }
            didMarkViewed = true
            onMarkViewed()
        }
    }
}

