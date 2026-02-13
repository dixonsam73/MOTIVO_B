// CHANGE-ID: 20260213_070034_PostShares_DuplicateOutcome
// SCOPE: Handle BackendPostShareOutcome.alreadyShared in Share sheet (show 'Already shared.'; keep existing styling).
// SEARCH-TOKEN: 20260213_070034_PostShares_DuplicateOutcome

// CHANGE-ID: 20260212_213900_CloseStage3_ContentView_InteractionShare
// SCOPE: Close Stage 3 — Replace legacy iOS ShareLink in SessionRow.interactionRow with Share-to-follower sheet (Result-based BackendEnvironment.shared.shares.sharePost). ContentView only; no other UI/logic changes.
// SEARCH-TOKEN: 20260212_213900_CloseStage3_ContentView_InteractionShare

// CHANGE-ID: 20260212_091600_OwnerShare_BadgeCompose_FIX
// SCOPE: Owner-Only Share — compose People '+' signal from follow requests + unread shares (no layout change)
// SEARCH-TOKEN: 20260210_181900_Phase15_Step2_AvatarRenderCache_CV_AVATAR

// CHANGE-ID: 20260212_091600_OwnerShare_BadgeCompose
// SCOPE: Owner-Only Share — compose People '+' indicator from follow requests OR unread post_shares; add refresh triggers (initial task, pull-to-refresh, foreground). ContentView only.
// SEARCH-TOKEN: 20260212_091600_OwnerShare_BadgeCompose


// CHANGE-ID: 20260203_093500_FeedThumbPrewarmFix
// SCOPE: Feed thumbnail & signed-URL prewarm (warm RemoteAttachmentPreview caches ahead of scroll) — ContentView only
// SEARCH-TOKEN: 20260203_093500_FeedThumbPrewarmFix
// CHANGE-ID: 20260202_224200_FeedNavFreezeV3
// SCOPE: Freeze merged feed row identity across detail navigation (interactive pop safe) — ContentView only
// SEARCH-TOKEN: 20260202_224200_FeedNavFreezeV3

// CHANGE-ID: 20260202_211500_RemoteRowSpaceStability
// SCOPE: Prevent feed card reflow on return by reserving remote attachment lane height and caching attachment presence per postID.
// SEARCH-TOKEN: 20260202_211500_RemoteRowSpaceStability

// CHANGE-ID: 20260202_112500_BackPopFeedFlashFix
// SCOPE: Prevent feed row flash on returning from BackendSessionDetailView by suppressing immediate auto-fetch.
// SEARCH-TOKEN: 20260202_112500_BackPopFeedFlashFix

// CHANGE-ID: 20260202_093500_RemoteThumbPlaceholderStability
// SCOPE: Feed Thumbnail Hydration Stability — Remove icon-based placeholders for remote thumbs; render neutral placeholders while signed URLs/posters load.
// SEARCH-TOKEN: 20260202_090000_FeedStatsReactivity

// CHANGE-ID: 20260129_171107_14_3I_FilterParity
// SCOPE: Phase 14.3I — Connected feed filter parity: apply instrument/activity/search/saved filters to remote posts and align local instrument filter with userInstrumentLabel for parity; no UI/layout changes; no backend/schema changes.
// SEARCH-TOKEN: 20260129_171107_14_3I_FilterParity

// CHANGE-ID: 20260129_080500_14_3G_SessionRow_UseAppleViewerID
// SCOPE: Phase 14.3G — Connected-mode feed: SessionRow must use Apple (local) user ID for local-session ownership checks so owner rows never fall into non-owner "User" fallback (no UI/layout changes; backend posts unaffected).
// SEARCH-TOKEN: 20260129_080500_14_3G_SessionRow_UseAppleViewerID

// CHANGE-ID: 20260129_072500_14_3F_ReactiveDirectoryInRemoteRow
// SCOPE: Phase 14.3F — Fix connected feed owner row name staleness by making RemotePostRowTwin observe BackendFeedStore and resolve DirectoryAccount reactively (no UI/layout changes; no auth/backend behavior changes).
// SEARCH-TOKEN: 20260129_072500_14_3F_ReactiveDirectoryInRemoteRow

// CHANGE-ID: 20260128_195000_14_3D_OwnerFeedNamePrecedence
// SCOPE: Phase 14.3D — Connected feed owner row name precedence: Profile.name → directoryAccount.displayName → "You"; remove "User" owner fallback; no UI/layout, schema, or non-owner behavior changes.
// SEARCH-TOKEN: 20260128_195000_14_3D_OwnerFeedNamePrecedence


// CHANGE-ID: 20260127_224800_14_3C_SelfNameAndDeleteFix_Clean
// SCOPE: Phase 14.3C — Fix connected feed owner-name resolution (self shows Profile.name, not 'User') and propagate local session delete to backend post DELETE; no UI/layout or schema changes.
// SEARCH-TOKEN: 20260127_224800_14_3C_SelfNameAndDeleteFix_Clean


// CHANGE-ID: 20260128_190000_14_3B_BackendOwnerID
// SCOPE: Phase 14.3B — Connected-mode owner identity: never fall back to Apple ID for backend ownership; hydrate backendUserID from stored Supabase access token when possible; no UI/layout changes.
// SEARCH-TOKEN: 20260128_190000_14_3B_BackendOwnerID


// CHANGE-ID: 20260122_223700_14_2_1d_RemoteThumbSignedURL
// SCOPE: Phase 14.2.1 — RemoteAttachmentPreview: load signed URL thumbnails for remote image attachments (feed parity); fallback to icon; cache by bucket|path.
// SEARCH-TOKEN: 20260122_220200_14_2_1c_RemoteTitlesParity
// CHANGE-ID: 20260123_174900_FixD_RemoteThumbCache_NoFlicker
// SCOPE: Fix D — RemoteAttachmentPreview: cache decoded image/video poster by postID+bucket+path to prevent placeholder flashes and eliminate cross-row thumbnail bleed; no UI/layout changes.
// SEARCH-TOKEN: 20260123_174900_FixD_RemoteThumbCache_NoFlicker


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

// CHANGE-ID: 20260205_065749_LocParity_d2c43ded
// SCOPE: Identity data parity — use backend account_directory.location for non-owner identity rows and peeks; owner continues to use local ProfileStore.
// SEARCH-TOKEN: 20260205_065749_LocParity_d2c43ded

import SwiftUI
import CoreData
import Combine
import CryptoKit

// CHANGE-ID: 20260202_215800_BackPopFlashNoState
// SCOPE: Prevent feed flash on return from BackendSessionDetailView without mutating ContentView state during the pop transition (use a static gate timestamp).
// SEARCH-TOKEN: 20260202_215800_BackPopFlashNoState

fileprivate enum BackendDetailPopGate {
    static var lastPopAt: Date = .distantPast
}


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


    @StateObject private var sharedWithYouStore = SharedWithYouStore()
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
    @State private var isFeedNavFrozen: Bool = false
    @State private var frozenFeedItems: [FeedRowItem] = []
    @State private var feedNavFreezeTask: Task<Void, Never>? = nil
    @State private var remotePrewarmNonce: Int = 0

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
    @ObservedObject private var backendFeedStore: BackendFeedStore = BackendFeedStore.shared

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
                .onChange(of: statsRange) { _, _ in refreshStats() }
                .onReceive(
                    NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
                        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
                ) { note in
                    guard notificationTouchesSessions(note) else { return }
                    refreshStats()
                }
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
                            let dedupedRemotePosts: [BackendPost] = remotePostsRaw.filter { post in
                                guard let sid = post.sessionID else { return true }
                                return !localSessionIDs.contains(sid)
                            }

                            // Apply the same filter semantics to remote posts as local sessions.
                            let remotePosts: [BackendPost] = filteredRemotePosts(dedupedRemotePosts)

                            // Phase 14.x: prewarm feed thumbnails/posters for the first screenful of remote posts (writes into RemoteAttachmentPreview caches).
                            let remoteWarmToken: String = {
                                let head = remotePosts.prefix(12).map { $0.id.uuidString }.joined(separator: ",")
                                return "\(remotePosts.count)|\(remotePrewarmNonce)|\(head)"
                            }()

                            Color.clear
                                .frame(height: 0)
                                .task(id: remoteWarmToken) {
                                    await warmRemoteFeedPreviews(posts: remotePosts, viewerUserID: effectiveBackendUserID, limit: 10)
                                }

                            // Build unified row source (Local sessions + Remote posts)
                            let liveFeedItems: [FeedRowItem] = FeedRowItem.build(
                                local: localRows,
                                remote: remotePosts
                            )

                            let renderFeedItems: [FeedRowItem] = (isFeedNavFrozen && !frozenFeedItems.isEmpty) ? frozenFeedItems : liveFeedItems

                            if renderFeedItems.isEmpty {
                                Text("No sessions match your filters yet.")
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            } else {
                                ForEach(renderFeedItems) { item in
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
                                                .onTapGesture {
                                                feedNavFreezeTask?.cancel()
                                                isFeedNavFrozen = true
                                                frozenFeedItems = renderFeedItems
                                                pushSessionID = (session.value(forKey: "id") as? UUID)
                                            }
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
                                                        currentUserID: (effectiveBackendUserID ?? "")
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
                                                viewerUserID: effectiveBackendUserID
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                            feedNavFreezeTask?.cancel()
                                            isFeedNavFrozen = true
                                            frozenFeedItems = renderFeedItems
                                            pushRemotePostID = post.id
                                        }
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
                                        guard idx < renderFeedItems.count else { continue }
                                        if case .local(let s) = renderFeedItems[idx].kind,
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

                        // When returning from BSDV, suppress the immediate auto-fetch to avoid a one-frame list rebind/flash.
                        if Date().timeIntervalSince(BackendDetailPopGate.lastPopAt) < 0.75 {
                            return
                        }

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
                    await sharedWithYouStore.refreshUnreadShares()
                    await MainActor.run {
                        refreshStats()
                    }
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
                        if (!followStore.requests.isEmpty) || sharedWithYouStore.hasUnreadShares {
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


            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackendSessionDetailView.didPop"))) { _ in
                pushRemotePostID = nil
                BackendDetailPopGate.lastPopAt = Date()
                remotePrewarmNonce &+= 1
            }

            // Feed identity freeze across navigation transitions (covers interactive pop where ContentView is visible before didPop fires).
            .onChange(of: pushRemotePostID) { _, _ in
                feedNavFreezeTask?.cancel()
                if pushRemotePostID != nil || pushSessionID != nil {
                    isFeedNavFrozen = true
                } else {
                    feedNavFreezeTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000) // ~0.30s tail after pop
                        if pushRemotePostID == nil && pushSessionID == nil {
                            isFeedNavFrozen = false
                            frozenFeedItems.removeAll(keepingCapacity: true)
                        }
                    }
                }
            }
            .onChange(of: pushSessionID) { _, _ in
                feedNavFreezeTask?.cancel()
                if pushRemotePostID != nil || pushSessionID != nil {
                    isFeedNavFrozen = true
                } else {
                    feedNavFreezeTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000) // ~0.30s tail after pop
                        if pushRemotePostID == nil && pushSessionID == nil {
                            isFeedNavFrozen = false
                            frozenFeedItems.removeAll(keepingCapacity: true)
                        }
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
                await sharedWithYouStore.refreshUnreadShares()
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

            .onChange(of: scenePhase) { _, phase in
                // Phase 14.1: refresh incoming follow requests when returning to foreground (no polling)
                guard phase == .active else { return }
                Task { @MainActor in
                    await followStore.refreshFromBackendIfPossible()
                    await sharedWithYouStore.refreshUnreadShares()
                }
            }
            .appBackground()
        }
    }


    private func notificationTouchesSessions(_ note: Notification) -> Bool {
        guard let info = note.userInfo else { return false }

        func containsSession(in any: Any?) -> Bool {
            guard let set = any as? Set<NSManagedObject>, !set.isEmpty else { return false }
            return set.contains { $0.entity.name == "Session" }
        }

        return containsSession(in: info[NSInsertedObjectsKey])
            || containsSession(in: info[NSUpdatedObjectsKey])
            || containsSession(in: info[NSDeletedObjectsKey])
            || containsSession(in: info[NSRefreshedObjectsKey])
            || containsSession(in: info[NSInvalidatedObjectsKey])
            || containsSession(in: info[NSInvalidatedAllObjectsKey])
    }

    private func refreshStats() {
        // De-populate when signed out to mirror other data fields
        guard userID != nil else {
            stats = .init(count: 0, seconds: 0)
            return
        }
        do {
            guard let uid = effectiveUserID else {
            stats = .init(count: 0, seconds: 0)
            return
        }
        stats = try StatsHelper.fetchStats(in: viewContext, range: statsRange, ownerUserID: uid)
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
            let targetName = (inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let targetNorm = targetName.lowercased()

            out = out.filter { s in
                // Primary: exact core instrument relationship match (existing behavior)
                if s.instrument?.objectID == id { return true }

                // Parity: also match on userInstrumentLabel so local sessions saved/published by label
                // are filter-consistent with remote posts (which only carry instrument_label).
                let label = ((s.value(forKey: "userInstrumentLabel") as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return !targetNorm.isEmpty && label == targetNorm
            }
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


    // MARK: - Remote filtering (connected feed parity)

    private func normalize(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func remoteMatchesSelectedInstrument(_ post: BackendPost) -> Bool {
        guard let inst = selectedInstrument else { return true }
        let target = normalize(inst.name)
        guard !target.isEmpty else { return true }
        return normalize(post.instrumentLabel) == target
    }

    private func remoteMatchesSelectedActivity(_ post: BackendPost) -> Bool {
        switch selectedActivity {
        case .any:
            return true

        case .core(let act):
            // Remote posts may carry either activity_label or activity_type (or neither).
            let candidates: [String] = [
                normalize(post.activityLabel),
                normalize(post.activityType),
                normalize(post.activityDetail)
            ]

            let label = normalize(act.label)
            let raw = String(act.rawValue).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let caseName = String(describing: act).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            return candidates.contains(where: { c in
                guard !c.isEmpty else { return false }
                return c == label || c == raw || c == caseName
            })

        case .custom(let name):
            let target = normalize(name)
            guard !target.isEmpty else { return true }
            let candidates: [String] = [
                normalize(post.activityLabel),
                normalize(post.activityType),
                normalize(post.activityDetail)
            ]
            return candidates.contains(where: { $0 == target })
        }
    }

    private func remoteMatchesSavedOnly(_ post: BackendPost) -> Bool {
        guard savedOnly else { return true }
        guard let vid = effectiveBackendUserID else { return false }
        return FeedInteractionStore.isSaved(post.id, viewerUserID: vid)
    }

    private func remoteMatchesSearch(_ post: BackendPost) -> Bool {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }

        // BackendPost does not currently decode "title". Search is therefore based on
        // activity fields, instrument label, and notes (if present).
        let haystacks: [String] = [
            post.activityLabel ?? "",
            post.activityType ?? "",
            post.activityDetail ?? "",
            post.instrumentLabel ?? "",
            post.notes ?? ""
        ]
        return haystacks.contains(where: { $0.localizedCaseInsensitiveContains(q) })
    }

    private func filteredRemotePosts(_ posts: [BackendPost]) -> [BackendPost] {
        // Ensure no data is shown when signed out
        guard userID != nil else { return [] }

        return posts.filter { post in
            remoteMatchesSelectedInstrument(post) &&
            remoteMatchesSelectedActivity(post) &&
            remoteMatchesSavedOnly(post) &&
            remoteMatchesSearch(post)
        }
    }


    // MARK: - Remote feed preview prewarm

    private func warmRemoteFeedPreviews(posts: [BackendPost], viewerUserID: String?, limit: Int = 10) async {
        guard !posts.isEmpty else { return }

        let currentUserID = viewerUserID ?? ""

        for post in posts.prefix(limit) {
            let model = BackendSessionViewModel(post: post, currentUserID: currentUserID)
            let refs = model.attachmentRefs

            // Match RemotePostRowTwin.favAndExtraCount: prefer image > video > other (but we only prewarm image/video).
            guard let fav = (refs.first(where: { $0.kind == .image })
                ?? refs.first(where: { $0.kind == .video })) else {
                continue
            }

            let key = "feedThumb|\(post.id.uuidString)|\(fav.bucket)|\(fav.path)"

            let signedURL: URL
            if let cached = RemoteSignedURLCache.shared.get(key) {
                signedURL = cached
            } else {
                let result = await NetworkManager.shared.createSignedStorageObjectURL(
                    bucket: fav.bucket,
                    path: fav.path,
                    expiresInSeconds: 300
                )
                switch result {
                case .success(let url):
                    RemoteSignedURLCache.shared.set(key, url: url, ttlSeconds: 300)
                    signedURL = url
                case .failure:
                    continue
                }
            }

            switch fav.kind {
            case .image:
                #if canImport(UIKit)
                if RemotePreviewCache.imageThumbCache.object(forKey: key as NSString) != nil { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: signedURL)
                    if let ui = UIImage(data: data) {
                        RemotePreviewCache.imageThumbCache.setObject(ui, forKey: key as NSString)
                    }
                } catch {
                    // ignore
                }
                #endif

            case .video:
                #if canImport(UIKit)
                if RemotePreviewCache.videoPosterCache.object(forKey: key as NSString) != nil { continue }
                let poster = await Task.detached(priority: .utility) {
                    AttachmentStore.generateVideoPoster(url: signedURL)
                }.value
                if let poster {
                    RemotePreviewCache.videoPosterCache.setObject(poster, forKey: key as NSString)
                }
                #endif

            default:
                continue
            }
        }
    }

    // MARK: - Delete

    private func deleteSessions(at offsets: IndexSet) {
        // Keep List's onDelete handler synchronous; do async backend delete + Core Data work on MainActor.
        Task { @MainActor in
            await deleteSessionsWithBackendIfNeeded(at: offsets)
        }
    }

    @MainActor
    private func deleteSessionsWithBackendIfNeeded(at offsets: IndexSet) async {
        let rows = filteredSessions
        do {
            for idx in offsets {
                guard idx < rows.count else { continue }
                let session = rows[idx]

                // Connected mode: delete matching backend post first (post id == session.id UUID).
                if useBackendFeed, let postID = session.value(forKey: "id") as? UUID {
                    _ = await BackendEnvironment.shared.publish.deletePost(postID)
                }

                // Gather attachment file paths for this session and delete from disk before deleting Core Data objects.
                let attachments = (session.attachments as? Set<Attachment>) ?? []
                let paths: [String] = attachments.compactMap { att in
                    if let s = att.value(forKey: "fileURL") as? String, !s.isEmpty { return s }
                    return nil
                }
                if !paths.isEmpty {
                    AttachmentStore.deleteAttachmentFiles(atPaths: paths)
                }

                viewContext.delete(session)
            }

            try viewContext.save()

            // Refresh backend feed after deletions so remote rows don't rehydrate.
            if useBackendFeed {
                let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
                _ = await BackendEnvironment.shared.publish.fetchFeed(scope: scopeKey)
            }
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
    @State private var isShareSheetPresented: Bool = false
    @State private var isSharing: Bool = false
    @State private var errorLine: String? = nil

    #if canImport(UIKit)
    @State private var remoteAvatar: UIImage? = nil
    #endif
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

        // Local sessions are keyed by the Apple (local) user ID, not the Supabase UUID.
        // Using backendUserID here causes SessionRow to treat the owner as a non-owner in connected mode.
        if let authID = auth.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authID.isEmpty {
            return authID
        }

        // Fallback (mirrors legacy behavior when AuthManager hasn't populated currentUserID yet)
        return PersistenceController.shared.currentUserID
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

                        let loc: String = {
                            if viewerIsOwner {
                                return ProfileStore.location(for: ownerIDNonEmpty)
                            }
                            if let acct = BackendFeedStore.shared.directoryAccountsByUserID[ownerIDNonEmpty],
                               let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            let lower = ownerIDNonEmpty.lowercased()
                            if let acct = BackendFeedStore.shared.directoryAccountsByUserID[lower],
                               let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            return ""
                        }()

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

            let acct = BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek]
                    ?? BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek.lowercased()]

            ProfilePeekView(
                ownerID: ownerForPeek,
                directoryDisplayName: acct?.displayName,
                directoryAccountID: acct?.accountID,
                directoryLocation: acct?.location,
                directoryAvatarKey: acct?.avatarKey,
                directoryInstruments: acct?.instruments
            )
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
                Button(action: {
                    isShareSheetPresented = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
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
        .sheet(isPresented: $isShareSheetPresented) {
            ShareToFollowerSheet(postID: sessionID, isPresented: $isShareSheetPresented)
        }
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

// Phase 14.2.1 — Remote post row that is a visual twin

// Remote row layout stability: cache whether a post has attachments (and its chosen "fav" ref).
// This prevents a transient empty attachmentRefs render from collapsing the thumbnail lane and then re-expanding it.
fileprivate final class RemotePostAttachmentMetaCache {
    struct Meta {
        let fav: BackendSessionViewModel.BackendAttachmentRef?
        let extraCount: Int
        let hasAny: Bool
    }

    static let shared = RemotePostAttachmentMetaCache()

    private let lock = NSLock()
    private var map: [UUID: Meta] = [:]

    func get(_ postID: UUID) -> Meta? {
        lock.lock(); defer { lock.unlock() }
        return map[postID]
    }

    func set(_ postID: UUID, _ meta: Meta) {
        lock.lock(); defer { lock.unlock() }
        map[postID] = meta
    }
}


// Mirror of SessionRow (read-only)


fileprivate struct ShareToFollowerSheet: View {
    let postID: UUID
    @Binding var isPresented: Bool

    @State private var isSharing: Bool = false
    @State private var errorLine: String? = nil

    private var followersSorted: [String] {
        Array(FollowStore.shared.followers).sorted()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if let errorLine {
                    Text(errorLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }

                if followersSorted.isEmpty {
                    VStack(spacing: 8) {
                        Text("No approved followers yet.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .padding(.top, 24)
                    Spacer()
                } else {
                    List {
                        ForEach(followersSorted, id: \.self) { followerID in
                            Button {
                                guard !isSharing else { return }
                                errorLine = nil
                                isSharing = true

                                Task {
                                    let result = await BackendEnvironment.shared.shares.sharePost(
                                        postID: postID,
                                        to: followerID
                                    )

                                    switch result {
                                    case .success(let outcome):
                                        switch outcome {
                                        case .shared:
                                            isPresented = false
                                        case .alreadyShared:
                                            errorLine = "Already shared."
                                            isSharing = false
                                        }
                                    case .failure:
                                        errorLine = "Couldn’t share right now."
                                        isSharing = false
                                    }
                                }
                            } label: {
                                Text(followerID)
                            }
                            .disabled(isSharing)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Share to")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

fileprivate struct RemotePostRowTwin: View {
    let post: BackendPost
    let scope: FeedScope
    let viewerUserID: String?

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var backendFeedStore: BackendFeedStore = BackendFeedStore.shared

    @State private var showPeek: Bool = false
    @State private var isSavedLocal: Bool = false

    private func favAndExtraCount(from refs: [BackendSessionViewModel.BackendAttachmentRef]) -> (BackendSessionViewModel.BackendAttachmentRef?, Int) {
        guard !refs.isEmpty else { return (nil, 0) }
        // Prefer image > video > audio (to match the calmest visual footprint in the feed).
        let fav = refs.first(where: { $0.kind == .image })
            ?? refs.first(where: { $0.kind == .video })
            ?? refs.first
        return (fav, max(0, refs.count - 1))
    }

    private var cachedAttachmentMeta: RemotePostAttachmentMetaCache.Meta? {
        RemotePostAttachmentMetaCache.shared.get(post.id)
    }

    private var effectiveHasAttachments: Bool {
        // Cache-first: if we've ever seen attachments for this post in this session, keep the lane reserved.
        if let cached = cachedAttachmentMeta, cached.hasAny { return true }
        return !model.attachmentRefs.isEmpty
    }

    private var effectiveFavAttachmentRef: BackendSessionViewModel.BackendAttachmentRef? {
        if !model.attachmentRefs.isEmpty {
            return favAndExtraCount(from: model.attachmentRefs).0
        }
        return cachedAttachmentMeta?.fav
    }

    private var effectiveExtraAttachmentCount: Int {
        if !model.attachmentRefs.isEmpty {
            return favAndExtraCount(from: model.attachmentRefs).1
        }
        return cachedAttachmentMeta?.extraCount ?? 0
    }

    private func updateAttachmentMetaCacheIfNeeded() {
        let refs = model.attachmentRefs
        guard !refs.isEmpty else { return }
        let (fav, extra) = favAndExtraCount(from: refs)
        RemotePostAttachmentMetaCache.shared.set(post.id, .init(fav: fav, extraCount: extra, hasAny: true))
    }

    @ViewBuilder
    private func attachmentLanePlaceholder() -> some View {
        // Reserve the exact same footprint as RemoteAttachmentPreview for non-audio thumbs.
        let size: CGFloat = FEED_IMAGE_VIDEO_THUMB
        RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.06), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }


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

    private var resolvedDirectoryAccount: DirectoryAccount? {
        // Resolve reactively from BackendFeedStore so the row updates when directory hydration completes.
        if let ownerRaw = post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ownerRaw.isEmpty {
            if let exact = backendFeedStore.directoryAccountsByUserID[ownerRaw] { return exact }
            let lower = ownerRaw.lowercased()
            if let byLower = backendFeedStore.directoryAccountsByUserID[lower] { return byLower }
        }
        return nil
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
                            DirectoryAvatarCircle(
                                ownerID: owner,
                                displayName: (resolvedDirectoryAccount?.displayName ?? (viewerIsOwner ? "You" : "User")),
                                directoryAvatarKey: (viewerIsOwner ? nil : resolvedDirectoryAccount?.avatarKey)
                            )
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // Name and optional location on one line
                        let realName: String = {
                            if viewerIsOwner {
                                // Owner precedence:
                                // 1) Local Profile.name (Core Data)
                                // 2) resolvedDirectoryAccount.displayName
                                // 3) "You"
                                let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                req.fetchLimit = 1
                                if let p = try? ctx.fetch(req).first,
                                   let nRaw = p.name {
                                    let n = nRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !n.isEmpty { return n }
                                }

                                if let acct = resolvedDirectoryAccount {
                                    let dn = acct.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !dn.isEmpty { return dn }
                                }

                                return "You"
                            }

                            if let acct = resolvedDirectoryAccount {
                                let dn = acct.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !dn.isEmpty { return dn }
                            }

                            return "User"
                        }()
                        let loc: String = {
                            if viewerIsOwner {
                                return ProfileStore.location(for: owner)
                            }
                            if let acct = backendFeedStore.directoryAccountsByUserID[owner],
                               let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            let lower = owner.lowercased()
                            if let acct = backendFeedStore.directoryAccountsByUserID[lower],
                               let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            return ""
                        }()


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
                if effectiveHasAttachments {
                    HStack(alignment: .center, spacing: 8) {
                        if let fav = effectiveFavAttachmentRef {
                            RemoteAttachmentPreview(ref: fav, postID: post.id)
                        } else {
                            attachmentLanePlaceholder()
                        }
                        Spacer()
                    }
                    .padding(.top, 2)

                    interactionRow(postID: post.id, attachmentCount: effectiveExtraAttachmentCount)
                        .padding(.top, 6)
                } else {
                    interactionRow(postID: post.id, attachmentCount: effectiveExtraAttachmentCount)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, effectiveHasAttachments ? 10 : 6)
.onAppear {
            updateAttachmentMetaCacheIfNeeded()
            // Keep initial saved state in sync for this viewer + post.
            let vid = (viewerUserID ?? "unknown")
            isSavedLocal = FeedInteractionStore.isSaved(post.id, viewerUserID: vid)
        }
        .onChange(of: model.attachmentRefs.count) { _, _ in
            updateAttachmentMetaCacheIfNeeded()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("row.openDetail")
        .sheet(isPresented: $showPeek) {
            let viewer = viewerUserID ?? ""
            let owner = post.ownerUserID ?? ""
            // Invariant: self-peek must never render follow gating in any mode.
            let ownerForPeek = (owner.isEmpty || owner == viewer) ? (viewer.isEmpty ? owner : viewer) : owner

            // CHANGE-ID: 20260211_142500_ContentView_PPV_RemotePeek_InjectDirectoryIdentity
            // SCOPE: Feed remote row ProfilePeekView must receive directory identity (name/location/avatar/instruments) to avoid "User •" fallback; no UI/layout changes.
            let acct = BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek]
                    ?? BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek.lowercased()]

            ProfilePeekView(
                ownerID: ownerForPeek,
                directoryDisplayName: acct?.displayName,
                directoryAccountID: acct?.accountID,
                directoryLocation: acct?.location,
                directoryAvatarKey: acct?.avatarKey,
                directoryInstruments: acct?.instruments
            )
                .environment(\.managedObjectContext, ctx)
                .environmentObject(auth)
        }
    }


// CHANGE-ID: 20260210_181900_Phase15_Step2_AvatarRenderCache
// SCOPE: Phase 15 Step 2 — helper view for rendering directory avatars with shared caches (feed + other non-owner identity surfaces).
// SEARCH-TOKEN: 20260210_181900_Phase15_Step2_AvatarRenderCache_DIR_AVATAR_VIEW
#if canImport(UIKit)
private struct DirectoryAvatarCircle: View {
    let ownerID: String
    let displayName: String
    let directoryAvatarKey: String?

    @State private var remoteAvatar: UIImage? = nil

    var body: some View {
        let key = directoryAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cacheKey = "avatars|\(key)"

        return Group {
            if let img = ProfileStore.avatarImage(for: ownerID) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if !key.isEmpty, let cached = RemoteAvatarImageCache.get(cacheKey) {
                Image(uiImage: cached).resizable().scaledToFill()
            } else if !key.isEmpty, let remoteAvatar {
                Image(uiImage: remoteAvatar).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2))
                    Text(initials(from: displayName))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .task(id: key) {
            guard !key.isEmpty else {
                remoteAvatar = nil
                return
            }
            if RemoteAvatarImageCache.get(cacheKey) != nil { return }
            if let ui = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: key) {
                remoteAvatar = ui
            }
        }
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
        let combo = (first + last)
        return combo.isEmpty ? "U" : combo
    }
}
#endif

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
        let expiresAt: Date
    }

    private var map: [String: Entry] = [:]
    private let lock = NSLock()

    /// Returns a cached URL only if it is still valid (not expired).
    func get(_ key: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = map[key] else { return nil }
        if Date() >= entry.expiresAt {
            map.removeValue(forKey: key)
            return nil
        }
        return entry.url
    }

    /// Stores a URL with an explicit TTL (seconds).
    func set(_ key: String, url: URL, ttlSeconds: Int) {
        lock.lock(); defer { lock.unlock() }
        map[key] = Entry(url: url, expiresAt: Date().addingTimeInterval(TimeInterval(ttlSeconds)))
    }
}

fileprivate enum RemotePreviewCache {
    #if canImport(UIKit)
    static let imageThumbCache = NSCache<NSString, UIImage>()
    static let videoPosterCache = NSCache<NSString, UIImage>()
    #endif
}
struct RemoteAttachmentPreview: View {
    // FIX-D: persistent in-memory thumbnail cache (keyed by postID + bucket + path)
    // Goal: prevent placeholder flashes and eliminate any chance of cross-row/cross-owner thumbnail reuse.
    #if canImport(UIKit)
    // Shared caches (also written by feed prewarmer)
    // See RemotePreviewCache.
    #endif

    let ref: BackendSessionViewModel.BackendAttachmentRef
    let postID: UUID

    @State private var signedURL: URL? = nil
    #if canImport(UIKit)
    @State private var resolvedImage: UIImage? = nil
    @State private var videoPoster: UIImage? = nil
    #endif

    private var cacheKey: String {
        "feedThumb|" + postID.uuidString + "|" + ref.bucket + "|" + ref.path
    }

    var body: some View {
        let kind = ref.kind
        let isAudio = (kind == .audio)
        let size: CGFloat = isAudio ? FEED_AUDIO_THUMB : FEED_IMAGE_VIDEO_THUMB

        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            // IMAGE
            if kind == .image {
                #if canImport(UIKit)
                if let ui = resolvedImage ?? RemotePreviewCache.imageThumbCache.object(forKey: cacheKey as NSString) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    neutralPlaceholder(kind: kind)
                }
                #else
                neutralPlaceholder(kind: kind)
                #endif
            }

            // VIDEO
            else if kind == .video {
                #if canImport(UIKit)
                if let poster = videoPoster ?? RemotePreviewCache.videoPosterCache.object(forKey: cacheKey as NSString) {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    neutralPlaceholder(kind: kind)
                }
                #else
                neutralPlaceholder(kind: kind)
                #endif

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }

            // AUDIO / PDF / OTHER
            else {
                placeholderIcon(kind: kind)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
                .stroke(.black.opacity(0.05), lineWidth: 1)
        )
        .accessibilityLabel("Attachment preview")
        .accessibilityIdentifier("row.attachmentPreview")
        .onChange(of: cacheKey) { _, _ in
            // Defensive reset: if SwiftUI reuses the view instance across rows, never show stale media.
            signedURL = nil
            #if canImport(UIKit)
            resolvedImage = nil
            videoPoster = nil
            #endif
        }
        .task(id: cacheKey) {
            await loadSignedURLIfNeeded()
            #if canImport(UIKit)
            await loadImageThumbIfNeeded()
            await loadVideoPosterIfNeeded()
            #endif
        }
    }

    @ViewBuilder
    private func neutralPlaceholder(kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> some View {
        // Neutral, quiet placeholder: background is already rendered by the base RoundedRectangle.
        // We intentionally avoid system glyphs here to prevent a “broken icon → real thumbnail” swap on first hydration.
        EmptyView()
    }

    @ViewBuilder
    private func placeholderIcon(kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> some View {
        // For non-thumbnail-able types (audio/pdf/other), an icon is stable and not a hydration artifact.
        Image(systemName: iconName(for: kind))
            .imageScale(.large)
            .foregroundStyle(Theme.Colors.secondaryText)
    }

    private func loadSignedURLIfNeeded() async {
        guard (ref.kind == .image) || (ref.kind == .video) else { return }

        // Keep the signed URL cached separately (short TTL) so we don't hammer RPCs.
        if let cached = RemoteSignedURLCache.shared.get(cacheKey) {
            if signedURL != cached { signedURL = cached }
            return
        }

        let ttlSeconds = 300

        let result = await NetworkManager.shared.createSignedStorageObjectURL(
            bucket: ref.bucket,
            path: ref.path,
            expiresInSeconds: ttlSeconds
        )

        guard case .success(let url) = result else { return }
        RemoteSignedURLCache.shared.set(cacheKey, url: url, ttlSeconds: ttlSeconds)

        if signedURL != url { signedURL = url }
    }

    #if canImport(UIKit)
    private func loadImageThumbIfNeeded() async {
        guard ref.kind == .image else { return }

        // 1) Prefer immediate in-memory cache.
        if let cached = RemotePreviewCache.imageThumbCache.object(forKey: cacheKey as NSString) {
            if resolvedImage !== cached { resolvedImage = cached }
            return
        }

        // 2) Need a signed URL to fetch bytes.
        guard let url = signedURL else { return }

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            guard let ui = UIImage(data: data) else { return }

            RemotePreviewCache.imageThumbCache.setObject(ui, forKey: cacheKey as NSString)
            if resolvedImage !== ui { resolvedImage = ui }
        } catch {
            // Ignore transient failures — placeholder remains; next navigation/refresh will retry.
        }
    }

    private func loadVideoPosterIfNeeded() async {
        guard ref.kind == .video else { return }

        // 1) Prefer immediate in-memory cache.
        if let cached = RemotePreviewCache.videoPosterCache.object(forKey: cacheKey as NSString) {
            if videoPoster !== cached { videoPoster = cached }
            return
        }

        // 2) Need a signed URL to generate the poster.
        guard let url = signedURL else { return }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    if let img {
                        RemotePreviewCache.videoPosterCache.setObject(img, forKey: cacheKey as NSString)
                        self.videoPoster = img
                    }
                    continuation.resume()
                }
            }
        }
    }
    #endif

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
