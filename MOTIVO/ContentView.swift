// CHANGE-ID: 20260122_223700_14_2_1d_RemoteThumbSignedURL
// SCOPE: Phase 14.2.1 — RemoteAttachmentPreview: load signed URL thumbnails for remote image attachments (feed parity); fallback to icon; cache by bucket|path.
// SEARCH-TOKEN: 20260122_220200_14_2_1c_RemoteTitlesParity

// CHANGE-ID: 20260122_203207_14_2_1_ContentViewConnectedFeedParity
// SCOPE: Phase 14.2.1 — ContentView Connected feed parity: render remote backend posts inline with local sessions using a unified row source; keep UI chrome and local SessionRow/navigation untouched; remote rows use SessionRow-twin layout and navigate to BackendSessionDetailView.
// SEARCH-TOKEN: 20260122_203207_14_2_1_ContentViewConnectedFeedParity
// CHANGE-ID: 20260122_190500_14_2_1_HeadlessConnectedRevert
// SCOPE: Phase 14.2.1 — Revert Connected feed UI to canonical local SessionRow + SessionDetailView navigation; keep headless connected-mode backend fetch/refresh triggers; do not render backend-specific feed rows in Connected mode.
// SEARCH-TOKEN: 20260122_190500_HeadlessConnectedRevert
// CHANGE-ID: 20260122_090100_Phase141_RequestBadge_RefreshTriggers
// SCOPE: Phase 14.1 — Requests '+' badge freshness: refresh FollowStore on pull-to-refresh and on app foreground (scenePhase active). No polling.
// SEARCH-TOKEN: 20260122_090100_Phase141_RequestBadge_RefreshTriggers

// CHANGE-ID: 20260121_183500_Phase14_Step4_IdentityInBackendFeed
// SCOPE: Phase 14 Step 4 — show account_directory identity (display_name + optional @account_id) in backend feed rows; no location; no behavior changes.

// CHANGE-ID: 20260121_115517_P13D2_ContentView
// SCOPE: Phase 13D.2 — Gate backend feed rendering on BackendEnvironment.isConnected (shipping) instead of isPreview (debug-only). No other UI/logic changes.
// SEARCH-TOKEN: 20260121_115517_P13D2_ContentView

// CHANGE-ID: 20260116_1627_Phase10_TopBarPeopleFix_7e4f15
// SCOPE: Phase 10: ContentView top-left People (magnifying glass) button — tighten spacing without overlap; ensure tap opens sheet.

// CHANGE-ID: 20260114_092641_P9D2_CommentsGate_8507525b
// SCOPE: Step 9D.2 — Gate Comments entry points based on backend follow approval (fail closed).
// SEARCH-TOKEN: 20260114_092641_Step9D2_CommentsGate

// CHANGE-ID: 20260112_131015_9A_backend_identity_canonicalisation
// SCOPE: Step 9A — Pass backendUserID into SessionsRootView and use it for backend preview ownership checks
// UNIQUE-TOKEN: 20260112_131015_contentview_backend_id

// CHANGE-ID: 20260112_133000_9A_fix_backendUserID_redecl
// SCOPE: 9A hotfix — remove duplicate backendUserID property in SessionsRootView to restore init signature (no behavior change).
// UNIQUE-TOKEN: 20260112_133000_9A_fix_backendUserID_redecl

// CHANGE-ID: 20260111_135903_9c2a7f1e
// SCOPE: ContentView — Feed Filter visual-only pass (Saved-only row alignment + collapsed header optical centering)
// UNIQUE-TOKEN: 20260111_135903_feed_filter_visual_pass3
// CHANGE-ID: v7.12B-ContentView-FixEffectiveUserID-20251112_135718
// SCOPE: Add effectiveUserID in SessionsRootView + DEBUG follow/publish gating in .all
// CHANGE-ID: v710H-TopButtonsSafeInset-20251030-1205
// SCOPE: ContentView — replace .toolbar with .safeAreaInset for avatar/record/plus (visual-only); remove toolbar capsule
// UNIQUE-TOKEN: v710H-TopButtonsSafeInset-20251030-1205
// CHANGE-ID: 20260105_191200_contentview_thumb_inclusion_invariant
// SCOPE: Feed thumbnail preview must never use private (not-included) attachments; if none included, show no thumbnail.
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
// CHANGE-ID: 20260111_132050_feed_filter_visual_overhaul
// SCOPE: Visual-only — shrink/soften Feed Filter collapsed+open states; no logic/behavior changes
// UNIQUE-TOKEN: 20260111_132050_feed_filter_visual_overhaul
// CHANGE-ID: 20260121_203420_Phase141_ContentView_FollowBadgeReactive_OwnerPeekFix
// SCOPE: Phase 14.1 — Observe FollowStore for reactive request '+' badge; unify viewerID for owner checks; ensure self-peek never gated.
// SEARCH-TOKEN: 20260121_203420_Phase141_ContentView_FollowBadgeReactive_OwnerPeekFix

// CHANGE-ID: 20260122_113000_Phase142_ContentViewIgnoreOverridesInConnected
// SCOPE: Phase 14.2 — Ignore debug identity overrides in connected mode (owner checks + viewer-local state)
// SEARCH-TOKEN: 20260122_113000_Phase142_ContentViewGuardrails

import SwiftUI
import CoreData
import Combine
import CryptoKit

private let FEED_IMAGE_VIDEO_THUMB: CGFloat = 88
private let FEED_AUDIO_THUMB: CGFloat = 56
private let FEED_THUMB_CORNER: CGFloat = 10

// MARK: - Top buttons UI constants (visual only)
private enum TopButtonsUI {
    static let size: CGFloat = 40       // was 44
    static let iconRecord: CGFloat = 19 // was 21
    static let iconPlus: CGFloat = 17   // was 19
    static let spacing: CGFloat = Theme.Spacing.l  // increase a notch
    static let fillOpacityLight: CGFloat = 0.96
    static let fillOpacityDark: CGFloat = 0.88
}

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

// Unified feed rows for ContentView List rendering (Local Core Data sessions + Remote backend posts).
fileprivate struct FeedRowItem: Identifiable {
    enum Kind {
        case local(Session)
        case remote(BackendPost)
    }

    let id: String
    let kind: Kind
    let sortDate: Date

    static func build(local: [Session], remote: [BackendPost]) -> [FeedRowItem] {
        var out: [FeedRowItem] = []

        out.append(contentsOf: local.map { s in
            let sid = s.objectID.uriRepresentation().absoluteString
            let ts = (s.value(forKey: "timestamp") as? Date) ?? Date.distantPast
            return FeedRowItem(id: "local:\(sid)", kind: .local(s), sortDate: ts)
        })

        out.append(contentsOf: remote.map { p in
            let ts = FeedRowItem.parseBackendDate(p.sessionTimestamp) ??
                     FeedRowItem.parseBackendDate(p.createdAt) ??
                     Date.distantPast
            return FeedRowItem(id: "remote:\(p.id.uuidString)", kind: .remote(p), sortDate: ts)
        })

        // Newest first.
        out.sort { $0.sortDate > $1.sortDate }
        return out
    }

    private static let iso = ISO8601DateFormatter()

    static func parseBackendDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        // Most Supabase timestamps are ISO8601; be forgiving.
        if let d = iso.date(from: s) { return d }
        // Attempt to handle fractional seconds if not handled by default formatter.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
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
@ObservedObject private var followStore = FollowStore.shared

    var body: some View {
        SessionsRootView(userID: auth.currentUserID, backendUserID: auth.backendUserID)
            .id(auth.currentUserID ?? "nil-user")
    }
}

// MARK: - Root

fileprivate struct SessionsRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    // Phase 14.1: make follow requests reactive in this view (badge)
    @ObservedObject private var followStore = FollowStore.shared

    let userID: String?
    let backendUserID: String?

    @AppStorage("filtersExpanded") private var filtersExpanded = false
    @AppStorage("BackendModeChangeTick_v1") private var backendModeChangeTick: Int = 0
    @State private var selectedInstrument: Instrument? = nil
    @State private var selectedActivity: ActivityFilter = .any
    @State private var selectedScope: FeedScope = .all
    @State private var searchText: String = ""
    @AppStorage("feedSavedOnly_v1") private var savedOnly: Bool = false
    @State private var debouncedQuery: String = ""
    @State private var pushSessionID: UUID? = nil
    @State private var pushRemotePostID: UUID? = nil

    @State private var statsRange: StatsRange = .week
    @State private var stats: SessionStats = .init(count: 0, seconds: 0)

    // Sheets
    @State private var showProfile = false
    @State private var showTimer = false
    @State private var showAdd = false
    @State private var showPeople = false

    #if DEBUG
    @State private var isDebugPresented: Bool = false
    @State private var _debugJSONBuffer: String = "{}"
    #endif

    // Debounce
    @State private var debounceCancellable: AnyCancellable?
    @State private var lastBackendAutoFetchKey: String = ""
    @State private var lastBackendAutoFetchAt: Date = .distantPast

    #if DEBUG
    private var effectiveUserID: String? {
        if BackendEnvironment.shared.isConnected == false,
           let o = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride") { return o }
        return userID
    }
    #else
    private var effectiveUserID: String? { userID }
    #endif

    /// Canonical backend identity for backend-preview ownership checks and scoping.
    /// Uses a dedicated DEBUG override so we don't mix local (Apple) IDs with backend UUIDs.
    private var effectiveBackendUserID: String? {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let o = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !o.isEmpty {
            return o.lowercased()
        }
        #endif
        let raw = (backendUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw.lowercased()
    }

    // Step 8C (backend preview): render backend-backed feed when Backend Preview mode is enabled
    @ObservedObject private var backendFeedStore: BackendFeedStore = .shared

    private var useBackendFeed: Bool {
        _ = backendModeChangeTick
        return BackendEnvironment.shared.isConnected &&
        BackendConfig.isConfigured &&
        (NetworkManager.shared.baseURL != nil)
    }

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
   


    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {

                // ---------- Stats (card) ----------
                VStack(alignment: .leading, spacing: 8) {
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
                .padding(.bottom, Theme.Spacing.s)

                // ---------- Filters (utility strip) ----------
                VStack(alignment: .leading, spacing: 6) {
                    // Header toggles expansion; visually demoted (utility row)
                    Button { withAnimation { filtersExpanded.toggle() } } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Feed Filter")
                                .font(Theme.Text.meta.weight(.semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)

                            Spacer(minLength: 0)

                            Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .imageScale(.small)
                                .padding(.top, 1)
                        }
                        .padding(.top, 1) // optical centering in collapsed pill
                        .contentShape(Rectangle())
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
                        searchText: $searchText,
                        savedOnly: $savedOnly
                    )
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.Colors.surface(colorScheme).opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.Colors.cardStroke(colorScheme).opacity(0.55), lineWidth: 1)
                )
                .padding(.bottom, Theme.Spacing.s)
// ---------- Sessions List ----------
                Group {
                    List {
                        Section {
                            let localRows: [Session] = filteredSessions

                            // Connected-mode remote posts (do not materialize into Core Data)
                            let remotePostsRaw: [BackendPost] = {
                                guard useBackendFeed else { return [] }
                                return (selectedScope == .mine) ? backendFeedStore.minePosts : backendFeedStore.allPosts
                            }()

                            // Dedupe: if a backend post corresponds to a local session on this device, prefer the local row.
                            let localSessionIDs: Set<UUID> = Set(localRows.compactMap { $0.value(forKey: "id") as? UUID })
                            let remotePosts: [BackendPost] = remotePostsRaw.filter { post in
                                guard let sid = post.sessionID else { return true }
                                return !localSessionIDs.contains(sid)
                            }

                            // Build unified row source (Local sessions + Remote posts)
                            let feedItems: [FeedRowItem] = FeedRowItem.build(
                                local: localRows,
                                remote: remotePosts
                            )

                            if feedItems.isEmpty {
                                Text("No sessions match your filters yet.")
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            } else {
                                ForEach(feedItems) { item in
                                    switch item.kind {
                                    case .local(let session):
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
                                                .cardSurface()
                                                .padding(.bottom, Theme.Spacing.section)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowSeparator(.hidden)
                                        .deleteDisabled(false)

                                    case .remote(let post):
                                        ZStack {
                                            NavigationLink(
                                                destination: BackendSessionDetailView(
                                                    model: BackendSessionViewModel(
                                                        post: post,
                                                        currentUserID: (effectiveUserID ?? "")
                                                    )
                                                ),
                                                isActive: Binding(
                                                    get: { pushRemotePostID == post.id },
                                                    set: { active in if !active { pushRemotePostID = nil } }
                                                )
                                            ) { EmptyView() }
                                            .opacity(0)

                                            RemotePostRowTwin(
                                                post: post,
                                                scope: selectedScope,
                                                directoryAccount: {
                                                    if let owner = post.ownerUserID {
                                                        return backendFeedStore.directoryAccountsByUserID[owner]
                                                    }
                                                    return nil
                                                }(),
                                                viewerUserID: effectiveUserID
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture { pushRemotePostID = post.id }
                                            .cardSurface()
                                            .padding(.bottom, Theme.Spacing.section)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowSeparator(.hidden)
                                        .deleteDisabled(true)
                                    }
                                }
                                .onDelete { offsets in
                                    // Local sessions only — remote rows are deleteDisabled(true)
                                    var localOffsets = IndexSet()
                                    for idx in offsets {
                                        guard idx < feedItems.count else { continue }
                                        if case .local(let s) = feedItems[idx].kind,
                                           let localIndex = localRows.firstIndex(where: { $0.objectID == s.objectID }) {
                                            localOffsets.insert(localIndex)
                                        }
                                    }
                                    if !localOffsets.isEmpty {
                                        deleteSessions(at: localOffsets)
                                    }
                                }
                            }
                        }
                        .listSectionSeparator(.hidden, edges: .all)
                    }
                    .task(id: selectedScope) {
                        guard useBackendFeed else { return }

                        let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
                        let key = "auto:\(scopeKey)"

                        // Debounce: prevent rapid consecutive auto-fetches for the same scope
                        if key == lastBackendAutoFetchKey &&
                           Date().timeIntervalSince(lastBackendAutoFetchAt) < 1.5 {
                            return
                        }

                        lastBackendAutoFetchKey = key
                        lastBackendAutoFetchAt = Date()

                        _ = await BackendEnvironment.shared.publish.fetchFeed(scope: scopeKey)
                    }
                }

                .refreshable {
                    // User-initiated refresh (pull-to-refresh)
                    if useBackendFeed {
                        let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
                        _ = await BackendEnvironment.shared.publish.fetchFeed(scope: scopeKey)
                    }
                    await followStore.refreshFromBackendIfPossible()
                }
                .id(backendModeChangeTick)
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .listRowBackground(Color.clear)
                .background(Theme.Colors.surface(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.cardStroke(colorScheme), lineWidth: 1)
                )
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
            // No big nav title
            
            .safeAreaInset(edge: .top) {
                HStack(spacing: TopButtonsUI.spacing) {
                    Button { showProfile = true } label: {
                        #if canImport(UIKit)
                        if let uiImage = ProfileStore.avatarImage(for: userID) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
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
                                    return combo.isEmpty ? "?" : combo
                                }
                                return "?"
                            }()

                            ZStack {
                                Circle().fill(.thinMaterial)
                                Text(initials)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                            .padding(8)
                        }
                        #else
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                            Image(systemName: "person.fill")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                        }
                        .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                        #endif
                    }
                    .accessibilityLabel("Open profile")
                    // People (search / follows)
                    Button {
                        showPeople = true
                    } label: {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)

                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                        .contentShape(Circle())

                        // Subtle "+" indicator for incoming follow requests (outside the pill)
                        if !followStore.requests.isEmpty {
                            Text("+")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .offset(x: 8, y: -8)
                        }
                    }
                    }
                        .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityLabel("People")
Spacer()
                    HStack(spacing: TopButtonsUI.spacing) {
                        Button { showTimer = true } label: {
                            ZStack {
                              Circle()
                                .fill(.thinMaterial)
                                .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)

                              Image(systemName: "record.circle.fill")
                                .font(.system(size: TopButtonsUI.iconRecord, weight: .regular))
                                .foregroundStyle(.red)
                            }
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                            .contentShape(Circle())
                            .buttonStyle(.plain)
                        }
                        .accessibilityLabel("Start session timer")
                        Button { showAdd = true } label: {
                            ZStack {
                              Circle()
                                .fill(.thinMaterial)
                                .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)

                              Image(systemName: "plus")
                                .font(.system(size: TopButtonsUI.iconPlus, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                            }
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                            .contentShape(Circle())
                            .buttonStyle(.plain)
                        }
                        .accessibilityLabel("Add manual session")
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
            }
#if DEBUG
.overlay(alignment: .top) {
    // Invisible hit area over the top toolbar GAP only (between avatar and record/add cluster)
    // Avatar is 40pt + 8pt padding each side inside the inset; right cluster has two 40pt buttons with spacing TopButtonsUI.spacing.
    // We place a narrow transparent rectangle centered in the remaining space so it doesn't intercept button taps.
    GeometryReader { geo in
        // Compute a conservative gap: full width minus left avatar block (~56) and right cluster (~40+spacing+40) and horizontal insets
        let horizontalInset = Theme.Spacing.l
        let leftBlock: CGFloat = (40 + 16) + TopButtonsUI.spacing + 40   // avatar block + spacing + People button
        let rightBlock: CGFloat = 40 + TopButtonsUI.spacing + 40
        let totalReserved = leftBlock + rightBlock + (horizontalInset * 2)
        let gapWidth = max(0, geo.size.width - totalReserved)
        // Place a centered rect in the remaining space with a modest width to avoid overlap
        let rectWidth = max(0, gapWidth - 16) // leave small margins from buttons
        let height: CGFloat = 56 // tall enough to be easy to hit, but within the inset area

        ZStack {
            Color.clear
                .frame(width: rectWidth, height: height)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.6) {
                    isDebugPresented = true
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Theme.Spacing.m) // align with the inset's top padding
        .padding(.horizontal, horizontalInset)
    }
    .allowsHitTesting(true)
    .accessibilityHidden(true)
}
#endif

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
            .sheet(isPresented: $showPeople) {
                NavigationStack {
                    PeopleView()
                }
            }
#if DEBUG
            .sheet(isPresented: $isDebugPresented) {
                NavigationStack {
                    DebugViewerView(title: "Feed Debug", jsonString: $_debugJSONBuffer)
                        .onAppear {
                            // Provide a minimal payload; reuse environment via containment
                            _debugJSONBuffer = #"{"feed":"root","userID":"\#(userID ?? "nil")"}"#
                        }
                }
            }
#endif
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

            .onChange(of: scenePhase) { phase in
                // Phase 14.1: refresh incoming follow requests when returning to foreground (no polling)
                guard phase == .active else { return }
                Task { @MainActor in
                    await followStore.refreshFromBackendIfPossible()
                }
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
            if let uid = effectiveUserID {
                out = out.filter { $0.ownerUserID == uid }
            } else {
                out = []
            }
        case .all:
            if let me = effectiveUserID {
                out = out.filter { s in
                    let isMine = (s.ownerUserID == me)
                    if isMine { return true }
                        #if DEBUG
                    if let owner = s.ownerUserID, FollowStore.shared.isFollowing(owner) {
                        if PublishService.shared.debugIsPublishedBy(owner: owner, objectID: s.objectID) { return true }
                    }
                    return false
                    #else
                    return PublishService.shared.isPublished(objectID: s.objectID)
                    #endif
                }
            } else {
                // No user — nothing should be visible
                out = []
            }
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

        // Saved-only (viewer-local)
        if savedOnly {
            guard let vid = effectiveUserID else { return [] }
            out = out.filter { s in
                guard let sid = (s.value(forKey: "id") as? UUID) else { return false }
                return FeedInteractionStore.isSaved(sid, viewerUserID: vid)
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
                let session = rows[idx]
                // Gather attachment file paths for this session and delete from disk before deleting the Core Data objects
                let attachments = (session.attachments as? Set<Attachment>) ?? []
                let paths: [String] = attachments.compactMap { att in
                    // Access KVC-safe String attribute `fileURL` if present
                    if let s = att.value(forKey: "fileURL") as? String, !s.isEmpty { return s }
                    return nil
                }
                if !paths.isEmpty {
                    AttachmentStore.deleteAttachmentFiles(atPaths: paths)
                }
                viewContext.delete(session)
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
    @Binding var savedOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // This view only renders contents when expanded (logic unchanged)
            if filtersExpanded {
                VStack(alignment: .leading, spacing: 8) {

                    // Scope
                    Picker("Scope", selection: $selectedScope) {
                        ForEach(FeedScope.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    // Search
                    TextField("Search", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(Theme.Text.meta)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .padding(.vertical, -2)
                        .padding(.horizontal, 2)
                        .controlSize(.small)

                    // Instrument
                    HStack(spacing: 10) {
                        Text("Instrument")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Spacer(minLength: 0)
                        Picker("Instrument", selection: $selectedInstrument) {
                            Text("Any").tag(nil as Instrument?)
                            ForEach(instruments, id: \.objectID) { inst in
                                Text(inst.name ?? "(Unnamed)").tag(inst as Instrument?)
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.85))
                        .tint(Theme.Colors.secondaryText)
                        .controlSize(.small)
                        .scaleEffect(0.92, anchor: .trailing)
                    }
                    .padding(.vertical, 2)

                    // Activity — include customs
                    HStack(spacing: 10) {
                        Text("Activity")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Spacer(minLength: 0)
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
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.85))
                        .tint(Theme.Colors.secondaryText)
                        .controlSize(.small)
                        .scaleEffect(0.92, anchor: .trailing)
                    }
                    .padding(.vertical, 2)

                    // Saved only — peer row (same label style/alignment as Instrument/Activity)
                    HStack(spacing: 10) {
                        Text("Saved only")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Spacer(minLength: 0)
                        Toggle("", isOn: $savedOnly)
                            .labelsHidden()
                            .controlSize(.small)
                            .scaleEffect(0.92, anchor: .trailing)
                            .padding(.trailing, 10) // aligns switch with menu picker trailing inset
                    }
                    .padding(.vertical, 2)
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

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var auth: AuthManager

    // Force refresh when any Attachment belonging to this session changes (e.g., isThumbnail toggled in Add/Edit)
    @State private var _refreshTick: Int = 0

    //@State private var showDetailFromComment: Bool = false // replaced per instructions
    @State private var isCommentsPresented: Bool = false
    @State private var showPeek: Bool = false
    @State private var isSavedLocal: Bool = false
    @State private var likeCountLocal: Int = 0
    @State private var commentCountLocal: Int = 0
    @ObservedObject private var commentsStore = CommentsStore.shared

    private var feedTitle: String { SessionActivity.feedTitle(for: session) }
    private var feedSubtitle: String { SessionActivity.feedSubtitle(for: session) }

    private var subtitleParts: [String] {
        // Split the existing subtitle by commas, trimming whitespace
        feedSubtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var dateTimeLine: String? {
        // Expect last two parts to be time then date; produce 'DATE at TIME'
        let parts = subtitleParts
        guard parts.count >= 2 else { return nil }
        let time = parts[parts.count - 2]
        let date = parts[parts.count - 1]
        return "\(date) at \(time)"
    }

    private var instrumentActivityLine: String {
        // Everything except the last two parts (time/date)
        let parts = subtitleParts
        if parts.count <= 2 {
            return parts.dropLast(max(0, parts.count - 2)).joined(separator: ", ")
        } else {
            return parts.dropLast(2).joined(separator: ", ")
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append(feedTitle)
        let meta = instrumentActivityLine
        if !meta.isEmpty {
            parts.append(meta)
        }
        if let dt = dateTimeLine {
            parts.append(dt)
        }
        return parts.joined(separator: ". ")
    }

    private var sessionUUID: UUID? { session.value(forKey: "id") as? UUID }
    private var isPrivatePost: Bool { session.isPublic == false }

    private var sessionIDForComments: UUID? {
        if let real = sessionUUID { return real }
        let uri = session.objectID.uriRepresentation().absoluteString
        return stableUUID(from: uri)
    }

    private var commentsCount: Int {
        guard let id = sessionIDForComments else { return 0 }
        return commentsStore.comments(for: id).count
    }

    /// Effective viewer ID, respecting DEBUG override, then Auth, then PersistenceController.
    private var viewerUserID: String? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"),
           !override.isEmpty {
            return override
        }
        #endif
        if let bid = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty {
            return bid.lowercased()
        }
        if let authID = auth.currentUserID, !authID.isEmpty {
            return authID
        }
        return try? PersistenceController.shared.currentUserID
    }

    private func stableUUID(from string: String) -> UUID {
        // Deterministic UUID v5-like using SHA256 first 16 bytes
        let digest = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(digest)
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid
    }

    private var attachments: [Attachment] {
        (session.attachments as? Set<Attachment>).map { Array($0) } ?? []
    }

    // Attachments included with the post (non-private). The feed thumbnail must come from this set.
    private var includedAttachments: [Attachment] {
        attachments.filter { !isPrivate($0) }
    }

    private var favoriteAttachment: Attachment? {
        pickFavoriteAttachment(from: includedAttachments)
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
        // Compare session.ownerUserID to the effective viewer ID, if available
        guard let viewer = viewerUserID, let owner = session.ownerUserID else { return false }
        return viewer == owner
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
                if scope != .mine,
                   let ownerIDNonEmpty = (session.ownerUserID ?? (viewerIsOwner ? viewerUserID : nil)),
                   !ownerIDNonEmpty.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        // Avatar 32pt circle
                        Button(action: { showPeek = true }) {
                            Group {
                                #if canImport(UIKit)
                                if let img = ProfileStore.avatarImage(for: ownerIDNonEmpty) {
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
                        }
                        .buttonStyle(.plain)

                        // Name and optional location on one line
                        let realName: String = {
                            // Source of truth: Core Data Profile.name for current device's user only.
                            // For other users (future), fallback to a neutral label.
                            if viewerIsOwner {
                                let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                req.fetchLimit = 1
                                if let ctx = session.managedObjectContext,
                                   let p = try? ctx.fetch(req).first,
                                   let n = p.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return n
                                }
                                return "You"
                            } else {
                                return "User"
                            }
                        }()

                        let loc = ProfileStore.location(for: ownerIDNonEmpty)

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

                if let dt = dateTimeLine {
                    Text(dt)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .padding(.bottom, 2)
                        .accessibilityLabel("Date and time")
                        .accessibilityIdentifier("row.datetime")
                }

                // Title only (paperclip removed)
                Text(feedTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("row.title")

                // Instrument / Activity subtitle (metadata)
                if !instrumentActivityLine.isEmpty {
                    Text(instrumentActivityLine)
                        .font(Theme.Text.meta)
                        .lineLimit(2)
                        .padding(.top, 3)
                        .accessibilityLabel("Instrument and activity")
                        .accessibilityIdentifier("row.subtitle")
                }

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
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("row.openDetail")
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            guard let updates = note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return }
            if updates.contains(where: { ($0 as? Attachment)?.session == self.session }) {
                _refreshTick &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            _refreshTick &+= 1
        }
        .task(id: sessionUUID) {
            if let sid = sessionUUID {
                if let vid = viewerUserID {
                isSavedLocal = FeedInteractionStore.isSaved(sid, viewerUserID: vid)
            } else {
                isSavedLocal = false
            }
                // 8H-A: no counts
                commentCountLocal = FeedInteractionStore.commentCount(sid)
            }
        }
        .onReceive(commentsStore.objectWillChange) { _ in
            // Update only when we can resolve a stable comments ID
            if let sid = sessionIDForComments {
                commentCountLocal = commentsStore.comments(for: sid).count
            }
        }
        .sheet(isPresented: $isCommentsPresented) {
            if let id = sessionIDForComments {
                CommentsView(sessionID: id, placeholderAuthor: "You")
            } else {
                Text("Comments unavailable for this item.").padding()
            }
        }
        .sheet(isPresented: $showPeek) {
            let viewer = viewerUserID ?? ""
            let owner = session.ownerUserID ?? ""
            // Invariant: self-peek must never render follow gating in any mode.
            let ownerForPeek = (owner.isEmpty || owner == viewer) ? (viewer.isEmpty ? owner : viewer) : owner

            ProfilePeekView(ownerID: ownerForPeek)
                .environment(\.managedObjectContext, ctx)
                .environmentObject(auth)
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
                let vid = viewerUserID ?? "unknown"
                let newState = FeedInteractionStore.toggleSaved(sessionID, viewerUserID: vid)
                isSavedLocal = newState
                // 8H-A: no counts

            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSavedLocal ? "heart.fill" : "heart")
                        .foregroundStyle(isSavedLocal ? Color.red : Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSavedLocal ? "Unsave" : "Save")

            // Comment (opens comments sheet)
            Button(action: {
                // 9D.2: gate comment entry points based on backend follow state (until comments are server-backed)
                if sessionIDForComments != nil {
                    if viewerIsOwner {
                        isCommentsPresented = true
                    } else if let owner = session.ownerUserID, FollowStore.shared.isFollowing(owner) {
                        isCommentsPresented = true
                    } else {
                        // Fail closed: do nothing.
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: commentsCount > 0 ? "text.bubble" : "bubble.right")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))

            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

            // Share (owner-only)
            if viewerIsOwner {
                ShareLink(item: shareText()) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export")
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
    }

    private func shareText() -> String {
        let title = SessionActivity.feedTitle(for: session)
        return "Check out my session: \(title) — via Motivo"
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
// MARK: - Step 8C Backend Feed Row (read-only)

fileprivate struct BackendPostRow: View {
    let model: BackendSessionViewModel
    let directoryAccount: DirectoryAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // Identity (Phase 14): display_name primary; @account_id optional secondary (demoted)
            if let acct = directoryAccount {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(acct.displayName)
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    if let handle = acct.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !handle.isEmpty {
                        Text("@\(handle)")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.75))
                    }

                    Spacer(minLength: 0)
                }
            }

            // Header: activity on the left, session time (if available) on the right
            HStack(alignment: .firstTextBaseline) {
                Text(model.activityLabel)
                    .font(Theme.Text.body)
                    .foregroundStyle(.primary)

                Spacer()

                Text(model.sessionTimestampRaw ?? model.createdAtRaw ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }

            // Secondary metadata lines
            VStack(alignment: .leading, spacing: 8) {
                if let instrument = model.instrumentLabel, !instrument.isEmpty {
                    Text(instrument)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                }

                if !model.ownerUserID.isEmpty {
                    Text(model.ownerUserID)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .cardSurface()
    }
}

// Phase 14.2.1 — Remote post row that is a visual twin of SessionRow (read-only)
fileprivate struct RemotePostRowTwin: View {
    let post: BackendPost
    let scope: FeedScope
    let directoryAccount: DirectoryAccount?
    let viewerUserID: String?

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var auth: AuthManager

    @State private var showPeek: Bool = false
    @State private var isSavedLocal: Bool = false

    private var viewerIsOwner: Bool {
        guard let viewer = viewerUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let owner = post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !viewer.isEmpty, !owner.isEmpty else { return false }
        return viewer == owner
    }

    private var ownerIDNonEmpty: String? {
        if let o = post.ownerUserID, !o.isEmpty { return o }
        return viewerIsOwner ? (viewerUserID ?? nil) : nil
    }

    private var model: BackendSessionViewModel {
        BackendSessionViewModel(post: post, currentUserID: (viewerUserID ?? ""))
    }

    private var activityName: String {
        if let label = post.activityLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        if let type = post.activityType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !type.isEmpty {
            return type
        }
        return "Practice"
    }

    private var postDescription: String {
        post.activityDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var instrumentName: String {
        if let inst = post.instrumentLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inst.isEmpty {
            return inst
        }
        return "Instrument"
    }

    private var timestampDate: Date {
        FeedRowItem.parseBackendDate(post.sessionTimestamp)
            ?? FeedRowItem.parseBackendDate(post.createdAt)
            ?? Date()
    }

    private var defaultDescription: String {
        "\(dayPart(for: timestampDate)) \(activityName)"
    }

    private var isUsingDefaultDescription: Bool {
        let desc = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else { return false }
        return desc.caseInsensitiveCompare(defaultDescription) == .orderedSame
    }

    private var feedTitle: String {
        // Mirror SessionActivity.feedTitle(for:) rules for BackendPost.
        let d = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return "\(instrumentName) : \(activityName)" }
        if isUsingDefaultDescription { return d }
        return d
    }

    private var feedSubtitle: String {
        // Mirror SessionActivity.feedSubtitle(for:) rules for BackendPost.
        let (timeStr, dateStr) = timeAndDateStrings(for: timestampDate)
        let d = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty {
            return [timeStr, dateStr].joined(separator: ", ")
        } else if isUsingDefaultDescription {
            return [instrumentName, timeStr, dateStr].joined(separator: ", ")
        } else {
            return [instrumentName, activityName, timeStr, dateStr].joined(separator: ", ")
        }
    }

    private var subtitleParts: [String] {
        // Split the existing subtitle by commas, trimming whitespace
        feedSubtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var dateTimeLine: String? {
        // Expect last two parts to be time then date; produce 'DATE at TIME'
        let parts = subtitleParts
        guard parts.count >= 2 else { return nil }
        let time = parts[parts.count - 2]
        let date = parts[parts.count - 1]
        return "\(date) at \(time)"
    }

    private var instrumentActivityLine: String {
        // Everything except the last two parts (time/date)
        let parts = subtitleParts
        if parts.count <= 2 {
            return parts.dropLast(max(0, parts.count - 2)).joined(separator: ", ")
        } else {
            return parts.dropLast(2).joined(separator: ", ")
        }
    }

    private func dayPart(for date: Date) -> String {
        // Local time components
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour], from: date)
        let hour = comps.hour ?? 0
        switch hour {
        case 0...4: return "Late Night"
        case 5...11: return "Morning"
        case 12...17: return "Afternoon"
        default: return "Evening" // 18...23
        }
    }

    private func timeAndDateStrings(for date: Date) -> (String, String) {
        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return (timeFormatter.string(from: date), dateFormatter.string(from: date))
    }

private var extraAttachmentCount: Int {
        let total = model.attachmentRefs.count
        return max(total - 1, 0)
    }

    private var favAttachmentRef: BackendSessionViewModel.BackendAttachmentRef? {
        model.attachmentRefs.first
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                // Identity header (match SessionRow: only when not in Mine)
                if scope != .mine,
                   let owner = ownerIDNonEmpty,
                   !owner.isEmpty {

                    HStack(alignment: .center, spacing: 8) {
                        // Avatar 32pt circle
                        Button(action: { showPeek = true }) {
                            Group {
                                #if canImport(UIKit)
                                if let img = ProfileStore.avatarImage(for: owner) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    let initials: String = {
                                        if let acct = directoryAccount {
                                            let words = acct.displayName
                                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                                .components(separatedBy: .whitespacesAndNewlines)
                                                .filter { !$0.isEmpty }
                                            if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
                                            let first = words.first?.first.map { String($0).uppercased() } ?? ""
                                            let last = words.last?.first.map { String($0).uppercased() } ?? ""
                                            let combo = (first + last)
                                            return combo.isEmpty ? "U" : combo
                                        }
                                        return viewerIsOwner ? "Y" : "U"
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
                        }
                        .buttonStyle(.plain)

                        // Name and optional location on one line
                        let realName: String = {
                            if viewerIsOwner { return "You" }
                            if let acct = directoryAccount { return acct.displayName }
                            return "User"
                        }()

                        let loc = ProfileStore.location(for: owner)

                        HStack(spacing: 6) {
                            Text(realName).font(.subheadline.weight(.semibold))
                            if !loc.isEmpty {
                                Text("•").foregroundStyle(Theme.Colors.secondaryText)
                                Text(loc).font(.footnote).foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 2)
                }

                if let dt = dateTimeLine {
                    Text(dt)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .padding(.bottom, 2)
                        .accessibilityLabel("Date and time")
                        .accessibilityIdentifier("row.datetime")
                }

                // Title only (paperclip removed)
                Text(feedTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityLabel("Session title")
                    .accessibilityIdentifier("row.title")

                // Activity subtitle (metadata)
                if !instrumentActivityLine.isEmpty {
                    Text(instrumentActivityLine)
                        .font(Theme.Text.meta)
                        .lineLimit(2)
                        .padding(.top, 3)
                        .accessibilityLabel(instrumentActivityLine)
                        .accessibilityIdentifier("row.subtitle")
                }

                // Attachment preview (twin placement to SessionRow)
                if let fav = favAttachmentRef {
                    HStack(alignment: .center, spacing: 8) {
                        RemoteAttachmentPreview(ref: fav)
                        Spacer()
                    }
                    .padding(.top, 2)

                    interactionRow(postID: post.id, attachmentCount: extraAttachmentCount)
                        .padding(.top, 6)
                } else {
                    interactionRow(postID: post.id, attachmentCount: extraAttachmentCount)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, !model.attachmentRefs.isEmpty ? 10 : 6)
        .onAppear {
            // Keep initial saved state in sync for this viewer + post.
            let vid = (viewerUserID ?? "unknown")
            isSavedLocal = FeedInteractionStore.isSaved(post.id, viewerUserID: vid)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("row.openDetail")
        .sheet(isPresented: $showPeek) {
            let viewer = viewerUserID ?? ""
            let owner = post.ownerUserID ?? ""
            // Invariant: self-peek must never render follow gating in any mode.
            let ownerForPeek = (owner.isEmpty || owner == viewer) ? (viewer.isEmpty ? owner : viewer) : owner

            ProfilePeekView(ownerID: ownerForPeek)
                .environment(\.managedObjectContext, ctx)
                .environmentObject(auth)
        }
    }

    private func interactionRow(postID: UUID, attachmentCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Save (viewer-local)
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                let vid = viewerUserID ?? "unknown"
                let newState = FeedInteractionStore.toggleSaved(postID, viewerUserID: vid)
                isSavedLocal = newState
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSavedLocal ? "heart.fill" : "heart")
                        .foregroundStyle(isSavedLocal ? Color.red : Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSavedLocal ? "Unsave" : "Save")

            // Comment (read-only row parity; backend comment UI is handled elsewhere)
            Button(action: {
                // Intentionally no-op in feed row; navigation to detail is the interaction surface.
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

            // Share (owner-only)
            if viewerIsOwner {
                ShareLink(item: shareText()) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export")
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
    }

    private func shareText() -> String {
        // Keep this conservative: title + date only.
        var out: [String] = [feedTitle]
        if let dt = dateTimeLine { out.append(dt) }
        return out.joined(separator: "\n")
    }
}

fileprivate final class RemoteSignedURLCache {
    static let shared = RemoteSignedURLCache()

    private struct Entry {
        let url: URL
        let createdAt: Date
    }

    private var map: [String: Entry] = [:]
    private let lock = NSLock()

    /// Signed URLs expire quickly. Treat cached entries as stale after ~55s so we refresh.
    func get(_ key: String, maxAgeSeconds: TimeInterval = 55) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = map[key] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) > maxAgeSeconds {
            map.removeValue(forKey: key)
            return nil
        }
        return entry.url
    }

    func set(_ key: String, url: URL) {
        lock.lock(); defer { lock.unlock() }
        map[key] = Entry(url: url, createdAt: Date())
    }
}

class RemotePosterCache {
    static let shared = RemotePosterCache()

    private var map: [String: UIImage] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return map[key]
    }

    func set(_ key: String, image: UIImage) {
        lock.lock(); defer { lock.unlock() }
        map[key] = image
    }
}

struct RemoteAttachmentPreview: View {
    let ref: BackendSessionViewModel.BackendAttachmentRef
    
    @State private var signedURL: URL? = nil
    @State private var videoPoster: UIImage? = nil
    
    private var cacheKey: String {
        "20260122_223700_14_2_1d_RemoteThumbSignedURL|" + ref.bucket + "|" + ref.path
    }
    
    var body: some View {
        let kind = ref.kind
        let isAudio = (kind == .audio)
        let size: CGFloat = isAudio ? FEED_AUDIO_THUMB : FEED_IMAGE_VIDEO_THUMB
        
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            
            if kind == .image, let url = signedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholderIcon(kind: kind)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderIcon(kind: kind)
                    @unknown default:
                        placeholderIcon(kind: kind)
                    }
                }
                .clipped()
            } else if kind == .video {
                if let poster = videoPoster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
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
            } else {
                placeholderIcon(kind: kind)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous).stroke(.black.opacity(0.05), lineWidth: 1))
        .accessibilityLabel("Attachment preview")
        .accessibilityIdentifier("row.attachmentPreview")
        .task(id: cacheKey) {
            await loadSignedURLIfNeeded()
        }
    }
    
    @ViewBuilder
    private func placeholderIcon(kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> some View {
        Image(systemName: iconName(for: kind))
            .imageScale(.large)
            .foregroundStyle(Theme.Colors.secondaryText)
    }
    
    private func loadSignedURLIfNeeded() async {
        guard (ref.kind == .image) || (ref.kind == .video) else { return }
        
        if let cached = RemoteSignedURLCache.shared.get(cacheKey) {
            if signedURL != cached { signedURL = cached }
            
            if ref.kind == .video, videoPoster == nil {
                if let cachedPoster = RemotePosterCache.shared.get(cacheKey) {
                    videoPoster = cachedPoster
                }
            }
            return
        }
        
        let result = await NetworkManager.shared.createSignedStorageObjectURL(
            bucket: ref.bucket,
            path: ref.path,
            expiresInSeconds: 60
        )
        
        guard case .success(let url) = result else { return }
        RemoteSignedURLCache.shared.set(cacheKey, url: url)
        
        if signedURL != url { signedURL = url }
        
        // Video: generate poster frame for feed thumbnail (cached by ref)
        if ref.kind == .video {
            if let cachedPoster = RemotePosterCache.shared.get(cacheKey) {
                videoPoster = cachedPoster
                return
            }
            
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let img = AttachmentStore.generateVideoPoster(url: url)
                    DispatchQueue.main.async {
                        if let img { RemotePosterCache.shared.set(cacheKey, image: img) }
                        videoPoster = img
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    private func iconName(for kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> String {
        switch kind {
        case .audio: return "waveform"
        case .video: return "video"
        case .image: return "photo"
        default:     return "doc"
        }
    }
}
    
    private struct PeoplePlaceholderView: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("People")
                    .font(Theme.Text.sectionHeader)
                    .foregroundStyle(Theme.Colors.secondaryText)
                
                Text("Placeholder — People hub will live here.")
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
                
                Spacer()
            }
            .padding(Theme.Spacing.l)
            .appBackground()
            // No navigationTitle here — keep it quiet.
        }
    }

