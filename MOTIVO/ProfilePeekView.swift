import SwiftUI
import CoreData

struct ProfilePeekView: View {
    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject var auth: AuthManager

    let ownerID: String

    // Derived
    private var viewerID: String {
        auth.currentUserID ?? (try? PersistenceController.shared.currentUserID) ?? "localUser"
    }
    private var canSee: Bool {
        FollowStore.shared.canSee(ownerID: viewerID, targetID: ownerID)
    }
    // Fetch a few lightweight stats locally
    @FetchRequest private var ownerSessions: FetchedResults<Session>

    init(ownerID: String) {
        self.ownerID = ownerID
        // fetch sessions for this owner (lightweight)
        let req = NSFetchRequest<Session>(entityName: "Session")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        req.predicate = NSPredicate(format: "ownerUserID == %@", ownerID)
        req.fetchLimit = 50
        _ownerSessions = FetchRequest(fetchRequest: req)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // Header
            HStack(spacing: Theme.Spacing.m) {
                // Avatar
                ProfileAvatar(ownerID: ownerID)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(ownerID))
                        .font(.headline)
                    let loc = ProfileStore.location(for: ownerID)
                    if !loc.isEmpty {
                        Text(loc)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                Spacer()
            }

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
        .padding(Theme.Spacing.l)
        .cardSurface()
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
    }

    // MARK: Helpers

    private func displayName(_ id: String) -> String {
        // Prefer AuthManager displayName if self; else Profile name; fallback short ID
        if id == (auth.currentUserID ?? "") {
            return auth.displayName ?? "You"
        }
        // If you maintain a Profile entity for others, fetch that name.
        // For now, fallback to short ownerID tail for clarity.
        let tail = String(id.suffix(6))
        return "User • \(tail)"
    }
}

private struct StatChip: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.Colors.secondaryText)
            Text(value).font(.headline)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
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
