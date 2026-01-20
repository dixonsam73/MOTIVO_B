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

import SwiftUI

/// Phase 10B — People Hub
/// Requests (conditional) · Intentional lookup (directory) · Connections
/// No counts. No discovery. Calm, ContentView-aligned UI.
struct PeopleView: View {

    @ObservedObject private var followStore = FollowStore.shared

    @State private var searchText: String = ""
    @State private var searchResults: [DirectoryAccount] = []
    @State private var searchError: String? = nil
    @State private var isSearching: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {

                Text("People")
                    .font(Theme.Text.sectionHeader)
                    .foregroundStyle(Theme.Colors.secondaryText)
                
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
    }

    // MARK: - Sections

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
                PeopleUserRow(userID: userID) {
                    ProfilePeekView(ownerID: userID)
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
                        overrideSubtitle: acct.accountID.map { "@\($0)" }
                    ) {
                        ProfilePeekView(
                            ownerID: acct.userID,
                            directoryDisplayName: acct.displayName,
                            directoryAccountID: acct.accountID
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
