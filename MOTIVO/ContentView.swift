//
//  ContentView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  ContentView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  ContentView.swift
//  MOTIVO
//

//
//  ContentView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  ContentView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        animation: .default
    ) private var sessions: FetchedResults<Session>

    @AppStorage("filtersExpanded") private var filtersExpanded = false
    @AppStorage("publicOnly") private var publicOnly = false

    @State private var selectedInstrument: Instrument? = nil
    @State private var selectedTagIDs: Set<NSManagedObjectID> = []

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var instruments: FetchedResults<Instrument>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var tags: FetchedResults<Tag>

    @State private var showAdd = false
    @State private var showProfile = false
    @State private var showTimer = false

    var body: some View {
        NavigationStack {
            List {
                Section { StatsBannerView(sessions: Array(filteredSessions)) }

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
                    if filteredSessions.isEmpty {
                        Text("No sessions match your filters yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredSessions, id: \.objectID) { session in
                            NavigationLink(destination: SessionDetailView(session: session)) {
                                SessionRow(session: session)
                            }
                        }
                        // ✅ Swipe-to-delete restored
                        .onDelete(perform: deleteSessions)
                    }
                }
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
            .sheet(isPresented: $showAdd) {
                AddEditSessionView(isPresented: $showAdd)
            }
            .sheet(isPresented: $showTimer) {
                PracticeTimerView(isPresented: $showTimer)
            }
            .sheet(isPresented: $showProfile) {
                ProfileView(onClose: { showProfile = false })
            }
        }
    }

    private var filteredSessions: [Session] {
        sessions.filter { s in
            if publicOnly && s.isPublic == false { return false }
            if let sel = selectedInstrument, s.instrument != sel { return false }
            if !selectedTagIDs.isEmpty {
                let sTagIDs: Set<NSManagedObjectID> = ((s.tags as? Set<Tag>) ?? [])
                    .reduce(into: []) { $0.insert($1.objectID) }
                if sTagIDs.intersection(selectedTagIDs).isEmpty { return false }
            }
            return true
        }
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

// ——— helpers (unchanged) ———
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
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let secs = sessions.filter { ($0.timestamp ?? Date()) >= startOfWeek }
            .map { Int($0.durationSeconds) }
            .reduce(0, +)
        return "\(secs / 60) min"
    }
    private var currentStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let uniqueDays = Set(sessions.compactMap { $0.timestamp?.stripToDay(using: calendar) })
        var streak = 0
        var day = Date().stripToDay(using: calendar)
        while uniqueDays.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }
    private var bestStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let uniqueDays = Set(sessions.compactMap { $0.timestamp?.stripToDay(using: calendar) }).sorted()
        var best = 0, run = 0, prev: Date?
        for d in uniqueDays {
            if let p = prev,
               let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: p),
               Calendar.current.isDate(d, inSameDayAs: nextDay) {
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
fileprivate struct StatCell: View { let title: String; let value: String
    var body: some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.headline); Text(title).font(.caption).foregroundStyle(.secondary) } }
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
                HStack { Text("Filters").font(.subheadline).bold(); Spacer(); Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary) }
            }
            if filtersExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Public only", isOn: $publicOnly)
                    Menu {
                        Button("Any Instrument") { selectedInstrument = nil }
                        Divider()
                        ForEach(instruments, id: \.objectID) { inst in
                            Button { selectedInstrument = inst } label: {
                                HStack { Text(inst.name ?? "(Unnamed)"); if selectedInstrument?.objectID == inst.objectID { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: { HStack { Text("Instrument"); Spacer(); Text(selectedInstrument?.name ?? "Any").foregroundStyle(.secondary) } }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags").font(.subheadline)
                        if tags.isEmpty { Text("No tags yet").foregroundStyle(.secondary) }
                        else {
                            ForEach(tags, id: \.objectID) { tag in
                                Button {
                                    let id = tag.objectID
                                    if selectedTagIDs.contains(id) { selectedTagIDs.remove(id) }
                                    else { selectedTagIDs.insert(id) }
                                } label: {
                                    HStack { Text(tag.name ?? "(Untitled)"); Spacer(); if selectedTagIDs.contains(tag.objectID) { Image(systemName: "checkmark") } }
                                }
                            }
                        }
                    }
                }.padding(.top, 8)
            }
        }
    }
}
fileprivate struct SessionRow: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayTitle).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(formattedDuration) • \(relativeTime)").font(.subheadline).foregroundStyle(.secondary)
                if !session.isPublic {
                    Image(systemName: "eye.slash").foregroundStyle(.secondary).imageScale(.small).padding(.leading, 6)
                }
            }
            if let notes = session.notes, !notes.isEmpty {
                Text(notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 12) {
                let tags = ((session.tags as? Set<Tag>) ?? []).compactMap { $0.name }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                if !tags.isEmpty { Text(tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                let attachmentCount = ((session.attachments as? Set<Attachment>) ?? []).count
                if attachmentCount > 0 { HStack(spacing: 4) { Image(systemName: "paperclip"); Text("\(attachmentCount)") }.font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var displayTitle: String {
        if let t = session.title, !t.isEmpty { return t }
        if let name = session.instrument?.name, !name.isEmpty { return "\(name) Practice" }
        return "Practice"
    }
    private var formattedDuration: String {
        let total = Int(session.durationSeconds); let h = total/3600; let m = (total%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private var relativeTime: String {
        guard let ts = session.timestamp else { return "" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: ts, relativeTo: Date())
    }
}
fileprivate extension Date {
    func stripToDay(using cal: Calendar) -> Date {
        let c = cal.dateComponents([.year,.month,.day], from: self)
        return cal.date(from: c) ?? self
    }
}
