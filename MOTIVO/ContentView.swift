//
//  ContentView.swift
//  MOTIVO
//
//  v7.8 Stage 2 — Filter: include custom activities in Activity picker
//  - Adds UserActivity fetch and includes custom names in the Activity filter.
//  - Introduces ActivityFilter enum: .any, .core(ActivityType), .custom(String).
//  - Filtering supports core (activityType) and customs via userActivityLabel/activityDetail.
//  - Whole-file replacement; no migrations.
//
//  [ROLLBACK ANCHOR] v7.8 Stage2 Filter — pre (before custom activities in filter)
//
import SwiftUI
import CoreData
import Combine

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

// New: unified filter type for Activity (core or custom)
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

    // New: fetch user-local custom activities for filter menu
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

    // Sheets (original buttons)
    @State private var showProfile = false
    @State private var showTimer = false
    @State private var showAdd = false

    // Debounce
    @State private var debounceCancellable: AnyCancellable?

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {

                // ---------- Filter bar OUTSIDE the List ----------
                FilterBar(
                    filtersExpanded: $filtersExpanded,
                    instruments: Array(instruments),
                    customNames: userActivities.map { ($0.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                    selectedInstrument: $selectedInstrument,
                    selectedActivity: $selectedActivity,
                    selectedScope: $selectedScope,
                    searchText: $searchText
                )
                .padding(.horizontal)

                // ---------- Content List ----------
                List {
                    // Stats
                    Section {
                        let statsInput: [Session] = filteredSessions
                        StatsBannerView(sessions: statsInput)
                    }

                    // Sessions
                    Section {
                        let rows: [Session] = filteredSessions
                        if rows.isEmpty {
                            Text("No sessions match your filters yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(rows, id: \.objectID) { session in
                                NavigationLink(destination: SessionDetailView(session: session)) {
                                    SessionRow(session: session)
                                }
                            }
                            .onDelete(perform: deleteSessions)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Motivo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: { Text("Profile") }
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
            // Debounce lifecycle (no deprecated onChange)
            .task {
                setUpDebounce()
            }
            .task(id: searchText) {
                debounceCancellable?.cancel()
                debounceCancellable = Just(searchText)
                    .delay(for: .milliseconds(250), scheduler: RunLoop.main)
                    .sink { debouncedQuery = $0 }
            }
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
                // Match either explicit label or exact detail match (case-insensitive)
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

// MARK: - Filter bar OUTSIDE the List (menu-style Pickers)

fileprivate struct FilterBar: View {
    @Binding var filtersExpanded: Bool
    let instruments: [Instrument]
    let customNames: [String]
    @Binding var selectedInstrument: Instrument?
    @Binding var selectedActivity: ActivityFilter
    @Binding var selectedScope: FeedScope
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { filtersExpanded.toggle() } } label: {
                HStack {
                    Text("Filters").font(.subheadline).bold()
                    Spacer()
                    Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            if filtersExpanded {
                VStack(alignment: .leading, spacing: 10) {
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
                    }
                }
            }
        }
    }
}

// MARK: - Stats (unchanged appearance)

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
            VStack(alignment: .leading) {
                Text("Sessions: \(count)")
                    .font(.subheadline)
                Text("Total Time: \(totalTimeDisplay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Row (shows derived title and subtitle)

fileprivate struct SessionRow: View {
    @ObservedObject var session: Session

    private var feedTitle: String {
        SessionActivity.feedTitle(for: session)
    }
    private var feedSubtitle: String {
        SessionActivity.feedSubtitle(for: session)
    }
    private var attachmentCount: Int {
        (session.attachments as? Set<Attachment>)?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(feedTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                if attachmentCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text("\(attachmentCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text(feedSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

//  [ROLLBACK ANCHOR] v7.8 Stage2 Filter — post
