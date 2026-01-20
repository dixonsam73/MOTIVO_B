// CHANGE-ID: 20260116_221900_phase10C_profilepeek_followactions_polish
// SCOPE: Phase 10C — remove duplicate follow status label; rename "Requested" to "Request sent"; remove invalid accessibility traits.

// CHANGE-ID: 20260120_113400_Phase12C_ProfilePeek_DirectoryHeader
// SCOPE: Phase 12C — Allow ProfilePeek header to show directory-provided display name and optional @account_id; no additional data fetch.
// SEARCH-TOKEN: 20260120_113400_Phase12C_ProfilePeek_DirectoryHeader

// CHANGE-ID: 20260120_124300_Phase12C_ProfilePeek_UseBackendUserID
// SCOPE: Phase 12C correctness — use auth.backendUserID (Supabase UUID) as viewerID for follow/directory logic; avoid Apple subject IDs.
import SwiftUI
import CoreData
import Combine

struct ProfilePeekView: View {
    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject var auth: AuthManager
    @State private var revealSelfName = false
    @State private var showUnfollowConfirm = false
    @Environment(\.colorScheme) private var colorScheme

    let ownerID: String
    let directoryDisplayName: String?
    let directoryAccountID: String?

    // Derived
    /// Effective viewer ID for backend follow/directory logic (Supabase auth.users UUID).
    /// Order: DEBUG backend override → Auth.backendUserID → AuthManager.canonicalBackendUserID() → local fallback.
    private var viewerID: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride"),
           !override.isEmpty {
            return override.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        #endif
        if let bid = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty {
            return bid.lowercased()
        }
        if let canon = AuthManager.canonicalBackendUserID() {
            return canon
        }
        return (try? PersistenceController.shared.currentUserID) ?? "localUser"
    }

    private var canSee: Bool {
        viewerID == ownerID || FollowStore.shared.state(for: ownerID) == .following
    }

    // Fetch a few lightweight stats locally
    @FetchRequest private var ownerSessions: FetchedResults<Session>
    @FetchRequest private var ownerInstruments: FetchedResults<UserInstrument>

    init(ownerID: String, directoryDisplayName: String? = nil, directoryAccountID: String? = nil) {
        self.ownerID = ownerID
        self.directoryDisplayName = directoryDisplayName
        self.directoryAccountID = directoryAccountID
        // fetch sessions for this owner (lightweight)
        let sReq = NSFetchRequest<Session>(entityName: "Session")
        sReq.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        sReq.predicate = NSPredicate(format: "ownerUserID == %@", ownerID)
        sReq.fetchLimit = 50
        _ownerSessions = FetchRequest(fetchRequest: sReq)

        // Instruments (visible only)
        let iReq = NSFetchRequest<UserInstrument>(entityName: "UserInstrument")
        iReq.predicate = NSPredicate(format: "ownerUserID == %@ AND isVisibleOnProfile == YES", ownerID)
        iReq.sortDescriptors = [
            NSSortDescriptor(key: "displayOrder", ascending: true),
            NSSortDescriptor(key: "displayName", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ]
        _ownerInstruments = FetchRequest(fetchRequest: iReq)
    }

    var body: some View {
        ZStack {
            Color.clear
                .appBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                // Header
                HStack(spacing: Theme.Spacing.m) {
                    // Avatar
                    Button(action: {
                        if viewerID == ownerID {
                            revealSelfName.toggle()
                        }
                    }) {
                        ProfileAvatar(ownerID: ownerID)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(ownerID))
                                .font(.headline)
                            if let handle = directoryAccountID?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty {
                                Text("@\(handle)")
                                    .font(Theme.Text.meta)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        let loc = ProfileStore.location(for: ownerID)
                        if !loc.isEmpty {
                            Text(loc)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)

                // Follow action (Phase 10C) — single calm control, no counts
                if viewerID != ownerID {
                    followActionRow
                        .padding(.top, 2)
                }

                if viewerID == ownerID || canSee {
                    // Visible summary
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Overview").sectionHeader()
                                                let sessionsCount = ownerSessions.count
                                                let totalSeconds = ownerSessions.reduce(0) { acc, s in
                                                    let attrs = s.entity.attributesByName
                                                    if attrs["durationSeconds"] != nil, let n = s.value(forKey: "durationSeconds") as? NSNumber { return acc + n.intValue }
                                                    if attrs["durationMinutes"] != nil, let n = s.value(forKey: "durationMinutes") as? NSNumber { return acc + (n.intValue * 60) }
                                                    if attrs["duration"] != nil, let n = s.value(forKey: "duration") as? NSNumber { return acc + (n.intValue * 60) }
                                                    if attrs["lengthMinutes"] != nil, let n = s.value(forKey: "lengthMinutes") as? NSNumber { return acc + (n.intValue * 60) }
                                                    return acc
                                                }
                                                let sessionsLabel = sessionsCount == 1 ? "1 session" : "\(sessionsCount) sessions"
                                                Text("\(sessionsLabel) · \(StatsHelper.formatDuration(totalSeconds)) total")
                                                    .font(Theme.Text.body)
                                                    .foregroundStyle(Color.primary.opacity(0.85))
                    }
                    .transition(.opacity)

                    Divider().overlay(Theme.Colors.stroke(colorScheme).opacity(0.5)).padding(.vertical, Theme.Spacing.s)

                    if (viewerID == ownerID || canSee), !ownerInstruments.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Instruments").sectionHeader()
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                ForEach(ownerInstruments, id: \.objectID) { inst in
                                    Text((inst.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(Theme.Text.body)
                                        .lineLimit(1)
                                        .foregroundStyle(Color.primary.opacity(0.85))
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                } else {
                    // Private banner (limited peek)
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Private profile").sectionHeader()
                        Text("Follow is required to view details.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .transition(.opacity)
                }
            }
            .task {
                // Trigger a one-time backfill only when peeking our own profile
                if viewerID == ownerID,
                   let uid = auth.backendUserID ?? AuthManager.canonicalBackendUserID() ?? (try? PersistenceController.shared.currentUserID) {
                    await PersistenceController.shared.runOneTimeBackfillIfNeeded(for: uid)
                }
            }
            .confirmationDialog("Unfollow?", isPresented: $showUnfollowConfirm, titleVisibility: .visible) {
                Button("Unfollow", role: .destructive) {
                    _ = FollowStore.shared.unfollow(ownerID)
                }
                Button("Cancel", role: .cancel) { }
            }
            .padding(16)
            .cardSurface()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var followActionRow: some View {
        let state = FollowStore.shared.state(for: ownerID)
        return HStack {
            Spacer(minLength: 0)
            switch state {
            case .none:
                Button {
                    _ = FollowStore.shared.requestFollow(to: ownerID)
                } label: {
                    FollowActionPill(title: "Follow", isEnabled: true)
                }
                .buttonStyle(.plain)
            case .requested:
                FollowActionPill(title: "Request sent", isEnabled: false)
            case .following:
                Button {
                    showUnfollowConfirm = true
                } label: {
                    FollowActionPill(title: "Following", isEnabled: true)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Helpers

    private func displayName(_ id: String) -> String {
        // Prefer AuthManager displayName if self; else Profile name; fallback short ID
        if id == (auth.backendUserID ?? "") {
            return revealSelfName ? (auth.displayName ?? "You") : "You"
        }
        if let s = directoryDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        // If you maintain a Profile entity for others, fetch that name.
        // For now, fallback to short ownerID tail for clarity.
        let tail = String(id.suffix(6))
        return "User • \(tail)"
    }
}


private struct FollowActionPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let isEnabled: Bool

    var body: some View {
        Text(title)
            .font(Theme.Text.meta.weight(.semibold))
            .foregroundStyle(Theme.Colors.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Theme.Colors.stroke(colorScheme).opacity(0.35), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1.0 : 0.55)
            .disabled(!isEnabled)
    }
}

private struct StatChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .stroke(Theme.Colors.stroke(colorScheme).opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct TagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct FlexibleChipsView: View {
    let items: [String]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.s)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(items, id: \.self) { item in
                TagChip(text: item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
    }
}

// Minimal avatar helper using ProfileStore cache if present.
private struct ProfileAvatar: View {
    let ownerID: String
    var body: some View {
        Group {
            if let img = ProfileStore.avatarImage(for: ownerID) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(.secondary.opacity(0.15))
                    Image(systemName: "person.crop.circle")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}


