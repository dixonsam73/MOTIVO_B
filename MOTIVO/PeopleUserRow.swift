//
//  PeopleUserRow.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 16/01/2026.
//
// CHANGE-ID: 20260120_113300_Phase12C_PeopleUserRow_DirectoryOverrides
// SCOPE: Phase 12C — Allow PeopleUserRow to display directory-provided displayName/handle subtitle when available; preserves existing fallbacks.
// SEARCH-TOKEN: 20260120_113300_Phase12C_PeopleUserRow_DirectoryOverrides

import SwiftUI

/// Shared row for People hub:
/// used by Requests, Lookup result, and Following list.
/// Shows avatar + lightweight identity summary and opens ProfilePeek on tap.
struct PeopleUserRow<Destination: View, Trailing: View>: View {

    let userID: String
    let overrideDisplayName: String?
    let overrideSubtitle: String?
    let destination: () -> Destination
    let trailing: () -> Trailing

    init(
        userID: String,
        overrideDisplayName: String? = nil,
        overrideSubtitle: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.userID = userID
        self.overrideDisplayName = overrideDisplayName
        self.overrideSubtitle = overrideSubtitle
        self.destination = destination
        self.trailing = trailing
    }

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: Theme.Spacing.m) {
                avatar

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(displayName)
                        .font(Theme.Text.body)
                        .foregroundStyle(Color.primary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer()

                trailing()
            }
            .padding(.vertical, Theme.Spacing.s)
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        if let s = overrideDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        // Default fallback: calm and non-performative.
        return "User • \(String(userID.suffix(6)))"
    }

    private var subtitle: String {
        if let s = overrideSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        let loc = ProfileStore.location(for: userID)
        return loc.isEmpty ? "" : loc
    }

    @ViewBuilder
    private var avatar: some View {
        if let img = ProfileStore.avatarImage(for: userID) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
        } else {
            Circle()
                .fill(.thinMaterial)
                .frame(width: 36, height: 36)
                .overlay(
                    Text("?")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                )
                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
        }
    }
}
