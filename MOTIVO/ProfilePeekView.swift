import SwiftUI
import CoreData
import Combine

struct ProfilePeekView: View {
    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject var auth: AuthManager
    @State private var revealSelfName = false
    @Environment(\.colorScheme) private var colorScheme

    let ownerID: String

    // Derived
    private var viewerID: String {
        auth.currentUserID ?? (try? PersistenceController.shared.currentUserID) ?? "localUser"
    }
    private var canSee: Bool {
        viewerID == ownerID || FollowStore.shared.state(for: ownerID) == .following
    }
    // Fetch a few lightweight stats locally
    @FetchRequest private var ownerSessions: FetchedResults<Session>
    @FetchRequest private var ownerInstruments: FetchedResults<UserInstrument>

    init(ownerID: String) {
        self.ownerID = ownerID
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
                        HStack(spacing: 8) {
                            Text(displayName(ownerID))
                                .font(.headline)
                            let myID = (try? PersistenceController.shared.currentUserID) ?? "local-device"
                            let isOwner = (ownerID == myID)
                            if !isOwner {
                                let state = (FollowStore.shared.state(for: ownerID))
                                FollowBadge(state: state)
                                    .accessibilityLabel("Follow state: \(state.rawValue)")
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

                if viewerID == ownerID || canSee {
                    // Visible summary
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Overview").sectionHeader()
                        HStack(spacing: Theme.Spacing.l) {
                            StatChip(title: "Sessions", value: "\(ownerSessions.count)")
                            let totalSeconds = ownerSessions.reduce(0) { acc, s in
                                let attrs = s.entity.attributesByName
                                if attrs["durationSeconds"] != nil, let n = s.value(forKey: "durationSeconds") as? NSNumber { return acc + n.intValue }
                                if attrs["durationMinutes"] != nil, let n = s.value(forKey: "durationMinutes") as? NSNumber { return acc + (n.intValue * 60) }
                                if attrs["duration"] != nil, let n = s.value(forKey: "duration") as? NSNumber { return acc + (n.intValue * 60) }
                                if attrs["lengthMinutes"] != nil, let n = s.value(forKey: "lengthMinutes") as? NSNumber { return acc + (n.intValue * 60) }
                                return acc
                            }
                            StatChip(title: "Time", value: StatsHelper.formatDuration(totalSeconds))
                        }
                    }
                    .transition(.opacity)

                    Divider().overlay(Theme.Colors.stroke(colorScheme).opacity(0.5)).padding(.vertical, Theme.Spacing.s)

                    if (viewerID == ownerID || canSee), !ownerInstruments.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Instruments").sectionHeader()
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(ownerInstruments, id: \.objectID) { inst in
                                    Text((inst.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(Theme.Text.body)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
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
                if viewerID == ownerID, let uid = auth.currentUserID ?? (try? PersistenceController.shared.currentUserID) {
                    await PersistenceController.shared.runOneTimeBackfillIfNeeded(for: uid)
                }
            }
            .padding(16)
            .cardSurface()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Helpers

    private func displayName(_ id: String) -> String {
        // Prefer AuthManager displayName if self; else Profile name; fallback short ID
        if id == (auth.currentUserID ?? "") {
            return revealSelfName ? (auth.displayName ?? "You") : "You"
        }
        // If you maintain a Profile entity for others, fetch that name.
        // For now, fallback to short ownerID tail for clarity.
        let tail = String(id.suffix(6))
        return "User • \(tail)"
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

// ===== v7.12A • Follow state badge (read-only)
private struct FollowBadge: View {
    let state: FollowState
    var body: some View {
        switch state {
        case .following:
            Text("Following").font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.15)).clipShape(Capsule())
        case .requested:
            Text("Requested").font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.yellow.opacity(0.15)).clipShape(Capsule())
        case .none:
            Text("Follow").font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.blue.opacity(0.15)).clipShape(Capsule())
        }
    }
}
