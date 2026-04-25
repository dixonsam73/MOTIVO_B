// CHANGE-ID: 20260425_171120_meview_quality_insight_label_tint_polish
// SCOPE: MeView-only polish for quality insight cards: clearer focus-specific titles, remove secondary avg-focus/time metadata, and tint only the card matching the active tint source. No analytics, layout hierarchy, navigation, Theme, SDV/BSDV, backend, or existing non-target card changes.
// SEARCH-TOKEN: 20260425_171120_meview_quality_insight_label_tint_polish

// CHANGE-ID: 20260425_170300_meview_quality_insights
// SCOPE: MeView-only quality insights layer below Focus card: highest focus session plus duration-weighted best thread/instrument/activity focus cards. No Theme, SDV/BSDV, backend schema, PublishService, or existing card changes.
// SEARCH-TOKEN: 20260425_170300_meview_quality_insights

// CHANGE-ID: 20260425_164850_meview_top_winner_tint_source_fix
// SCOPE: MeView-only tint-source correction: Top activity / Top instrument cards use the active semantic tint source without requiring range-local variation. No layout, analytics, Theme, SDV, Core Data, or backend changes.
// SEARCH-TOKEN: 20260425_164850_meview_top_winner_tint_source_fix

// CHANGE-ID: 20260425_163420_meview_top_winner_tint_cards_build_fix
// SCOPE: MeView-only build fix: keep Top activity / Top instrument tinting, restore StreaksCard neutral card surface. No UI, analytics, Theme, SDV, Core Data, or backend changes.
// SEARCH-TOKEN: 20260425_163420_meview_top_winner_tint_cards_build_fix

// CHANGE-ID: 20260425_161500_meview_top_winner_tint_cards
// SCOPE: MeView-only: tint Top activity / Top instrument winner card backgrounds according to active Theme tint source. No analytics, layout, SDV, Theme, Core Data, or backend changes.
// SEARCH-TOKEN: 20260425_161500_meview_top_winner_tint_cards

// CHANGE-ID: 20260425_112000_meview_focus_card_subtitle_removal
// SCOPE: MeView Focus card polish only: remove subtitle copy and rebalance internal Focus card spacing. No analytics, animation, rendering, Core Data, backend, or other card changes.
// SEARCH-TOKEN: 20260425_112000_meview_focus_card_subtitle_removal

// CHANGE-ID: 20260425_113000_meview_focus_circle_first_appearance_polish
// SCOPE: MeView-only Focus Circle first-appearance animation plus layout reposition/tightening. FocusCircleView, analytics, Core Data, and backend unchanged.
// SEARCH-TOKEN: 20260425_113000_meview_focus_circle_first_appearance_polish

// CHANGE-ID: 20260425_110500_meview_focus_circle_data_repair
// SCOPE: Restore MeView FocusCircle summary and repair local/backend focus aggregation using duration-weighted stored focus values. MeView only.
// SEARCH-TOKEN: 20260425_110500_meview_focus_circle_data_repair

// CHANGE-ID: 20260421_181500_meview_chart_palette_ranked
// SCOPE: Replace MeView time-distribution chart segment and legend colors with a MeView-local analytical rank-based palette. No layout, logic, Theme, ContentView, or Journal tint changes.
// SEARCH-TOKEN: 20260421_181500_meview_chart_palette_ranked

// CHANGE-ID: 20260318_193200_meview_owner_scoped_local_analytics
// SCOPE: Owner-scope MeView local analytics to the current local user ID while preserving backend fallback when no owner-local sessions exist. No UI/layout changes.

// CHANGE-ID: 20260309_170500_meview_backend_owner_fallback_narrow
// SCOPE: Add local-first connected-owner backend analytics fallback only when no local sessions exist on this device. Preserve local MeView behavior, SessionDetailView navigation, and thread analytics; backend mode leaves threads empty and longest/first informational only.
// SEARCH-TOKEN: 20260309_170500_meview_backend_owner_fallback_narrow
// CHANGE-ID: 20260305_103500_timecard_sessioncount_secondary
// SCOPE: MeView TimeCard typography: render session count as secondary text; no layout/logic changes.
// CHANGE-ID: 20260305_094600_meview_thread_analytics_v3
// CHANGE-ID: 20260305_100200_meview_avg_first_session
// SCOPE: MeView analytics: add Average session length + First session in range cards. MeView-only; no other logic/UI changes.
// SCOPE: MeView analytics: add time-by-thread distribution + top thread; rename activity distribution title. No changes outside MeView.
// CHANGE-ID: 20260106_221700-meview-calmtext-scrollindicators
// SCOPE: Visual-only: soften key highlight text + hide scroll indicators in MeView. No logic/state changes.
// CHANGE-ID: 20251015_150332-me-focus-from-notes
// SCOPE: Me dashboard — Focus average parsed from Session.notes token "FocusDotIndex: n" (fallback: legacy StateIndex→center dots).
// NOTES: Timestamp-only predicates; no schema changes.

import SwiftUI
import CoreData
import UIKit

private let kCardMinHeightCompact: CGFloat = 120
private let kCardMinHeightRegular: CGFloat = 140

@inline(__always)
private func baselineCardMinHeight(for hSizeClass: UserInterfaceSizeClass?) -> CGFloat {
    (hSizeClass == .regular) ? kCardMinHeightRegular : kCardMinHeightCompact
}

private struct ActivitySlice { let name: String; let seconds: Int }

private let qualityInsightMinimumDurationSeconds: Double = 300

private struct FocusInsightSession {
    let session: Session
    let title: String
    let date: Date?
    let seconds: Int
    let normalizedFocus: Double
}

private struct FocusCategoryInsight {
    let name: String
    let averageFocus: Double
    let seconds: Int
    let sessionCount: Int
}

private func timeDistribution(from sessions: [Session]) -> [ActivitySlice] {
    var totals: [String: Int] = [:]
    for s in sessions {
        let label = SessionActivity.name(for: s as NSManagedObject).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { continue }
        let secs = (s.value(forKey: "durationSeconds") as? Int) ?? 0
        guard secs > 0 else { continue }
        totals[label, default: 0] += secs
    }
    guard !totals.isEmpty else { return [] }
    let sorted = totals.sorted { $0.value > $1.value }
    let head = Array(sorted.prefix(6))
    let tail = sorted.dropFirst(6)
    let headSlices = head.map { ActivitySlice(name: $0.key, seconds: $0.value) }
    let otherTotal = tail.reduce(0) { $0 + $1.value }
    return otherTotal > 0 ? headSlices + [ActivitySlice(name: "Other", seconds: otherTotal)] : headSlices
}


private struct ThreadAnalyticsResult {
    let title: String
    let slices: [ActivitySlice]
    let uniqueCount: Int
    let top: (name: String, seconds: Int)?
}

private func threadAnalytics(from sessions: [Session]) -> ThreadAnalyticsResult {
    var totals: [String: Int] = [:]
    for s in sessions {
        let raw = s.value(forKey: "threadLabel") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { continue }
        let secs = (s.value(forKey: "durationSeconds") as? Int) ?? 0
        guard secs > 0 else { continue }
        totals[trimmed, default: 0] += secs
    }

    guard !totals.isEmpty else { return .init(title: "Time by thread", slices: [], uniqueCount: 0, top: nil) }

    let sorted = totals.sorted { $0.value > $1.value }
    let uniqueCount = totals.count

    let head = Array(sorted.prefix(6))
    let tail = sorted.dropFirst(6)
    let headSlices = head.map { ActivitySlice(name: $0.key, seconds: $0.value) }
    let otherTotal = tail.reduce(0) { $0 + $1.value }
    let slices = otherTotal > 0 ? headSlices + [ActivitySlice(name: "Other", seconds: otherTotal)] : headSlices

    let top: (name: String, seconds: Int)? = sorted.first.map { ($0.key, $0.value) }

    return .init(title: "Time by thread", slices: slices, uniqueCount: uniqueCount, top: top)
}

private func percent(_ part: Int, of total: Int) -> Int {
    guard total > 0 else { return 0 }
    return Int(round((Double(part) / Double(total)) * 100.0))
}

private func totalSessionsCount(in sessions: [Session]) -> Int { sessions.count }

struct MeView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager
    @AppStorage("appSettings_tintMode") private var tintModeRaw: String = Theme.TintMode.auto.rawValue
    @State private var range: StatsRange = .total
    @State private var sessionStats: SessionStats = .init(count: 0, seconds: 0)
    @State private var avgSessionSeconds: Int64? = nil
    @State private var firstSessionDate: Date? = nil
    @State private var longestSessionSeconds: Int64? = nil
    @State private var longestSessionDate: Date? = nil
    @State private var longestSession: Session? = nil
    @State private var firstSession: Session? = nil
    @State private var selectedInsightSession: Session? = nil
    @State private var bestStreakRangeText: String? = nil
    @State private var currentStreakValue: Int = 0
    @State private var bestStreakValue: Int = 0
    @State private var isBackendAnalyticsMode = false
    @State private var backendAnalyticsLoadKey: String? = nil
    @State private var backendAnalyticsLoading = false

    @State private var allSessions: [Session] = []
    @State private var avgFocus: Double? = nil
    @State private var animatedFocus: Double = 0
    @State private var didRunFocusInitialAnimation = false
    @State private var topInstrumentByTime: (name: String, seconds: Int)? = nil
    @State private var topActivityByTime: (name: String, seconds: Int)? = nil
    @State private var instrumentTintCounts: [String: Int] = [:]
    @State private var activityTintCounts: [String: Int] = [:]
    @State private var timeDistributionSlices: [ActivitySlice] = []
    @State private var threadDistributionSlices: [ActivitySlice] = []
    @State private var instrumentDistributionSlices: [ActivitySlice] = []
    @State private var threadUniqueCountInRange: Int = 0
    @State private var instrumentUniqueCountInRange: Int = 0
    @State private var topThread: (name: String, seconds: Int)? = nil
    @State private var uniqueActivityCount: Int = 0
    @State private var highestFocusSession: FocusInsightSession? = nil
    @State private var bestThreadFocus: FocusCategoryInsight? = nil
    @State private var bestInstrumentFocus: FocusCategoryInsight? = nil
    @State private var bestActivityFocus: FocusCategoryInsight? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                rangePickerHeader
                // Full-width Time card with date range header
                TimeCard(seconds: sessionStats.seconds, count: sessionStats.count, range: $range, dateRange: dateWindowSubtitle(for: range, firstSessionDate: firstSessionDate))
                if let avgFocus {
                    FocusCard(normalizedFocus: animatedFocus)
                        .onAppear {
                            triggerFocusCircleAnimationIfNeeded(targetAverage: avgFocus)
                        }
                }
                if hasQualityInsights {
                    AdaptiveGrid {
                        if let insight = highestFocusSession {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedInsightSession = insight.session
                            } label: {
                                HighestFocusInsightCard(insight: insight)
                            }
                            .buttonStyle(InsightCardButtonStyle())
                        }
                        if let insight = bestThreadFocus {
                            BestFocusCategoryInsightCard(title: "Most focused thread", insight: insight)
                        }
                        if let insight = bestInstrumentFocus {
                            BestFocusCategoryInsightCard(
                                title: "Most focused instrument",
                                insight: insight,
                                fillColor: bestInstrumentFocusCardFillColor,
                                strokeColor: bestInstrumentFocusCardStrokeColor
                            )
                        }
                        if let insight = bestActivityFocus {
                            BestFocusCategoryInsightCard(
                                title: "Most focused activity",
                                insight: insight,
                                fillColor: bestActivityFocusCardFillColor,
                                strokeColor: bestActivityFocusCardStrokeColor
                            )
                        }
                    }
                }
                AdaptiveGrid {
                    StreaksCard(current: currentStreakValue, best: bestStreakValue, bestRangeText: bestStreakRangeText)
                    if let avg = avgSessionSeconds {
                        AverageSessionCard(seconds: avg)
                    }
                    if let longest = longestSessionSeconds, let d = longestSessionDate {
                        if let target = longestSession {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedInsightSession = target
                            } label: {
                                LongestSessionCard(range: range, seconds: longest, date: d)
                            }
                            .buttonStyle(InsightCardButtonStyle())
                        } else {
                            LongestSessionCard(range: range, seconds: longest, date: d)
                        }
                    }
                    if let first = firstSessionDate {
                        if let target = firstSession {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedInsightSession = target
                            } label: {
                                FirstSessionCard(range: range, date: first)
                            }
                            .buttonStyle(InsightCardButtonStyle())
                        } else {
                            FirstSessionCard(range: range, date: first)
                        }
                    }
                    if uniqueActivityCount > 1 {
                        TimeDistributionCard(title: "Time by activity", slices: timeDistributionSlices)
                        TopTimeWinnerCard(
                            title: "Top activity",
                            winner: topActivityByTime,
                            fillColor: topActivityCardFillColor,
                            strokeColor: topActivityCardStrokeColor
                        )
                    }
                    if threadUniqueCountInRange >= 2 {
                        TimeDistributionCard(title: "Time by thread", slices: threadDistributionSlices)
                    }
                    if topThread != nil {
                        TopThreadCard(winner: topThread)
                    }
                    if instrumentUniqueCountInRange >= 2 {
                        TimeDistributionCard(title: "Time by instrument", slices: instrumentDistributionSlices)
                    }
                    if topInstrumentByTime != nil {
                        TopTimeWinnerCard(
                            title: "Top instrument",
                            winner: topInstrumentByTime,
                            fillColor: topInstrumentCardFillColor,
                            strokeColor: topInstrumentCardStrokeColor
                        )
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xl)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await reload() } }
        .onChange(of: range) { _, _ in Task { await reload() } }
        .onChange(of: auth.backendUserID) { _, _ in Task { await reload() } }
        .onChange(of: avgFocus) { _, newValue in
            updateFocusCircleTargetAfterInitialAppearance(newValue)
        }
        .appBackground()
        .background {
            NavigationLink(
                isActive: Binding(
                    get: { selectedInsightSession != nil },
                    set: { isActive in
                        if !isActive { selectedInsightSession = nil }
                    }
                )
            ) {
                if let session = selectedInsightSession {
                    SessionDetailView(session: session)
                } else {
                    EmptyView()
                }
            } label: {
                EmptyView()
            }
            .hidden()
        }
    }

    private func normalizedFocusValue(for average: Double) -> Double {
        let clampedVisualValue = max(1.0, min(10.0, average))
        return (clampedVisualValue - 1.0) / 9.0
    }
    private func triggerFocusCircleAnimationIfNeeded(targetAverage: Double) {
        let target = normalizedFocusValue(for: targetAverage)

        guard didRunFocusInitialAnimation == false else {
            animateFocusCircle(to: target)
            return
        }

        didRunFocusInitialAnimation = true
        animatedFocus = 0

        DispatchQueue.main.async {
            animateFocusCircle(to: target)
        }
    }

    private func updateFocusCircleTargetAfterInitialAppearance(_ average: Double?) {
        guard didRunFocusInitialAnimation, let average else { return }
        animateFocusCircle(to: normalizedFocusValue(for: average))
    }

    private func animateFocusCircle(to target: Double) {
        withAnimation(.easeOut(duration: 5.0)) {
            animatedFocus = target
        }
    }

    private var rangePickerHeader: some View {
        HStack {
            Text("Insights").sectionHeader()
            Spacer()
        }
    }

    @MainActor
    private func reload() async {
        let localOwnerUserID = canonicalLocalOwnerUserID
        let localStats = (try? StatsHelper.fetchStats(in: ctx, range: range, ownerUserID: localOwnerUserID)) ?? .init(count: 0, seconds: 0)
        let localAllSessions = fetchSessions(limit: nil, start: nil, end: nil, ownerUserID: localOwnerUserID)

        guard localAllSessions.isEmpty,
              BackendEnvironment.shared.isConnected,
              let backendOwnerUserID = canonicalBackendOwnerUserID,
              backendOwnerUserID.isEmpty == false else {
            applyLocalAnalytics(localStats: localStats, allSessions: localAllSessions, ownerUserID: localOwnerUserID)
            return
        }

        let loadKey = backendOwnerUserID.lowercased() + "|" + range.rawValue
        if backendAnalyticsLoading, backendAnalyticsLoadKey == loadKey { return }
        if isBackendAnalyticsMode, backendAnalyticsLoadKey == loadKey { return }

        backendAnalyticsLoading = true
        defer { backendAnalyticsLoading = false }

        let result = await BackendEnvironment.shared.publish.fetchAllOwnerPostsForAnalytics(ownerUserID: backendOwnerUserID, pageSize: 500)
        switch result {
        case .success(let posts):
            applyBackendAnalytics(posts: posts, ownerUserID: backendOwnerUserID)
            backendAnalyticsLoadKey = loadKey
        case .failure:
            applyLocalAnalytics(localStats: localStats, allSessions: localAllSessions, ownerUserID: localOwnerUserID)
        }
    }

    @MainActor
    private func applyLocalAnalytics(localStats: SessionStats, allSessions: [Session], ownerUserID: String?) {
        isBackendAnalyticsMode = false
        backendAnalyticsLoadKey = nil
        sessionStats = localStats
        self.allSessions = allSessions
        currentStreakValue = Stats.currentStreakDays(sessions: allSessions)
        bestStreakValue = Stats.bestStreakDays(sessions: allSessions)
        if let best = Stats.bestStreakRange(sessions: allSessions) {
            bestStreakRangeText = formatStreakRange(start: best.start, end: best.end)
        } else {
            bestStreakRangeText = nil
        }
        let (start, end) = StatsHelper.dateBounds(for: range)
        let sessionsInRange = fetchSessions(limit: nil, start: start, end: end, ownerUserID: ownerUserID)
        avgFocus = averageFocus(from: sessionsInRange)
        var longestSecs: Int64 = 0
        var longestDate: Date? = nil
        var longestFound: Session? = nil
        for s in sessionsInRange {
            let secs64 = (s.value(forKey: "durationSeconds") as? Int64)
            let secs = secs64 ?? Int64((s.value(forKey: "durationSeconds") as? Int) ?? 0)
            guard secs > 0 else { continue }
            if secs > longestSecs {
                longestSecs = secs
                longestDate = (s.value(forKey: "timestamp") as? Date)
                longestFound = s
            }
        }
        if longestSecs > 0, let ld = longestDate, let ls = longestFound {
            longestSessionSeconds = longestSecs
            longestSessionDate = ld
            longestSession = ls
        } else {
            longestSessionSeconds = nil
            longestSessionDate = nil
            longestSession = nil
        }
        timeDistributionSlices = timeDistribution(from: sessionsInRange)
        let activityTotals = categoryTotals(from: sessionsInRange) { s in
            let raw = SessionActivity.name(for: s as NSManagedObject)
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? nil : label
        }
        activityTintCounts = categoryCounts(from: sessionsInRange) { s in
            let raw = SessionActivity.name(for: s as NSManagedObject)
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? nil : label
        }
        uniqueActivityCount = activityTotals.count
        topActivityByTime = topDurationWinner(from: activityTotals)
        avgSessionSeconds = sessionStats.count > 0 ? Int64(sessionStats.seconds) / Int64(sessionStats.count) : nil
        let firstPair = sessionsInRange.compactMap { session -> (Session, Date)? in
            guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
            return (session, date)
        }.min { lhs, rhs in
            lhs.1 < rhs.1
        }
        firstSessionDate = firstPair?.1
        firstSession = firstPair?.0
        let threadStats = threadAnalytics(from: sessionsInRange)
        threadDistributionSlices = threadStats.slices
        threadUniqueCountInRange = threadStats.uniqueCount
        topThread = threadStats.top
        let instrumentTotals = categoryTotals(from: sessionsInRange) { s in
            instrumentLabel(for: s)
        }
        instrumentTintCounts = categoryCounts(from: sessionsInRange) { s in
            instrumentLabel(for: s)
        }
        instrumentUniqueCountInRange = instrumentTotals.count
        instrumentDistributionSlices = distributionSlices(from: instrumentTotals)
        topInstrumentByTime = topDurationWinner(from: instrumentTotals)

        highestFocusSession = highestFocusInsight(from: sessionsInRange)
        bestThreadFocus = bestFocusCategoryInsight(from: sessionsInRange, requiresMultipleEligibleGroups: true) { session in
            let raw = session.value(forKey: "threadLabel") as? String
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        if hasMeaningfulInstrumentVariation(in: allSessions, fallbackSessions: sessionsInRange) {
            bestInstrumentFocus = bestFocusCategoryInsight(from: sessionsInRange, requiresMultipleEligibleGroups: false) { session in
                instrumentLabel(for: session)
            }
        } else {
            bestInstrumentFocus = nil
        }

        if hasMeaningfulActivityVariation(in: allSessions, fallbackSessions: sessionsInRange) {
            bestActivityFocus = bestFocusCategoryInsight(from: sessionsInRange, requiresMultipleEligibleGroups: false) { session in
                let raw = SessionActivity.name(for: session as NSManagedObject)
                let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return label.isEmpty ? nil : label
            }
        } else {
            bestActivityFocus = nil
        }
    }

    @MainActor
    private func applyBackendAnalytics(posts: [BackendPost], ownerUserID: String) {
        isBackendAnalyticsMode = true
        allSessions = []

        let canonicalOwnerUserID = ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allOwnerPosts = posts.filter {
            ($0.ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == canonicalOwnerUserID
        }

        let snapshot = StatsHelper.buildBackendStatsSnapshot(posts: allOwnerPosts, range: range, ownerUserID: canonicalOwnerUserID)
        sessionStats = snapshot.stats
        avgSessionSeconds = snapshot.stats.count > 0 ? Int64(snapshot.stats.seconds) / Int64(snapshot.stats.count) : nil
        avgFocus = backendAverageFocus(from: snapshot.filteredPosts)

        if let longest = snapshot.longestPost,
           let date = StatsHelper.analyticsDate(for: longest) {
            longestSessionSeconds = Int64(max(0, longest.durationSeconds ?? 0))
            longestSessionDate = date
            longestSession = nil
        } else {
            longestSessionSeconds = nil
            longestSessionDate = nil
            longestSession = nil
        }

        if let first = snapshot.firstPost,
           let date = StatsHelper.analyticsDate(for: first) {
            firstSessionDate = date
            firstSession = nil
        } else {
            firstSessionDate = nil
            firstSession = nil
        }

        uniqueActivityCount = snapshot.activityDistribution.count
        timeDistributionSlices = snapshot.activityDistribution.map { ActivitySlice(name: $0.label, seconds: $0.seconds) }
        topActivityByTime = snapshot.activityDistribution.first.map { (name: $0.label, seconds: $0.seconds) }
        activityTintCounts = Dictionary(uniqueKeysWithValues: snapshot.activityDistribution.map { ($0.label, max(0, $0.seconds)) })

        instrumentUniqueCountInRange = snapshot.instrumentDistribution.count
        instrumentDistributionSlices = snapshot.instrumentDistribution.map { ActivitySlice(name: $0.label, seconds: $0.seconds) }
        topInstrumentByTime = snapshot.instrumentDistribution.first.map { (name: $0.label, seconds: $0.seconds) }
        instrumentTintCounts = Dictionary(uniqueKeysWithValues: snapshot.instrumentDistribution.map { ($0.label, max(0, $0.seconds)) })

        threadDistributionSlices = []
        threadUniqueCountInRange = 0
        topThread = nil
        highestFocusSession = nil
        bestThreadFocus = nil
        bestInstrumentFocus = nil
        bestActivityFocus = nil

        currentStreakValue = StatsHelper.backendCurrentStreakDays(from: snapshot.filteredPosts)
        bestStreakValue = StatsHelper.backendBestStreakDays(from: snapshot.filteredPosts)
        if let bestRange = backendBestStreakRange(from: snapshot.filteredPosts.compactMap({ StatsHelper.analyticsDate(for: $0) })) {
            bestStreakRangeText = formatStreakRange(start: bestRange.start, end: bestRange.end)
        } else {
            bestStreakRangeText = nil
        }
    }

    private var canonicalBackendOwnerUserID: String? {
        let raw = (auth.backendUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private var canonicalLocalOwnerUserID: String? {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        #endif

        if let authID = auth.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authID.isEmpty {
            return authID
        }

        let persisted = (PersistenceController.shared.currentUserID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return persisted.isEmpty ? nil : persisted
    }

    private var tintMode: Theme.TintMode {
        Theme.TintMode(rawValue: tintModeRaw) ?? .auto
    }

    private var topWinnerTintOwnerID: String? {
        canonicalLocalOwnerUserID ?? canonicalBackendOwnerUserID
    }

    private var topWinnerActiveTintSource: Theme.ResolvedTintSource {
        switch tintMode {
        case .off:
            return .off
        case .instrument:
            return .instrument
        case .activity:
            return .activity
        case .auto:
            if let storedSource = Theme.storedAutoTintSource(), storedSource != .off {
                return storedSource
            }

            let globalInstrumentCounts = categoryCounts(from: allSessions) { s in
                instrumentLabel(for: s)
            }
            let globalActivityCounts = categoryCounts(from: allSessions) { s in
                let raw = SessionActivity.name(for: s as NSManagedObject)
                let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return label.isEmpty ? nil : label
            }

            if globalInstrumentCounts.isEmpty == false || globalActivityCounts.isEmpty == false {
                return Theme.resolvedTintSource(
                    tintMode: .auto,
                    instrumentCounts: globalInstrumentCounts,
                    activityCounts: globalActivityCounts,
                    persistedAutoSource: nil,
                    persistAutoSource: false
                )
            }

            return Theme.resolvedTintSource(
                tintMode: .auto,
                instrumentCounts: instrumentTintCounts,
                activityCounts: activityTintCounts,
                persistedAutoSource: nil,
                persistAutoSource: false
            )
        }
    }

    private var hasQualityInsights: Bool {
        highestFocusSession != nil || bestThreadFocus != nil || bestInstrumentFocus != nil || bestActivityFocus != nil
    }

    private var bestInstrumentFocusCardTint: Theme.ResolvedTint? {
        guard let insight = bestInstrumentFocus else { return nil }
        guard topWinnerActiveTintSource == .instrument else { return nil }
        return Theme.ResolvedTint(
            source: .instrument,
            instrumentLabel: insight.name,
            activityLabel: nil
        )
    }

    private var bestActivityFocusCardTint: Theme.ResolvedTint? {
        guard let insight = bestActivityFocus else { return nil }
        guard topWinnerActiveTintSource == .activity else { return nil }
        return Theme.ResolvedTint(
            source: .activity,
            instrumentLabel: nil,
            activityLabel: insight.name
        )
    }

    private var bestInstrumentFocusCardFillColor: Color? {
        bestInstrumentFocusCardTint?.fill(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private var bestInstrumentFocusCardStrokeColor: Color? {
        bestInstrumentFocusCardTint?.stroke(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private var bestActivityFocusCardFillColor: Color? {
        bestActivityFocusCardTint?.fill(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private var bestActivityFocusCardStrokeColor: Color? {
        bestActivityFocusCardTint?.stroke(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private var topActivityCardTint: Theme.ResolvedTint? {
        guard let winner = topActivityByTime else { return nil }
        guard topWinnerActiveTintSource == .activity else { return nil }
        return Theme.ResolvedTint(
            source: .activity,
            instrumentLabel: nil,
            activityLabel: winner.name
        )
    }

    private var topInstrumentCardTint: Theme.ResolvedTint? {
        guard let winner = topInstrumentByTime else { return nil }
        guard topWinnerActiveTintSource == .instrument else { return nil }
        return Theme.ResolvedTint(
            source: .instrument,
            instrumentLabel: winner.name,
            activityLabel: nil
        )
    }

    private var topActivityCardFillColor: Color? {
        topActivityCardTint?.fill(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private var topActivityCardStrokeColor: Color? {
        topActivityCardTint?.stroke(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private var topInstrumentCardFillColor: Color? {
        topInstrumentCardTint?.fill(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private var topInstrumentCardStrokeColor: Color? {
        topInstrumentCardTint?.stroke(
            ownerID: topWinnerTintOwnerID,
            scheme: colorScheme,
            strength: .cardMediumLight
        )
    }

    private func backendBestStreakRange(from dates: [Date]) -> (start: Date, end: Date)? {
        let tz = TimeZone(identifier: "Europe/London") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let sortedDays = Array(Set(dates.map { cal.startOfDay(for: $0) })).sorted()
        guard sortedDays.isEmpty == false else { return nil }

        var bestLength = 1
        var bestStart = sortedDays[0]
        var bestEnd = sortedDays[0]
        var runLength = 1
        var runStart = sortedDays[0]
        var previous = sortedDays[0]

        for day in sortedDays.dropFirst() {
            let expectedNext = cal.date(byAdding: .day, value: 1, to: previous)
            if let expectedNext, cal.isDate(day, inSameDayAs: expectedNext) {
                runLength += 1
            } else {
                if runLength > bestLength {
                    bestLength = runLength
                    bestStart = runStart
                    bestEnd = previous
                }
                runLength = 1
                runStart = day
            }
            previous = day
        }

        if runLength > bestLength {
            bestStart = runStart
            bestEnd = previous
        }

        return (bestStart, bestEnd)
    }

    private func fetchSessions(limit: Int?, start: Date?, end: Date?, ownerUserID: String?) -> [Session] {
        let req = NSFetchRequest<Session>(entityName: "Session")
        var preds: [NSPredicate] = []
        if let ownerUserID, ownerUserID.isEmpty == false {
            preds.append(NSPredicate(format: "ownerUserID == %@", ownerUserID))
        }
        if let start, let end { preds.append(NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate)) }
        else if let start { preds.append(NSPredicate(format: "timestamp >= %@", start as NSDate)) }
        else if let end { preds.append(NSPredicate(format: "timestamp < %@", end as NSDate)) }
        if !preds.isEmpty { req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds) }
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        if let limit { req.fetchLimit = limit }
        do { return try ctx.fetch(req) } catch { return [] }
    }

    // MARK: - Focus (duration-weighted visual average)
    private func averageFocus(from sessions: [Session]) -> Double? {
        guard sessions.isEmpty == false else { return nil }

        var weightedTotal = 0.0
        var durationTotal = 0.0

        for session in sessions {
            guard let storedValue = storedFocusValue(for: session),
                  let visualValue = FocusCircleView.visualFocusValue(forStoredFocusValue: storedValue) else { continue }

            let duration = sessionDurationSeconds(for: session)
            guard duration > 0 else { continue }

            weightedTotal += Double(visualValue) * duration
            durationTotal += duration
        }

        guard durationTotal > 0 else { return nil }
        return weightedTotal / durationTotal
    }

    private func highestFocusInsight(from sessions: [Session]) -> FocusInsightSession? {
        var best: (session: Session, visualFocus: Double, duration: Double, date: Date?)?

        for session in sessions {
            let duration = sessionDurationSeconds(for: session)
            guard duration >= qualityInsightMinimumDurationSeconds,
                  let storedValue = storedFocusValue(for: session),
                  let visualValue = FocusCircleView.visualFocusValue(forStoredFocusValue: storedValue) else { continue }

            let candidate = (session: session, visualFocus: Double(visualValue), duration: duration, date: session.value(forKey: "timestamp") as? Date)
            if let current = best {
                if candidate.visualFocus > current.visualFocus {
                    best = candidate
                } else if candidate.visualFocus == current.visualFocus {
                    if candidate.duration > current.duration {
                        best = candidate
                    } else if candidate.duration == current.duration,
                              (candidate.date ?? .distantPast) > (current.date ?? .distantPast) {
                        best = candidate
                    }
                }
            } else {
                best = candidate
            }
        }

        guard let best else { return nil }
        let title = (best.session.value(forKey: "title") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FocusInsightSession(
            session: best.session,
            title: (title?.isEmpty == false ? title : nil) ?? "Session",
            date: best.date,
            seconds: Int(best.duration),
            normalizedFocus: max(0.0, min(1.0, best.visualFocus / 11.0))
        )
    }

    private func bestFocusCategoryInsight(
        from sessions: [Session],
        requiresMultipleEligibleGroups: Bool,
        label: (Session) -> String?
    ) -> FocusCategoryInsight? {
        struct Bucket {
            var weightedTotal: Double = 0
            var durationTotal: Double = 0
            var sessionCount: Int = 0
        }

        var buckets: [String: Bucket] = [:]

        for session in sessions {
            guard let raw = label(session) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false,
                  let storedValue = storedFocusValue(for: session),
                  let visualValue = FocusCircleView.visualFocusValue(forStoredFocusValue: storedValue) else { continue }

            let duration = sessionDurationSeconds(for: session)
            guard duration >= qualityInsightMinimumDurationSeconds else { continue }

            var bucket = buckets[trimmed, default: Bucket()]
            bucket.weightedTotal += Double(visualValue) * duration
            bucket.durationTotal += duration
            bucket.sessionCount += 1
            buckets[trimmed] = bucket
        }

        let eligible = buckets.compactMap { entry -> FocusCategoryInsight? in
            let bucket = entry.value
            guard bucket.durationTotal > 0 else { return nil }
            return FocusCategoryInsight(
                name: entry.key,
                averageFocus: bucket.weightedTotal / bucket.durationTotal,
                seconds: Int(bucket.durationTotal),
                sessionCount: bucket.sessionCount
            )
        }

        guard eligible.count >= (requiresMultipleEligibleGroups ? 2 : 1) else { return nil }
        return eligible.sorted { lhs, rhs in
            if lhs.averageFocus != rhs.averageFocus { return lhs.averageFocus > rhs.averageFocus }
            if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.first
    }

    private func hasMeaningfulInstrumentVariation(in sessions: [Session], fallbackSessions: [Session]) -> Bool {
        let counts = meaningfulCounts(primary: sessions, fallback: fallbackSessions) { session in
            instrumentLabel(for: session)
        }
        let sortedCounts = counts.values.sorted(by: >)
        guard sortedCounts.count >= 2 else { return false }
        return sortedCounts.dropFirst().first ?? 0 >= 2
    }

    private func hasMeaningfulActivityVariation(in sessions: [Session], fallbackSessions: [Session]) -> Bool {
        let counts = meaningfulCounts(primary: sessions, fallback: fallbackSessions) { session in
            let raw = SessionActivity.name(for: session as NSManagedObject)
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? nil : label
        }
        let sortedCounts = counts.values.sorted(by: >)
        guard sortedCounts.count >= 2 else { return false }
        return (sortedCounts.dropFirst().first ?? 0) >= 2 || sortedCounts.count >= 3
    }

    private func meaningfulCounts(primary: [Session], fallback: [Session], label: (Session) -> String?) -> [String: Int] {
        let primaryCounts = categoryCounts(from: primary, label: label)
        if primaryCounts.isEmpty == false { return primaryCounts }
        return categoryCounts(from: fallback, label: label)
    }

    private func backendAverageFocus(from posts: [BackendPost]) -> Double? {
        guard posts.isEmpty == false else { return nil }

        var weightedTotal = 0.0
        var durationTotal = 0.0

        for post in posts {
            guard let storedValue = post.effort,
                  storedValue != 5,
                  let visualValue = FocusCircleView.visualFocusValue(forStoredFocusValue: storedValue),
                  let durationSeconds = post.durationSeconds,
                  durationSeconds > 0 else { continue }

            weightedTotal += Double(visualValue) * Double(durationSeconds)
            durationTotal += Double(durationSeconds)
        }

        guard durationTotal > 0 else { return nil }
        return weightedTotal / durationTotal
    }

    /// Parse legacy focus tokens from Session.notes. Current saved values should come from attributes first.
    private func focusFromNotes(for s: Session) -> Int? {
        let attrs = s.entity.attributesByName
        guard attrs["notes"] != nil else { return nil }
        guard let notes = s.value(forKey: "notes") as? String, !notes.isEmpty else { return nil }

        if let n = extractInt(after: "FocusDotIndex:", in: notes), (0...11).contains(n) {
            return n == 5 ? nil : n
        }

        if let n = extractInt(after: "StateIndex:", in: notes), (0...3).contains(n) {
            let visualCenters = [1, 4, 7, 10]
            return FocusCircleView.storedFocusValue(forVisualFocusValue: visualCenters[n])
        }

        return nil
    }

    /// Current focus source: stored mood first, effort fallback. Legacy focus attributes remain as final fallback.
    private func focusFromAttributes(for s: Session) -> Int? {
        let attrs = s.entity.attributesByName
        let preferred = ["mood", "effort", "focusDotIndex", "focusIndex", "focus", "stateIndex"]

        for key in preferred where attrs[key] != nil {
            if let value = numericValue(for: key, in: s),
               let storedValue = clampedStoredFocusValue(value) {
                return storedValue
            }
        }

        if let key = attrs.keys.first(where: { $0.lowercased().contains("focus") }),
           let value = numericValue(for: key, in: s),
           let storedValue = clampedStoredFocusValue(value) {
            return storedValue
        }

        return nil
    }

    private func storedFocusValue(for session: Session) -> Int? {
        focusFromAttributes(for: session) ?? focusFromNotes(for: session)
    }

    private func sessionDurationSeconds(for session: Session) -> Double {
        if let n = session.value(forKey: "durationSeconds") as? NSNumber { return max(0.0, n.doubleValue) }
        if let i = session.value(forKey: "durationSeconds") as? Int { return max(0.0, Double(i)) }
        if let d = session.value(forKey: "durationSeconds") as? Double { return max(0.0, d) }
        if let i16 = session.value(forKey: "durationSeconds") as? Int16 { return max(0.0, Double(i16)) }
        if let i32 = session.value(forKey: "durationSeconds") as? Int32 { return max(0.0, Double(i32)) }
        if let i64 = session.value(forKey: "durationSeconds") as? Int64 { return max(0.0, Double(i64)) }
        return 0.0
    }

    private func extractInt(after token: String, in text: String) -> Int? {
        guard let range = text.range(of: token) else { return nil }
        let tail = text[range.upperBound...]
        let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return Int(line.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func numericValue(for key: String, in s: Session) -> Double? {
        if let n = s.value(forKey: key) as? NSNumber { return n.doubleValue }
        if let i = s.value(forKey: key) as? Int { return Double(i) }
        if let d = s.value(forKey: key) as? Double { return d }
        if let i16 = s.value(forKey: key) as? Int16 { return Double(i16) }
        if let i32 = s.value(forKey: key) as? Int32 { return Double(i32) }
        if let i64 = s.value(forKey: key) as? Int64 { return Double(i64) }
        return nil
    }

    private func clampedStoredFocusValue(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = Int(round(value))
        guard (0...11).contains(rounded), rounded != 5 else { return nil }
        return rounded
    }

    // MARK: - Time-based category helpers
    private func categoryTotals(from sessions: [Session], label: (Session) -> String?) -> [String: Int] {
        var totals: [String: Int] = [:]
        for s in sessions {
            guard let raw = label(s) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let secs = (s.value(forKey: "durationSeconds") as? Int) ?? Int((s.value(forKey: "durationSeconds") as? Int64) ?? 0)
            guard secs > 0 else { continue }
            totals[trimmed, default: 0] += secs
        }
        return totals
    }

    private func categoryCounts(from sessions: [Session], label: (Session) -> String?) -> [String: Int] {
        var counts: [String: Int] = [:]
        for s in sessions {
            guard let raw = label(s) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        return counts
    }

    private func distributionSlices(from totals: [String: Int]) -> [ActivitySlice] {
        guard !totals.isEmpty else { return [] }
        let sorted = totals.sorted { $0.value > $1.value }
        let head = Array(sorted.prefix(6))
        let tail = sorted.dropFirst(6)
        let headSlices = head.map { ActivitySlice(name: $0.key, seconds: $0.value) }
        let otherTotal = tail.reduce(0) { $0 + $1.value }
        return otherTotal > 0 ? headSlices + [ActivitySlice(name: "Other", seconds: otherTotal)] : headSlices
    }

    private func topDurationWinner(from totals: [String: Int]) -> (name: String, seconds: Int)? {
        guard !totals.isEmpty else { return nil }
        let sorted = totals.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        guard let top = sorted.first else { return nil }
        return (name: top.key, seconds: top.value)
    }

    // MARK: Instrument label (safe)
    private func instrumentLabel(for s: Session) -> String? {
        let rels = s.entity.relationshipsByName
        if rels["instrument"] != nil, let obj = s.value(forKey: "instrument") as? NSManagedObject {
            if let name = stringAttribute(from: obj, keys: ["name","title","label"]) { return name }
        }
        if let name = stringAttribute(from: s, keys: ["instrumentName","instrument","instrument_title","instrumentLabel"]) { return name }
        return stringAttribute(containing: "instrument", from: s)
    }

    private func stringAttribute(from obj: AnyObject, keys: [String]) -> String? {
        guard let mo = obj as? NSManagedObject else { return nil }
        let attrs = mo.entity.attributesByName
        for k in keys {
            if attrs[k] != nil, let s = mo.value(forKey: k) as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func stringAttribute(containing needle: String, from obj: AnyObject) -> String? {
        guard let mo = obj as? NSManagedObject else { return nil }
        let attrs = mo.entity.attributesByName
        if let k = attrs.keys.first(where: { $0.lowercased().contains(needle.lowercased()) }),
           let s = mo.value(forKey: k) as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func label(for r: StatsRange) -> String {
        switch r {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .total: return "Total"
        }
    }

    private func dateWindowSubtitle(for r: StatsRange, firstSessionDate: Date?) -> String? {
        let (startOpt, endOpt) = StatsHelper.dateBounds(for: r)

        // Week/Month/Year: show the existing bounded window.
        if let start = startOpt, let end = endOpt {
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
            return "\(df.string(from: start)) – \(df.string(from: end.addingTimeInterval(-86400)))"
        }

        // Total: show first recorded date → today (only if we have at least one session date).
        guard r == .total, let first = firstSessionDate else { return nil }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        return "\(df.string(from: first)) → Today"
    }
}

    private func formatStreakRange(start: Date, end: Date) -> String {
        let tz = TimeZone(identifier: "Europe/London") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        let currentYear = cal.component(.year, from: Date())
        func format(_ d: Date) -> String {
            let y = cal.component(.year, from: d)
            let df = DateFormatter()
            df.locale = .current
            df.timeZone = tz
            df.dateFormat = (y == currentYear) ? "MMM d" : "MMM d yyyy"
            return df.string(from: d)
        }

        return "\(format(start)) – \(format(end))"
    }


// MARK: - Adaptive grid container
fileprivate struct AdaptiveGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Theme.Spacing.section)], spacing: Theme.Spacing.section) { content() }
    }
}

// MARK: - Shared StatTile

fileprivate struct StatTile: View {
    let title: String
    let value: String
    let subtitle: String?
    let isEmphasized: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(title: String, value: String, subtitle: String? = nil, isEmphasized: Bool = false) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.isEmphasized = isEmphasized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.75))

            if let s = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                Text(s)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(isEmphasized ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.Colors.stroke(colorScheme).opacity(0.3), lineWidth: 0.5)
        )
    }
}

fileprivate struct InsightCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Cards

fileprivate struct TimeCard: View {
    let seconds: Int; let count: Int; @Binding var range: StatsRange
    var dateRange: String? = nil

    private func labelForRange(_ r: StatsRange) -> String {
        switch r {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .total: return "Total"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Time").sectionHeader()
            Picker("Range", selection: $range) {
                ForEach(StatsRange.allCases) { r in Text(labelForRange(r)).tag(r) }
            }
            .pickerStyle(.segmented)
            
            if let dateRange, !dateRange.isEmpty {
                Text(dateRange)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(StatsHelper.formatDuration(seconds))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(" · \(count) sessions")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
.frame(maxWidth: .infinity, alignment: .leading)
.cardSurface(padding: Theme.Spacing.m)
    }
}

fileprivate struct StreaksCard: View {
    let current: Int
    let best: Int
    let bestRangeText: String?
    

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Streaks").sectionHeader()
            HStack(alignment: .top) {
                StatTile(title: "Current", value: "\(current) days", isEmphasized: current > best)
                Spacer()
                StatTile(title: "Best", value: "\(best) days", subtitle: bestRangeText, isEmphasized: best > current)
            }
        }
        .cardSurface(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streaks: current \(current) days, best \(best) days")
    }
}
fileprivate struct FocusCard: View {
    let normalizedFocus: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus").sectionHeader()

            FocusCircleView(normalizedFocus: CGFloat(normalizedFocus), size: 86)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, -3)
                .padding(.bottom, 19)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: Theme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus")
    }
}

fileprivate struct AverageSessionCard: View {
    let seconds: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Average session length").sectionHeader()
            Text(StatsHelper.formatDuration(Int(seconds)))
                .font(.title3.weight(.semibold))
        }
        .cardSurface(padding: Theme.Spacing.m)
    }
}

fileprivate struct LongestSessionCard: View {
    let range: StatsRange
    let seconds: Int64
    let date: Date

    private static let dfNoYear: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "EEE d MMM · HH:mm"
        return df
    }()

    private static let dfWithYear: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "EEE d MMM yyyy · HH:mm"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Longest session").sectionHeader()
            Text(StatsHelper.formatDuration(Int(seconds)))
                .font(.title3.weight(.semibold))
            Text((range == .total ? Self.dfWithYear : Self.dfNoYear).string(from: date))
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .cardSurface(padding: Theme.Spacing.m)
    }
}


fileprivate struct FirstSessionCard: View {
    let range: StatsRange
    let date: Date

    private static let dfNoYear: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "EEE d MMM · HH:mm"
        return df
    }()

    private static let dfWithYear: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "EEE d MMM yyyy · HH:mm"
        return df
    }()

    private var title: String {
        switch range {
        case .week:  return "First session this week"
        case .month: return "First session this month"
        case .year:  return "First session this year"
        case .total: return "First logged session"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).sectionHeader()
            Text((range == .total ? Self.dfWithYear : Self.dfNoYear).string(from: date))
                .font(.body).bold()
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .cardSurface(padding: Theme.Spacing.m)
    }
}


fileprivate struct HighestFocusInsightCard: View {
    let insight: FocusInsightSession

    private static let df: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "EEE d MMM · HH:mm"
        return df
    }()

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Highest focus").sectionHeader()
                Text(insight.title)
                    .font(.body).bold()
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(detailText)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: Theme.Spacing.s)

            FocusCircleView(normalizedFocus: CGFloat(insight.normalizedFocus), size: 42)
                .accessibilityHidden(true)
        }
        .cardSurface(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Highest focus: \(insight.title), \(StatsHelper.formatDuration(insight.seconds))")
    }

    private var detailText: String {
        let duration = StatsHelper.formatDuration(insight.seconds)
        guard let date = insight.date else { return duration }
        return "\(Self.df.string(from: date)) · \(duration)"
    }
}

fileprivate struct BestFocusCategoryInsightCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let insight: FocusCategoryInsight
    let fillColor: Color?
    let strokeColor: Color?

    init(
        title: String,
        insight: FocusCategoryInsight,
        fillColor: Color? = nil,
        strokeColor: Color? = nil
    ) {
        self.title = title
        self.insight = insight
        self.fillColor = fillColor
        self.strokeColor = strokeColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).sectionHeader()
            Text(insight.name)
                .font(.body).bold()
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

        }
        .cardSurface(
            padding: Theme.Spacing.m,
            fillColor: fillColor ?? Theme.Colors.surface(colorScheme),
            strokeColor: strokeColor ?? Theme.Colors.cardStroke(colorScheme)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(insight.name)")
    }
}

fileprivate struct TopTimeWinnerCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let winner: (name: String, seconds: Int)?
    let fillColor: Color?
    let strokeColor: Color?

    init(
        title: String,
        winner: (name: String, seconds: Int)?,
        fillColor: Color? = nil,
        strokeColor: Color? = nil
    ) {
        self.title = title
        self.winner = winner
        self.fillColor = fillColor
        self.strokeColor = strokeColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).sectionHeader()
            if let w = winner {
                HStack {
                    Text(w.name)
                        .font(.body).bold()
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(StatsHelper.formatDuration(w.seconds))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cardSurface(
            padding: Theme.Spacing.m,
            fillColor: fillColor ?? Theme.Colors.surface(colorScheme),
            strokeColor: strokeColor ?? Theme.Colors.cardStroke(colorScheme)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let w = winner {
            return "\(title): \(w.name), \(StatsHelper.formatDuration(w.seconds))"
        } else {
            return "\(title): no data"
        }
    }
}


fileprivate struct TopThreadCard: View {
    let winner: (name: String, seconds: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Top thread").sectionHeader()
            if let w = winner {
                HStack {
                    Text(w.name)
                        .font(.body).bold()
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(StatsHelper.formatDuration(w.seconds))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
.cardSurface(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let w = winner {
            return "Top thread: \(w.name), \(StatsHelper.formatDuration(w.seconds))"
        } else {
            return "Top thread: no data"
        }
    }
}

fileprivate struct TimeDistributionCard: View {
    let title: String
    let slices: [ActivitySlice]

    init(title: String = "Time distribution", slices: [ActivitySlice]) {
        self.title = title
        self.slices = slices
    }


    private static let meViewChartPalette: [Color] = [
        Color(red: 58.0 / 255.0, green: 111.0 / 255.0, blue: 163.0 / 255.0),   // Blue
        Color(red: 58.0 / 255.0, green: 181.0 / 255.0, blue: 132.0 / 255.0),   // Green
        Color(red: 245.0 / 255.0, green: 156.0 / 255.0, blue: 28.0 / 255.0),   // Orange
        Color(red: 164.0 / 255.0, green: 91.0 / 255.0, blue: 214.0 / 255.0),   // Purple
        Color(red: 1.0, green: 107.0 / 255.0, blue: 87.0 / 255.0),             // Red
        Color(red: 1.0, green: 214.0 / 255.0, blue: 10.0 / 255.0),             // Yellow
        Color(red: 1.0, green: 95.0 / 255.0, blue: 162.0 / 255.0)              // Pink
    ]

    private static let meViewChartFallback = Color(
        red: 199.0 / 255.0,
        green: 199.0 / 255.0,
        blue: 204.0 / 255.0
    ) // Grey fallback

    private func chartColor(for slice: ActivitySlice, index: Int) -> Color {
        if slice.name == "Other" {
            return Self.meViewChartFallback
        }
        guard index < Self.meViewChartPalette.count else {
            return Self.meViewChartFallback
        }
        return Self.meViewChartPalette[index]
    }

    private func percent(_ part: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(round((Double(part) / Double(total)) * 100.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).sectionHeader()

            if slices.isEmpty {
                Text("No time logged this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // --- stacked bar (100% width) ---
                GeometryReader { geo in
                    let total = slices.reduce(0) { $0 + $1.seconds }
                    ZStack {
                        // background track for clarity
                        Capsule().fill(.secondary.opacity(0.15))
                        // segments
                        HStack(spacing: 0) {
                            ForEach(0..<slices.count, id: \.self) { i in
                                let w = CGFloat(slices[i].seconds) / CGFloat(max(total, 1)) * geo.size.width
                                Rectangle()
                                    .foregroundStyle(chartColor(for: slices[i], index: i))
                                    .frame(width: max(1, w), height: 12) // ensure visible slivers
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 12)

                // --- legend (dots share the same shade as segments) ---
                let total = slices.reduce(0) { $0 + $1.seconds }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(0..<slices.count, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline) {
                            HStack(spacing: 8) {
                                Circle()
                                    .frame(width: 8, height: 8)
                                    .foregroundStyle(chartColor(for: slices[i], index: i))
                                Text(slices[i].name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Spacer()
                            Text("\(percent(slices[i].seconds, of: total))%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .font(.body)
                    }
                }
            }
        }
.cardSurface(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yText)
    }

    private var a11yText: String {
        guard !slices.isEmpty else { return "\(title): no data this period" }
        let total = slices.reduce(0) { $0 + $1.seconds }
        let parts = slices.map { "\($0.name) \(percent($0.seconds, of: total)) percent" }
        return "\(title): " + parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        MeView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
