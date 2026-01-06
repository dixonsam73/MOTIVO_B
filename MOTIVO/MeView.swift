// CHANGE-ID: 20260106_221700-meview-calmtext-scrollindicators
// SCOPE: Visual-only: soften key highlight text + hide scroll indicators in MeView. No logic/state changes.
// CHANGE-ID: 20251015_150332-me-focus-from-notes
// SCOPE: Me dashboard — Focus average parsed from Session.notes token "FocusDotIndex: n" (fallback: legacy StateIndex→center dots).
// NOTES: Timestamp-only predicates; no schema changes.

import SwiftUI
import CoreData

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

private func percent(_ part: Int, of total: Int) -> Int {
    guard total > 0 else { return 0 }
    return Int(round((Double(part) / Double(total)) * 100.0))
}

private func totalSessionsCount(in sessions: [Session]) -> Int { sessions.count }

struct MeView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var range: StatsRange = .week
    @State private var sessionStats: SessionStats = .init(count: 0, seconds: 0)
    @State private var allSessions: [Session] = []
    @State private var avgFocus: Double? = nil
    @State private var topInstrument: (name: String, count: Int)? = nil
    @State private var topActivity: (name: String, count: Int)? = nil
    @State private var timeDistributionSlices: [ActivitySlice] = []
    @State private var totalInRange: Int = 0
    @State private var uniqueInstrumentCount: Int = 0
    @State private var uniqueActivityCount: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                rangePickerHeader
                // Full-width Time card with date range header
                TimeCard(seconds: sessionStats.seconds, count: sessionStats.count, range: $range, dateRange: dateWindowSubtitle(for: range))
                AdaptiveGrid {
                    StreaksCard(current: currentStreakDays, best: bestStreakDays)
                    FocusCard(average: avgFocus)
                    TimeDistributionCard(slices: timeDistributionSlices)
                    TopWinnerCard(title: "Top instrument", winner: topInstrument, totalCount: totalInRange)
                    if uniqueActivityCount > 1 {
                        TopWinnerCard(title: "Top activity",   winner: topActivity,   totalCount: totalInRange)
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
        .onAppear { reload() }
        .onChange(of: range) { _, _ in reload() }
    }

    private var rangePickerHeader: some View {
        HStack {
            Text("Dashboard").sectionHeader()
            Spacer()
        }
    }

    private var currentStreakDays: Int { Stats.currentStreakDays(sessions: allSessions) }
    private var bestStreakDays: Int { Stats.bestStreakDays(sessions: allSessions) }

    private func reload() {
        sessionStats = (try? StatsHelper.fetchStats(in: ctx, range: range)) ?? .init(count: 0, seconds: 0)
        allSessions = fetchSessions(limit: nil, start: nil, end: nil)
        let (start, end) = StatsHelper.dateBounds(for: range)
        avgFocus = averageFocus(start: start, end: end)
        let sessionsInRange = fetchSessions(limit: nil, start: start, end: end)
        self.timeDistributionSlices = timeDistribution(from: sessionsInRange)
        self.totalInRange = totalSessionsCount(in: sessionsInRange)
        // Compute top winners within the current range
        topInstrument = bestInstrument(from: sessionsInRange)
        topActivity   = bestActivity(from: sessionsInRange)

        self.uniqueInstrumentCount = {
            var set = Set<String>()
            for s in allSessions {
                if let label = instrumentLabel(for: s) { set.insert(label) }
            }
            return set.count
        }()
        self.uniqueActivityCount = {
            var set = Set<String>()
            for s in allSessions {
                let raw = SessionActivity.name(for: s as NSManagedObject)
                let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { set.insert(label) }
            }
            return set.count
        }()
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

    // MARK: - Top winners (instrument / activity)
    private func bestInstrument(from sessions: [Session]) -> (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        var latest: [String: Date] = [:]
        for s in sessions {
            guard let label = instrumentLabel(for: s) else { continue }
            counts[label, default: 0] += 1
            let d = (s.entity.attributesByName["timestamp"] != nil ? (s.value(forKey: "timestamp") as? Date) : nil) ?? .distantPast
            latest[label] = max(latest[label] ?? .distantPast, d)
        }
        return pickWinner(from: counts, latest: latest)
    }

    private func bestActivity(from sessions: [Session]) -> (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        var latest: [String: Date] = [:]
        for s in sessions {
            let raw = SessionActivity.name(for: s as NSManagedObject)
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            counts[label, default: 0] += 1
            let d = (s.entity.attributesByName["timestamp"] != nil ? (s.value(forKey: "timestamp") as? Date) : nil) ?? .distantPast
            latest[label] = max(latest[label] ?? .distantPast, d)
        }
        return pickWinner(from: counts, latest: latest)
    }

    private func pickWinner(from counts: [String: Int], latest: [String: Date]) -> (name: String, count: Int)? {
        guard !counts.isEmpty else { return nil }
        let sorted = counts.sorted { (lhs, rhs) in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            if let dl = latest[lhs.key], let dr = latest[rhs.key], dl != dr { return dl > dr }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        if let top = sorted.first { return (top.key, top.value) }
        return nil
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

    private func dateWindowSubtitle(for r: StatsRange) -> String {
        let (startOpt, endOpt) = StatsHelper.dateBounds(for: r)
        guard let start = startOpt, let end = endOpt else { return "" }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        return "\(df.string(from: start)) – \(df.string(from: end.addingTimeInterval(-86400)))"
    }
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
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.75))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.Colors.stroke(colorScheme).opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Cards

fileprivate struct TimeCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

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
            
            if let dateRange {
                Text(dateRange)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("\(StatsHelper.formatDuration(seconds)) · \(count) sessions")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
.frame(maxWidth: .infinity, alignment: .leading)
.cardSurface(padding: Theme.Spacing.m)
    }
}

fileprivate struct StreaksCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let current: Int; let best: Int
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Streaks").sectionHeader()
            HStack {
                StatTile(title: "Current", value: "\(current) days")
                Spacer()
                StatTile(title: "Best", value: "\(best) days")
            }
        }
.cardSurface(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streaks: current \(current) days, best \(best) days")
    }
}

fileprivate struct FocusCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

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

fileprivate struct TopWinnerCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let title: String
    let winner: (name: String, count: Int)?
    let totalCount: Int

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
                    Text("\(w.count) sessions").font(.subheadline).foregroundStyle(.secondary)
                }
                if totalCount > 0 {
                    Text("\(Int(round((Double(w.count) / Double(totalCount)) * 100)))% of sessions")
                        .font(.footnote)
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
            if totalCount > 0 {
                let pct = Int(round((Double(w.count) / Double(totalCount)) * 100))
                return "\(title): \(w.name), \(w.count) sessions, \(pct) percent of sessions"
            } else {
                return "\(title): \(w.name), \(w.count) sessions"
            }
        } else {
            return "\(title): no data"
        }
    }
}

fileprivate struct TimeDistributionCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let slices: [ActivitySlice]

    // rank-based shades (index 0 = biggest slice)
    private let opacities: [Double] = [0.95, 0.75, 0.6, 0.45, 0.3]

    private func opacityForIndex(_ i: Int) -> Double {
        guard i < opacities.count else { return 0.3 }
        return opacities[i]
    }

    private func percent(_ part: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(round((Double(part) / Double(total)) * 100.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Time distribution").sectionHeader()

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
        guard !slices.isEmpty else { return "Time distribution by activity: no data this period" }
        let total = slices.reduce(0) { $0 + $1.seconds }
        let parts = slices.map { "\($0.name) \(percent($0.seconds, of: total)) percent" }
        return "Time distribution by activity: " + parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        MeView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
