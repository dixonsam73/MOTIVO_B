// CHANGE-ID: 20260521_153000_ContentViewJournalTintResolverPass3
// SCOPE: ContentView Pass 3 — extract Journal tint derivation into ContentViewJournalTintResolver; preserve UI, filtering, routing, backend behaviour, and state ownership.
// SEARCH-TOKEN: 20260521_153000_ContentViewJournalTintResolverPass3

// CHANGE-ID: 20260520_223500_ContentViewJournalSectionBuilderPass2
// SCOPE: ContentView Pass 2 — extract Journal section/date/model construction into ContentViewJournalSectionBuilder; preserve UI, filtering, routing, backend behaviour, and state ownership.
// SEARCH-TOKEN: 20260520_223500_ContentViewJournalSectionBuilderPass2

// CHANGE-ID: 20260520_211500_ContentViewRowExtractionPass1
// SCOPE: ContentView row subsystem extraction pass 1; remove moved row/support declarations only, preserve orchestration, filtering, routing, and behaviour.
// SEARCH-TOKEN: 20260520_211500_ContentViewRowExtractionPass1

// CHANGE-ID: 20260518_223800_RelationalUnseenCountCentralization
// SCOPE: Centralize relational unseen count derivation via RelationalUnseenCountStore; preserve existing UI, routing, and clearing semantics; backend, layout, or routing enum changes.
// SEARCH-TOKEN: 20260518_223800_RelationalUnseenCountCentralization

// CHANGE-ID: 20260518_161900_FilterIconTimelinePulse
// SCOPE: ContentView filter header icon pulse now uses the People button TimelineView sine-wave animation when filters are active and collapsed. No filter logic, layout, navigation, or UI changes outside this icon animation.
// SEARCH-TOKEN: 20260518_161900_FilterIconTimelinePulse

// CHANGE-ID: 20260518_111500_CV_ThreadChipMicroParity
// SCOPE: Visual-only — align Journal Thought thread chip selected-state parity with session rows; no filter, leader, Feed, or layout changes.
// SEARCH-TOKEN: 20260518_111500_CV_ThreadChipMicroParity

// CHANGE-ID: 20260505_174500_ContentView_SaveHint
// SCOPE: Add one-time inline Save helper above existing heart action rows only; no save/backend/layout behaviour changes.
// SEARCH-TOKEN: 20260505_174500_ContentView_SaveHint
// CHANGE-ID: 20260504_180500_ContentView_JournalThoughtSaveParity
// SCOPE: Journal Week Thought rows only — add existing viewer-local Save heart control beneath Thought content using FeedInteractionStore; no Feed/session/detail/filter/model/backend changes.
// SEARCH-TOKEN: 20260504_180500_ContentView_JournalThoughtSaveParity

// CHANGE-ID: 20260504_174500_ThoughtsContentFilter
// SCOPE: Add Content filter row for All/Sessions/Thoughts and compose it through Journal Week, Journal Month, Feed, Saved, and search placeholder only; no model/backend/analytics/card visual changes.
// SEARCH-TOKEN: 20260504_174500_ThoughtsContentFilter

// CHANGE-ID: 20260513_171900_ThoughtThreadDisplayParity
// SCOPE: Thought thread display parity for Journal Week and Month Thought rows only; add subdued thread chip continuity display while preserving Year, analytics, metrics, backend, tint, and existing session row logic.
// SEARCH-TOKEN: 20260513_171900_ThoughtThreadDisplayParity

// CHANGE-ID: 20260430_175500_ContentView_FeedThoughtIdentityHeader
// SCOPE: ContentView Feed only — route local Thought posts through the existing SessionRow Feed wrapper so identity header and actions remain shared; Thought-specific rendering is limited to the content block; no Journal/backend/model changes.
// SEARCH-TOKEN: 20260430_175500_ContentView_FeedThoughtIdentityHeader

// CHANGE-ID: 20260430_170000_ContentView_JournalWeekThoughtDensity
// SCOPE: ContentView — Journal Week Thought cards only: tighten internal vertical rhythm and soften Thought typography without changing Feed, session cards, Month/Year, thumbnail size, or card container system.
// SEARCH-TOKEN: 20260430_170000_ContentView_JournalWeekThoughtDensity

// CHANGE-ID: 20260430_181500_ContentView_FinalRenderFeedPrivacyGate
// SCOPE: ContentView - fail-close final Feed render source so private local rows cannot flash from live or frozen feed items; no UI/schema/backend changes.
// SEARCH-TOKEN: 20260430_181500_ContentView_FinalRenderFeedPrivacyGate

// CHANGE-ID: 20260430_170500_ContentView_EarlyFeedPrivacyGate
// SCOPE: ContentView privacy only — exclude all private local rows at the earliest Feed filtering branch to prevent private Thoughts flashing during Journal→Feed transitions; no visual/backend/schema changes.
// SEARCH-TOKEN: 20260430_170500_ContentView_EarlyFeedPrivacyGate

// CHANGE-ID: 20260430_164500_ContentView_ThoughtRowFullWidth
// SCOPE: ContentView only — force local Thought rows to use one full-width layout path so short, multiline, and attachment Thoughts share the same card structure; no model/backend/filter changes.
// SEARCH-TOKEN: 20260430_164500_ContentView_ThoughtRowFullWidth

// CHANGE-ID: 20260430_151500_ContentView_ThoughtPolishPass2Safe
// SCOPE: ContentView only — restore Thought rows to neutral SessionRow card containers, keep notes-first internals, ensure private Thoughts are excluded from Feed without new service calls, and render backend Thoughts with Thought layout; no model/schema/backend/analytics or other file changes.
// SEARCH-TOKEN: 20260430_151500_ContentView_ThoughtPolishPass2Safe

// CHANGE-ID: 20260429_222500_ContentView_MonthTintInsetSource
// SCOPE: ContentView - Month journal yearCompact row inset only: reserve leader text inset from resolved Month tint source instead of per-row accent presence; preserve Week/Year/tint/thread/filter/backend behavior.
// SEARCH-TOKEN: 20260429_222500_ContentView_MonthTintInsetSource

// CHANGE-ID: 20260429_145500_ContentView_ThreadTintWiring
// SCOPE: ContentView - wire Thread tint counts and labels into owner-local Journal tint resolution; preserve existing instrument/activity behavior, filters, layout, navigation, backend surfaces, and row rendering.
// SEARCH-TOKEN: 20260429_145500_ContentView_ThreadTintWiring

// CHANGE-ID: 20260426_184250_PeoplePulseCancelFix_a81f
// SCOPE: Cancel People notification pulse in-place when unseen People notifications clear; preserve existing single-icon notification behaviour
// SEARCH-TOKEN: 20260426_184250_PeoplePulseCancelFix_a81f

// CHANGE-ID: 20260426_180020_PeoplePulseRestartFix_9f4c
// SCOPE: Restart People notification icon pulse on feed re-entry/relaunch when unseen items already exist; no layout/navigation/store changes
// SEARCH-TOKEN: 20260426_180020_PeoplePulseRestartFix_9f4c

// CHANGE-ID: 20260424_131500_ContentView_StableTintCorpus_NoAutoPersist_7d2a
// SCOPE: ContentView tint decision wiring only - use an unfiltered owner-local tint corpus for Journal Week/Month/Year tint source decisions and prevent render-time Auto tint persistence. Preserve all filtering, layout, navigation, row rendering, and palette behavior.
// SEARCH-TOKEN: 20260424_131500_ContentView_StableTintCorpus_NoAutoPersist_7d2a

// CHANGE-ID: 20260424_103000_ContentView_LocalVideoPosterCache_9f3a
// SCOPE: ContentView only - add an in-memory cache for local video attachment posters used by Journal row previews; preserve existing layout, navigation, feed behavior, and thumbnail generation logic.
// SEARCH-TOKEN: 20260424_103000_ContentView_LocalVideoPosterCache_9f3a

// CHANGE-ID: 20260421_183700_ContentView_JournalTintResolverPass_7c2d
// SCOPE: Journal tint resolver wiring only — owner-local Journal Week/Month/Year now resolve tint source through Theme.resolvedTint / resolvedTintSource, aligned with extracted Year month row file. No feed, layout, routing, spacing, or behavior changes.
// SEARCH-TOKEN: 20260421_183700_ContentView_JournalTintResolverPass_7c2d

// CHANGE-ID: 20260420_165900_ContentView_FilterBarExtractionSafetyPass1_7f2a
// SCOPE: ContentView only — extract the filter-card rendering cluster into a separate file with no behavior, spacing, navigation, data-flow, or visual changes. Keep all list, anchor, Journal, Feed, and row rendering logic in ContentView.
// SEARCH-TOKEN: 20260420_165900_ContentView_FilterBarExtractionSafetyPass1_7f2a

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
// CHANGE-ID: 20260424_122000_ContentView_FilterIconActiveIndicator_a8c4
// SCOPE: ContentView only — add a subtle active-filter visual state to the collapsed filter icon while preserving all filter logic, row rendering, tint resolution, navigation, and backend behavior.
// SEARCH-TOKEN: 20260424_122000_ContentView_FilterIconActiveIndicator_a8c4


#if canImport(UIKit)
enum ContentViewKeyboardDismiss {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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



enum FeedJournalAlignmentUI {
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

enum ActivityType: Int16, CaseIterable, Identifiable {
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

enum FeedScope: String, CaseIterable, Identifiable {
    case mine = "Journal"
    case all = "Feed"
    var id: String { rawValue }
}

enum JournalTimeLens: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    var id: String { rawValue }
}

// Unified feed rows for ContentView List rendering (Local Core Data sessions + Remote backend posts).
struct FeedRowItem: Identifiable {
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
enum ActivityFilter: Hashable, Identifiable {
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


enum ContentFilter: String, CaseIterable, Identifiable {
    case all
    case sessions
    case thoughts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .sessions: return "Sessions"
        case .thoughts: return "Thoughts"
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .all: return "Search"
        case .sessions: return "Search sessions"
        case .thoughts: return "Search thoughts"
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


struct JournalYearMonthRowModel: Identifiable {
    let id: String
    let monthStart: Date
    let year: Int
    let monthLabel: String
    let totalSeconds: Int
    let sessionCount: Int
    let metadataText: String?
    let dominantInstrumentLabel: String?
    let dominantActivityLabel: String?
    let dominantThreadLabel: String?
    let ownerUserID: String?
    let tintSource: Theme.ResolvedTintSource
    let widthFraction: CGFloat
    let densityFraction: CGFloat
    let isFutureMonth: Bool
    let isCurrentMonth: Bool

    var hasSessions: Bool { sessionCount > 0 }
}

fileprivate struct SessionsRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appRoute: AppRouteStore

    @State private var showPublishSkipOversizeAlert = false
    @State private var publishSkipOversizeMessage = ""
    @AppStorage("appSettings_tintMode") private var tintModeRawValue: String = Theme.TintMode.auto.rawValue

    // Phase 14.1: make follow requests reactive in this view (badge)
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var ensembleStore = EnsembleStore.shared


    @ObservedObject private var unreadCommentsStore = UnreadCommentsStore.shared
    @ObservedObject private var relationalUnseenCountStore = RelationalUnseenCountStore.shared

    @StateObject private var sharedWithYouStore = SharedWithYouStore.shared
    let userID: String?
    let backendUserID: String?

    @State private var filtersExpanded = false
    @AppStorage("BackendModeChangeTick_v1") private var backendModeChangeTick: Int = 0
    @State private var selectedInstrument: Instrument? = nil
    @State private var selectedActivity: ActivityFilter = .any
    @State private var selectedContentFilter: ContentFilter = .all
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
        .onChange(of: selectedScope) {  _, newValue in
            #if canImport(UIKit)
            ContentViewKeyboardDismiss.dismiss()
            #endif
            isAwaitingFeedFetchStart = (newValue == .all) && useBackendFeed
        }
        .onChange(of: backendFeedStore.isFetching) {  _, isFetching in
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
                            ZStack {
                                if filterHeaderIndicatorActive {
                                    Capsule(style: .continuous)
                                        .fill(Theme.Colors.accent.opacity(0.14))
                                }

                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(
                                        filterHeaderIndicatorActive
                                        ? Theme.Colors.accent
                                        : Theme.Colors.secondaryText
                                    )
                            }
                            .frame(width: 34, height: 26)
                            .animation(.none, value: filterHeaderIndicatorActive)
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
                        selectedContentFilter: $selectedContentFilter,
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
                                if selectedScope == .mine,
                                   selectedJournalLens == .month,
                                   let firstMonthSection = journalYearSections(sessions: journalArchiveSessions).first {
                                    proxy.scrollTo(journalMonthSectionAnchorID(for: firstMonthSection), anchor: .top)
                                } else {
                                    proxy.scrollTo(topID, anchor: .top)
                                }
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

                                // Defence-in-depth: local Feed rows have already passed the shared isPublic gate
                                // in filteredSessions, but keep the source array fail-closed here too.
                                let feedVisibleLocalRows = localRows.filter { $0.isPublic }

                                func normalizedOwnerID(_ raw: String?) -> String {
                                    (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                }

                                let me = normalizedOwnerID(effectiveUserID)
                                guard !me.isEmpty else { return feedVisibleLocalRows }

                                if hasExplicitFeedNarrowing {
                                    return feedVisibleLocalRows
                                }

                                let hasEligibleNonOwnerLocalPost = feedVisibleLocalRows.contains {
                                    normalizedOwnerID($0.ownerUserID) != me
                                }

                                let hasEligibleNonOwnerRemotePost = remotePosts.contains {
                                    normalizedOwnerID($0.ownerUserID) != me
                                }

                                guard !(hasEligibleNonOwnerLocalPost || hasEligibleNonOwnerRemotePost) else {
                                    return feedVisibleLocalRows
                                }

                                return feedVisibleLocalRows.filter { normalizedOwnerID($0.ownerUserID) != me }
                            }()

                            let liveFeedItems: [FeedRowItem] = FeedRowItem.build(
                                local: finalLocalRowsForFeed,
                                remote: remotePosts
                            )

                            let renderFeedItems: [FeedRowItem] = {
                                let source = (isFeedNavFrozen && !frozenFeedItems.isEmpty) ? frozenFeedItems : liveFeedItems
                                guard selectedScope == .all else { return source }

                                // Final render gate: private local rows must never reach the Feed ForEach,
                                // including stale/frozen items captured during scope transitions.
                                return source.filter { item in
                                    switch item.kind {
                                    case .local(let session):
                                        return session.isPublic
                                    case .remote(let post):
                                        return post.isPublic == true
                                    }
                                }
                            }()

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

                                                    if session.isThought {
                                                        ThoughtRow(
                                                                session: session,
                                                                scope: selectedScope,
                                                                selectedThread: $selectedThread,
                                                                context: .journalWeek,
                                                                viewerUserID: effectiveUserID,
                                                                threadChipFillColor: journalThoughtThreadChipFillColor(for: session),
                                                                threadChipTextColor: journalThoughtThreadChipTextColor(for: session)
                                                            )
                                                            .cardSurface()
                                                            .contentShape(Rectangle())
                                                            .onTapGesture {
                                                                feedNavFreezeTask?.cancel()
                                                                isFeedNavFrozen = true
                                                                frozenFeedItems = renderFeedItems
                                                                pushSessionID = (session.value(forKey: "id") as? UUID)
                                                            }
                                                            .padding(.bottom, rowIndex == section.sessions.count - 1 ? Theme.Spacing.xl : Theme.Spacing.m + 2)
                                                    } else {
                                                        SessionRow(session: session, scope: selectedScope, selectedThread: $selectedThread, activeUserFilterUserID: $activeUserFilterUserID, activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs, filtersExpanded: $filtersExpanded)
                                                            .contentShape(Rectangle())
                                                            .onTapGesture {
                                                                feedNavFreezeTask?.cancel()
                                                                isFeedNavFrozen = true
                                                                frozenFeedItems = renderFeedItems
                                                                pushSessionID = (session.value(forKey: "id") as? UUID)
                                                            }
                                                            .modifier(
                                                                JournalWeekLeadingTintCardModifier(
                                                                    tintColor: journalMonthBarAccentColor(for: session, in: journalWeekTintContextSessions) ?? journalWeekCardFillColor(for: session, in: journalWeekTintContextSessions),
                                                                    strokeColor: journalWeekCardStrokeColor(for: session, in: journalWeekTintContextSessions),
                                                                    showsLeadingTint: journalResolvedTintSource(in: journalWeekTintContextSessions) != .off
                                                                )
                                                            )
                                                            .padding(.bottom, rowIndex == section.sessions.count - 1 ? Theme.Spacing.xl : Theme.Spacing.m + 2)
                                                    }
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
                                    let monthShouldReserveTintInset = journalResolvedTintSource(in: journalTintContextSessions) != .off

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

                                                    Group {
                                                        if session.isThought {
                                                            MonthThoughtRow(
                                                                    session: session,
                                                                    selectedThread: $selectedThread,
                                                                    threadChipFillColor: journalThoughtThreadChipFillColor(for: session),
                                                                    threadChipTextColor: journalThoughtThreadChipTextColor(for: session)
                                                                )
                                                        } else {
                                                            SessionRow(
                                                                session: session,
                                                                scope: selectedScope,
                                                                selectedThread: $selectedThread,
                                                                activeUserFilterUserID: $activeUserFilterUserID,
                                                                activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs,
                                                                filtersExpanded: $filtersExpanded,
                                                                journalStyle: .yearCompact,
                                                                yearCompactHorizontalPadding: monthShouldReserveTintInset ? 12 : 6
                                                            )
                                                            .modifier(
                                                                JournalArchiveRowContainerModifier(
                                                                    lens: usesYearArchivePresentation ? .year : selectedJournalLens,
                                                                    yearWidthFraction: journalYearSurfaceWidthFraction(for: session, maxDuration: journalYearMaxDuration(for: localRows)),
                                                                    barFillColor: journalMonthBarFillColor(for: session, in: journalTintContextSessions),
                                                                    barStrokeColor: journalMonthBarStrokeColor(for: session, in: journalTintContextSessions),
                                                                    barAccentColor: journalMonthBarAccentColor(for: session, in: journalTintContextSessions),
                                                                    barAccentWidth: 6
                                                                )
                                                            )
                                                        }
                                                    }
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        feedNavFreezeTask?.cancel()
                                                        isFeedNavFrozen = true
                                                        frozenFeedItems = renderFeedItems
                                                        pushSessionID = (session.value(forKey: "id") as? UUID)
                                                    }
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
                                    let yearSections = journalCalendarYearSections(sessions: localRows.filter { !$0.isThought })
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
                                                .cardSurface()
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    feedNavFreezeTask?.cancel()
                                                    isFeedNavFrozen = true
                                                    frozenFeedItems = renderFeedItems
                                                    pushSessionID = (session.value(forKey: "id") as? UUID)
                                                }
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
                    .onChange(of: selectedScope) {
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

                                if relationalUnseenCountStore.relationalUnseenCount > 0 {
                                    relationalUnseenCountChip(count: relationalUnseenCountStore.relationalUnseenCount)
                                        .offset(x: 7, y: -7)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityLabel("People")
                    } else {
                        Spacer()
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
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
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.6)
                            .onEnded { _ in
                                isDebugPresented = true
                            }
                    )
#endif
                }
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
                Task { await performPeopleReturnNotificationRefreshBundle() }
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
                consumePendingContentLaunchScopeOverrideIfNeeded()
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

    private func performPeopleReturnNotificationRefreshBundle() async {
        // PeopleView is the modal surface that clears People notifications.
        // Refresh this ContentView's notification stores immediately on return,
        // without the feed-pop suppression/debounce used for general feed refreshes.
        await followStore.refreshFromBackendIfPossible()
        await sharedWithYouStore.refreshUnreadShares()
        await unreadCommentsStore.refresh(force: true)
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
                    // Feed is shared-space only. Private local rows — Thoughts and normal sessions —
                    // must never enter the Feed source array, even briefly during scope transitions.
                    if s.isPublic == false { return false }

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

        // Content (sessions / Thoughts)
        switch selectedContentFilter {
        case .all:
            break
        case .sessions:
            out = out.filter { !$0.isThought }
        case .thoughts:
            out = out.filter { $0.isThought }
        }

        // Instrument (core)
        if let inst = selectedInstrument {
            out = out.filter { !$0.isThought }
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
        if selectedActivity != .any {
            out = out.filter { !$0.isThought }
        }
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

    private var journalTintMode: Theme.TintMode {
        Theme.TintMode(rawValue: tintModeRawValue) ?? .auto
    }

    private func journalInstrumentLabel(for session: Session) -> String? {
        ContentViewJournalTintResolver.instrumentLabel(for: session)
    }

    private func journalActivityLabel(for session: Session) -> String? {
        ContentViewJournalTintResolver.activityLabel(for: session)
    }

    private func journalInstrumentOwnerID(for session: Session) -> String? {
        ContentViewJournalTintResolver.instrumentOwnerID(
            for: session,
            fallbackUserID: effectiveUserID
        )
    }

    private func journalInstrumentCounts(in sessions: [Session]) -> [String: Int] {
        ContentViewJournalTintResolver.instrumentCounts(in: sessions)
    }

    private func journalActivityCounts(in sessions: [Session]) -> [String: Int] {
        ContentViewJournalTintResolver.activityCounts(in: sessions)
    }

    private func journalThreadLabel(for session: Session) -> String? {
        ContentViewJournalTintResolver.threadLabel(for: session)
    }

    private func journalThreadCounts(in sessions: [Session]) -> [String: Int] {
        ContentViewJournalTintResolver.threadCounts(in: sessions)
    }

    private func journalResolvedTintSource(in sessions: [Session]) -> Theme.ResolvedTintSource {
        ContentViewJournalTintResolver.resolvedTintSource(
            in: sessions,
            tintMode: journalTintMode
        )
    }

    private func journalResolvedTint(for session: Session, in sessions: [Session]) -> Theme.ResolvedTint {
        ContentViewJournalTintResolver.resolvedTint(
            for: session,
            in: sessions,
            tintMode: journalTintMode
        )
    }

    private func journalWeekCardFillColor(for session: Session, in sessions: [Session]) -> Color {
        ContentViewJournalTintResolver.weekCardFillColor(
            for: session,
            in: sessions,
            tintMode: journalTintMode,
            fallbackUserID: effectiveUserID,
            colorScheme: colorScheme
        )
    }

    private func journalWeekCardStrokeColor(for session: Session, in sessions: [Session]) -> Color {
        ContentViewJournalTintResolver.weekCardStrokeColor(
            for: session,
            in: sessions,
            tintMode: journalTintMode,
            fallbackUserID: effectiveUserID,
            colorScheme: colorScheme
        )
    }

    private func journalMonthBarFillColor(for session: Session, in sessions: [Session]) -> Color {
        ContentViewJournalTintResolver.monthBarFillColor(
            for: session,
            in: sessions,
            tintMode: journalTintMode,
            fallbackUserID: effectiveUserID,
            colorScheme: colorScheme
        )
    }

    private func journalMonthBarStrokeColor(for session: Session, in sessions: [Session]) -> Color {
        ContentViewJournalTintResolver.monthBarStrokeColor(
            for: session,
            in: sessions,
            tintMode: journalTintMode,
            fallbackUserID: effectiveUserID,
            colorScheme: colorScheme
        )
    }

    private func journalMonthBarAccentColor(for session: Session, in sessions: [Session]) -> Color? {
        ContentViewJournalTintResolver.monthBarAccentColor(
            for: session,
            in: sessions,
            tintMode: journalTintMode,
            fallbackUserID: effectiveUserID,
            colorScheme: colorScheme
        )
    }

    private func journalThoughtThreadTint(for session: Session) -> Theme.ResolvedTint? {
        ContentViewJournalTintResolver.thoughtThreadTint(
            for: session,
            tintMode: journalTintMode,
            contextSessions: journalTintContextSessions
        )
    }

    private func journalThoughtThreadChipFillColor(for session: Session) -> Color? {
        ContentViewJournalTintResolver.thoughtThreadChipFillColor(
            for: session,
            tintMode: journalTintMode,
            contextSessions: journalTintContextSessions,
            fallbackUserID: effectiveUserID,
            colorScheme: colorScheme
        )
    }

    private func journalThoughtThreadChipTextColor(for session: Session) -> Color? {
        ContentViewJournalTintResolver.thoughtThreadChipTextColor(
            for: session,
            tintMode: journalTintMode,
            contextSessions: journalTintContextSessions,
            fallbackUserID: effectiveUserID,
            colorScheme: colorScheme
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
            let isThought = backendPostIsThought(post)

            switch selectedContentFilter {
            case .all:
                break
            case .sessions:
                guard !isThought else { return false }
            case .thoughts:
                guard isThought else { return false }
            }

            if selectedInstrument != nil || selectedActivity != .any || selectedThread != nil {
                guard !isThought else { return false }
            }
            return remoteMatchesSelectedInstrument(post) &&
            remoteMatchesSelectedActivity(post) &&
            remoteMatchesSelectedEnsemble(post) &&
            remoteMatchesActiveUserFilter(post) &&
            remoteMatchesSavedOnly(post) &&
            remoteMatchesSearch(post)
        }
    }

    private func backendPostIsThought(_ post: BackendPost) -> Bool {
        let model = BackendSessionViewModel(post: post, currentUserID: (effectiveBackendUserID ?? ""))
        return BackendThoughtRules.isThought(post: post, model: model)
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


    // JournalSection and JournalYearSectionModel are defined in ContentViewJournalSectionBuilder.swift.

    private var journalGroupingCalendar: Calendar {
        ContentViewJournalSectionBuilder.groupingCalendar
    }

    private func journalWeekStart(for date: Date) -> Date {
        ContentViewJournalSectionBuilder.weekStart(for: date)
    }

    private func journalDate(for session: Session) -> Date {
        ContentViewJournalSectionBuilder.date(for: session)
    }

    private func journalMonthStart(for date: Date) -> Date {
        ContentViewJournalSectionBuilder.monthStart(for: date)
    }

    private func journalYearStart(for date: Date) -> Date {
        ContentViewJournalSectionBuilder.yearStart(for: date)
    }

    private func journalWeekHeaderTitle(for weekStart: Date) -> String {
        ContentViewJournalSectionBuilder.weekHeaderTitle(for: weekStart)
    }

    private func journalWeekDateRangeText(start: Date, end: Date) -> String {
        ContentViewJournalSectionBuilder.weekDateRangeText(start: start, end: end)
    }

    private func journalMonthWeekRangeText(start: Date, end: Date) -> String {
        ContentViewJournalSectionBuilder.monthWeekRangeText(start: start, end: end)
    }

    private var hasAnyJournalContent: Bool {
        sessions.isEmpty == false
    }

    private var filterHeaderIndicatorActive: Bool {
        hasExplicitFeedNarrowing && !filtersExpanded
    }

    @ViewBuilder
    private func relationalUnseenCountChip(count: Int) -> some View {
        let displayCount = count > 99 ? "99+" : "\(count)"

        Text(displayCount)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, count > 9 ? 6 : 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.Colors.accent.opacity(colorScheme == .dark ? 0.20 : 0.13))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.Colors.accent.opacity(colorScheme == .dark ? 0.34 : 0.24), lineWidth: 0.8)
            )
    }

    private func consumePendingContentLaunchScopeOverrideIfNeeded() {
        guard appRoute.pendingContentLaunchScopeOverride == "feed" else { return }
        appRoute.pendingContentLaunchScopeOverride = nil
        selectedScope = .all
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
        let hasSelectedContentFilter = selectedContentFilter != .all

        return hasActiveUserFilter ||
            hasSelectedInstrument ||
            hasSelectedActivity ||
            hasSelectedThread ||
            hasSelectedEnsemble ||
            hasSelectedContentFilter ||
            savedOnly ||
            hasSearchQuery
    }

    private var journalArchiveSessions: [Session] {
        let baseSessions = filteredSessions
        guard selectedScope == .mine else { return baseSessions }
        return baseSessions.sorted { journalDate(for: $0) > journalDate(for: $1) }
    }

    private var journalTintContextSessions: [Session] {
        guard selectedScope == .mine, let uid = effectiveUserID else { return journalArchiveSessions }
        return Array(sessions)
            .filter { $0.ownerUserID == uid && !$0.isThought }
            .sorted { journalDate(for: $0) > journalDate(for: $1) }
    }

    private var journalWeekTintContextSessions: [Session] {
        journalTintContextSessions
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
        journalCurrentPeriodSessions.filter { !$0.isThought }.reduce(0) { partial, session in
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
        ContentViewJournalSectionBuilder.weekSections(sessions: sessions)
    }

    private func journalMonthSections(sessions: [Session]) -> [JournalSection] {
        ContentViewJournalSectionBuilder.monthSections(sessions: sessions)
    }

    private func journalYearSections(sessions: [Session]) -> [JournalSection] {
        ContentViewJournalSectionBuilder.yearSections(sessions: sessions)
    }

    private func journalCalendarYearSections(sessions: [Session]) -> [JournalYearSectionModel] {
        ContentViewJournalSectionBuilder.calendarYearSections(
            sessions: sessions,
            tintSource: journalResolvedTintSource(in: journalTintContextSessions),
            fallbackOwnerUserID: effectiveUserID
        )
    }

    private func journalCurrentMonthAnchorID(in sections: [JournalYearSectionModel]) -> String? {
        ContentViewJournalSectionBuilder.currentMonthAnchorID(in: sections)
    }

    private func journalMonthSectionAnchorID(for monthStart: Date) -> String {
        ContentViewJournalSectionBuilder.monthSectionAnchorID(for: monthStart)
    }

    private func journalMonthSectionAnchorID(for section: JournalSection) -> String {
        ContentViewJournalSectionBuilder.monthSectionAnchorID(for: section)
    }

    private func hasVisibleJournalMonthSection(for monthStart: Date, in sessions: [Session]) -> Bool {
        ContentViewJournalSectionBuilder.hasVisibleMonthSection(for: monthStart, in: sessions)
    }

    private func journalDurationSeconds(for session: Session) -> Int {
        ContentViewJournalSectionBuilder.durationSeconds(for: session)
    }

    private func journalYearMaxDuration(for sessions: [Session]) -> Int {
        ContentViewJournalSectionBuilder.yearMaxDuration(for: sessions)
    }

    private func journalYearSurfaceWidthFraction(for session: Session, maxDuration: Int) -> CGFloat {
        ContentViewJournalSectionBuilder.yearSurfaceWidthFraction(for: session, maxDuration: maxDuration)
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


fileprivate struct JournalWeekLeadingTintCardModifier: ViewModifier {
    let tintColor: Color
    let strokeColor: Color?
    let showsLeadingTint: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        let resolvedStroke = strokeColor ?? Theme.Colors.cardStroke(colorScheme)
        let leaderWidth: CGFloat = 22
        let contentLeadingInset = Theme.Spacing.card + (showsLeadingTint ? leaderWidth - 2 : 0)

        return content
            .padding(.top, Theme.Spacing.card)
            .padding(.trailing, Theme.Spacing.card)
            .padding(.bottom, Theme.Spacing.card)
            .padding(.leading, contentLeadingInset)
            .background {
                ZStack(alignment: .leading) {
                    cardShape
                        .fill(Theme.Colors.surface(colorScheme))

                    if showsLeadingTint {
                        MonthBarLeadingAccentShape(cornerRadius: Theme.Radius.card)
                            .fill(tintColor.opacity(0.8))
                            .frame(width: leaderWidth)
                    }
                }
            }
            .clipShape(cardShape)
            .overlay(
                cardShape
                    .stroke(resolvedStroke, lineWidth: 1)
            )
    }
}





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

