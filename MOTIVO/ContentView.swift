//
//  ContentView.swift
//  MOTIVO
//
//  v7.8 Stage 2 — Filter includes custom activities (kept)
//  v7.8 DesignLite — Feed polish: app background, carded filters + stats, plain list rows.
//  - Removed big navigation title ("Motivo").
//  - Visual-only changes; no behavior changes.
//
//  [ROLLBACK ANCHOR] v7.8 DesignLite — pre
//
// CHANGE-ID: 20251008_164453_70d21
// SCOPE: Visual-only — capitalize 'Feed Filter'; tint Instrument & Activity pickers to header light grey
import SwiftUI
import CoreData
import Combine

private let FEED_IMAGE_VIDEO_THUMB: CGFloat = 88
private let FEED_AUDIO_THUMB: CGFloat = 56
private let FEED_THUMB_CORNER: CGFloat = 10

// MARK: - Local helper enums

fileprivate enum ActivityType: Int16, CaseIterable, Identifiable {
    case practice = 0, rehearsal = 1, recording = 2, lesson = 3, performance = 4
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .practice: return "Practice"
        case .rehearsal: return "Rehearsal"
        case .recording: return "Recording"
        case .lesson: return "Lesson"
        case .performance: return "Performance"
        }
    }
}
fileprivate func from(_ code: Int16?) -> ActivityType {
    guard let c = code, let v = ActivityType(rawValue: c) else { return .practice }
    return v
}

fileprivate enum FeedScope: String, CaseIterable, Identifiable {
    case all = "All"
    case mine = "Mine"
    var id: String { rawValue }
}

// Unified filter type for Activity (core or custom)
fileprivate enum ActivityFilter: Hashable, Identifiable {
    case any
    case core(ActivityType)
    case custom(String)

    var id: String {
        switch self {
        case .any: return "any"
        case .core(let a): return "core:\(a.rawValue)"
        case .custom(let name): return "custom:\(name)"
        }
    }

    var label: String {
        switch self {
        case .any: return "Any"
        case .core(let a): return a.label
        case .custom(let name): return name
        }
    }
}

// MARK: - Entry

struct ContentView: View {
    @EnvironmentObject private var auth: AuthManager
    var body: some View {
        SessionsRootView(userID: auth.currentUserID)
            .id(auth.currentUserID ?? "nil-user")
    }
}

// MARK: - Root

fileprivate struct SessionsRootView: View {
    @Environment(\.managedObjectContext) private var viewContext

    let userID: String?

    // Fetch ALL sessions; filter in-memory to avoid mutating @FetchRequest.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        predicate: NSPredicate(value: true),
        animation: .default
    ) private var sessions: FetchedResults<Session>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default
    ) private var instruments: FetchedResults<Instrument>

    // Fetch user-local custom activities for filter menu
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "displayName", ascending: true)],
        animation: .default
    ) private var userActivities: FetchedResults<UserActivity>

    // UI state
    @AppStorage("filtersExpanded") private var filtersExpanded = false
    @State private var selectedInstrument: Instrument? = nil
    @State private var selectedActivity: ActivityFilter = .any
    @State private var selectedScope: FeedScope = .all
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var pushSessionID: UUID? = nil

    @State private var statsRange: StatsRange = .week
    @State private var stats: SessionStats = .init(count: 0, seconds: 0)

    // Sheets
    @State private var showProfile = false
    @State private var showTimer = false
    @State private var showAdd = false

    // Debounce
    @State private var debounceCancellable: AnyCancellable?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {

                // ---------- Stats (card) ----------
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    // CHANGE-ID: 20251015_132452-me-entry-icononly
                    // SCOPE: Add inline icon-only Me dashboard entry in Your Sessions header
                    HStack {
                        Text("Your Sessions").sectionHeader()
                        Spacer()
                        NavigationLink {
                            MeView()
                        } label: {
                            Image(systemName: "chart.bar")
                                .imageScale(.large)
                                .accessibilityLabel("Open Dashboard")
                        }
                        .buttonStyle(.plain)
                    }
                    Picker("", selection: $statsRange) {
                        ForEach(StatsRange.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(stats.count) activities")
                        Text("\(StatsHelper.formatDuration(stats.seconds)) total")
                    }
                }
                .onAppear { refreshStats() }
                .onChange(of: statsRange) { _ in refreshStats() }
                .cardSurface()

                // ---------- Filters (card) ----------
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    // Header now toggles expansion; chevron on same line
                    Button { withAnimation { filtersExpanded.toggle() } } label: {
                        HStack {
                            Text("Feed Filter").sectionHeader()
                            Spacer()
                            Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)

                    FilterBar(
                        filtersExpanded: $filtersExpanded,
                        instruments: Array(instruments),
                        customNames: userActivities
                            .map { ($0.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty },
                        selectedInstrument: $selectedInstrument,
                        selectedActivity: $selectedActivity,
                        selectedScope: $selectedScope,
                        searchText: $searchText
                    )
                }
                .cardSurface()
                .padding(.bottom, -8)

                // ---------- Sessions List ----------
                List {
                    Section {
                        let rows: [Session] = filteredSessions
                        if rows.isEmpty {
                            Text("No sessions match your filters yet.")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        } else {
                            ForEach(rows, id: \.objectID) { session in
                                ZStack {
                                    NavigationLink(
                                        destination: SessionDetailView(session: session),
                                        isActive: Binding(
                                            get: { pushSessionID == (session.value(forKey: "id") as? UUID) },
                                            set: { active in if !active { pushSessionID = nil } }
                                        )
                                    ) { EmptyView() }
                                    .opacity(0)

                                    SessionRow(session: session, scope: selectedScope)
                                        .contentShape(Rectangle())
                                        .onTapGesture { pushSessionID = (session.value(forKey: "id") as? UUID) }
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteSessions)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
            // No big nav title
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        #if canImport(UIKit)
                        if let uiImage = ProfileStore.avatarImage(for: userID) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                                .padding(8)
                        } else {
                            // Match initials behavior to identity row when no avatar image is available
                            let initials: String = {
                                // Source of truth: Core Data Profile.name for current device's user only.
                                let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                req.fetchLimit = 1
                                if let uid = userID, !uid.isEmpty, let ctx = viewContext as NSManagedObjectContext?, let p = try? ctx.fetch(req).first, let n = p.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    let words = n.trimmingCharacters(in: .whitespacesAndNewlines)
                                        .components(separatedBy: .whitespacesAndNewlines)
                                        .filter { !$0.isEmpty }
                                    if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
                                    let first = words.first?.first.map { String($0).uppercased() } ?? ""
                                    let last = words.last?.first.map { String($0).uppercased() } ?? ""
                                    let combo = (first + last)
                                    return combo.isEmpty ? "Y" : combo
                                }
                                return "Y"
                            }()

                            ZStack {
                                Circle().fill(Color.gray.opacity(0.2))
                                Text(initials)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                            .padding(8)
                        }
                        #else
                        Image(systemName: "person.fill")
                            .imageScale(.large)
                        #endif
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showTimer = true } label: {
                        Image(systemName: "record.circle.fill").foregroundColor(.red)
                    }
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            // Sheets
            .sheet(isPresented: $showTimer) {
                PracticeTimerView(isPresented: $showTimer)
            }
            .sheet(isPresented: $showAdd) {
                AddEditSessionView()
            }
            .sheet(isPresented: $showProfile) {
                ProfileView(onClose: { showProfile = false })
            }
            // Debounce lifecycle
            .task {
                setUpDebounce()
            }
            .onChange(of: userID) { _, _ in
                refreshStats()
            }
            .task(id: searchText) {
                debounceCancellable?.cancel()
                debounceCancellable = Just(searchText)
                    .delay(for: .milliseconds(250), scheduler: RunLoop.main)
                    .sink { debouncedQuery = $0 }
            }
            .appBackground()
        }
    }

    private func refreshStats() {
        // De-populate when signed out to mirror other data fields
        guard userID != nil else {
            stats = .init(count: 0, seconds: 0)
            return
        }
        do {
            stats = try StatsHelper.fetchStats(in: viewContext, range: statsRange)
        } catch {
            stats = .init(count: 0, seconds: 0)
        }
    }

    // MARK: - Filtering (Scope • Instrument • Activity • Search)

    private var filteredSessions: [Session] {
        // Ensure no data is shown when signed out
        guard userID != nil else { return [] }
        var out = Array(sessions)

        // Scope
        switch selectedScope {
        case .mine:
            if let uid = userID {
                out = out.filter { $0.ownerUserID == uid }
            } else {
                out = []
            }
        case .all:
            break
        }

        // Instrument (core)
        if let inst = selectedInstrument {
            let id = inst.objectID
            out = out.filter { $0.instrument?.objectID == id }
        }

        // Activity (core enum or custom name)
        switch selectedActivity {
        case .any:
            break
        case .core(let act):
            out = out.filter { ($0.value(forKey: "activityType") as? Int16) == act.rawValue }
        case .custom(let name):
            out = out.filter { s in
                let label = (s.value(forKey: "userActivityLabel") as? String) ?? ""
                let detail = (s.value(forKey: "activityDetail") as? String) ?? ""
                return label.caseInsensitiveCompare(name) == .orderedSame ||
                       detail.caseInsensitiveCompare(name) == .orderedSame
            }
        }

        // Search (title or notes)
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            out = out.filter { s in
                let t = (s.title ?? "")
                let n = (s.notes ?? "")
                return t.localizedCaseInsensitiveContains(q) || n.localizedCaseInsensitiveContains(q)
            }
        }

        return out
    }

    // MARK: - Delete

    private func deleteSessions(at offsets: IndexSet) {
        let rows = filteredSessions
        do {
            for idx in offsets {
                viewContext.delete(rows[idx])
            }
            try viewContext.save()
        } catch {
            print("Delete error: \(error)")
        }
    }

    // MARK: - Debounce

    private func setUpDebounce() {
        debounceCancellable?.cancel()
        debounceCancellable = Just(searchText)
            .delay(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { debouncedQuery = $0 }
    }
}

// MARK: - Filter bar (unchanged logic, wrapped by a card above)

fileprivate struct FilterBar: View {
    @Binding var filtersExpanded: Bool
    let instruments: [Instrument]
    let customNames: [String]
    @Binding var selectedInstrument: Instrument?
    @Binding var selectedActivity: ActivityFilter
    @Binding var selectedScope: FeedScope
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // Header button now controls expansion; this view only renders contents when expanded
            if filtersExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    // Scope
                    Picker("Scope", selection: $selectedScope) {
                        ForEach(FeedScope.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Search
                    TextField("Search title or notes", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    // Instrument
                    HStack {
                        Text("Instrument")
                        Spacer()
                        Picker("Instrument", selection: $selectedInstrument) {
                            Text("Any").tag(nil as Instrument?)
                            ForEach(instruments, id: \.objectID) { inst in
                                Text(inst.name ?? "(Unnamed)").tag(inst as Instrument?)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.Colors.secondaryText)
                    }

                    // Activity — include customs
                    HStack {
                        Text("Activity")
                        Spacer()
                        Picker("Activity", selection: $selectedActivity) {
                            Text("Any").tag(ActivityFilter.any)
                            // Core activities
                            ForEach(ActivityType.allCases) { a in
                                Text(a.label).tag(ActivityFilter.core(a))
                            }
                            // Custom activities
                            if !customNames.isEmpty {
                                ForEach(customNames, id: \.self) { name in
                                    Text(name).tag(ActivityFilter.custom(name))
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.Colors.secondaryText)
                    }
                }
            }
        }
    }
}

// MARK: - Stats (card content)

fileprivate struct StatsBannerView: View {
    let sessions: [Session]

    private var totalSeconds: Int {
        var total = 0
        for s in sessions {
            let attrs = s.entity.attributesByName
            if attrs["durationSeconds"] != nil, let n = s.value(forKey: "durationSeconds") as? NSNumber {
                total += n.intValue
            } else if attrs["durationMinutes"] != nil, let n = s.value(forKey: "durationMinutes") as? NSNumber {
                total += n.intValue * 60
            } else if attrs["duration"] != nil, let n = s.value(forKey: "duration") as? NSNumber {
                total += n.intValue * 60
            } else if attrs["lengthMinutes"] != nil, let n = s.value(forKey: "lengthMinutes") as? NSNumber {
                total += n.intValue * 60
            }
        }
        return max(0, total)
    }

    private var totalTimeDisplay: String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var count: Int { sessions.count }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Sessions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text("\(count) activities")
                    .font(.subheadline)
                Text("\(totalTimeDisplay) total")
                    .font(.subheadline)
            }
            Spacer()
        }
        .padding(.vertical, 4)

    }
}

// MARK: - Row (shows derived title and subtitle)

fileprivate struct SessionRow: View {
    @ObservedObject var session: Session
    let scope: FeedScope
    // Force refresh when any Attachment belonging to this session changes (e.g., isThumbnail toggled in Add/Edit)
    @State private var _refreshTick: Int = 0

    @State private var showDetailFromComment: Bool = false
    @State private var isLikedLocal: Bool = false
    @State private var likeCountLocal: Int = 0
    @State private var commentCountLocal: Int = 0

    private var feedTitle: String { SessionActivity.feedTitle(for: session) }
    private var feedSubtitle: String { SessionActivity.feedSubtitle(for: session) }

    private var sessionUUID: UUID? { session.value(forKey: "id") as? UUID }
    private var isPrivatePost: Bool { session.isPublic == false }

    private func shareText() -> String {
        let title = SessionActivity.feedTitle(for: session)
        return "Check out my session: \(title) — via Motivo"
    }

    private var attachments: [Attachment] {
        (session.attachments as? Set<Attachment>).map { Array($0) } ?? []
    }
    private var favoriteAttachment: Attachment? {
        pickFavoriteAttachment(from: attachments)
    }

    // Visible attachments for the current viewer (owner sees all; others see non-private only)
    private var visibleAttachments: [Attachment] {
        if viewerIsOwner { return attachments }
        return attachments.filter { !isPrivate($0) }
    }

    private var extraAttachmentCount: Int {
        let total = visibleAttachments.count
        return max(total - 1, 0)
    }

    private var viewerIsOwner: Bool {
        // Compare session.ownerUserID to the current signed-in user, if available
        let current = (try? PersistenceController.shared.currentUserID) ?? nil
        let owner = session.ownerUserID
        if let c = current, let o = owner { return c == o }
        return false
    }
    private func isPrivate(_ att: Attachment) -> Bool {
        let id = att.value(forKey: "id") as? UUID
        // Resolve a stable URL if possible
        let url = attachmentFileURL(att)
        return AttachmentPrivacy.isPrivate(id: id, url: url)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                // Identity header
                if scope != .mine, let ownerID = (session.ownerUserID ?? (viewerIsOwner ? ((try? PersistenceController.shared.currentUserID) ?? nil) : nil)), !ownerID.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        // Avatar 32pt circle
                        Group {
                            #if canImport(UIKit)
                            if let img = ProfileStore.avatarImage(for: ownerID) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                // If viewer is owner, derive initials from Profile.name; else show a neutral 'U'
                                let initials: String = {
                                    if viewerIsOwner {
                                        let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                        req.fetchLimit = 1
                                        if let ctx = session.managedObjectContext,
                                           let p = try? ctx.fetch(req).first,
                                           let n = p.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            let words = n.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                                            if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
                                            let first = words.first?.first.map { String($0).uppercased() } ?? ""
                                            let last = words.last?.first.map { String($0).uppercased() } ?? ""
                                            return first + last
                                        }
                                        return "Y"
                                    } else {
                                        return "U"
                                    }
                                }()
                                ZStack {
                                    Circle().fill(Color.gray.opacity(0.2))
                                    Text(initials)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                            }
                            #else
                            ZStack {
                                Circle().fill(Color.gray.opacity(0.2))
                                Text("U").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                            }
                            #endif
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))

                        // Name and optional location on one line
                        let realName: String = {
                            // Source of truth: Core Data Profile.name for current device's user only.
                            // For other users (future), fallback to a neutral label.
                            if viewerIsOwner {
                                let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                req.fetchLimit = 1
                                if let ctx = session.managedObjectContext, let p = try? ctx.fetch(req).first, let n = p.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return n
                                }
                                return "You"
                            } else {
                                return "User"
                            }
                        }()

                        let loc = ProfileStore.location(for: ownerID)

                        HStack(spacing: 6) {
                            Text(realName).font(.subheadline.weight(.semibold))
                            if !loc.isEmpty {
                                Text("•").foregroundStyle(Theme.Colors.secondaryText)
                                Text(loc).font(.footnote).foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 2) // minimal spacing to title
                }

                // Title only (paperclip removed)
                Text(feedTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("row.title")

                // Subtitle (metadata)
                Text(feedSubtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(2)
                    .padding(.top, 3)
                    .accessibilityLabel("Instrument and activity")
                    .accessibilityIdentifier("row.subtitle")

                // Single favorite attachment preview (only one allowed/displayed)
                if let fav = favoriteAttachment {
                    // If viewer isn't the owner, hide preview when favorite is private
                    if viewerIsOwner || !isPrivate(fav) {
                        HStack(alignment: .center, spacing: 8) {
                            SingleAttachmentPreview(attachment: fav)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                    // Interaction row (Like · Comment · Share) — placed directly under thumbnail when present
                    if let sid = sessionUUID {
                        interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                            .padding(.top, 6)
                    }
                }
                // Fallback: if there is no thumbnail, place the interaction row below the subtitle
                else if let sid = sessionUUID {
                    interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, !attachments.isEmpty ? 10 : 6)
        .id(_refreshTick)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open session")
        .accessibilityIdentifier("row.openDetail")
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            guard let updates = note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return }
            if updates.contains(where: { ($0 as? Attachment)?.session == self.session }) {
                _refreshTick &+= 1
            }
        }
        .task(id: sessionUUID) {
            if let sid = sessionUUID {
                isLikedLocal = FeedInteractionStore.isLiked(sid)
                likeCountLocal = FeedInteractionStore.likeCount(sid)
                commentCountLocal = FeedInteractionStore.commentCount(sid)
            }
        }
    }

    @ViewBuilder
    private func interactionRow(sessionID: UUID, attachmentCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Like
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                let newState = FeedInteractionStore.toggleLike(sessionID)
                isLikedLocal = newState
                likeCountLocal = FeedInteractionStore.likeCount(sessionID)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isLikedLocal ? "heart.fill" : "heart")
                        .foregroundStyle(isLikedLocal ? Color.red : Theme.Colors.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLikedLocal ? "Unlike" : "Like")

            // Comment (navigates to detail)
            Button(action: {
                showDetailFromComment = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

            // Share
            Group {
                if isPrivatePost && !viewerIsOwner {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .opacity(0.4)
                    }
                    .accessibilityHidden(true)
                } else {
                    ShareLink(item: shareText()) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer(minLength: 0)
            
            if attachmentCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text("\(attachmentCount)")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
                .padding(6)
                .accessibilityLabel("\(attachmentCount) attachments")
            }
        }
        .padding(.top, -2)
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        // Hidden NavigationLink for Comment tap
        .background(
            NavigationLink(isActive: $showDetailFromComment) {
                SessionDetailView(session: session)
            } label: { EmptyView() }
            .hidden()
        )
    }
}

fileprivate struct VideoOrIconTile: View {
    let attachment: Attachment
    @State private var poster: UIImage? = nil

    var body: some View {
        let kind = attachmentKind(attachment)
        ZStack(alignment: .center) {
            if kind == "video" {
                ZStack(alignment: .center) {
                    if let poster {
                        Image(uiImage: poster)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipped()
                    } else {
                        Image(systemName: "video")
                            .imageScale(.large)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .task {
                    if poster == nil, let url = attachmentFileURL(attachment) {
                        await loadPoster(url)
                    }
                }
            } else {
                Image(systemName: symbolName(for: kind))
                    .imageScale(.large)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(width: 64, height: 64)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func symbolName(for kind: String) -> String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "pdf":   return "doc.richtext"
        default:        return "doc"
        }
    }

    private func loadPoster(_ url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    self.poster = img
                    continuation.resume()
                }
            }
        }
    }
}

fileprivate struct SingleAttachmentPreview: View {
    let attachment: Attachment
    @State private var poster: UIImage? = nil

    var body: some View {
        let kind = attachmentKind(attachment)
        let isAudio = (kind == "audio")
        let size: CGFloat = isAudio ? FEED_AUDIO_THUMB : FEED_IMAGE_VIDEO_THUMB
        ZStack(alignment: .center) {
            if kind == "image" {
                AttachmentThumb(attachment: attachment)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous).stroke(.black.opacity(0.05), lineWidth: 1))
            } else if kind == "video" {
                ZStack(alignment: .center) {
                    if let poster {
                        Image(uiImage: poster)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                    } else {
                        Image(systemName: "video")
                            .imageScale(.large)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .task {
                    if poster == nil, let url = attachmentFileURL(attachment) { await loadPoster(url) }
                }
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous).stroke(.black.opacity(0.05), lineWidth: 1))
            } else {
                Image(systemName: symbolName(for: kind))
                    .imageScale(.large)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: size, height: size)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous).stroke(.black.opacity(0.05), lineWidth: 1))
            }
        }
        .accessibilityLabel("Attachment preview")
        .accessibilityIdentifier("row.attachmentPreview")
    }

    private func symbolName(for kind: String) -> String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "pdf":   return "doc.richtext"
        default:        return "doc"
        }
    }

    private func loadPoster(_ url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    self.poster = img
                    continuation.resume()
                }
            }
        }
    }
}

// PDF / audio / video icons
fileprivate struct NonImageTile: View {
    let kind: String
    @State private var poster: UIImage? = nil
    @State private var triedLoad = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            Group {
                if kind == "video", let poster {
                    Image(uiImage: poster).resizable().scaledToFill()
                } else {
                    Image(systemName: symbolName)
                        .imageScale(.large)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .onAppear {
            // Best-effort: if this is a video, attempt to load poster from the first available video attachment's URL in context.
            guard !triedLoad, kind == "video" else { return }
            triedLoad = true
        }
    }
    private var symbolName: String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "pdf":   return "doc.richtext"
        default:        return "doc"
        }
    }
}

// MARK: - Image thumbnail (actual image if available)

fileprivate struct AttachmentThumb: View {
    @ObservedObject var attachment: Attachment
    #if canImport(UIKit)
    @StateObject private var loader: AttachmentThumbLoader
    init(attachment: Attachment) {
        self._attachment = ObservedObject(initialValue: attachment)
        _loader = StateObject(wrappedValue: AttachmentThumbLoader(attachment: attachment))
    }
    #endif

    var body: some View {
        #if canImport(UIKit)
        Group {
            if let ui = loader.image {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if loader.isFinished {
                // Finished but no image -> neutral photo placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            } else {
                // Loading
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                    ProgressView().progressViewStyle(.circular)
                }
            }
        }
        #else
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(Theme.Colors.secondaryText)
            .background(Color.secondary.opacity(0.08))
        #endif
    }
}
#if canImport(UIKit)
import UIKit

final class AttachmentThumbLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isFinished: Bool = false

    private static let cache = NSCache<NSString, UIImage>()
    private let att: Attachment
    private let maxSide: CGFloat = 100 // small thumb

    init(attachment: Attachment) {
        self.att = attachment
        load()
    }

    private func load() {
        isFinished = false
        let key = att.objectID.uriRepresentation().absoluteString as NSString
        if let cached = Self.cache.object(forKey: key) {
            self.image = cached
            self.isFinished = true
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var ui: UIImage? = nil
            // Try inline first
            ui = attachmentImage(self.att)
            // Try file URL next
            if ui == nil, let url = attachmentFileURL(self.att) {
                if url.isFileURL {
                    ui = UIImage(contentsOfFile: url.path)
                }
            }
            // Try Photos asset (localIdentifier) synchronously for a tiny target
            if ui == nil {
                ui = attachmentPhotoLibraryImage(self.att, targetMax: self.maxSide)
            }
            var final: UIImage? = nil
            if let ui {
                final = self.downscale(ui, to: self.maxSide)
            }
            DispatchQueue.main.async {
                if let final {
                    Self.cache.setObject(final, forKey: key)
                    self.image = final
                }
                self.isFinished = true
            }
        }
    }

    private func downscale(_ img: UIImage, to max: CGFloat) -> UIImage? {
        let size = img.size
        guard size.width > 0 && size.height > 0 else { return img }
        let scale = min(max / size.width, max / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif



// MARK: - Favorite image selection

fileprivate func pickFavoriteImage(from images: [Attachment]) -> Attachment? {
    // Prefer explicit favorite/primary/thumbnail flags if present
    for a in images {
        if isTrueFlag(a, keys: ["isThumbnail","thumbnail","isFavorite","favorite","isStarred","starred","isPrimary","isCover"]) {
            return a
        }
    }
    // Otherwise, first image
    return images.first
}

fileprivate func pickFavoriteAttachment(from attachments: [Attachment]) -> Attachment? {
    // Prefer explicit favorite/primary/thumbnail flags if present across any kind
    for a in attachments {
        if isTrueFlag(a, keys: ["isThumbnail","thumbnail","isFavorite","favorite","isStarred","starred","isPrimary","isCover"]) {
            return a
        }
    }
    // Otherwise, prefer first image, else first attachment of any kind
    if let firstImage = attachments.first(where: { attachmentKind($0) == "image" }) { return firstImage }
    return attachments.first
}

fileprivate func isTrueFlag(_ a: Attachment, keys: [String]) -> Bool {
    let props = a.entity.propertiesByName
    for k in keys where props[k] != nil {
        if let n = a.value(forKey: k) as? NSNumber { if n.boolValue { return true } }
        if let b = a.value(forKey: k) as? Bool, b { return true }
    }
    return false
}

// MARK: - Attachment helpers (KVC-safe + file URL + Photos fallback)

fileprivate func attachmentKind(_ a: Attachment) -> String {
    let props = a.entity.propertiesByName
    func str(_ k: String) -> String? { props[k] != nil ? (a.value(forKey: k) as? String) : nil }

    // MIME-ish fields
    let typeStr = (str("type") ?? str("kind") ?? str("mimeType") ?? "").lowercased()
    if typeStr.contains("image") { return "image" }
    if typeStr.contains("video") { return "video" }
    if typeStr.contains("audio") { return "audio" }
    if typeStr.contains("pdf")   { return "pdf" }

    // URL/path
    let urlStr = (str("url") ?? str("fileURL") ?? str("path") ?? "").lowercased()
    if urlStr.hasSuffix(".png") || urlStr.hasSuffix(".jpg") || urlStr.hasSuffix(".jpeg") || urlStr.hasSuffix(".heic") { return "image" }
    if urlStr.hasSuffix(".mp4") || urlStr.hasSuffix(".mov") || urlStr.hasSuffix(".m4v") { return "video" }
    if urlStr.hasSuffix(".m4a") || urlStr.hasSuffix(".mp3") || urlStr.hasSuffix(".wav") { return "audio" }
    if urlStr.hasSuffix(".pdf") { return "pdf" }

    return "unknown"
}

fileprivate func attachmentFileURL(_ a: Attachment) -> URL? {

    func fallbackByFilename(_ filename: String) -> URL? {
        let fm = FileManager.default
        let dirs: [URL?] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory())
        ]
        for d in dirs.compactMap({ $0 }) {
            let candidate = d.appendingPathComponent(filename)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
    let props = a.entity.propertiesByName

    // URL-typed properties
    let urlKeysURL = ["url", "fileURL", "pathURL", "localURL"]
    for k in urlKeysURL where props[k] != nil {
        if let u = a.value(forKey: k) as? URL {
            if u.isFileURL {
                if FileManager.default.fileExists(atPath: u.path) { return u }
                if let alt = fallbackByFilename(u.lastPathComponent) { return alt }
            } else {
                return u
            }
        }
    }

    // String-typed properties
    let urlKeysString = ["url", "fileURL", "path", "localPath", "filename"]
    for k in urlKeysString where props[k] != nil {
        if let sVal = a.value(forKey: k) as? String, !sVal.isEmpty {
            // If it's a file:// URL string
            if let u = URL(string: sVal), u.scheme?.hasPrefix("file") == true {
                if FileManager.default.fileExists(atPath: u.path) { return u }
                if let alt = fallbackByFilename(u.lastPathComponent) { return alt }
            }
            // Absolute path string
            if sVal.hasPrefix("/") {
                if FileManager.default.fileExists(atPath: sVal) { return URL(fileURLWithPath: sVal) }
                if let alt = fallbackByFilename(URL(fileURLWithPath: sVal).lastPathComponent) { return alt }
            }
            // Relative path or plain filename
            if let alt = fallbackByFilename(sVal) { return alt }
        }
    }

    // Bookmark data
    let bookmarkKeys = ["bookmark", "bookmarkData"]
    for k in bookmarkKeys where props[k] != nil {
        if let d = a.value(forKey: k) as? Data {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return u
            }
        }
    }

    return nil
}

#if canImport(UIKit)
import UIKit
fileprivate func attachmentImage(_ a: Attachment) -> UIImage? {
    let props = a.entity.propertiesByName
    // inline data or transformables (expanded keys)
    let keys = ["thumbnail", "thumbnailData", "thumbData", "thumbnailSmall", "imageData", "image", "data", "preview", "previewData", "photoData"]
    for k in keys where props[k] != nil {
        if let d = a.value(forKey: k) as? Data, let img = UIImage(data: d) { return img }
        if let img = a.value(forKey: k) as? UIImage { return img }
    }
    return nil
}
#endif

#if canImport(Photos)
import Photos
fileprivate func attachmentPhotoLibraryImage(_ a: Attachment, targetMax: CGFloat) -> UIImage? {
    let props = a.entity.propertiesByName
    func str(_ k: String) -> String? { props[k] != nil ? (a.value(forKey: k) as? String) : nil }
    guard let id = (str("phLocalIdentifier") ?? str("localIdentifier") ?? str("assetIdentifier")) else {
        return nil
    }
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
    guard let asset = assets.firstObject else { return nil }
    let manager = PHImageManager.default()
    let size = CGSize(width: targetMax, height: targetMax)
    let opts = PHImageRequestOptions()
    opts.isSynchronous = true
    opts.deliveryMode = .fastFormat
    opts.resizeMode = .fast
    var result: UIImage?
    manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: opts) { img, _ in
        result = img
    }
    return result
}
#else
fileprivate func attachmentPhotoLibraryImage(_ a: Attachment, targetMax: CGFloat) -> UIImage? { nil }
#endif

