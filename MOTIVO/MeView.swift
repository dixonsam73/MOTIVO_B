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
    let head = Array(sorted.prefix(4))
    let tail = sorted.dropFirst(4)
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

    let head = Array(sorted.prefix(4))
    let tail = sorted.dropFirst(4)
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
    @EnvironmentObject private var auth: AuthManager
    @State private var range: StatsRange = .week
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
    @State private var topInstrumentByTime: (name: String, seconds: Int)? = nil
    @State private var topActivityByTime: (name: String, seconds: Int)? = nil
    @State private var timeDistributionSlices: [ActivitySlice] = []
    @State private var threadDistributionSlices: [ActivitySlice] = []
    @State private var instrumentDistributionSlices: [ActivitySlice] = []
    @State private var threadUniqueCountInRange: Int = 0
    @State private var instrumentUniqueCountInRange: Int = 0
    @State private var topThread: (name: String, seconds: Int)? = nil
    @State private var uniqueActivityCount: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                rangePickerHeader
                // Full-width Time card with date range header
                TimeCard(seconds: sessionStats.seconds, count: sessionStats.count, range: $range, dateRange: dateWindowSubtitle(for: range, firstSessionDate: firstSessionDate))
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
                    if avgFocus != nil {
                        FocusCard(average: avgFocus)
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
                        TopTimeWinnerCard(title: "Top activity", winner: topActivityByTime)
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
                        TopTimeWinnerCard(title: "Top instrument", winner: topInstrumentByTime)
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

    private var rangePickerHeader: some View {
        HStack {
            Text("Insights").sectionHeader()
            Spacer()
        }
    }

    @MainActor
    private func reload() async {
        let localStats = (try? StatsHelper.fetchStats(in: ctx, range: range)) ?? .init(count: 0, seconds: 0)
        let localAllSessions = fetchSessions(limit: nil, start: nil, end: nil)

        guard localAllSessions.isEmpty,
              BackendEnvironment.shared.isConnected,
              let backendOwnerUserID = canonicalBackendOwnerUserID,
              backendOwnerUserID.isEmpty == false else {
            applyLocalAnalytics(localStats: localStats, allSessions: localAllSessions)
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
            applyLocalAnalytics(localStats: localStats, allSessions: localAllSessions)
        }
    }

    @MainActor
    private func applyLocalAnalytics(localStats: SessionStats, allSessions: [Session]) {
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
        avgFocus = averageFocus(start: start, end: end)
        let sessionsInRange = fetchSessions(limit: nil, start: start, end: end)
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
        instrumentUniqueCountInRange = instrumentTotals.count
        instrumentDistributionSlices = distributionSlices(from: instrumentTotals)
        topInstrumentByTime = topDurationWinner(from: instrumentTotals)
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
        avgFocus = snapshot.averageEffort

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

        instrumentUniqueCountInRange = snapshot.instrumentDistribution.count
        instrumentDistributionSlices = snapshot.instrumentDistribution.map { ActivitySlice(name: $0.label, seconds: $0.seconds) }
        topInstrumentByTime = snapshot.instrumentDistribution.first.map { (name: $0.label, seconds: $0.seconds) }

        threadDistributionSlices = []
        threadUniqueCountInRange = 0
        topThread = nil

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

    private func fetchSessions(limit: Int?, start: Date?, end: Date?) -> [Session] {
        let req = NSFetchRequest<Session>(entityName: "Session")
        var preds: [NSPredicate] = []
        if let start, let end { preds.append(NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate)) }
        else if let start { preds.append(NSPredicate(format: "timestamp >= %@", start as NSDate)) }
        else if let end { preds.append(NSPredicate(format: "timestamp < %@", end as NSDate)) }
        if !preds.isEmpty { req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds) }
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        if let limit { req.fetchLimit = limit }
        do { return try ctx.fetch(req) } catch { return [] }
    }

    // MARK: - Focus (from notes)
    private func averageFocus(start: Date?, end: Date?) -> Double? {
        let sessions = fetchSessions(limit: nil, start: start, end: end)
        guard !sessions.isEmpty else { return nil }
        var total = 0.0
        var count = 0.0
        for s in sessions {
            if let v = focusFromNotes(for: s) ?? focusFromAttributes(for: s) {
                total += v; count += 1
            }
        }
        guard count > 0 else { return nil }
        return total / count
    }

    /// Parse "FocusDotIndex: n" from Session.notes; fallback "StateIndex: n" mapped to center dots (0..3 → 1,4,7,10)
    private func focusFromNotes(for s: Session) -> Double? {
        let attrs = s.entity.attributesByName
        guard attrs["notes"] != nil else { return nil }
        guard let notes = s.value(forKey: "notes") as? String, !notes.isEmpty else { return nil }
        if let n = extractInt(after: "FocusDotIndex:", in: notes), (0...11).contains(n) {
            return Double(n)
        }
        if let n = extractInt(after: "StateIndex:", in: notes), (0...3).contains(n) {
            let centers = [1,4,7,10]
            return Double(centers[n])
        }
        return nil
    }

    /// Fallback: try attributes like focusDotIndex/focusIndex/focus/stateIndex if they exist
    private func focusFromAttributes(for s: Session) -> Double? {
        let attrs = s.entity.attributesByName
        let preferred = ["focusDotIndex","focusIndex","focus","stateIndex"]
        for key in preferred {
            if attrs[key] != nil {
                if let v = numericValue(for: key, in: s) { return clamp011(v) }
            }
        }
        if let k = attrs.keys.first(where: { $0.lowercased().contains("focus") }),
           let v = numericValue(for: k, in: s) { return clamp011(v) }
        return nil
    }

    private func extractInt(after token: String, in text: String) -> Int? {
        guard let r = text.range(of: token) else { return nil }
        let tail = text[r.upperBound...]
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

    private func clamp011(_ v: Double) -> Double { max(0.0, min(11.0, v)) }

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

    private func distributionSlices(from totals: [String: Int]) -> [ActivitySlice] {
        guard !totals.isEmpty else { return [] }
        let sorted = totals.sorted { $0.value > $1.value }
        let head = Array(sorted.prefix(4))
        let tail = sorted.dropFirst(4)
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
    let average: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Focus").sectionHeader()
            if let avg = average {
                Text("Average").font(.caption).foregroundStyle(.secondary)
                // Round to nearest dot index 0...11
                let index = Int(round(avg))
                FocusDots(value: avg, highlightedIndex: index)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            } else {
                Text("No focus data in this period.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
.frame(maxWidth: .infinity, alignment: .leading)
.cardSurface(padding: Theme.Spacing.m)
        .accessibilityLabel(average != nil ? "Focus average" : "No focus data")
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


fileprivate struct FocusDots: View {
    @Environment(\.colorScheme) private var colorScheme

    let value: Double
    let highlightedIndex: Int?

    private let dotCount = 12

    /// DARK → LIGHT across the row (left→right), to match Focus field cards elsewhere
    private func opacityForDot(_ i: Int) -> Double {
        let start: Double = 0.95   // darker (more opaque) on the left
        let end:   Double = 0.15   // lighter (less opaque) on the right
        guard dotCount > 1 else { return start }
        let t = Double(i) / Double(dotCount - 1)
        return start + (end - start) * t
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let spacing: CGFloat = 8
            let count = dotCount
            // Compute diameter so dots + spacings fill available width (with sensible caps)
            let diameter = max(14, min(32, (totalWidth - spacing * CGFloat(count - 1)) / CGFloat(count)))
            let ringDot = max(0, min(count - 1, (highlightedIndex ?? Int(round(value)))))

            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let isRinged = (i == ringDot)
                    let baseScale: CGFloat = isRinged ? 1.18 : 1.0
                    Circle()
                        .fill(FocusDotStyle.fillColor(index: i, total: count, colorScheme: colorScheme))
                        // Hairline outline for guaranteed contrast on all dots
                        .overlay(
                            Circle().stroke(FocusDotStyle.hairlineColor, lineWidth: FocusDotStyle.hairlineWidth)
                        )
                        // Adaptive ring for the selected/average index
                        .overlay(
                            Group {
                                if i == ringDot {
                                    Circle().stroke(
                                        FocusDotStyle.ringColor(for: colorScheme),
                                        lineWidth: FocusDotStyle.ringWidth
                                    )
                                }
                            }
                        )
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(baseScale)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 44)
    }
}

fileprivate struct TopTimeWinnerCard: View {
    let title: String
    let winner: (name: String, seconds: Int)?

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
.cardSurface(padding: Theme.Spacing.m)
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


    // rank-based shades (index 0 = biggest slice)
    private let opacities: [Double] = [1.00, 0.62, 0.36, 0.18, 0.08]

    private func opacityForIndex(_ i: Int) -> Double {
        guard i < opacities.count else { return opacities.last ?? 0.12 }
        return opacities[i]
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
                                    .foregroundStyle(.primary)     // system adaptive
                                    .opacity(opacityForIndex(i))    // rank shade
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
                                    .foregroundStyle(.primary)
                                    .opacity(opacityForIndex(i))
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
