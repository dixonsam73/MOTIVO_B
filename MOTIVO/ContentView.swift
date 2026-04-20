// CHANGE-ID: 20260407_214600_ContentView_FeedEmptyState_CachedHydrationGate_c91d
// SCOPE: ContentView only — keep Feed empty-state copy deferred while Feed hydrates, but treat already-cached visible Feed content as ready when returning from Journal. Preserve feed composition, filtering, ordering, Journal behavior, and empty-state copy.
// SEARCH-TOKEN: 20260407_214600_ContentView_FeedEmptyState_CachedHydrationGate_c91d

// CHANGE-ID: 20260405_201900_ContentView_FilterMicroContrastPass_6d3e
// SCOPE: ContentView filter-card visual-only micro pass — slightly strengthen search-field contrast, raise light-mode divider visibility, tighten expanded-row rhythm, and make the filter control surface fractionally flatter while preserving all filter logic, layout structure, navigation, and backend behavior.
// SEARCH-TOKEN: 20260405_201900_ContentView_FilterMicroContrastPass_6d3e

// CHANGE-ID: 20260330_194600_ContentView_FinalFilterPolishKeyboardDismiss_42bf
// SCOPE: Final filter micro-polish plus outside-tap keyboard dismissal for the search field; preserve layout structure, filter logic, state, navigation, and backend behavior.
// SEARCH-TOKEN: 20260330_194600_ContentView_FinalFilterPolishKeyboardDismiss_42bf

// CHANGE-ID: 20260330_190800_ContentView_FilterCardFeedParity_3f7c
// SCOPE: Week-mode filter card visual parity pass — restyle the filter container and expanded rows to match feed card rhythm, soften the search field, and preserve all filter logic/state/navigation/backend behavior.
// SEARCH-TOKEN: 20260330_190800_ContentView_FilterCardFeedParity_3f7c

// CHANGE-ID: 20260325_223000_ContentView_YearCalendarSpacingMicroPass_8d2a
// SCOPE: Phase 2B Year journal correction pass — refine Year-only month-aggregate row rendering to borrow Month’s existing bar/spacing language more directly, with tighter compression and clearer bar visibility. Preserve Week, Month, Feed, filters, routing, Theme, and aggregation behavior unchanged.
// SEARCH-TOKEN: 20260325_214500_ContentView_YearCalendarOverviewCompaction_a9d1

// CHANGE-ID: 20260324_145100_ContentView_RootRouteRecordButton_6ab4
// SCOPE: ContentView only — preserve the existing top-right record button visually, replace dismiss-based timer return with root-route switching, and leave all feed/journal/people/debug/filter behavior unchanged. No other UI or logic changes.
// SEARCH-TOKEN: 20260324_145100_ContentView_RootRouteRecordButton_6ab4

// CHANGE-ID: 20260323_155800_ContentView_JournalArchiveCorrectionDensityScaling_1B1_c8d4
// SCOPE: Phase 2B micro-pass — Year journal mode only. Tighten first-row/top spacing and inter-row vertical rhythm so all 12 months fit more cleanly while preserving the existing Year bars, aggregation, and hidden Year filter behavior. Week/Month/Feed/routing/search/backend/schema/Theme unchanged.
// SEARCH-TOKEN: 20260325_223000_ContentView_YearCalendarSpacingMicroPass_8d2a
// CHANGE-ID: 20260323_153900_ContentView_JournalTimeLensPhase1A_b61e
// SCOPE: Journal mode only — add Week/Month/Year time-lens control, period summary label + total, and time-windowed owner dataset switching while preserving Feed summary, MeView button, current Journal Week rendering, and existing filter semantics. No backend/model/storage/sync changes.
// SEARCH-TOKEN: 20260323_153900_ContentView_JournalTimeLensPhase1A_b61e
// CHANGE-ID: 20260323_151500_ContentView_FeedJournalAlignmentPass_f4c2
// SCOPE: Final Feed + Journal alignment pass in ContentView only — journal scroll-to-top anchors to first header, feed top spacing aligned, journal thread pill matches feed, feed cards slightly lightened, feed identity block tightened, attachment badge unified, and edge alignment preserved. No data/filter/backend/navigation changes.
// SEARCH-TOKEN: 20260323_151500_ContentView_FeedJournalAlignmentPass_f4c2
// CHANGE-ID: 20260323_093800_ContentView_JournalFinalRefine_a91d
// SCOPE: Journal mode only — remove grouped outer section container feel, render quieter ambient week headers on canvas, and increase section/card breathing room. Feed/All, card styling, logic, filters, navigation, and remote rows unchanged.
// SEARCH-TOKEN: 20260323_093800_ContentView_JournalFinalRefine_a91d
// CHANGE-ID: 20260323_084700_ContentView_JournalModeRefine_b7d2
// SCOPE: Journal mode only — final visual refinement pass for grouped owner feed: anchor headers closer to first card, enforce single-line metadata truncation, separate metadata and notes, soften attachment indicator, and normalize card vertical rhythm. Feed/All, remote rows, filters, navigation, and behavior unchanged.
// SEARCH-TOKEN: 20260323_084700_ContentView_JournalModeRefine_b7d2
// CHANGE-ID: 20260322_121500_ContentView_FeedScopeLabelsAndDefault_3e7b
// SCOPE: Rename feed scope labels All→Feed and Mine→Journal, reorder segmented control to Journal then Feed, and default ContentView scope to Journal. No other UI or logic changes.
// SEARCH-TOKEN: 20260322_121500_ContentView_FeedScopeLabelsAndDefault_3e7b
// CHANGE-ID: 20260310_111500_OnboardingGateReactivity_7c4d
// SCOPE: Restore AppSetUp presentation reactivity for true new accounts and incomplete local profiles while preserving second-device backend bootstrap hardening. No other UI or logic changes.
// SEARCH-TOKEN: 20260310_111500_OnboardingGateReactivity_7c4d
// CHANGE-ID: 20260309_144500_ContentViewOwnerStatsFallback_5f2a
// SEARCH-TOKEN: 20260309_144500_ContentViewOwnerStatsFallback_5f2a
// CHANGE-ID: 20260304_210000_FeedPivot_ThreadPillTap_2f6b
// SCOPE: ContentView SessionRow thread pill: tap filters feed to that thread and expands filter panel (visual/control only; no filter logic changes)
// SEARCH-TOKEN: 20260304_210000_FeedPivot_ThreadPillTap_2f6b

// CHANGE-ID: 20260304_202700_ThreadMetaPill_1c9e
// SCOPE: Session row metadata: render thread label as subtle pill using segmented-style fill (visual-only)
// SEARCH-TOKEN: 20260304_202700_ThreadMetaPill_1c9e

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260304_164700_FeedFilter_ThreadParityMenu_5b40
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260203_093500_FeedThumbPrewarmFix
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260202_224200_FeedNavFreezeV3

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260202_211500_RemoteRowSpaceStability

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260202_112500_BackPopFeedFlashFix

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260202_090000_FeedStatsReactivity

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260129_171107_14_3I_FilterParity

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260129_080500_14_3G_SessionRow_UseAppleViewerID

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260129_072500_14_3F_ReactiveDirectoryInRemoteRow

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260128_195000_14_3D_OwnerFeedNamePrecedence


// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260127_224800_14_3C_SelfNameAndDeleteFix_Clean


// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260128_190000_14_3B_BackendOwnerID


// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260122_220200_14_2_1c_RemoteTitlesParity
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260123_174900_FixD_RemoteThumbCache_NoFlicker


// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260122_203207_14_2_1_ContentViewConnectedFeedParity
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260122_190500_HeadlessConnectedRevert
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260122_090100_Phase141_RequestBadge_RefreshTriggers

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260121_115517_P13D2_ContentView

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260114_092641_Step9D2_CommentsGate

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// UNIQUE-TOKEN: 20260112_131015_contentview_backend_id

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// UNIQUE-TOKEN: 20260112_133000_9A_fix_backendUserID_redecl

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// UNIQUE-TOKEN: 20260111_135903_feed_filter_visual_pass3
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// UNIQUE-TOKEN: v710H-TopButtonsSafeInset-20251030-1205
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
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
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// UNIQUE-TOKEN: 20260111_132050_feed_filter_visual_overhaul
// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260121_203420_Phase141_ContentView_FollowBadgeReactive_OwnerPeekFix

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260122_113000_Phase142_ContentViewGuardrails

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260205_065749_LocParity_d2c43ded

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260304_114800_Threads_S5_ContentView_ThreadFilter

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260304_124300_Threads_S6_ContentView_ThreadOptionsAndRowMeta

// CHANGE-ID: 20260319_103400_ContentView_WeeklyPulseTimeOnly_Refined_4d2e
// SCOPE: Refine the weekly pulse card to a softer visual treatment with time-only display and more breathing room for the muted streak line. No other UI or logic changes.
// SEARCH-TOKEN: 20260319_073600_ContentView_WeeklyPulseCard_6f3c

// CHANGE-ID: 20260319_111600_ContentView_RecordOnlyToolbar_8a1d
// CHANGE-ID: 20260323_161800_ContentView_SummaryHeightNormalization_6b2c
// SCOPE: Normalize the top summary card outer height across Journal and Feed so the permanent mode selector remains visually anchored during mode switches. No logic, filter, navigation, or content rendering changes.
// SEARCH-TOKEN: 20260323_161800_ContentView_SummaryHeightNormalization_6b2c
// CHANGE-ID: 20260323_160900_ContentView_ModeSelectorHierarchyCorrection_4a7f
// SCOPE: Reposition the Journal/Feed mode selector out of the Feed Filter card and place it directly below the summary card as a permanent primary mode switch. No filter logic, Feed/Journal behavior, navigation, or other UI changes.
// SEARCH-TOKEN: 20260323_160900_ContentView_ModeSelectorHierarchyCorrection_4a7f
// CHANGE-ID: 20260323_162900_ContentView_ModeSelectorSoftening_5d1a
// SCOPE: Soften the permanent Journal/Feed mode selector styling and tighten its spacing to the summary card without changing selector logic, layout structure, filters, or behavior.
// SEARCH-TOKEN: 20260323_162900_ContentView_ModeSelectorSoftening_5d1a
import SwiftUI


#if canImport(UIKit)
private enum ContentViewKeyboardDismiss {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif


#if DEBUG
private struct TopToolbarPeopleFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct TopToolbarTimerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
#endif
import CoreData
import Combine
import CryptoKit

// CHANGE-ID: 20260317_150900_FeedTopTapGapOnly_a1d7
// SCOPE: Use the existing gap between Feed Filter and feed card as the tap target for animated scroll-to-top; no visual or list-structure changes.
// SEARCH-TOKEN: 20260317_150900_FeedTopTapGapOnly_a1d7

// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260202_215800_BackPopFlashNoState

fileprivate enum BackendDetailPopGate {
    static var lastPopAt: Date = .distantPast
}


private let FEED_IMAGE_VIDEO_THUMB: CGFloat = 88
private let FEED_AUDIO_THUMB: CGFloat = 56
private let FEED_THUMB_CORNER: CGFloat = 10

private enum FeedJournalAlignmentUI {
    static let firstContentTopGap: CGFloat = 6
    static let attachmentBadgeIconOpacity: CGFloat = 0.68
    static let attachmentBadgeTextOpacity: CGFloat = 0.72
    static let attachmentBadgeStrokeOpacity: CGFloat = 0.10
}

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
    case mine = "Journal"
    case all = "Feed"
    var id: String { rawValue }
}

fileprivate enum JournalTimeLens: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
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
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appRoute: AppRouteStore

    @State private var showPublishSkipOversizeAlert = false
    @State private var publishSkipOversizeMessage = ""

    // Phase 14.1: make follow requests reactive in this view (badge)
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var ensembleStore = EnsembleStore.shared


    @ObservedObject private var unreadCommentsStore = UnreadCommentsStore.shared

    @StateObject private var sharedWithYouStore = SharedWithYouStore()
    let userID: String?
    let backendUserID: String?

    @State private var filtersExpanded = false
    @AppStorage("BackendModeChangeTick_v1") private var backendModeChangeTick: Int = 0
    @State private var selectedInstrument: Instrument? = nil
    @State private var selectedActivity: ActivityFilter = .any
    @State private var selectedThread: String? = nil
    @State private var activeUserFilterUserID: String? = nil
    @State private var selectedEnsembleID: String? = nil
    @State private var selectedScope: FeedScope = .mine
    @State private var selectedJournalLens: JournalTimeLens = .week
    @State private var searchText: String = ""
    @AppStorage("feedSavedOnly_v1") private var savedOnly: Bool = false
    @State private var debouncedQuery: String = ""
    @State private var pushSessionID: UUID? = nil
    @State private var pushRemotePostID: UUID? = nil
    @State private var isFeedNavFrozen: Bool = false
    @State private var frozenFeedItems: [FeedRowItem] = []
    @State private var feedNavFreezeTask: Task<Void, Never>? = nil
    @State private var remotePrewarmNonce: Int = 0
    @State private var pendingJournalMonthTargetMonthStart: Date? = nil
    
    @State private var stats: SessionStats = .init(count: 0, seconds: 0)
    @State private var backendOwnerStatsSnapshot: BackendStatsSnapshot? = nil
    @State private var backendStatsLoading: Bool = false

    // Sheets
    @State private var showProfile = false
        @State private var showAdd = false
    @State private var showPeople = false

    #if canImport(UIKit)
    @State private var toolbarRemoteAvatar: UIImage? = nil
    #endif

    #if DEBUG
    @State private var isDebugPresented: Bool = false
    @State private var _debugJSONBuffer: String = "{}"
    @State private var topToolbarPeopleFrame: CGRect = .zero
    @State private var topToolbarTimerFrame: CGRect = .zero
    #endif

    // Debounce
    @State private var debounceCancellable: AnyCancellable?
    @State private var lastBackendAutoFetchKey: String = ""
    @State private var lastBackendAutoFetchAt: Date = .distantPast


    // Auto-refresh bundle debounce (return-to-feed)
    @State private var lastBackendAutoBundleKey: String = ""
    @State private var lastBackendAutoBundleAt: Date = .distantPast
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
    private var toolbarAvatarKeyNormalized: String {
        auth.backendAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var toolbarAvatarCacheKey: String {
        "avatars|\(toolbarAvatarKeyNormalized)"
    }

    private var appSetUpBootstrapStateKey: String {
        switch auth.backendBootstrapState {
        case .unknown: return "unknown"
        case .checking: return "checking"
        case .existingAccount: return "existingAccount"
        case .newAccount: return "newAccount"
        }
    }

    private var appSetUpCompletenessKey: String {
        guard auth.isSignedIn else { return "signedOut" }
        guard BackendConfig.isConfigured else { return "backendNotConfigured" }
        guard let uid = userID, !uid.isEmpty else { return "missingUserID" }

        let req: NSFetchRequest<Profile> = Profile.fetchRequest()
        req.fetchLimit = 1

        guard let profile = (try? viewContext.fetch(req))?.first else {
            return "uid:\(uid.lowercased())|profile:none"
        }

        let name = (profile.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let instrumentCount = instruments.reduce(into: 0) { count, instrument in
            if instrument.profile == profile { count += 1 }
        }

        return "uid:\(uid.lowercased())|profile:\(profile.objectID.uriRepresentation().absoluteString)|name:\(name)|instrumentCount:\(instrumentCount)"
    }


    // Step 8C (backend preview): render backend-backed feed when Backend Preview mode is enabled
    @ObservedObject private var backendFeedStore: BackendFeedStore = BackendFeedStore.shared
    @ObservedObject private var commentPresence = CommentPresenceStore.shared
    @State private var isAwaitingFeedFetchStart: Bool = false

    private var useBackendFeed: Bool {
        _ = backendModeChangeTick
        return BackendEnvironment.shared.isConnected &&
        BackendConfig.isConfigured &&
        (NetworkManager.shared.baseURL != nil)
    }

    private var shouldDeferFeedEmptyState: Bool {
        selectedScope == .all && useBackendFeed && (isAwaitingFeedFetchStart || backendFeedStore.isFetching)
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


    private var summaryTotalTextColor: Color {
        if selectedScope == .all {
            return displayedStats.count == 0
                ? Theme.Colors.secondaryText.opacity(0.7)
                : Color.primary
        }
        return journalCurrentPeriodSessions.isEmpty
            ? Theme.Colors.secondaryText.opacity(0.7)
            : Color.primary
    }

    @ViewBuilder
    private var summaryHeaderContent: some View {
        if selectedScope == .all {
            Text("This week")
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(JournalTimeLens.allCases) { lens in
                    Button {
                        #if canImport(UIKit)
                        ContentViewKeyboardDismiss.dismiss()
                        #endif
                        selectedJournalLens = lens
                    } label: {
                        Text(lens.rawValue)
                            .font(Theme.Text.meta.weight(selectedJournalLens == lens ? .semibold : .regular))
                            .foregroundStyle(
                                selectedJournalLens == lens
                                ? Color.primary
                                : Theme.Colors.secondaryText.opacity(0.78)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var summaryBodyContent: some View {
        if selectedScope == .all {
            if displayedStats.count == 0 {
                Text("0h 0m")
                    .font(Theme.Text.body)
                    .foregroundStyle(summaryTotalTextColor)
            } else {
                Text(StatsHelper.formatDuration(displayedStats.seconds))
                    .font(Theme.Text.body)
                    .foregroundStyle(summaryTotalTextColor)

                if displayedCurrentStreak >= 2 {
                    Text("\(displayedCurrentStreak)-day streak")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                        .padding(.top, 4)
                }
            }
        } else {
            Text(journalCurrentPeriodSummaryLabel)
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))

            Text(StatsHelper.formatDuration(journalCurrentPeriodTotalSeconds))
                .font(Theme.Text.body)
                .foregroundStyle(summaryTotalTextColor)
        }
    }

    private var meViewButton: some View {
        NavigationLink {
            MeView()
        } label: {
            Image(systemName: "rectangle.stack")
                .imageScale(.medium)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                .accessibilityLabel("Open Insights")
        }
        .buttonStyle(.plain)
    }

    private var modeSelectorControl: some View {
        Picker("Mode", selection: $selectedScope) {
            ForEach(FeedScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .onChange(of: selectedScope) { newValue in
            #if canImport(UIKit)
            ContentViewKeyboardDismiss.dismiss()
            #endif
            isAwaitingFeedFetchStart = (newValue == .all) && useBackendFeed
        }
        .onChange(of: backendFeedStore.isFetching) { isFetching in
            if isFetching {
                isAwaitingFeedFetchStart = false
            }
        }
      }

    @ViewBuilder
    private var journalSummaryBaselineContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    ForEach(JournalTimeLens.allCases) { lens in
                        Text(lens.rawValue)
                            .font(Theme.Text.meta.weight(selectedJournalLens == lens ? .semibold : .regular))
                    }
                }

                Spacer()

                meViewButton
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(journalCurrentPeriodSummaryLabel)
                    .font(Theme.Text.meta)
                Text(StatsHelper.formatDuration(journalCurrentPeriodTotalSeconds))
                    .font(Theme.Text.body)
            }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private var summaryCard: some View {
        ZStack(alignment: .topLeading) {
            if selectedScope == .all {
                journalSummaryBaselineContent
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    summaryHeaderContent

                    Spacer()

                    meViewButton
                }

                VStack(alignment: .leading, spacing: 4) {
                    summaryBodyContent
                }
            }
        }
        .onAppear { refreshStats() }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        ) { note in
            guard notificationTouchesSessions(note) else { return }
            refreshStats()
        }
        .cardSurface()
        .padding(.bottom, 6)
    }
   


    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {

                // ---------- Stats (card) ----------
                summaryCard

                modeSelectorControl

                // ---------- Filters (card-parity refinement) ----------
                // CHANGE-ID: 20260330_191900_ContentView_FilterDensityTypography_b91a
                // SCOPE: Tighten expanded filter density and typography; quiet search row while preserving behaviour
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        #if canImport(UIKit)
                        ContentViewKeyboardDismiss.dismiss()
                        #endif
                        withAnimation { filtersExpanded.toggle() }
                    } label: {
                        HStack(alignment: .center, spacing: Theme.Spacing.inline) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)

                            Spacer(minLength: 0)

                            Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .imageScale(.small)
                        }
                        .padding(.horizontal, Theme.Spacing.card)
                        .padding(.vertical, 9)
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
                        searchText: $searchText,
                        savedOnly: $savedOnly,
                        selectedThread: $selectedThread,
                        selectedEnsembleID: $selectedEnsembleID,
                        threadOptions: existingThreadOptions,
                        ensembles: ensembleStore.ensembles
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    #if canImport(UIKit)
                    ContentViewKeyboardDismiss.dismiss()
                    #endif
                }
                .cardSurface()
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.012 : 0.028))
                        .allowsHitTesting(false)
                }
// ---------- Sessions List ----------
                ScrollViewReader { proxy in
                    let topID = "feed-top-anchor"

                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: Theme.Spacing.s)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                            withAnimation {
                                proxy.scrollTo(topID, anchor: .top)
                            }
                        }

                    Group {
                        List {
                        Section {
                            let localRows: [Session] = (selectedScope == .mine) ? journalArchiveSessions : filteredSessions

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

                            Group {}
                                .task(id: remoteWarmToken) {
                                    await warmRemoteFeedPreviews(posts: remotePosts, viewerUserID: effectiveBackendUserID, limit: 10)
                                }

                            // Build unified row source (Local sessions + Remote posts)
                            let finalLocalRowsForFeed: [Session] = {
                                guard selectedScope == .all else { return localRows }

                                func normalizedOwnerID(_ raw: String?) -> String {
                                    (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                }

                                let me = normalizedOwnerID(effectiveUserID)
                                guard !me.isEmpty else { return localRows }

                                if hasExplicitFeedNarrowing {
                                    return localRows
                                }

                                let hasEligibleNonOwnerLocalPost = localRows.contains {
                                    normalizedOwnerID($0.ownerUserID) != me
                                }

                                let hasEligibleNonOwnerRemotePost = remotePosts.contains {
                                    normalizedOwnerID($0.ownerUserID) != me
                                }

                                guard !(hasEligibleNonOwnerLocalPost || hasEligibleNonOwnerRemotePost) else {
                                    return localRows
                                }

                                return localRows.filter { normalizedOwnerID($0.ownerUserID) != me }
                            }()

                            let liveFeedItems: [FeedRowItem] = FeedRowItem.build(
                                local: finalLocalRowsForFeed,
                                remote: remotePosts
                            )

                            let renderFeedItems: [FeedRowItem] = (isFeedNavFrozen && !frozenFeedItems.isEmpty) ? frozenFeedItems : liveFeedItems

                            if selectedScope == .mine {
                                switch selectedJournalLens {
                                case .week:
                                    let journalSections = journalWeekSections(sessions: localRows)

                                    if journalSections.isEmpty {
                                        if !hasAnyJournalContent {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Your journal is empty.")
                                                Text("Log your first session to begin.")
                                                    .foregroundStyle(Theme.Colors.secondaryText)
                                            }
                                            .id(topID)
                                        } else {
                                            Text("No sessions match your filters.")
                                                .foregroundStyle(Theme.Colors.secondaryText)
                                                .id(topID)
                                        }
                                    } else {
                                        ForEach(Array(journalSections.enumerated()), id: \.element.id) { sectionIndex, section in
                                            HStack {
                                                Text(section.title)
                                                    .font(Theme.Text.meta)
                                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(selectedJournalLens == .year ? 0.56 : 0.60))
                                                    .textCase(nil)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.top, sectionIndex == 0 ? FeedJournalAlignmentUI.firstContentTopGap : Theme.Spacing.xl + 2)
                                            .padding(.bottom, 4)
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                            .id(sectionIndex == 0 ? topID : nil)

                                            ForEach(Array(section.sessions.enumerated()), id: \.element.objectID) { rowIndex, session in
                                                ZStack {
                                                    NavigationLink(
                                                        destination: SessionDetailView(session: session),
                                                        isActive: Binding(
                                                            get: { pushSessionID == (session.value(forKey: "id") as? UUID) },
                                                            set: { active in if !active { pushSessionID = nil } }
                                                        )
                                                    ) { EmptyView() }
                                                    .opacity(0)

                                                    SessionRow(session: session, scope: selectedScope, selectedThread: $selectedThread, activeUserFilterUserID: $activeUserFilterUserID, activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs, filtersExpanded: $filtersExpanded)
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            feedNavFreezeTask?.cancel()
                                                            isFeedNavFrozen = true
                                                            frozenFeedItems = renderFeedItems
                                                            pushSessionID = (session.value(forKey: "id") as? UUID)
                                                        }
                                                        .cardSurface(
                                                            fillColor: journalWeekCardFillColor(for: session),
                                                            strokeColor: journalWeekCardStrokeColor(for: session)
                                                        )
                                                        .padding(.bottom, rowIndex == section.sessions.count - 1 ? Theme.Spacing.xl : Theme.Spacing.m + 2)
                                                }
                                                                                            .buttonStyle(.plain)
                                                .listRowSeparator(.hidden)
                                                .listRowBackground(Color.clear)
                                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                                .deleteDisabled(false)
                                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                    Button {
                                                        if let localIndex = localRows.firstIndex(where: { $0.objectID == session.objectID }) {
                                                            deleteSessions(at: IndexSet(integer: localIndex))
                                                        }
                                                    } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                    .tint(.red)
                                                }
                                            }
                                        }
                                    }

                                case .month:
                                    let journalSections = journalYearSections(sessions: localRows)
                                    let usesYearArchivePresentation = true

                                    if journalSections.isEmpty {
                                        if !hasAnyJournalContent {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Your journal is empty.")
                                                Text("Log your first session to begin.")
                                                    .foregroundStyle(Theme.Colors.secondaryText)
                                            }
                                            .id(topID)
                                        } else {
                                            Text("No sessions match your filters.")
                                                .foregroundStyle(Theme.Colors.secondaryText)
                                                .id(topID)
                                        }
                                    } else {
                                        ForEach(Array(journalSections.enumerated()), id: \.element.id) { sectionIndex, section in
                                            HStack {
                                                Text(section.title)
                                                    .font(Theme.Text.meta)
                                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.54))
                                                    .textCase(nil)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.top, sectionIndex == 0 ? FeedJournalAlignmentUI.firstContentTopGap : Theme.Spacing.xl + 2)
                                            .padding(.bottom, 4)
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                            .id(journalMonthSectionAnchorID(for: section))

                                            ForEach(Array(section.sessions.enumerated()), id: \.element.objectID) { rowIndex, session in
                                                ZStack {
                                                    NavigationLink(
                                                        destination: SessionDetailView(session: session),
                                                        isActive: Binding(
                                                            get: { pushSessionID == (session.value(forKey: "id") as? UUID) },
                                                            set: { active in if !active { pushSessionID = nil } }
                                                        )
                                                    ) { EmptyView() }
                                                    .opacity(0)

                                                    SessionRow(
                                                        session: session,
                                                        scope: selectedScope,
                                                        selectedThread: $selectedThread,
                                                        activeUserFilterUserID: $activeUserFilterUserID,
                                                        activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs,
                                                        filtersExpanded: $filtersExpanded,
                                                        journalStyle: .yearCompact
                                                    )
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        feedNavFreezeTask?.cancel()
                                                        isFeedNavFrozen = true
                                                        frozenFeedItems = renderFeedItems
                                                        pushSessionID = (session.value(forKey: "id") as? UUID)
                                                    }
                                                    .modifier(
                                                        JournalArchiveRowContainerModifier(
                                                            lens: usesYearArchivePresentation ? .year : selectedJournalLens,
                                                            yearWidthFraction: journalYearSurfaceWidthFraction(for: session, maxDuration: journalYearMaxDuration(for: localRows)),
                                                            barFillColor: journalMonthBarFillColor(for: session),
                                                            barStrokeColor: journalMonthBarStrokeColor(for: session),
                                                            barAccentColor: journalMonthBarAccentColor(for: session),
                                                            barAccentWidth: 6
                                                        )
                                                    )
                                                    .padding(.bottom, rowIndex == section.sessions.count - 1 ? Theme.Spacing.xl : 4)
                                                }
                                                .buttonStyle(.plain)
                                                .listRowSeparator(.hidden)
                                                .listRowBackground(Color.clear)
                                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                                .deleteDisabled(false)
                                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                    Button {
                                                        if let localIndex = localRows.firstIndex(where: { $0.objectID == session.objectID }) {
                                                            deleteSessions(at: IndexSet(integer: localIndex))
                                                        }
                                                    } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                    .tint(.red)
                                                }
                                            }
                                        }
                                    }

                                case .year:
                                    let yearSections = journalCalendarYearSections(sessions: localRows)
                                    let currentMonthAnchorID = journalCurrentMonthAnchorID(in: yearSections)

                                    if yearSections.isEmpty {
                                        EmptyView()
                                            .id(topID)
                                    } else {
                                        VStack(alignment: .leading, spacing: Theme.Spacing.l + 6) {
                                            ForEach(Array(yearSections.enumerated()), id: \.element.id) { sectionIndex, section in
                                                VStack(alignment: .leading, spacing: Theme.Spacing.s + 6) {
                                                    HStack {
                                                        Text(String(section.year))
                                                            .font(.caption.weight(.medium))
                                                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.48))
                                                            .textCase(nil)
                                                        Spacer(minLength: 0)
                                                    }
                                                    .padding(.top, sectionIndex == 0 ? FeedJournalAlignmentUI.firstContentTopGap : Theme.Spacing.xxl + 4)
                                                    .padding(.bottom, 6)

                                                    VStack(alignment: .leading, spacing: 0) {
                                                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { rowIndex, row in
                                                            JournalYearMonthRow(row: row, isFirstInYear: rowIndex == 0)
                                                                .contentShape(Rectangle())
                                                                .onTapGesture {
                                                                    guard row.sessionCount > 0 else { return }
                                                                    pendingJournalMonthTargetMonthStart = row.monthStart
                                                                    selectedJournalLens = .month
                                                                }
                                                                .id(row.id)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.bottom, Theme.Spacing.xxl)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .id(topID)
                                        .task(id: currentMonthAnchorID ?? "journal-year-no-anchor") {
                                            guard selectedScope == .mine, selectedJournalLens == .year else { return }
                                            let targetID = currentMonthAnchorID ?? topID
                                            DispatchQueue.main.async {
                                                proxy.scrollTo(targetID, anchor: .top)
                                            }
                                        }
                                    }
                                }
                            } else if renderFeedItems.isEmpty {
                                if shouldDeferFeedEmptyState {
                                    EmptyView()
                                        .id(topID)
                                } else if hasExplicitFeedNarrowing {
                                    Text("No sessions match your filters.")
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                        .id(topID)
                                } else {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Your feed is empty.")
                                        Text("Follow people to see their sessions here.")
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .id(topID)
                                }
                            } else {
                                ForEach(Array(renderFeedItems.enumerated()), id: \.element.id) { index, item in
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

                                            SessionRow(session: session, scope: selectedScope, selectedThread: $selectedThread, activeUserFilterUserID: $activeUserFilterUserID, activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs, filtersExpanded: $filtersExpanded)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    feedNavFreezeTask?.cancel()
                                                    isFeedNavFrozen = true
                                                    frozenFeedItems = renderFeedItems
                                                    pushSessionID = (session.value(forKey: "id") as? UUID)
                                                }
                                                .cardSurface()
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                                        .fill(Theme.Colors.surface(colorScheme).opacity(0.035))
                                                        .opacity(selectedScope == .all ? 1 : 0)
                                                        .allowsHitTesting(false)
                                                }
                                                .padding(.top, index == 0 ? FeedJournalAlignmentUI.firstContentTopGap : 0)
                                                .padding(.bottom, Theme.Spacing.section)
                                        }
                                        .id(index == 0 ? topID : nil)
                                        .buttonStyle(.plain)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .deleteDisabled(false)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button {
                                                if let localIndex = localRows.firstIndex(where: { $0.objectID == session.objectID }) {
                                                    deleteSessions(at: IndexSet(integer: localIndex))
                                                }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            .tint(.red)
                                        }

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
                                                    set: { active in
                                                        if !active {
                                                            pushRemotePostID = nil
                                                            BackendDetailPopGate.lastPopAt = Date()
                                                            remotePrewarmNonce &+= 1
                                                        }
                                                    }
                                                )
                                            ) { EmptyView() }
                                            .opacity(0)

                                            RemotePostRowTwin(
                                                post: post,
                                                scope: selectedScope,
                                                viewerUserID: effectiveBackendUserID,
                                                activeUserFilterUserID: $activeUserFilterUserID,
                                                activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                feedNavFreezeTask?.cancel()
                                                isFeedNavFrozen = true
                                                frozenFeedItems = renderFeedItems
                                                pushRemotePostID = post.id
                                            }
                                            .cardSurface()
                                            .overlay {
                                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                                    .fill(Theme.Colors.surface(colorScheme).opacity(0.035))
                                                    .opacity(selectedScope == .all ? 1 : 0)
                                                    .allowsHitTesting(false)
                                            }
                                            .padding(.top, index == 0 ? FeedJournalAlignmentUI.firstContentTopGap : 0)
                                            .padding(.bottom, Theme.Spacing.section)
                                        }
                                        .id(index == 0 ? topID : nil)
                                        .buttonStyle(.plain)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .deleteDisabled(true)
                                    }
                                }
                            }                        }
                        .listSectionSeparator(.hidden, edges: .all)
                    }
                    .task(id: selectedScope) {
                        guard useBackendFeed else {
                            return
                        }

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
                   

                        await performAutoReturnRefreshBundle(scopeKey: scopeKey)
                    }
                    .onChange(of: selectedScope) { _ in
                        DispatchQueue.main.async {
                            proxy.scrollTo(topID, anchor: .top)
                        }
                    }
                    .task(id: pendingJournalMonthTargetMonthStart?.timeIntervalSinceReferenceDate ?? -1) {
                        guard selectedScope == .mine,
                              selectedJournalLens == .month,
                              let targetMonthStart = pendingJournalMonthTargetMonthStart,
                              hasVisibleJournalMonthSection(for: targetMonthStart, in: journalArchiveSessions) else { return }
                        let targetID = journalMonthSectionAnchorID(for: targetMonthStart)
                        DispatchQueue.main.async {
                            proxy.scrollTo(targetID, anchor: .top)
                            pendingJournalMonthTargetMonthStart = nil
                        }
                    
                    }
                    }

                    .refreshable {
                        await performUserInitiatedRefreshBundle()
                    }
                    .id(backendModeChangeTick)
                    .listStyle(.plain)
                    .listRowSeparator(.hidden)
                    .scrollContentBackground(.hidden)
                    .listRowBackground(Color.clear)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
            // No big nav title
            
            .safeAreaInset(edge: .top) {
                HStack(spacing: TopButtonsUI.spacing) {
                    Button { appRoute.isProfilePresented = true } label: {
                        #if canImport(UIKit)
                        if let uiImage = ProfileStore.avatarImage(for: userID) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                                .padding(8)
                        } else if !toolbarAvatarKeyNormalized.isEmpty, let cached = RemoteAvatarImageCache.get(toolbarAvatarCacheKey) {
                            Image(uiImage: cached)
                                .resizable()
                                .scaledToFill()
                                .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                                .padding(8)
                        } else if !toolbarAvatarKeyNormalized.isEmpty, let toolbarRemoteAvatar {
                            Image(uiImage: toolbarRemoteAvatar)
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
                    if selectedScope == .all {
                        Button {
                            showPeople = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                ZStack {
                                    Circle()
                                        .fill(.thinMaterial)
                                        .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)

                                    Image(systemName: "person.2")
                                        .font(.system(size: 19, weight: .regular))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                                .contentShape(Circle())

                                // Subtle "+" indicator for incoming follow requests (outside the pill)
                                if (!followStore.requests.isEmpty) || sharedWithYouStore.hasUnreadShares || unreadCommentsStore.hasUnread {
                                    Text("+")
                                        .font(Theme.Text.body)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityLabel("People")
                        #if DEBUG
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: TopToolbarPeopleFramePreferenceKey.self,
                                        value: proxy.frame(in: .named("TopToolbarRow"))
                                    )
                            }
                        )
                        #endif
                    } else {
                        Spacer()
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                        #if DEBUG
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: TopToolbarPeopleFramePreferenceKey.self,
                                            value: proxy.frame(in: .named("TopToolbarRow"))
                                        )
                                }
                            )
                        #endif
                    }
                    Spacer()
                    Button { appRoute.route = .timer } label: {
                        ZStack {
                          Circle()
                            .fill(.thinMaterial)
                            .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)

                          Image(systemName: "record.circle.fill")
                            .font(.system(size: TopButtonsUI.iconRecord, weight: .regular))
                            .foregroundStyle(.red.opacity(0.75))
                        }
                        .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                        .contentShape(Circle())
                        .buttonStyle(.plain)
                    }
                    .accessibilityLabel("Start session timer")
                    #if DEBUG
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: TopToolbarTimerFramePreferenceKey.self,
                                    value: proxy.frame(in: .named("TopToolbarRow"))
                                )
                        }
                    )
                    #endif
                }
                .coordinateSpace(name: "TopToolbarRow")
                #if DEBUG
                .onPreferenceChange(TopToolbarPeopleFramePreferenceKey.self) { topToolbarPeopleFrame = $0 }
                .onPreferenceChange(TopToolbarTimerFramePreferenceKey.self) { topToolbarTimerFrame = $0 }
                #endif
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
            }
            #if canImport(UIKit)
            .task(id: toolbarAvatarKeyNormalized) {
                guard !toolbarAvatarKeyNormalized.isEmpty else {
                    toolbarRemoteAvatar = nil
                    return
                }
                if RemoteAvatarImageCache.get(toolbarAvatarCacheKey) != nil { return }
                if let ui = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: toolbarAvatarKeyNormalized) {
                    toolbarRemoteAvatar = ui
                }
            }
            #endif
#if DEBUG
.overlay(alignment: .topLeading) {
    let gapStart = topToolbarPeopleFrame.maxX
    let gapEnd = topToolbarTimerFrame.minX
    let gapWidth = max(0, gapEnd - gapStart)

    if gapWidth > 0 {
        Color.clear
            .frame(width: gapWidth, height: max(topToolbarPeopleFrame.height, topToolbarTimerFrame.height))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.6) {
                isDebugPresented = true
            }
            .offset(x: gapStart, y: Theme.Spacing.m)
            .accessibilityHidden(true)
    }
}
#endif


     

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
                    
                        
            .sheet(isPresented: $showAdd) {
                AddEditSessionView()
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
            
            // Auto refresh notifications when returning to the feed from modal sheets (timer/add/profile/people).
            // This covers the common “navigate away and come back” flow because these destinations are presented as sheets.
            .onChange(of: showAdd) { _, isPresented in
                guard isPresented == false else { return }
                let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
                Task { await performAutoReturnRefreshBundle(scopeKey: scopeKey) }
            }
            .onChange(of: showProfile) { _, isPresented in
                guard isPresented == false else { return }
                let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
                Task { await performAutoReturnRefreshBundle(scopeKey: scopeKey) }
            }
            .onChange(of: showPeople) { _, isPresented in
                guard isPresented == false else { return }
                let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
                Task { await performAutoReturnRefreshBundle(scopeKey: scopeKey) }
            }

// Debounce lifecycle
            .task {
                setUpDebounce()
                await sharedWithYouStore.refreshUnreadShares()
                await unreadCommentsStore.refresh(force: true)
               
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
                    await unreadCommentsStore.refresh(force: true)
                }
            }
            .onAppear {
                filtersExpanded = false
            }
            .appBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .backendPublishSkippedOversizedAttachments)) { note in
            let count = (note.userInfo?["count"] as? Int) ?? 0
            guard count > 0 else { return }
            if count == 1 {
                publishSkipOversizeMessage = "1 attachment was too large to publish. It remains saved locally."
            } else {
                publishSkipOversizeMessage = "\(count) attachments were too large to publish. They remain saved locally."
            }
            showPublishSkipOversizeAlert = true
        }
        .alert("Publish limit", isPresented: $showPublishSkipOversizeAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(publishSkipOversizeMessage)
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
    // CHANGE-ID: 20260226_152200_ContentView_AutoRefreshBundleOnReturn
    // SCOPE: Reuse existing refresh bundle on pull-to-refresh; add debounced notification refresh on return-to-feed (no UI changes).
    private func performUserInitiatedRefreshBundle() async {
        // User-initiated refresh (pull-to-refresh)
        if useBackendFeed {
            let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
            _ = await BackendEnvironment.shared.publish.fetchFeed(scope: scopeKey)
        }
        await followStore.refreshFromBackendIfPossible()
        await sharedWithYouStore.refreshUnreadShares()
        await unreadCommentsStore.refresh(force: true)
        await MainActor.run {
            refreshStats()
        }
    }

    private func performAutoReturnRefreshBundle(scopeKey: String) async {
        // Auto refresh when returning to the feed: notifications only (posts refresh already handled separately).
        // Keep the same BSDV back-pop suppression window to avoid one-frame list rebind/flash.
        if Date().timeIntervalSince(BackendDetailPopGate.lastPopAt) < 0.75 {
            return
        }

        let key = "bundle:\(scopeKey)"

        // Debounce: prevent rapid consecutive auto refreshes for the same scope
        if key == lastBackendAutoBundleKey &&
           Date().timeIntervalSince(lastBackendAutoBundleAt) < 1.5 {
            return
        }

        lastBackendAutoBundleKey = key
        lastBackendAutoBundleAt = Date()

        await followStore.refreshFromBackendIfPossible()
        await sharedWithYouStore.refreshUnreadShares()
        await unreadCommentsStore.refresh(force: true)
    }



    private var displayedStats: SessionStats {
        backendOwnerStatsSnapshot?.stats ?? stats
    }

    private var displayedCurrentStreak: Int {
        if let backendOwnerStatsSnapshot {
            return backendOwnerStatsSnapshot.currentStreakDays
        }
        guard let uid = effectiveUserID else { return 0 }
        let ownerSessions = sessions.filter {
            ($0.ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == uid
        }
        return Stats.currentStreakDays(sessions: ownerSessions)
    }

    private func refreshStats() {
        // De-populate when signed out to mirror other data fields
        guard userID != nil else {
            stats = .init(count: 0, seconds: 0)
            backendOwnerStatsSnapshot = nil
            backendStatsLoading = false
            return
        }
        do {
            guard let uid = effectiveUserID else {
                stats = .init(count: 0, seconds: 0)
                backendOwnerStatsSnapshot = nil
                backendStatsLoading = false
                return
            }
            stats = try StatsHelper.fetchStats(in: viewContext, range: .week, ownerUserID: uid)
            let localOwnerHasSessions = hasLocalOwnerSessions(for: uid, range: .week)
            if localOwnerHasSessions {
                backendOwnerStatsSnapshot = nil
                backendStatsLoading = false
            } else {
                Task { await loadBackendOwnerStatsIfNeeded(localOwnerHasSessions: localOwnerHasSessions) }
            }
        } catch {
            stats = .init(count: 0, seconds: 0)
            backendOwnerStatsSnapshot = nil
            backendStatsLoading = false
        }
    }

    private func hasLocalOwnerSessions(for ownerUserID: String, range: StatsRange) -> Bool {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Session")
        var predicates: [NSPredicate] = [NSPredicate(format: "ownerUserID == %@", ownerUserID)]
        let bounds = StatsHelper.dateBounds(for: range)
        if let start = bounds.start, let end = bounds.end {
            predicates.append(NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        do {
            return try viewContext.count(for: request) > 0
        } catch {
            return false
        }
    }

    @MainActor
    private func loadBackendOwnerStatsIfNeeded(localOwnerHasSessions: Bool) async {
        guard localOwnerHasSessions == false else {
            backendOwnerStatsSnapshot = nil
            backendStatsLoading = false
            return
        }
        guard userID != nil,
              useBackendFeed,
              let backendOwnerUserID = effectiveBackendUserID,
              backendOwnerUserID.isEmpty == false else {
            backendOwnerStatsSnapshot = nil
            backendStatsLoading = false
            return
        }

        backendStatsLoading = true
        let result = await BackendEnvironment.shared.publish.fetchAllOwnerPostsForAnalytics(ownerUserID: backendOwnerUserID, pageSize: 500)
        switch result {
        case .success(let posts):
            backendOwnerStatsSnapshot = StatsHelper.buildBackendStatsSnapshot(
                posts: posts,
                range: .week,
                ownerUserID: backendOwnerUserID
            )
        case .failure:
            backendOwnerStatsSnapshot = nil
        }
        backendStatsLoading = false
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

        // Thread (owner-only; local-only)
        if let selected = selectedThread {
            let target = selected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let me = effectiveUserID, !target.isEmpty {
                out = out.filter { s in
                    guard s.ownerUserID == me else { return false }
                    let raw = ((s.value(forKey: "threadLabel") as? String) ?? "")
                    let norm = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return !norm.isEmpty && norm == target
                }
            } else {
                out = []
            }
        }

        // Ensemble (viewer-local feed lens only)
        if selectedScope == .all, selectedEnsembleID != nil, !activeEnsembleMemberUserIDs.isEmpty {
            out = out.filter { localMatchesSelectedEnsemble($0) }
        }

        // Single-user filter (local view-state only)
        if let selectedOwner = activeUserFilterUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !selectedOwner.isEmpty {
            out = out.filter { s in
                let owner = (s.ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !owner.isEmpty && owner == selectedOwner
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

        // Search (activity description / notes / local audio-video attachment titles)
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let audioTitles = loadFeedPersistedTitles(kind: .audio)
            let videoTitles = loadFeedPersistedTitles(kind: .video)
            out = out.filter { s in
                let haystacks: [String] = [
                    s.title ?? "",
                    s.notes ?? ""
                ] + localAttachmentSearchTerms(for: s, audioTitles: audioTitles, videoTitles: videoTitles)
                return haystacks.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }
        }

        return out
    }


    // MARK: - Remote filtering (connected feed parity)

    private func normalize(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func journalInstrumentLabel(for session: Session) -> String? {
        let explicitLabel = (session.value(forKey: "userInstrumentLabel") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitLabel, !explicitLabel.isEmpty {
            return explicitLabel
        }

        let fallbackName = session.instrument?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackName, !fallbackName.isEmpty {
            return fallbackName
        }

        return nil
    }

    private func journalInstrumentOwnerID(for session: Session) -> String? {
        let ownerID = session.ownerUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let ownerID, !ownerID.isEmpty {
            return ownerID
        }
        return effectiveUserID
    }

    private func journalWeekCardFillColor(for session: Session) -> Color {
        Theme.InstrumentTint.surfaceFill(
            for: journalInstrumentLabel(for: session),
            ownerID: journalInstrumentOwnerID(for: session),
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private func journalWeekCardStrokeColor(for session: Session) -> Color {
        Theme.InstrumentTint.cardStroke(
            for: journalInstrumentLabel(for: session),
            ownerID: journalInstrumentOwnerID(for: session),
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private func journalMonthBarFillColor(for session: Session) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.055)
    }

    private func journalMonthBarStrokeColor(for session: Session) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.05)
    }

    private func journalMonthBarAccentColor(for session: Session) -> Color? {
        Theme.InstrumentTint.visibleAccentColor(
            for: journalInstrumentLabel(for: session),
            ownerID: journalInstrumentOwnerID(for: session),
            scheme: colorScheme
        )
    }

    private var activeEnsembleMemberUserIDs: Set<String> {
        guard selectedScope == .all else { return [] }
        return ensembleStore.memberUserIDs(for: selectedEnsembleID)
    }

    private func localMatchesSelectedEnsemble(_ session: Session) -> Bool {
        guard selectedScope == .all else { return true }
        guard selectedEnsembleID != nil else { return true }
        guard !activeEnsembleMemberUserIDs.isEmpty else { return true }
        let owner = normalize(session.ownerUserID)
        return !owner.isEmpty && activeEnsembleMemberUserIDs.contains(owner)
    }

    private func remoteMatchesSelectedEnsemble(_ post: BackendPost) -> Bool {
        guard selectedScope == .all else { return true }
        guard selectedEnsembleID != nil else { return true }
        guard !activeEnsembleMemberUserIDs.isEmpty else { return true }
        let owner = normalize(post.ownerUserID)
        return !owner.isEmpty && activeEnsembleMemberUserIDs.contains(owner)
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

    private func remoteMatchesActiveUserFilter(_ post: BackendPost) -> Bool {
        guard let selectedOwner = activeUserFilterUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !selectedOwner.isEmpty else { return true }
        let owner = (post.ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !owner.isEmpty && owner == selectedOwner
    }

    // CHANGE-ID: 20260314_081900_FeedSearchNamesAndAttachmentTitles_6f3a
    // SCOPE: Feed search only — add remote owner display-name matching and attachment title matching (remote display_name + local persisted audio/video titles). No UI or non-search logic changes.
    // SEARCH-TOKEN: 20260314_081900_FeedSearchNamesAndAttachmentTitles_6f3a
    @MainActor
    private func feedSearchNamespaceUserID() -> String? {
        if BackendEnvironment.shared.isConnected,
           let connected = AttachmentTitlePersistenceKeys.normalize(AuthManager.canonicalBackendUserID()) {
            return connected
        }
        if let local = AttachmentTitlePersistenceKeys.normalize(auth.currentUserID) {
            return local
        }
        if let fallback = AttachmentTitlePersistenceKeys.normalize(PersistenceController.shared.currentUserID) {
            return fallback
        }
        return nil
    }

    @MainActor
    private func loadFeedPersistedTitles(kind: AttachmentTitlePersistenceKeys.Kind) -> [String: String] {
        let defaults = UserDefaults.standard
        if let userID = feedSearchNamespaceUserID() {
            let namespacedKey = AttachmentTitlePersistenceKeys.namespacedKey(for: kind, userID: userID)
            if let namespaced = defaults.dictionary(forKey: namespacedKey) as? [String: String] {
                return namespaced
            }
            let legacyKey = AttachmentTitlePersistenceKeys.legacyKey(for: kind)
            if let legacy = defaults.dictionary(forKey: legacyKey) as? [String: String] {
                defaults.set(legacy, forKey: namespacedKey)
                defaults.removeObject(forKey: legacyKey)
                return legacy
            }
            return [:]
        }
        return (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: kind)) as? [String: String]) ?? [:]
    }

    private func localAttachmentSearchTerms(for session: Session, audioTitles: [String: String], videoTitles: [String: String]) -> [String] {
        let attachments = (session.attachments as? Set<Attachment>) ?? []

        return attachments.compactMap { attachment in
            let kind = ((attachment.value(forKey: "kind") as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard kind == "audio" || kind == "video" else { return nil }
            guard let attachmentID = attachment.value(forKey: "id") as? UUID else { return nil }

            let persistedRaw: String?
            switch kind {
            case "audio":
                persistedRaw = audioTitles[attachmentID.uuidString]
            case "video":
                persistedRaw = videoTitles[attachmentID.uuidString]
            default:
                persistedRaw = nil
            }

            let persisted = (persistedRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !persisted.isEmpty { return persisted }

            guard let fileURLString = attachment.value(forKey: "fileURL") as? String else { return nil }
            let parsed = URL(string: fileURLString)
            let url = ((parsed?.scheme?.isEmpty == false) ? parsed : nil) ?? URL(fileURLWithPath: fileURLString, isDirectory: false)
            let stem = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return stem.isEmpty ? nil : stem
        }
    }

    private func remoteOwnerDisplayName(for post: BackendPost) -> String {
        let owner = (post.ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return "" }
        if let acct = BackendFeedStore.shared.directoryAccountsByUserID[owner] {
            return acct.displayName
        }
        let lower = owner.lowercased()
        if let acct = BackendFeedStore.shared.directoryAccountsByUserID[lower] {
            return acct.displayName
        }
        return ""
    }

    private func remoteMatchesSearch(_ post: BackendPost) -> Bool {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }

        let attachmentTitles = BackendSessionViewModel(post: post, currentUserID: (effectiveBackendUserID ?? ""))
            .attachmentRefs
            .compactMap { ref in
                let raw = ref.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return raw.isEmpty ? nil : raw
            }

        let haystacks: [String] = [
            post.activityLabel ?? "",
            post.activityType ?? "",
            post.activityDetail ?? "",
            post.instrumentLabel ?? "",
            post.notes ?? "",
            remoteOwnerDisplayName(for: post)
        ] + attachmentTitles

        return haystacks.contains(where: { $0.localizedCaseInsensitiveContains(q) })
    }

    private func filteredRemotePosts(_ posts: [BackendPost]) -> [BackendPost] {
        // Ensure no data is shown when signed out
        guard userID != nil else { return [] }

        // Thread filter is owner-only metadata; remote posts never participate.
        if selectedThread != nil { return [] }

        return posts.filter { post in
            remoteMatchesSelectedInstrument(post) &&
            remoteMatchesSelectedActivity(post) &&
            remoteMatchesSelectedEnsemble(post) &&
            remoteMatchesActiveUserFilter(post) &&
            remoteMatchesSavedOnly(post) &&
            remoteMatchesSearch(post)
        }
    }



    // MARK: - Thread options (owner-only; local-only)

    private var existingThreadOptions: [String] {
        // Ensure no data is shown when signed out
        guard userID != nil else { return [] }
        guard let me = effectiveUserID else { return [] }

        var out: [String] = []
        var seen: Set<String> = []

        for s in sessions {
            guard s.ownerUserID == me else { continue }
            let raw = ((s.value(forKey: "threadLabel") as? String) ?? "")
            guard let sanitized = ThreadLabelSanitizer.sanitize(raw, maxLength: 32) else { continue }

            let key = sanitized.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(sanitized)
        }

        // Consistent ordering: alphabetical (case-insensitive).
        return out.sorted { a, b in
            a.localizedCaseInsensitiveCompare(b) == .orderedAscending
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
        var didDeleteAny: Bool = false

        do {
            for idx in offsets {
                guard idx < rows.count else { continue }
                let session = rows[idx]

                // Connected mode: delete matching backend post first.
                // Invariant (published sessions): posts.id is client-assigned and equals the local Session UUID.
                if useBackendFeed {
                    guard let postID = session.id else {
                        // Fail-closed: if we cannot derive the backend postID, abort the entire delete operation.
                        print("[Delete][FAIL-CLOSED] session.id missing; cannot delete backend post. Aborting delete.")
                        return
                    }

                    let result = await BackendEnvironment.shared.publish.deletePost(postID)
                    switch result {
                    case .success:
                        break
                    case .failure(let err):
                        // Fail-closed: abort immediately — do NOT proceed to any local deletion.
                        print("[Delete][FAIL-CLOSED] backend deletePost failed postID=\(postID) err=\(err)")
                        return
                    }
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
                didDeleteAny = true
            }

            if didDeleteAny {
                try viewContext.save()

                // Refresh backend feed after deletions so remote rows don't rehydrate.
                if useBackendFeed {
                    let scopeKey: String = (selectedScope == .mine) ? "mine" : "all"
                    _ = await BackendEnvironment.shared.publish.fetchFeed(scope: scopeKey)
                }
            }
        } catch {
            print("Delete error: \(error)")
        }
    }


    private struct JournalSection: Identifiable {
        let id: String
        let title: String
        let sessions: [Session]
    }

    fileprivate struct JournalYearMonthRowModel: Identifiable {
        let id: String
        let monthStart: Date
        let year: Int
        let monthLabel: String
        let totalSeconds: Int
        let sessionCount: Int
        let metadataText: String?
        let dominantInstrumentLabel: String?
        let ownerUserID: String?
        let widthFraction: CGFloat
        let densityFraction: CGFloat
        let isFutureMonth: Bool
        let isCurrentMonth: Bool

        var hasSessions: Bool { sessionCount > 0 }
    }

    fileprivate struct JournalYearSectionModel: Identifiable {
        let id: String
        let year: Int
        let rows: [JournalYearMonthRowModel]
    }

    private var journalGroupingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func journalWeekStart(for date: Date) -> Date {
        let calendar = journalGroupingCalendar
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func journalDate(for session: Session) -> Date {
        (session.value(forKey: "timestamp") as? Date) ?? Date.distantPast
    }

    private func journalMonthStart(for date: Date) -> Date {
        let calendar = journalGroupingCalendar
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func journalYearStart(for date: Date) -> Date {
        let calendar = journalGroupingCalendar
        let components = calendar.dateComponents([.year], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func journalWeekHeaderTitle(for weekStart: Date) -> String {
        let calendar = journalGroupingCalendar
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return journalWeekDateRangeText(start: weekStart, end: weekEnd)
    }

    private func journalWeekDateRangeText(start: Date, end: Date) -> String {
        let calendar = journalGroupingCalendar

        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let startMonth = Self.journalMonthFormatter.string(from: start)
        let endMonth = Self.journalMonthFormatter.string(from: end)
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)

        if calendar.isDate(start, equalTo: end, toGranularity: .year),
           calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(startDay)–\(endDay) \(startMonth) \(startYear)"
        }

        if startYear == endYear {
            return "\(startDay) \(startMonth) – \(endDay) \(endMonth) \(startYear)"
        }

        return "\(startDay) \(startMonth) \(startYear) – \(endDay) \(endMonth) \(endYear)"
    }

    private func journalMonthWeekRangeText(start: Date, end: Date) -> String {
        let calendar = journalGroupingCalendar
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let month = Self.journalMonthFormatter.string(from: start)
        return "\(startDay)–\(endDay) \(month)"
    }

    private var hasAnyJournalContent: Bool {
        sessions.isEmpty == false
    }

    private var hasExplicitFeedNarrowing: Bool {
        let activeUserFilter = (activeUserFilterUserID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hasActiveUserFilter = !activeUserFilter.isEmpty
        let hasSelectedInstrument = (selectedInstrument != nil)
        let hasSelectedActivity: Bool = {
            switch selectedActivity {
            case .any:
                return false
            case .core, .custom:
                return true
            }
        }()
        let hasSelectedThread = !(selectedThread ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasSelectedEnsemble = !(selectedEnsembleID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasSearchQuery = !debouncedQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        return hasActiveUserFilter ||
            hasSelectedInstrument ||
            hasSelectedActivity ||
            hasSelectedThread ||
            hasSelectedEnsemble ||
            savedOnly ||
            hasSearchQuery
    }

    private var journalArchiveSessions: [Session] {
        let baseSessions = filteredSessions
        guard selectedScope == .mine else { return baseSessions }
        return baseSessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
    }

    private var journalCurrentPeriodSessions: [Session] {
        let calendar = journalGroupingCalendar
        let now = Date()

        return journalArchiveSessions.filter { session in
            let date = journalDate(for: session)
            switch selectedJournalLens {
            case .week:
                let nowComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                let sessionComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return nowComponents.yearForWeekOfYear == sessionComponents.yearForWeekOfYear
                    && nowComponents.weekOfYear == sessionComponents.weekOfYear
            case .month:
                return calendar.isDate(date, equalTo: now, toGranularity: .month)
                    && calendar.isDate(date, equalTo: now, toGranularity: .year)
            case .year:
                return calendar.isDate(date, equalTo: now, toGranularity: .year)
            }
        }
    }

    private var journalCurrentPeriodTotalSeconds: Int {
        journalCurrentPeriodSessions.reduce(0) { partial, session in
            partial + Int(session.durationSeconds)
        }
    }

    private var journalCurrentPeriodSummaryLabel: String {
        let now = Date()

        switch selectedJournalLens {
        case .week:
            return "This week"
        case .month:
            return Self.journalMonthYearFormatter.string(from: now)
        case .year:
            return Self.journalYearFormatter.string(from: now)
        }
    }

    private func journalWeekSections(sessions: [Session]) -> [JournalSection] {
        let sortedSessions = sessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
        guard !sortedSessions.isEmpty else { return [] }

        let grouped = Dictionary(grouping: sortedSessions) { journalWeekStart(for: journalDate(for: $0)) }

        return grouped.keys
            .sorted(by: >)
            .compactMap { weekStart in
                guard let sessions = grouped[weekStart], !sessions.isEmpty else { return nil }
                return JournalSection(
                    id: Self.journalWeekIDFormatter.string(from: weekStart),
                    title: journalWeekHeaderTitle(for: weekStart),
                    sessions: sessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
                )
            }
    }

    private func journalMonthSections(sessions: [Session]) -> [JournalSection] {
        let sortedSessions = sessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
        guard !sortedSessions.isEmpty else { return [] }

        let grouped = Dictionary(grouping: sortedSessions) { session in
            journalMonthStart(for: journalDate(for: session))
        }

        return grouped.keys
            .sorted(by: >)
            .compactMap { monthStart in
                guard let sessions = grouped[monthStart], !sessions.isEmpty else { return nil }
                return JournalSection(
                    id: "month-\(Self.journalWeekIDFormatter.string(from: monthStart))",
                    title: Self.journalMonthYearFormatter.string(from: monthStart),
                    sessions: sessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
                )
            }
    }

    private func journalYearSections(sessions: [Session]) -> [JournalSection] {
        let sortedSessions = sessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
        guard !sortedSessions.isEmpty else { return [] }

        let grouped = Dictionary(grouping: sortedSessions) { session in
            journalMonthStart(for: journalDate(for: session))
        }

        return grouped.keys
            .sorted(by: >)
            .compactMap { monthStart in
                guard let sessions = grouped[monthStart], !sessions.isEmpty else { return nil }
                return JournalSection(
                    id: "year-\(Self.journalWeekIDFormatter.string(from: monthStart))",
                    title: Self.journalMonthYearFormatter.string(from: monthStart),
                    sessions: sessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
                )
            }
    }

    private func journalCalendarYearSections(sessions: [Session]) -> [JournalYearSectionModel] {
        let calendar = journalGroupingCalendar
        let now = Date()
        let currentMonthStart = journalMonthStart(for: now)
        let currentYear = calendar.component(.year, from: now)

        let earliestSessionDate = sessions
            .map { journalDate(for: $0) }
            .min() ?? now
        let earliestSessionYear = calendar.component(.year, from: earliestSessionDate)
        let earliestSessionMonth = calendar.component(.month, from: earliestSessionDate)

        guard earliestSessionYear <= currentYear else { return [] }

        let grouped = Dictionary(grouping: sessions) { session in
            journalMonthStart(for: journalDate(for: session))
        }

        let allMonthStarts: [Date] = stride(from: currentYear, through: earliestSessionYear, by: -1).flatMap { year in
            let months = stride(from: 12, through: 1, by: -1).filter { month in
                if year == earliestSessionYear {
                    return month >= earliestSessionMonth
                }
                return true
            }

            return months.compactMap { month in
                calendar.date(from: DateComponents(year: year, month: month, day: 1))
            }
        }

        let maxTotalSeconds = max(
            allMonthStarts.map { monthStart in
                grouped[monthStart, default: []].reduce(0) { $0 + journalDurationSeconds(for: $1) }
            }.max() ?? 0,
            1
        )

        let maxSessionCount = max(
            allMonthStarts.map { grouped[$0, default: []].count }.max() ?? 0,
            1
        )

        let rows: [JournalYearMonthRowModel] = allMonthStarts.map { monthStart in
            let monthSessions = grouped[monthStart, default: []]
                .sorted { journalDate(for: $0) > journalDate(for: $1) }

            let totalSeconds = monthSessions.reduce(0) { $0 + journalDurationSeconds(for: $1) }
            let sessionCount = monthSessions.count
            let dominantInstrument = journalYearDominantInstrument(
                for: monthSessions,
                totalSeconds: totalSeconds
            )
            let metadataText = journalYearMetadataText(
                for: monthSessions,
                totalSeconds: totalSeconds,
                sessionCount: sessionCount
            )
            let rowOwnerUserID = monthSessions
                .compactMap { session in
                    let ownerID = session.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (ownerID?.isEmpty == false) ? ownerID : nil
                }
                .first ?? effectiveUserID

            let rawWidthFraction = CGFloat(totalSeconds) / CGFloat(maxTotalSeconds)
            let widthFraction: CGFloat = totalSeconds > 0 ? min(max(rawWidthFraction, 0.08), 1.0) : 0.0

            let rawDensityFraction = CGFloat(sessionCount) / CGFloat(maxSessionCount)
            let densityFraction: CGFloat = sessionCount > 0
                ? min(rawDensityFraction, 1.0)
                : 0.0

            return JournalYearMonthRowModel(
                id: "calendar-year-\(Self.journalWeekIDFormatter.string(from: monthStart))",
                monthStart: monthStart,
                year: calendar.component(.year, from: monthStart),
                monthLabel: Self.journalMonthFormatter.string(from: monthStart),
                totalSeconds: totalSeconds,
                sessionCount: sessionCount,
                metadataText: metadataText,
                dominantInstrumentLabel: dominantInstrument?.label,
                ownerUserID: rowOwnerUserID,
                widthFraction: widthFraction,
                densityFraction: densityFraction,
                isFutureMonth: calendar.component(.year, from: monthStart) == currentYear && monthStart > currentMonthStart,
                isCurrentMonth: calendar.isDate(monthStart, equalTo: currentMonthStart, toGranularity: .month)
            )
        }

        let sections = Dictionary(grouping: rows) { $0.year }

        return sections.keys
            .sorted(by: >)
            .compactMap { year in
                guard let rows = sections[year], !rows.isEmpty else { return nil }
                return JournalYearSectionModel(
                    id: "calendar-year-section-\(year)",
                    year: year,
                    rows: rows
                )
            }
    }

    private func journalCurrentMonthAnchorID(in sections: [JournalYearSectionModel]) -> String? {
        sections
            .flatMap { $0.rows }
            .first(where: { $0.isCurrentMonth })?
            .id
    }

    private func journalMonthSectionAnchorID(for monthStart: Date) -> String {
        "journal-month-section-\(Self.journalWeekIDFormatter.string(from: monthStart))"
    }

    private func journalMonthSectionAnchorID(for section: JournalSection) -> String {
        let monthStart = section.sessions
            .map { journalDate(for: $0) }
            .map { journalMonthStart(for: $0) }
            .max() ?? Date.distantPast
        return journalMonthSectionAnchorID(for: monthStart)
    }

    private func hasVisibleJournalMonthSection(for monthStart: Date, in sessions: [Session]) -> Bool {
        journalYearSections(sessions: sessions)
            .contains { section in
                section.sessions.contains {
                    journalMonthStart(for: journalDate(for: $0)) == monthStart
                }
            }
    }

    private struct JournalYearFacetSummary {
        let label: String
        let seconds: Int
        let distinctCount: Int
    }

    private func journalYearMetadataText(
        for sessions: [Session],
        totalSeconds: Int,
        sessionCount: Int
    ) -> String? {
        guard sessionCount > 0, totalSeconds > 0 else { return nil }

        var parts: [String] = [
            StatsHelper.formatDuration(totalSeconds),
            sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        ]

        if let instrument = journalYearDominantInstrument(for: sessions, totalSeconds: totalSeconds) {
            parts.append("\(instrument.label) \(StatsHelper.formatDuration(instrument.seconds))")
        }

        if let activity = journalYearDominantActivity(for: sessions, totalSeconds: totalSeconds) {
            parts.append("\(activity.label) \(StatsHelper.formatDuration(activity.seconds))")
        }

        return parts.joined(separator: " • ")
    }

    private func journalYearDominantInstrument(
        for sessions: [Session],
        totalSeconds: Int
    ) -> JournalYearFacetSummary? {
        journalYearDominantFacet(
            for: sessions,
            totalSeconds: totalSeconds,
            label: journalYearInstrumentLabel(for:)
        )
    }

    private func journalYearDominantActivity(
        for sessions: [Session],
        totalSeconds: Int
    ) -> JournalYearFacetSummary? {
        journalYearDominantFacet(
            for: sessions,
            totalSeconds: totalSeconds,
            label: journalYearActivityLabel(for:)
        )
    }

    private func journalYearDominantFacet(
        for sessions: [Session],
        totalSeconds: Int,
        label: (Session) -> String?
    ) -> JournalYearFacetSummary? {
        let totals = sessions.reduce(into: [String: Int]()) { partial, session in
            guard let rawLabel = label(session) else { return }
            let trimmed = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            partial[trimmed, default: 0] += journalDurationSeconds(for: session)
        }

        let sorted = totals.sorted {
            if $0.value == $1.value {
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            return $0.value > $1.value
        }

        guard let top = sorted.first, top.value > 0 else { return nil }

        let distinctCount = sorted.count
        // Always use the highest-duration instrument for the month
        return JournalYearFacetSummary(label: top.key, seconds: top.value, distinctCount: distinctCount)
    }

    private func journalYearInstrumentLabel(for session: Session) -> String? {
        let directLabel = ((session.value(forKey: "userInstrumentLabel") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !directLabel.isEmpty { return directLabel }

        let relationshipLabel = session.instrument?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return relationshipLabel.isEmpty ? nil : relationshipLabel
    }

    private func journalYearActivityLabel(for session: Session) -> String? {
        let directLabel = ((session.value(forKey: "userActivityLabel") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !directLabel.isEmpty { return directLabel }

        if let code = session.value(forKey: "activityType") as? Int16 {
            return from(code).label
        }

        return nil
    }

    private func journalYearLabelsMatch(_ lhs: String, _ rhs: String?) -> Bool {
        guard let rhs else { return false }
        return lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private func journalDurationSeconds(for session: Session) -> Int {
        let attrs = session.entity.attributesByName
        if attrs["durationSeconds"] != nil, let n = session.value(forKey: "durationSeconds") as? NSNumber {
            return max(0, n.intValue)
        } else if attrs["durationMinutes"] != nil, let n = session.value(forKey: "durationMinutes") as? NSNumber {
            return max(0, n.intValue * 60)
        } else if attrs["duration"] != nil, let n = session.value(forKey: "duration") as? NSNumber {
            return max(0, n.intValue * 60)
        } else if attrs["lengthMinutes"] != nil, let n = session.value(forKey: "lengthMinutes") as? NSNumber {
            return max(0, n.intValue * 60)
        }
        return 0
    }

    private func journalYearMaxDuration(for sessions: [Session]) -> Int {
        max(sessions.map(journalDurationSeconds(for:)).max() ?? 0, 1)
    }

    private func journalYearSurfaceWidthFraction(for session: Session, maxDuration: Int) -> CGFloat {
        guard maxDuration > 0 else { return 0.05 }
        let raw = max(0, CGFloat(journalDurationSeconds(for: session)) / CGFloat(maxDuration))
        let scaled = pow(raw, 0.75)
        return scaled
    }

    private static let journalMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MMMM"
        return f
    }()

    private static let journalWeekIDFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let journalMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let journalYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "yyyy"
        return f
    }()

    // MARK: - Debounce

    private func setUpDebounce() {
        debounceCancellable?.cancel()
        debounceCancellable = Just(searchText)
            .delay(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { debouncedQuery = $0 }
    }
}

// MARK: - Filter bar (unchanged logic, wrapped by a card above)


fileprivate struct FilterSelectorValueControl: View {
    let valueText: String

    var body: some View {
        HStack(spacing: 5) {
            Text(valueText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .animation(nil, value: valueText)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.regular))
                .imageScale(.small)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 3)
    }
}

fileprivate struct FilterSelectorTrailingControlStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.66))
            .tint(Theme.Colors.secondaryText.opacity(0.66))
            .controlSize(.small)
            .scaleEffect(1.0, anchor: .trailing)
    }
}



fileprivate enum FilterCardUI {
    static let rowMinHeight: CGFloat = 33
    static let rowVerticalPadding: CGFloat = 2
    static let trailingControlWidth: CGFloat = 160
    static let searchCornerRadius: CGFloat = 12
}

fileprivate struct FilterCardDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke(colorScheme).opacity(colorScheme == .dark ? 0.09 : 0.05))
            .frame(height: 1)
    }
}

fileprivate struct FilterCardRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))

            Spacer(minLength: Theme.Spacing.s)

            trailing()
                .frame(width: FilterCardUI.trailingControlWidth, alignment: .trailing)
                .padding(.trailing, 3)
        }
        .frame(minHeight: FilterCardUI.rowMinHeight)
        .padding(.horizontal, Theme.Spacing.card)
        .padding(.vertical, FilterCardUI.rowVerticalPadding)
    }
}

fileprivate struct FilterCardSearchField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))

            TextField(
                "Search",
                text: $text,
                prompt: Text("Search")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(colorScheme == .dark ? 0.92 : 0.86))
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .font(.footnote)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: FilterCardUI.searchCornerRadius, style: .continuous)
                .fill(
                    colorScheme == .dark
                    ? Theme.Colors.surface(colorScheme).opacity(0.94)
                    : Color.primary.opacity(0.035)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: FilterCardUI.searchCornerRadius, style: .continuous)
                .stroke(
                    colorScheme == .dark
                    ? Theme.Colors.cardStroke(colorScheme).opacity(0.18)
                    : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
fileprivate struct FilterBar: View {
    @Binding var filtersExpanded: Bool
    let instruments: [Instrument]
    let customNames: [String]
    @Binding var selectedInstrument: Instrument?
    @Binding var selectedActivity: ActivityFilter
    @Binding var searchText: String
    @Binding var savedOnly: Bool
    @Binding var selectedThread: String?
    @Binding var selectedEnsembleID: String?
    let threadOptions: [String]
    let ensembles: [Ensemble]

    @State private var showThreadPicker: Bool = false

    private var sortedEnsembles: [Ensemble] {
        ensembles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedEnsembleName: String {
        guard let selectedEnsembleID,
              let ensemble = sortedEnsembles.first(where: { $0.id == selectedEnsembleID }) else {
            return "Any"
        }
        return ensemble.name
    }

    private var selectedInstrumentLabel: String {
        if let inst = selectedInstrument {
            let name = (inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "(Unnamed)" : name
        } else {
            return "Any"
        }
    }

    var body: some View {
        if filtersExpanded {
            VStack(alignment: .leading, spacing: 0) {
                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                HStack(spacing: 0) {
                    FilterCardSearchField(text: $searchText)
                }
                .frame(minHeight: FilterCardUI.rowMinHeight)
                .padding(.horizontal, Theme.Spacing.card)
                .padding(.vertical, FilterCardUI.rowVerticalPadding)

                FilterCardRow(label: "Instrument") {
                    Menu {
                        Button("Any") {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                            selectedInstrument = nil
                        }
                        ForEach(instruments, id: \.objectID) { inst in
                            Button(((inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? "(Unnamed)" : (inst.name ?? "")) {
                                #if canImport(UIKit)
                                ContentViewKeyboardDismiss.dismiss()
                                #endif
                                selectedInstrument = inst
                            }
                        }
                    } label: {
                        FilterSelectorValueControl(valueText: selectedInstrumentLabel)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                    )
                    .modifier(FilterSelectorTrailingControlStyle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Activity") {
                    Menu {
                        Button("Any") {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                            selectedActivity = .any
                        }
                        ForEach(ActivityType.allCases) { a in
                            Button(a.label) {
                                #if canImport(UIKit)
                                ContentViewKeyboardDismiss.dismiss()
                                #endif
                                selectedActivity = .core(a)
                            }
                        }
                        if !customNames.isEmpty {
                            ForEach(customNames, id: \.self) { name in
                                Button(name) {
                                    #if canImport(UIKit)
                                    ContentViewKeyboardDismiss.dismiss()
                                    #endif
                                    selectedActivity = .custom(name)
                                }
                            }
                        }
                    } label: {
                        FilterSelectorValueControl(valueText: selectedActivity.label)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                    )
                    .modifier(FilterSelectorTrailingControlStyle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Thread") {
                    Button {
                        #if canImport(UIKit)
                        ContentViewKeyboardDismiss.dismiss()
                        #endif
                        showThreadPicker = true
                    } label: {
                        FilterSelectorValueControl(valueText: selectedThread ?? "Any")
                    }
                    .buttonStyle(.plain)
                    .modifier(FilterSelectorTrailingControlStyle())
                    .contentShape(Rectangle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Ensemble") {
                    Menu {
                        Button("Any") {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                            selectedEnsembleID = nil
                        }
                        ForEach(sortedEnsembles) { ensemble in
                            Button(ensemble.name) {
                                #if canImport(UIKit)
                                ContentViewKeyboardDismiss.dismiss()
                                #endif
                                selectedEnsembleID = ensemble.id
                            }
                        }
                    } label: {
                        FilterSelectorValueControl(valueText: selectedEnsembleName)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                    )
                    .modifier(FilterSelectorTrailingControlStyle())
                }

                FilterCardDivider()
                    .padding(.horizontal, Theme.Spacing.card)

                FilterCardRow(label: "Saved only") {
                    Toggle("", isOn: $savedOnly)
                        .labelsHidden()
                        .tint(Theme.Colors.accent.opacity(0.72))
                        .controlSize(.small)
                        .scaleEffect(1.0, anchor: .trailing)
                        .onChange(of: savedOnly) { _ in
                            #if canImport(UIKit)
                            ContentViewKeyboardDismiss.dismiss()
                            #endif
                        }
                }
            }
            .padding(.top, 1)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                #if canImport(UIKit)
                ContentViewKeyboardDismiss.dismiss()
                #endif
            }
            .sheet(isPresented: $showThreadPicker) {
                ThreadPickerView(
                    selectedThread: $selectedThread,
                    title: "Thread",
                    recentThreads: threadOptions,
                    maxLength: 32
                )
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

fileprivate struct JournalYearMonthRow: View {
    let row: SessionsRootView.JournalYearMonthRowModel
    let isFirstInYear: Bool

    @Environment(\.colorScheme) private var colorScheme

    private let barCornerRadius: CGFloat = 8
    private let activeBarHeight: CGFloat = 4
    private let quietBarHeight: CGFloat = 1.5
    private let leaderLaneWidth: CGFloat = 5
    private let leaderGapToContent: CGFloat = 4
    private let leaderCornerRadius: CGFloat = 1.5

    private var activeBarFill: Color {
        let baseOpacity: Double = colorScheme == .dark ? 0.105 : 0.03
        let densityLift: Double = colorScheme == .dark ? 0.075 : 0.095
        let adjustedDensity = pow(Double(row.densityFraction), 0.6)
        return Color.primary.opacity(baseOpacity + densityLift * adjustedDensity)
    }

    private var activeBarStroke: Color {
        let baseOpacity: Double = colorScheme == .dark ? 0.065 : 0.012
        let densityLift: Double = colorScheme == .dark ? 0.02 : 0.026
        return Color.primary.opacity(baseOpacity + densityLift * Double(row.densityFraction))
    }

    private var quietTextOpacity: Double {
        row.isFutureMonth ? 0.28 : 0.42
    }

    private var metadataOpacity: Double {
        row.isFutureMonth ? 0.2 : 0.4
    }

    private var quietBarOpacity: Double {
        row.isFutureMonth ? 0.016 : 0.028
    }

    private var showsMetadata: Bool {
        row.hasSessions && row.metadataText != nil
    }

    private var rowTopPadding: CGFloat {
        isFirstInYear ? 2 : 8
    }

    private var rowBottomPadding: CGFloat {
        row.hasSessions ? 12 : 11
    }

    private var leaderColor: Color? {
        Theme.InstrumentTint.visibleAccentColor(
            for: row.dominantInstrumentLabel,
            ownerID: row.ownerUserID,
            scheme: colorScheme,
            shouldAssignIfNeeded: false
        )
    }

    private var barHeight: CGFloat {
        row.hasSessions ? activeBarHeight : quietBarHeight
    }

    var body: some View {
        HStack(alignment: .top, spacing: leaderGapToContent) {
            leaderLane

            VStack(alignment: .leading, spacing: 0) {
                Text(row.monthLabel)
                    .font(.caption.weight(row.hasSessions ? .semibold : .medium))
                    .foregroundStyle(Color.primary.opacity(row.hasSessions ? 0.96 : quietTextOpacity))
                    .lineLimit(1)
                    .padding(.bottom, showsMetadata ? 2 : 7)

                if let metadata = row.metadataText, row.hasSessions {
                    let metadataParts = metadata.components(separatedBy: " • ")
                    let primaryTime = metadataParts.first ?? metadata
                    let secondaryMetadata = metadataParts.dropFirst().joined(separator: " • ")

                    Group {
                        if secondaryMetadata.isEmpty {
                            Text(primaryTime)
                                .font(.caption2.weight(.semibold))
                        } else {
                            Text(primaryTime)
                                .font(.caption2.weight(.semibold))
                            + Text(" • \(secondaryMetadata)")
                                .font(.caption2)
                        }
                    }
                        .foregroundStyle(Color.primary.opacity(metadataOpacity))
                        .lineLimit(1)
                        .padding(.bottom, 9)
                }

                GeometryReader { proxy in
                    let totalWidth = max(0, proxy.size.width)
                    let clampedFraction = min(max(row.widthFraction, 0.08), 1.0)
                    let fillWidth = row.hasSessions ? max(0, totalWidth * clampedFraction) : 0

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(quietBarOpacity))
                            .frame(width: totalWidth, height: quietBarHeight)

                        if row.hasSessions {
                            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                                .fill(activeBarFill)
                                .frame(width: fillWidth, height: activeBarHeight)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                                        .stroke(activeBarStroke, lineWidth: 0.45)
                                        .frame(width: fillWidth, height: activeBarHeight)
                                }
                        }
                    }
                }
                .frame(height: barHeight)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                if let leaderColor {
                    RoundedRectangle(cornerRadius: leaderCornerRadius, style: .continuous)
                        .fill(leaderColor)
                        .frame(width: leaderLaneWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .offset(x: -(leaderLaneWidth + leaderGapToContent))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, rowTopPadding)
        .padding(.bottom, rowBottomPadding)
    }

    @ViewBuilder
    private var leaderLane: some View {
        Color.clear
            .frame(width: leaderLaneWidth)
    }
}


fileprivate func isActiveUserFilter(_ candidateUserID: String?, activeUserFilterUserID: String?) -> Bool {
    let candidate = (candidateUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let active = (activeUserFilterUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !candidate.isEmpty && !active.isEmpty && candidate == active
}

fileprivate func isActiveEnsembleMember(_ candidateUserID: String?, activeEnsembleMemberUserIDs: Set<String>) -> Bool {
    let candidate = (candidateUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !candidate.isEmpty && activeEnsembleMemberUserIDs.contains(candidate)
}

fileprivate struct ThreadMetaPill: View {
    let title: String
    let isSelected: Bool
    var font: Font = Theme.Text.body
    var verticalPadding: CGFloat = 2

    var body: some View {
        Text(title)
            .font(font)
            .padding(.horizontal, 8)
            .padding(.vertical, verticalPadding)
            .background(
                isSelected
                ? Color(uiColor: .systemGray2)
                : Color(uiColor: .tertiarySystemFill)
            )
            .clipShape(Capsule())
    }
}

fileprivate struct AttachmentCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .foregroundStyle(Theme.Colors.secondaryText.opacity(FeedJournalAlignmentUI.attachmentBadgeIconOpacity))
            Text("\(count)")
                .foregroundStyle(Theme.Colors.secondaryText.opacity(FeedJournalAlignmentUI.attachmentBadgeTextOpacity))
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(FeedJournalAlignmentUI.attachmentBadgeStrokeOpacity), lineWidth: 0.5))
        .padding(6)
        .accessibilityLabel("\(count) attachments")
    }
}

fileprivate struct JournalArchiveRowContainerModifier: ViewModifier {
    let lens: JournalTimeLens
    let yearWidthFraction: CGFloat
    let barFillColor: Color?
    let barStrokeColor: Color?
    let barAccentColor: Color?
    let barAccentWidth: CGFloat

    init(
        lens: JournalTimeLens,
        yearWidthFraction: CGFloat,
        barFillColor: Color? = nil,
        barStrokeColor: Color? = nil,
        barAccentColor: Color? = nil,
        barAccentWidth: CGFloat = 0
    ) {
        self.lens = lens
        self.yearWidthFraction = yearWidthFraction
        self.barFillColor = barFillColor
        self.barStrokeColor = barStrokeColor
        self.barAccentColor = barAccentColor
        self.barAccentWidth = barAccentWidth
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch lens {
        case .week:
            content.cardSurface()
        case .month:
            content.cardSurface()
        case .year:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 58, alignment: .leading)
                .background(alignment: .leading) {
                    GeometryReader { proxy in
                        let clampedFraction = min(max(yearWidthFraction, 0.05), 0.94)
                        let width = max(0, proxy.size.width * clampedFraction)

                        let cornerRadius: CGFloat = 10
                        let resolvedFill = barFillColor ?? Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.055)
                        let resolvedStroke = barStrokeColor ?? Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.05)
                        let hasAccent = barAccentColor != nil && barAccentWidth > 0
                        let accentWidth = hasAccent ? min(barAccentWidth, width) : 0
                        let bodyWidth = max(0, width - accentWidth)

                        let fullShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        let accentShape = MonthBarLeadingAccentShape(cornerRadius: cornerRadius)
                        let bodyShape = MonthBarTrailingBodyShape(cornerRadius: cornerRadius)

                        ZStack(alignment: .leading) {
                            if hasAccent, let accentColor = barAccentColor {
                                if bodyWidth > 0 {
                                    bodyShape
                                        .fill(resolvedFill)
                                        .frame(width: bodyWidth, height: 58, alignment: .leading)
                                        .offset(x: accentWidth)

                                    bodyShape
                                        .stroke(resolvedStroke, lineWidth: 0.5)
                                        .frame(width: bodyWidth, height: 58, alignment: .leading)
                                        .offset(x: accentWidth)
                                }

                                accentShape
                                    .fill(accentColor)
                                    .frame(width: accentWidth, height: 58, alignment: .leading)

                                accentShape
                                    .stroke(resolvedStroke, lineWidth: 0.5)
                                    .frame(width: accentWidth, height: 58, alignment: .leading)
                            } else {
                                fullShape
                                    .fill(resolvedFill)
                                    .frame(width: width, height: 58, alignment: .leading)

                                fullShape
                                    .stroke(resolvedStroke, lineWidth: 0.5)
                                    .frame(width: width, height: 58, alignment: .leading)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
    }
}

fileprivate struct MonthBarLeadingAccentShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
fileprivate struct MonthBarTrailingBodyShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

fileprivate struct SessionRow: View {
    fileprivate enum JournalStyle {
        case standard
        case monthCompact
        case yearCompact
    }

    @ObservedObject var session: Session
    let scope: FeedScope
    let journalStyle: JournalStyle

    @Binding var selectedThread: String?
    @Binding var activeUserFilterUserID: String?
    let activeEnsembleMemberUserIDs: Set<String>
    @Binding var filtersExpanded: Bool

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
    @ObservedObject private var commentPresence = CommentPresenceStore.shared

    init(
        session: Session,
        scope: FeedScope,
        selectedThread: Binding<String?>,
        activeUserFilterUserID: Binding<String?>,
        activeEnsembleMemberUserIDs: Set<String>,
        filtersExpanded: Binding<Bool>,
        journalStyle: JournalStyle = .standard
    ) {
        self._session = ObservedObject(initialValue: session)
        self.scope = scope
        self.journalStyle = journalStyle
        self._selectedThread = selectedThread
        self._activeUserFilterUserID = activeUserFilterUserID
        self.activeEnsembleMemberUserIDs = activeEnsembleMemberUserIDs
        self._filtersExpanded = filtersExpanded
    }

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
        guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
        return "\(Self.sessionRowDateFormatter.string(from: date)) at \(Self.sessionRowTimeFormatter.string(from: date))"
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

    private var journalThreadLabel: String? {
        ThreadLabelSanitizer.sanitize(session.threadLabel ?? "", maxLength: 32)
    }

    private var journalDateText: String? {
        guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
        return Self.sessionRowDateFormatter.string(from: date)
    }

    private var journalTimeText: String? {
        guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
        return Self.sessionRowTimeFormatter.string(from: date)
    }

    private var journalDurationText: String? {
        let attrs = session.entity.attributesByName
        let seconds: Int?
        if attrs["durationSeconds"] != nil, let n = session.value(forKey: "durationSeconds") as? NSNumber {
            seconds = n.intValue
        } else if attrs["durationMinutes"] != nil, let n = session.value(forKey: "durationMinutes") as? NSNumber {
            seconds = n.intValue * 60
        } else if attrs["duration"] != nil, let n = session.value(forKey: "duration") as? NSNumber {
            seconds = n.intValue * 60
        } else if attrs["lengthMinutes"] != nil, let n = session.value(forKey: "lengthMinutes") as? NSNumber {
            seconds = n.intValue * 60
        } else {
            seconds = nil
        }

        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    private var journalMetadataLine: String {
        [
            journalThreadLabel,
            instrumentActivityLine.isEmpty ? nil : instrumentActivityLine,
            journalDateText,
            journalTimeText,
            journalDurationText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var journalMetadataTailLine: String {
        [
            instrumentActivityLine.isEmpty ? nil : instrumentActivityLine,
            journalDateText,
            journalTimeText,
            journalDurationText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var yearCompactInstrumentOnlyLine: String {
        subtitleParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var yearCompactMetadataLine: String {
        let instrumentText = yearCompactInstrumentOnlyLine.isEmpty ? nil : yearCompactInstrumentOnlyLine
        let fallbackInstrumentActivityText = instrumentActivityLine.isEmpty ? nil : instrumentActivityLine

        return [
            journalThreadLabel,
            journalThreadLabel == nil ? fallbackInstrumentActivityText : instrumentText,
            journalDateText,
            journalDurationText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var yearCompactMetadataTailLine: String {
        let instrumentText = yearCompactInstrumentOnlyLine.isEmpty ? nil : yearCompactInstrumentOnlyLine
        let fallbackInstrumentActivityText = instrumentActivityLine.isEmpty ? nil : instrumentActivityLine

        return [
            journalThreadLabel == nil ? fallbackInstrumentActivityText : instrumentText,
            journalDateText,
            journalDurationText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var notesPreviewText: String? {
        let trimmed = (session.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let bulletChars = CharacterSet(charactersIn: "•◦▪▫●○■□-–—*·")
        let normalizedLines = trimmed
            .components(separatedBy: .newlines)
            .map { line -> String in
                var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                while let scalar = value.unicodeScalars.first, bulletChars.contains(scalar) {
                    value = String(value.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return value
            }
            .filter { !$0.isEmpty }

        let flattened = normalizedLines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return flattened.isEmpty ? nil : flattened
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append(feedTitle)
        let meta: String
        if scope == .mine {
            meta = isYearCompactJournalRow ? yearCompactMetadataLine : journalMetadataLine
        } else {
            meta = instrumentActivityLine
        }
        if !meta.isEmpty {
            parts.append(meta)
        }
        if scope != .mine, let dt = dateTimeLine {
            parts.append(dt)
        }
        if scope == .mine, journalStyle == .standard, let notesPreviewText {
            parts.append(notesPreviewText)
        }
        return parts.joined(separator: ". ")
    }

    private var isMonthCompactJournalRow: Bool {
        scope == .mine && journalStyle == .monthCompact
    }

    private var isYearCompactJournalRow: Bool {
        scope == .mine && journalStyle == .yearCompact
    }

    private var isCompactJournalRow: Bool {
        isMonthCompactJournalRow || isYearCompactJournalRow
    }

    private var showsJournalNotesPreview: Bool {
        scope == .mine && journalStyle == .standard
    }

    private var showsJournalAttachmentPreview: Bool {
        scope != .mine || journalStyle == .standard
    }

    private static let sessionRowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return f
    }()

    private static let sessionRowTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

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

    var hasComments: Bool {
        guard let id = sessionIDForComments else { return false }
        if auth.isConnected {
            return CommentPresenceStore.shared.hasComments(postID: id)
        }
        return commentsCount > 0
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

    private var activeHeaderFilterOwnerID: String? {
        let owner = (session.ownerUserID ?? (viewerIsOwner ? viewerUserID : nil))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let owner, !owner.isEmpty else { return nil }
        return owner
    }

    private var isHeaderFilterActive: Bool {
        guard scope == .all else { return false }
        return isActiveUserFilter(activeHeaderFilterOwnerID, activeUserFilterUserID: activeUserFilterUserID)
            || isActiveEnsembleMember(activeHeaderFilterOwnerID, activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs)
    }

    private func toggleHeaderUserFilter(ownerID: String) {
        guard scope == .all else { return }
        if isActiveUserFilter(ownerID, activeUserFilterUserID: activeUserFilterUserID) {
            activeUserFilterUserID = nil
        } else {
            activeUserFilterUserID = ownerID
        }
    }

    private var identityHeaderHighlight: some View {
        Capsule(style: .continuous)
            .fill(isHeaderFilterActive ? Color(uiColor: .systemGray5) : .clear)
    }

    private func isPrivate(_ att: Attachment) -> Bool {
        let id = att.value(forKey: "id") as? UUID
        // Resolve a stable URL if possible
        let url = attachmentFileURL(att)
        return AttachmentPrivacy.isPrivate(id: id, url: url)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: isYearCompactJournalRow ? 2 : (isMonthCompactJournalRow ? 3 : 6)) {
                // Identity header
                if scope != .mine,
                   let ownerIDNonEmpty = activeHeaderFilterOwnerID,
                   !ownerIDNonEmpty.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            // Avatar 32pt circle
                            Button(action: { showPeek = true }) {
                            Group {
                                #if canImport(UIKit)
                                let ownerAvatarKey = viewerIsOwner ? (auth.backendAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : ""
                                let ownerAvatarCacheKey = "avatars|\(ownerAvatarKey)"

                                if let img = ProfileStore.avatarImage(for: ownerIDNonEmpty) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else if viewerIsOwner, !ownerAvatarKey.isEmpty, let cached = RemoteAvatarImageCache.get(ownerAvatarCacheKey) {
                                    Image(uiImage: cached)
                                        .resizable()
                                        .scaledToFill()
                                } else if viewerIsOwner, !ownerAvatarKey.isEmpty, let remoteAvatar {
                                    Image(uiImage: remoteAvatar)
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
                                    .task(id: ownerAvatarKey) {
                                        guard viewerIsOwner, !ownerAvatarKey.isEmpty else {
                                            remoteAvatar = nil
                                            return
                                        }
                                        if RemoteAvatarImageCache.get(ownerAvatarCacheKey) != nil { return }
                                        if let ui = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: ownerAvatarKey) {
                                            remoteAvatar = ui
                                        }
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
                                let local = ProfileStore.location(for: ownerIDNonEmpty).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !local.isEmpty { return local }

                                let canonicalOwner = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                if !canonicalOwner.isEmpty {
                                    if let acct = BackendFeedStore.shared.directoryAccountsByUserID[canonicalOwner],
                                       let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                        return s
                                    }
                                    let lower = canonicalOwner.lowercased()
                                    if let acct = BackendFeedStore.shared.directoryAccountsByUserID[lower],
                                       let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                        return s
                                    }
                                }
                                return ""
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(realName)
                                .font(.subheadline.weight(.semibold))
                            if !loc.isEmpty {
                                Text(loc)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        

                        }
                        .background(
                            identityHeaderHighlight
                                .padding(.trailing, -12)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleHeaderUserFilter(ownerID: ownerIDNonEmpty)
                        }
                        .accessibilityLabel(isHeaderFilterActive ? "Clear user filter" : "Filter feed to this user")

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 0) // tighter feed identity-to-title spacing
                }

                if scope != .mine, let dt = dateTimeLine {
                    Text(dt)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .padding(.bottom, 1)
                        .accessibilityLabel("Date and time")
                        .accessibilityIdentifier("row.datetime")
                }

                // Title only (paperclip removed)
                Text(feedTitle)
                    .font(isYearCompactJournalRow ? .subheadline.weight(.semibold) : (isMonthCompactJournalRow ? .subheadline.weight(.medium) : .headline))
                    .lineLimit(isYearCompactJournalRow ? 1 : 2)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("row.title")

                if scope == .mine {
                    let metaLine = isYearCompactJournalRow ? yearCompactMetadataLine : journalMetadataLine
                    let thread = journalThreadLabel
                    let tailLine = isYearCompactJournalRow ? yearCompactMetadataTailLine : journalMetadataTailLine

                    if let thread, !thread.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Button {
                                if selectedThread == thread {
                                    selectedThread = nil
                                } else {
                                    selectedThread = thread
                                }
                            } label: {
                                ThreadMetaPill(title: thread, isSelected: selectedThread == thread, font: .caption, verticalPadding: 1)
                            }
                            .buttonStyle(.plain)

                            if !tailLine.isEmpty {
                                Text("· \(tailLine)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.top, isYearCompactJournalRow ? 0 : (isMonthCompactJournalRow ? 1 : 2))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Session metadata")
                        .accessibilityIdentifier("row.subtitle")
                    } else if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.top, isYearCompactJournalRow ? 0 : (isMonthCompactJournalRow ? 1 : 2))
                            .accessibilityLabel("Session metadata")
                            .accessibilityIdentifier("row.subtitle")
                    }

                    if showsJournalNotesPreview, let notesPreviewText {
                        Text(notesPreviewText)
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.96))
                            .lineLimit(2)
                            .padding(.top, metaLine.isEmpty ? 4 : 6)
                            .accessibilityLabel("Notes preview")
                            .accessibilityIdentifier("row.notesPreview")
                    }
                } else {
                    // Instrument / Activity subtitle (metadata) — Thread pill when present (local-only)
                    let metaLine = instrumentActivityLine
                    let thread = journalThreadLabel

                    if let thread, !thread.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Button {
                                if selectedThread == thread {
                                    selectedThread = nil
                                } else {
                                    selectedThread = thread
                                }
                            } label: {
                                ThreadMetaPill(title: thread, isSelected: selectedThread == thread)
                            }
                            .buttonStyle(.plain)

                            if !metaLine.isEmpty {
                                Text("·")
                                    .font(Theme.Text.body)

                                Text(metaLine)
                                    .font(Theme.Text.body)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 3)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Instrument and activity")
                        .accessibilityIdentifier("row.subtitle")
                    } else if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(Theme.Text.body)
                            .lineLimit(2)
                            .padding(.top, 3)
                            .accessibilityLabel("Instrument and activity")
                            .accessibilityIdentifier("row.subtitle")
                    }
                }

                if showsJournalAttachmentPreview, let fav = favoriteAttachment {
                    // If viewer isn't the owner, hide preview when favorite is private
                    if viewerIsOwner || !isPrivate(fav) {
                        HStack(alignment: .center, spacing: 8) {
                            SingleAttachmentPreview(attachment: fav)
                                .scaleEffect(scope == .mine ? 0.92 : 1.0, anchor: .leading)
                                .opacity(scope == .mine ? 0.96 : 1.0)
                            Spacer()
                        }
                        .padding(.top, scope == .mine ? (isMonthCompactJournalRow ? 3 : 5) : 2)
                    }
                    // Interaction row (Like · Comment · Share) — placed directly under thumbnail when present
                    if let sid = sessionUUID {
                        interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                            .padding(.top, scope == .mine ? (isMonthCompactJournalRow ? 4 : 7) : 6)
                    }
                }
                // Fallback: if there is no thumbnail, place the interaction row below the subtitle
                else if !isYearCompactJournalRow, let sid = sessionUUID {
                    interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                        .padding(.top, scope == .mine ? (isMonthCompactJournalRow ? 4 : 7) : 6)
                }
            }
        }
                .padding(.horizontal, isYearCompactJournalRow ? 12 : 0)
        .padding(.vertical,
            isYearCompactJournalRow ? 1 :
            (isMonthCompactJournalRow ? 3 :
                (scope == .mine ? (!attachments.isEmpty ? 9 : 7) : (!attachments.isEmpty ? 10 : 6)))
        )
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
            if auth.isConnected, let postID = sessionUUID {
                let raw = (auth.backendUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let viewerBackendID = raw.isEmpty ? nil : raw.lowercased()
                if let viewerBackendID {
                    CommentsView(
                        postID: postID,
                        ownerUserID: viewerBackendID,
                        viewerUserID: viewerBackendID,
                        ownerDisplayName: auth.displayName,
                        placeholderAuthor: "You"
                    )
                } else {
                    Text("Comments unavailable for this item.").padding()
                }
            } else if let id = sessionIDForComments {
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
                        .foregroundStyle(isSavedLocal ? Color.red.opacity(0.75) : Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSavedLocal ? "Unsave" : "Save")

            if scope != .mine {
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
                        Image(systemName: hasComments ? "text.bubble" : "bubble.right")
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
            }

            Spacer(minLength: 0)

            if attachmentCount > 0 {
                AttachmentCountBadge(count: attachmentCount)
            }
        }
        .padding(.top, scope == .mine ? -1 : -2)
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isShareSheetPresented) {
            ShareToFollowerSheet(postID: sessionID, isPresented: $isShareSheetPresented)
        }
    }

    private func shareText() -> String {
        let title = SessionActivity.feedTitle(for: session)
        return "Check out my session: \(title) — via Études"
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
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    if let handle = acct.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !handle.isEmpty {
                        Text("@\(handle)")
                            .font(Theme.Text.body)
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




// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260214_103700_Etudes_ShareTo_InlineNav

fileprivate struct ShareToFollowerSheet: View {
    let postID: UUID
    @Binding var isPresented: Bool

    @State private var isSharing: Bool = false
    @State private var errorLine: String? = nil

    @State private var directory: [String: DirectoryAccount] = [:]
    @State private var isDirectoryLoading: Bool = false

    private var followerIDs: [String] {
        Array(FollowStore.shared.followers)
    }

    private func normalized(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A–Z by display name (case/diacritic insensitive), with fallback:
    /// 1) displayName
    /// 2) handle (accountID)
    /// 3) stable internal ID (never rendered)
    private func sortKey(for userID: String) -> (String, String, String) {
        if let acct = directory[userID] {
            let name = normalized(acct.displayName)
            let handle = normalized(acct.accountID ?? "")
            let primary = !name.isEmpty ? name : (!handle.isEmpty ? handle : normalized(userID))
            return (primary, handle, normalized(userID))
        } else {
            // Directory missing: keep stable ordering but never render raw IDs.
            return ("", "", normalized(userID))
        }
    }

    private var followerIDsSorted: [String] {
        followerIDs.sorted { a, b in
            let ka = sortKey(for: a)
            let kb = sortKey(for: b)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return ka.2 < kb.2
        }
    }

    private func loadDirectoryIfNeeded() async {
        guard !isDirectoryLoading else { return }
        let ids = followerIDs
        guard !ids.isEmpty else { return }

        isDirectoryLoading = true
        defer { isDirectoryLoading = false }

        let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids)
        switch result {
        case .success(let map):
            directory = map
        case .failure:
            // UI-only polish: keep the picker functional, but never show raw IDs.
            directory = [:]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let errorLine {
                    Text(errorLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }

                if followerIDsSorted.isEmpty {
                    VStack(spacing: 8) {
                        Text("No approved followers yet.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .padding(.top, 24)
                    Spacer()
                } else {
                    List {
                        ForEach(followerIDsSorted, id: \.self) { followerID in
                            Button(action: {
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
                            }) {
                                let acct = directory[followerID]
                                PeopleUserRow(
                                    userID: followerID,
                                    overrideDisplayName: acct?.displayName ?? "User",
                                    overrideSubtitle: acct?.accountID.map { "@\($0)" },
                                    overrideAvatarKey: acct?.avatarKey
                                ) {
                                    EmptyView()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isSharing)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .appBackground()
                }
            }
            .appBackground()
            .navigationTitle("Share to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.left")
                    }
                }
            }
.task {
                await loadDirectoryIfNeeded()
            }
        }
    }
}

fileprivate struct RemotePostRowTwin: View {
    let post: BackendPost
    let scope: FeedScope
    let viewerUserID: String?
    @Binding var activeUserFilterUserID: String?
    let activeEnsembleMemberUserIDs: Set<String>

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var backendFeedStore: BackendFeedStore = BackendFeedStore.shared

    @State private var showPeek: Bool = false
    @State private var isSavedLocal: Bool = false
    @State private var isRemoteCommentsPresented: Bool = false

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

    private var isHeaderFilterActive: Bool {
        guard scope == .all else { return false }
        return isActiveUserFilter(ownerIDNonEmpty, activeUserFilterUserID: activeUserFilterUserID)
            || isActiveEnsembleMember(ownerIDNonEmpty, activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs)
    }

    private func toggleHeaderUserFilter(ownerID: String) {
        guard scope == .all else { return }
        if isActiveUserFilter(ownerID, activeUserFilterUserID: activeUserFilterUserID) {
            activeUserFilterUserID = nil
        } else {
            activeUserFilterUserID = ownerID
        }
    }

    private var identityHeaderHighlight: some View {
        Capsule(style: .continuous)
            .fill(isHeaderFilterActive ? Color(uiColor: .systemGray5) : .clear)
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

    private var recognizedDefaultDescriptions: [String] {
        let parts = ["Morning", "Afternoon", "Evening", "Late Night"]
        return parts.map { "\($0) \(activityName)" }
    }

    private var isUsingDefaultDescription: Bool {
        let desc = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else { return false }
        if desc.caseInsensitiveCompare(defaultDescription) == .orderedSame { return true }
        return recognizedDefaultDescriptions.contains { desc.caseInsensitiveCompare($0) == .orderedSame }
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
                        HStack(alignment: .center, spacing: 8) {
                            // Avatar 32pt circle
                            Button(action: { showPeek = true }) {
                            DirectoryAvatarCircle(
                                ownerID: owner,
                                displayName: (resolvedDirectoryAccount?.displayName ?? (viewerIsOwner ? "You" : "User")),
                                directoryAvatarKey: (viewerIsOwner ? auth.backendAvatarKey : resolvedDirectoryAccount?.avatarKey)
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
                                if let canonicalOwner = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !canonicalOwner.isEmpty {
                                    let canonicalLocal = ProfileStore.location(for: canonicalOwner).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !canonicalLocal.isEmpty { return canonicalLocal }
                                }

                                let local = ProfileStore.location(for: owner).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !local.isEmpty { return local }

                                if let acct = resolvedDirectoryAccount,
                                   let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !s.isEmpty {
                                    return s
                                }

                                if let canonicalOwner = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !canonicalOwner.isEmpty {
                                    if let acct = backendFeedStore.directoryAccountsByUserID[canonicalOwner],
                                       let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !s.isEmpty {
                                        return s
                                    }

                                    let lower = canonicalOwner.lowercased()
                                    if let acct = backendFeedStore.directoryAccountsByUserID[lower],
                                       let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !s.isEmpty {
                                        return s
                                    }
                                }

                                return ""
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


                        VStack(alignment: .leading, spacing: 2) {
                            Text(realName)
                                .font(.subheadline.weight(.semibold))
                            if !loc.isEmpty {
                                Text(loc)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        

                        }
                        .background(
                            identityHeaderHighlight
                                .padding(.trailing, -12)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleHeaderUserFilter(ownerID: owner)
                        }
                        .accessibilityLabel(isHeaderFilterActive ? "Clear user filter" : "Filter feed to this user")

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 0)
                }

                if let dt = dateTimeLine {
                    Text(dt)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .padding(.bottom, 1)
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
                        .font(Theme.Text.body)
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
        .sheet(isPresented: $isRemoteCommentsPresented) {
            let owner = (post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            let viewer = (viewerUserID ?? auth.backendUserID ?? auth.currentUserID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !owner.isEmpty, !viewer.isEmpty {
                CommentsView(
                    postID: post.id,
                    ownerUserID: owner,
                    viewerUserID: viewer,
                    ownerDisplayName: resolvedDirectoryAccount?.displayName,
                    placeholderAuthor: "You"
                )
                .environment(\.managedObjectContext, ctx)
                .environmentObject(auth)
            } else {
                EmptyView()
            }
        }

    }


// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
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
                        .foregroundStyle(isSavedLocal ? Color.red.opacity(0.75) : Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSavedLocal ? "Unsave" : "Save")

            // Comment
            Button(action: {
                let owner = (post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                let viewer = (viewerUserID ?? auth.backendUserID ?? auth.currentUserID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !owner.isEmpty, !viewer.isEmpty else { return }
                isRemoteCommentsPresented = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: CommentPresenceStore.shared.hasComments(postID: post.id) ? "text.bubble" : "bubble.right")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

       

            Spacer(minLength: 0)

            if attachmentCount > 0 {
                AttachmentCountBadge(count: attachmentCount)
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
                .font(Theme.Text.body)
                .foregroundStyle(Theme.Colors.secondaryText)

            Spacer()
        }
        .padding(Theme.Spacing.l)
        .appBackground()
        // No navigationTitle here — keep it quiet.
    }
}


// MARK: - Thread label sanitizer (shared)

fileprivate enum ThreadLabelSanitizer {
    /// Trims, collapses internal whitespace, enforces max length, and returns nil for empty.
    static func sanitize(_ raw: String, maxLength: Int = 32) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collapsed = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }

        if collapsed.count <= maxLength {
            return collapsed
        } else {
            let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
            return String(collapsed[..<idx])
        }
    }
}
