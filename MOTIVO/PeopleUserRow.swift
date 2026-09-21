// CHANGE-ID: 20260211_211900_Phase15B_RemoteAvatars_PeopleFollowsRows
// SCOPE: Phase 15B — Wire remote avatars into People + Followers/Following rows (UI-only). PeopleUserRow now uses overrideAvatarKey with RemoteAvatarPipeline (signed URL + cache) while preserving initials fallback and existing layout.
// SEARCH-TOKEN: 20260211_211900_Phase15B_RemoteAvatars_PeopleFollowsRows

//
//  PeopleUserRow.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 16/01/2026.
//
// CHANGE-ID: 20260120_113300_Phase12C_PeopleUserRow_DirectoryOverrides
// SCOPE: Phase 12C — Allow PeopleUserRow to display directory-provided displayName/handle subtitle when available; preserves existing fallbacks.
// SEARCH-TOKEN: 20260120_113300_Phase12C_PeopleUserRow_DirectoryOverrides
// CHANGE-ID: 20260318_173000_PeopleUserRow_SubtleVerticalBreathing
// SCOPE: Visual-only micro-adjustment — add +2pt vertical padding to row content for slightly calmer spacing in Followers/Following cards. No divider, layout, avatar, or logic changes.
// SEARCH-TOKEN: 20260318_173000_PeopleUserRow_SubtleVerticalBreathing

// CHANGE-ID: 20260121_135214_P13C_AvatarInitials_PeopleUserRow
// SCOPE: 13C — Replace '?' avatar placeholder with initials derived from display name; no logic changes.

import SwiftUI

/// The second line of a people row, composed from what the directory ALREADY
/// returned for that account.
///
/// **It invents nothing.** It consumes only `instruments` and `location` as they
/// arrive on `DirectoryAccount`, and it has no access to a fetch, a discovery
/// gate, a search, or the viewer's own local profile — so it can never present
/// one person's location as another's. When both are absent the result is the
/// empty string and the row renders no second line, which is already what the
/// three directory rows carrying no handle did before this existed.
///
/// **It replaced `@handle`, which was occupying this slot.** A name-derived
/// handle with a numeric suffix distinguished two rows without helping anyone
/// choose between them; the instrument and the town do.
public enum DirectorySubtitle {

    /// At most this many instruments are named; the rest become `+N`.
    ///
    /// A bound rather than a truncation: a row that ends `"+3"` is honest about
    /// how much it is not showing, where an elided list is not.
    public static let namedInstrumentLimit = 2

    public static func text(instruments: [String]?, location: String?) -> String {
        let named = (instruments ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parts: [String] = []

        if !named.isEmpty {
            let shown = named.prefix(namedInstrumentLimit).joined(separator: ", ")
            let remainder = named.count - min(named.count, namedInstrumentLimit)
            parts.append(remainder > 0 ? "\(shown) +\(remainder)" : shown)
        }

        if let place = location?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            parts.append(place)
        }

        return parts.joined(separator: " · ")
    }

    /// Convenience for the eight call sites that hold a whole row.
    ///
    /// Returns `nil` rather than `""` when there is nothing to say, so a caller
    /// passing it to `overrideSubtitle` expresses "no override" rather than
    /// "override with a blank" — the two are distinguishable at the call site
    /// and only one of them is truthful.
    public static func text(for account: DirectoryAccount?) -> String? {
        guard let account else { return nil }
        let t = text(instruments: account.instruments, location: account.location)
        return t.isEmpty ? nil : t
    }
}

/// Shared row for People hub:
/// used by Requests, Lookup result, and Following list.
/// Shows avatar + lightweight identity summary and opens ProfilePeek on tap.
struct PeopleUserRow<Destination: View, Trailing: View>: View {

    let userID: String
    let overrideDisplayName: String?
    let overrideSubtitle: String?
    let overrideAvatarKey: String?
    /// C-34: `account_directory.avatar_version`.
    let overrideAvatarVersion: String?
    let destination: () -> Destination
    let trailing: () -> Trailing

    @State private var remoteAvatarImage: UIImage?

    init(
        userID: String,
        overrideDisplayName: String? = nil,
        overrideSubtitle: String? = nil,
        overrideAvatarKey: String? = nil,
        overrideAvatarVersion: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.userID = userID
        self.overrideDisplayName = overrideDisplayName
        self.overrideSubtitle = overrideSubtitle
        self.overrideAvatarKey = overrideAvatarKey
        self.overrideAvatarVersion = overrideAvatarVersion
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
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + 2)
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

    /// **No fallback, deliberately.** This used to fall back to
    /// `ProfileStore.location(for: userID)`, which is a LOCAL store written only
    /// for the owner's own backend id (`ProfileStore.setLocation` has no other
    /// caller shape) — so for every other member it resolved to `""` and the
    /// branch was dead. Callers now pass `DirectorySubtitle.text(for:)`, which
    /// uses that member's OWN returned values; reinstating a local fallback here
    /// would risk presenting the viewer's own location under someone else's name.
    private var subtitle: String {
        guard let s = overrideSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return ""
        }
        return s
    }

    private func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        let words = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        if words.isEmpty { return "?" }
        if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
        let first = words.first?.first.map { String($0).uppercased() } ?? ""
        let last = words.last?.first.map { String($0).uppercased() } ?? ""
        let combo = first + last
        return combo.isEmpty ? "?" : combo
    }

    private var trimmedAvatarKey: String? {
        guard let k = overrideAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty else {
            return nil
        }
        return k
    }

    @ViewBuilder
    private var avatar: some View {
        // Preserve existing local override behaviour (e.g., current user).
        if let img = ProfileStore.avatarImage(for: userID) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
        } else if let remote = remoteAvatarImage {
            Image(uiImage: remote)
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
                    Text(initials(from: displayName))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                )
                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                // C-34: version is part of the identity.
                .task(id: "\(trimmedAvatarKey ?? "")|\(overrideAvatarVersion ?? "")") {
                    // UI-only: reuse existing signed-URL + cache pipeline (no refactors / new services).
                    guard let key = trimmedAvatarKey else {
                        if remoteAvatarImage != nil { remoteAvatarImage = nil }
                        return
                    }
                    let img = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(
                        avatarKey: key, version: overrideAvatarVersion)
                    if Task.isCancelled { return }
                    remoteAvatarImage = img
                }
        }
    }
}
