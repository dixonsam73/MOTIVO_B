// CHANGE-ID: 20251015_142943-me-mvp-fix3-timestamp-only
// SCOPE: Me dashboard (MVP) — fix crash by using only 'timestamp' in predicates/sorts (no 'startDate')
// NOTES: Reuses StatsRange & StatsHelper; no schema changes

import SwiftUI
import CoreData

struct MeView: View {
    @Environment(\.managedObjectContext) private var ctx

    @State private var range: StatsRange = .week
    @State private var sessionStats: SessionStats = .init(count: 0, seconds: 0)
    @State private var recentSessions: [Session] = []
    @State private var allSessions: [Session] = [] // for streaks over all time

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                AdaptiveGrid {
                    TimeCard(seconds: sessionStats.seconds, count: sessionStats.count, range: range)
                    StreaksCard(current: currentStreakDays, best: bestStreakDays)
                }

                RecentList(sessions: recentSessions)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: range) { _, _ in reload() }
    }

    // MARK: - Header (segmented control + date window)
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Me").font(.largeTitle).bold()
                Spacer()
            }
            Picker("Range", selection: $range) {
                ForEach(StatsRange.allCases) { r in
                    Text(label(for: r)).tag(r)
                }
            }
            .pickerStyle(.segmented)

            Text(dateWindowSubtitle(for: range))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Computed streaks
    private var currentStreakDays: Int { Stats.currentStreakDays(sessions: allSessions) }
    private var bestStreakDays: Int { Stats.bestStreakDays(sessions: allSessions) }

    // MARK: - Actions
    private func reload() {
        // Totals via StatsHelper (throws)
        sessionStats = (try? StatsHelper.fetchStats(in: ctx, range: range)) ?? .init(count: 0, seconds: 0)

        // Recent sessions within current date bounds (limit 10)
        let (start, end) = StatsHelper.dateBounds(for: range)
        recentSessions = fetchSessions(limit: 10, start: start, end: end)

        // All sessions for streaks (no date bounds)
        allSessions = fetchSessions(limit: nil, start: nil, end: nil)
    }

    private func fetchSessions(limit: Int?, start: Date?, end: Date?) -> [Session] {
        let req = NSFetchRequest<Session>(entityName: "Session")
        var preds: [NSPredicate] = []
        if let start, let end {
            preds.append(NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate))
        } else if let start {
            preds.append(NSPredicate(format: "timestamp >= %@", start as NSDate))
        } else if let end {
            preds.append(NSPredicate(format: "timestamp < %@", end as NSDate))
        }
        if !preds.isEmpty {
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        }
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        if let limit { req.fetchLimit = limit }

        do { return try ctx.fetch(req) } catch { return [] }
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
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return "\(df.string(from: start)) – \(df.string(from: end.addingTimeInterval(-86400)))"
    }
}

// MARK: - Adaptive grid container
fileprivate struct AdaptiveGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            content()
        }
    }
}

// MARK: - Cards

fileprivate struct TimeCard: View {
    let seconds: Int
    let count: Int
    let range: StatsRange
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Time trained").font(.headline)
                Text(StatsHelper.formatDuration(seconds))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(count) sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Time trained: \(StatsHelper.formatDuration(seconds)), \(count) sessions")
    }
}

fileprivate struct StreaksCard: View {
    let current: Int
    let best: Int
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Streaks").font(.headline)
                HStack {
                    VStack(alignment: .leading) {
                        Text("Current").font(.caption).foregroundStyle(.secondary)
                        Text("\(current) days").font(.title3).bold()
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Best").font(.caption).foregroundStyle(.secondary)
                        Text("\(best) days").font(.title3).bold()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streaks: current \(current) days, best \(best) days")
    }
}

fileprivate struct RecentList: View {
    let sessions: [Session]
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent sessions").font(.headline)
                if sessions.isEmpty {
                    Text("No sessions in this period yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions.prefix(10), id: \.objectID) { s in
                        RecentRow(session: s)
                        if s.objectID != sessions.prefix(10).last?.objectID {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

fileprivate struct RecentRow: View {
    let session: Session
    var body: some View {
        HStack {
            Text(shortDate(from: session))
            Spacer()
            Text(durationString(from: session)).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session on \(shortDate(from: session)), duration \(durationString(from: session))")
    }

    private func shortDate(from s: Session) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let d = (s.value(forKey: "timestamp") as? Date) ?? Date.distantPast
        return df.string(from: d)
    }

    private func durationString(from s: Session) -> String {
        let secs = (s.value(forKey: "durationSeconds") as? Int) ?? 0
        return StatsHelper.formatDuration(secs)
    }
}

// MARK: - Card container
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
        MeView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
