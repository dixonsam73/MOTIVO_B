//
//  PeopleView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 16/01/2026.
//
// CHANGE-ID: 20260117_122600_Phase10D_PeopleView_RequestFilter_LookupStyle
// SCOPE: Phase 10D.1 + 10D.3 — Defensive incoming-requests filtering and remove remaining system-default controls in PeopleView.
// SEARCH-TOKEN: 20260117_122600_Phase10D_PeopleView_RequestFilter_LookupStyle

import SwiftUI

/// Phase 10B — People Hub
/// Requests (conditional) · Intentional lookup (temporary: userID) · Connections
/// No counts. No discovery. Calm, ContentView-aligned UI.
struct PeopleView: View {

    @ObservedObject private var followStore = FollowStore.shared

    @State private var lookupText: String = ""
    @State private var lookupResultUserID: String? = nil
    @State private var lookupError: String? = nil
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

                // Intentional lookup (temporary)
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
                TextField("Paste user ID (temporary)", text: $lookupText)
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
                    performLookup()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.thinMaterial)
                            .opacity(colorScheme == .dark ? 0.12 : 0.85)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(lookupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Lookup user")
            }

            if let uid = lookupResultUserID {
                PeopleUserRow(userID: uid) {
                    ProfilePeekView(ownerID: uid)
                }
            } else if let err = lookupError {
                Text(err)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
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

    private func performLookup() {
        lookupError = nil
        lookupResultUserID = nil

        let raw = lookupText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        // We don’t have directory/handle lookup wired yet.
        // Keep this as explicit userID paste (still aligns with “intentional connection” policy).
        lookupResultUserID = raw
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
