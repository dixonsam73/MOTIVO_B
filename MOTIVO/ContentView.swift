////
//  ContentView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData
import Combine

struct ContentView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        SessionsRootView(userID: auth.currentUserID)
            .id(auth.currentUserID ?? "nil-user")
    }
}

fileprivate struct SessionsRootView: View {
    @Environment(\.managedObjectContext) private var viewContext

    let userID: String?

    @FetchRequest private var sessions: FetchedResults<Session>

    @AppStorage("filtersExpanded") private var filtersExpanded = false
    @AppStorage("publicOnly") private var publicOnly = false

    @State private var selectedInstrument: Instrument? = nil
    @State private var selectedTagIDs: Set<NSManagedObjectID> = []
    @State private var selectionSnapshot: Set<NSManagedObjectID> = []

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var instruments: FetchedResults<Instrument>

    @FetchRequest private var tags: FetchedResults<Tag>

    // Single refresh key to drive list re-render
    @State private var refreshKey: Int = 0

    @State private var showAdd = false
    @State private var showProfile = false
    @State private var showTimer = false

    init(userID: String?) {
        self.userID = userID
        let predicate: NSPredicate = {
            if let uid = userID { return NSPredicate(format: "ownerUserID == %@", uid) }
            else { return NSPredicate(value: false) }
        }()
        _sessions = FetchRequest<Session>(
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
            predicate: predicate,
            animation: .default
        )
        _tags = FetchRequest<Tag>(
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
            predicate: predicate,
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Compute once to keep generics simpler
                    let statsInput: [Session] = filteredSessions
                    StatsBannerView(sessions: statsInput)
                }

                Section {
                    FilterPanel(
                        filtersExpanded: $filtersExpanded,
                        publicOnly: $publicOnly,
                        instruments: Array(instruments),
                        selectedInstrument: $selectedInstrument,
                        tags: Array(tags),
                        selectedTagIDs: $selectedTagIDs
                    )
                }

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
            .id(refreshKey)
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
            .sheet(isPresented: $showAdd) {
                AddEditSessionView(isPresented: $showAdd)
            }
            .sheet(isPresented: $showTimer) {
                PracticeTimerView(isPresented: $showTimer)
            }
            .sheet(isPresented: $showProfile) {
                ProfileView(onClose: { showProfile = false })
            }
            // ✅ iOS 17 onChange style (old,new)
            .onChange(of: filtersExpanded) { _, newValue in
                if newValue { selectionSnapshot = selectedTagIDs }
            }
            // Listen for Attachment inserts/deletes in ANY context and bump the key
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: nil)) { note in
                if let inserts = note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>,
                   inserts.contains(where: { $0.entity.name == "Attachment" }) {
                    refreshKey &+= 1
                }
                if let deletes = note.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>,
                   deletes.contains(where: { $0.entity.name == "Attachment" }) {
                    refreshKey &+= 1
                }
            }
            // Also listen for saves (self or merges) and nudge the list + refresh relationships
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: nil)) { _ in
                viewContext.perform {
                    viewContext.refreshAllObjects()
                }
                refreshKey &+= 1
            }
        }
    }

    // MARK: - Filtering (split into simple steps to aid type-checker)

    private var filteredSessions: [Session] {
        var out: [Session] = Array(sessions)

        if publicOnly {
            out = out.filter { $0.isPublic }
        }

        if let sel = selectedInstrument {
            let selID = sel.objectID
            out = out.filter { $0.instrument?.objectID == selID }
        }

        if !selectedTagIDs.isEmpty {
            out = out.filter { sessionHasSelectedTags($0) }
        }

        return out
    }

    private func sessionHasSelectedTags(_ s: Session) -> Bool {
        guard let set = s.tags as? Set<Tag>, !set.isEmpty else { return false }
        let ids: Set<NSManagedObjectID> = Set(set.map { $0.objectID })
        return !ids.intersection(selectedTagIDs).isEmpty
    }

    // MARK: - Delete

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = filteredSessions[index]
            viewContext.delete(session)
        }
        do {
            try viewContext.save()
        } catch {
            print("Delete error: \(error)")
        }
    }
}

// ——— helpers (simplified to keep expressions small) ———
fileprivate struct StatsBannerView: View {
    let sessions: [Session]
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            StatCell(title: "This Week", value: minutesThisWeekString)
            StatCell(title: "Current Streak", value: "\(currentStreak) d")
            StatCell(title: "Best Streak", value: "\(bestStreak) d")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var minutesThisWeekString: String {
        let now = Date()
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let startOfWeek = calendar.date(from: comps) ?? now

        let durations: [Int] = sessions.compactMap { s in
            guard let ts = s.timestamp else { return nil }
            return ts >= startOfWeek ? Int(s.durationSeconds) : nil
        }

        let total = durations.reduce(0, +)
        return "\(total / 60) min"
    }

    private var currentStreak: Int {
        let timestamps: [Date] = sessions.compactMap { $0.timestamp }
        guard !timestamps.isEmpty else { return 0 }

        let days: [Date] = timestamps.map { calendar.startOfDay(for: $0) }
        let unique: Set<Date> = Set(days)

        var streak = 0
        var probe = calendar.startOfDay(for: Date())
        while unique.contains(probe) {
            streak += 1
            probe = calendar.date(byAdding: .day, value: -1, to: probe) ?? probe
        }
        return streak
    }

    private var bestStreak: Int {
        let timestamps: [Date] = sessions.compactMap { $0.timestamp }
        guard !timestamps.isEmpty else { return 0 }

        let uniqueDaysSorted: [Date] = Array(Set(timestamps.map { calendar.startOfDay(for: $0) })).sorted()

        var best = 0
        var run = 0
        var prev: Date? = nil

        for d in uniqueDaysSorted {
            if let p = prev,
               let next = calendar.date(byAdding: .day, value: 1, to: p),
               calendar.isDate(d, inSameDayAs: next) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            prev = d
        }
        return best
    }
}

fileprivate struct StatCell: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

fileprivate struct FilterPanel: View {
    @Binding var filtersExpanded: Bool
    @Binding var publicOnly: Bool
    let instruments: [Instrument]
    @Binding var selectedInstrument: Instrument?
    let tags: [Tag]
    @Binding var selectedTagIDs: Set<NSManagedObjectID>
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
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Public only", isOn: $publicOnly)

                    Menu {
                        Button("Any Instrument") { selectedInstrument = nil }
                        Divider()
                        ForEach(instruments, id: \.objectID) { inst in
                            Button { selectedInstrument = inst } label: {
                                HStack {
                                    Text(inst.name ?? "(Unnamed)")
                                    if selectedInstrument?.objectID == inst.objectID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Instrument")
                            Spacer()
                            Text(selectedInstrument?.name ?? "Any").foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags").font(.subheadline)
                        if tags.isEmpty {
                            Text("No tags yet").foregroundStyle(.secondary)
                        } else {
                            ForEach(tags, id: \.objectID) { tag in
                                Button {
                                    let id = tag.objectID
                                    if selectedTagIDs.contains(id) { selectedTagIDs.remove(id) }
                                    else { selectedTagIDs.insert(id) }
                                } label: {
                                    HStack {
                                        Text(tag.name ?? "(Untitled)")
                                        Spacer()
                                        if selectedTagIDs.contains(tag.objectID) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

fileprivate struct SessionRow: View {
    let session: Session

    private var displayTitle: String {
        if let t = session.title, !t.isEmpty { return t }
        if let name = session.instrument?.name, !name.isEmpty { return "\(name) Practice" }
        return "Practice"
    }

    private var formattedDuration: String {
        let seconds = Int(session.durationSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: session.timestamp ?? Date(), relativeTo: Date())
    }

    private var attachmentCount: Int {
        let set: Set<Attachment> = (session.attachments as? Set<Attachment>) ?? []
        return set.count
    }

    private var tagNames: [String] {
        let set: Set<Tag> = (session.tags as? Set<Tag>) ?? []
        return set.compactMap { $0.name }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayTitle).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(formattedDuration) • \(relativeTime)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !session.isPublic {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                        .padding(.leading, 6)
                }
            }
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                if !tagNames.isEmpty {
                    Text(tagNames.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        }
        .padding(.vertical, 4)
    }
}
