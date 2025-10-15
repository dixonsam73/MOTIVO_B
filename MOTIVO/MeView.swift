// CHANGE-ID: 20251015_150332-me-focus-from-notes
// SCOPE: Me dashboard — Focus average parsed from Session.notes token "FocusDotIndex: n" (fallback: legacy StateIndex→center dots).
// NOTES: Timestamp-only predicates; no schema changes.

import SwiftUI
import CoreData

struct MeView: View {
    @Environment(\.managedObjectContext) private var ctx

    @State private var range: StatsRange = .week
    @State private var sessionStats: SessionStats = .init(count: 0, seconds: 0)
    @State private var allSessions: [Session] = []
    @State private var avgFocus: Double? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rangePickerHeader
                // Full-width Time card with date range header
                TimeCard(seconds: sessionStats.seconds, count: sessionStats.count, range: range, dateRange: dateWindowSubtitle(for: range))
                AdaptiveGrid {
                    StreaksCard(current: currentStreakDays, best: bestStreakDays)
                    FocusCard(average: avgFocus)
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: range) { _, _ in reload() }
    }

    private var rangePickerHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $range) {
                ForEach(StatsRange.allCases) { r in Text(label(for: r)).tag(r) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var currentStreakDays: Int { Stats.currentStreakDays(sessions: allSessions) }
    private var bestStreakDays: Int { Stats.bestStreakDays(sessions: allSessions) }

    private func reload() {
        sessionStats = (try? StatsHelper.fetchStats(in: ctx, range: range)) ?? .init(count: 0, seconds: 0)
        allSessions = fetchSessions(limit: nil, start: nil, end: nil)
        let (start, end) = StatsHelper.dateBounds(for: range)
        avgFocus = averageFocus(start: start, end: end)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) { content() }
    }
}

// MARK: - Cards

fileprivate struct TimeCard: View {
    let seconds: Int; let count: Int; let range: StatsRange
    var dateRange: String? = nil
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if let dateRange {
                    Text(dateRange)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(StatsHelper.formatDuration(seconds)).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(count) sessions").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Time trained: \(StatsHelper.formatDuration(seconds)), \(count) sessions")
    }
}

fileprivate struct StreaksCard: View {
    let current: Int; let best: Int
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Streaks").font(.headline)
                HStack {
                    VStack(alignment: .leading) { Text("Current").font(.caption).foregroundStyle(.secondary); Text("\(current) days").font(.title3).bold() }
                    Spacer()
                    VStack(alignment: .leading) { Text("Best").font(.caption).foregroundStyle(.secondary); Text("\(best) days").font(.title3).bold() }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streaks: current \(current) days, best \(best) days")
    }
}

fileprivate struct FocusCard: View {
    let average: Double?
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Focus").font(.headline)
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
        }
        .accessibilityLabel(average != nil ? "Focus average" : "No focus data")
    }
}

fileprivate struct FocusDots: View {
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
                        .fill(Color.black.opacity(opacityForDot(i))) // dark→light gradient look
                        .overlay(
                            Circle()
                                .stroke(isRinged ? Color.black.opacity(0.95) : Color.clear,
                                        lineWidth: isRinged ? 1.5 : 1)
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

fileprivate struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        MeView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
