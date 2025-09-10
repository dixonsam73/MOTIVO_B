//
//  ContentView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var ctx

    // Core Data fetches
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        animation: .default
    ) private var sessions: FetchedResults<Session>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var allTags: FetchedResults<Tag>

    // Filters
    @AppStorage("showFilters") private var showFilters: Bool = true
    @State private var selectedTagKeys: Set<String> = []
    @State private var showPublicOnly: Bool = false
    @State private var selectedInstrument: String? = nil
    @State private var showTagsDisclosure: Bool = false

    // Sheet routing
    @State private var showAddEdit: Bool = false
    @State private var showTimer: Bool = false
    @State private var showProfile: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                StatsBannerView(sessions: Array(sessions))
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Filters
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup(isExpanded: $showFilters) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Public only", isOn: $showPublicOnly)

                            HStack {
                                Text("Instrument")
                                Spacer()
                                Picker("Instrument", selection: Binding(
                                    get: { selectedInstrument ?? "All" },
                                    set: { newValue in
                                        selectedInstrument = (newValue == "All") ? nil : newValue
                                    }
                                )) {
                                    Text("All").tag("All")
                                    ForEach(instruments, id: \.self) { ins in
                                        Text(ins).tag(ins)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            if !allTagsArray.isEmpty {
                                DisclosureGroup(isExpanded: $showTagsDisclosure) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 4) {
                                                ForEach(allTagsArray, id: \.self) { name in
                                                    let key = name.lowercased()
                                                    Button {
                                                        if selectedTagKeys.contains(key) { selectedTagKeys.remove(key) }
                                                        else { selectedTagKeys.insert(key) }
                                                    } label: {
                                                        HStack {
                                                            Image(systemName: selectedTagKeys.contains(key) ? "checkmark.circle.fill" : "circle")
                                                                .foregroundStyle(.secondary)
                                                            Text(name)
                                                            Spacer()
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                    .padding(.vertical, 4)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        .frame(maxHeight: 180)

                                        if !selectedTagKeys.isEmpty {
                                            Button {
                                                selectedTagKeys.removeAll()
                                            } label: {
                                                Label("Clear selected tags", systemImage: "xmark.circle")
                                            }
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 4)
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "tag")
                                        Text("Tags")
                                        if !selectedTagKeys.isEmpty {
                                            Spacer()
                                            TagPill(text: "\(selectedTagKeys.count) selected")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("Filters")
                            Spacer()
                            if let ins = selectedInstrument { TagPill(text: ins) }
                            if showPublicOnly { TagPill(text: "Public") }
                            if !selectedTagKeys.isEmpty { TagPill(text: "\(selectedTagKeys.count) tag\(selectedTagKeys.count == 1 ? "" : "s")") }
                        }
                        .contentShape(Rectangle())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Feed
                List(filteredSessions, id: \.objectID) { s in
                    NavigationLink(destination: SessionDetailView(session: s)) {
                        SessionRow(session: s)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Motivo")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showTimer = true } label: {
                        Image(systemName: "record.circle")
                            .imageScale(.large)
                            .accessibilityLabel("Record")
                    }
                    Button { showAddEdit = true } label: {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                            .accessibilityLabel("Add Session")
                    }
                    Button("Profile") { showProfile = true }
                }
            }
        }
        .sheet(isPresented: $showTimer) { PracticeTimerView() }
        .sheet(isPresented: $showAddEdit) { AddEditSessionView() }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .onAppear {
            try? TagCanonicalizer.dedupe(in: ctx)
        }
    }

    // MARK: - Derived
    private var allTagsArray: [String] {
        allTags.compactMap { $0.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var instruments: [String] {
        let names = sessions
            .compactMap { $0.instrument?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let uniq = Array(Set(names))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return uniq
    }

    private var filteredSessions: [Session] {
        sessions.filter { s in
            if showPublicOnly && s.isPublic == false { return false }
            if let ins = selectedInstrument, (s.instrument ?? "") != ins { return false }
            if !selectedTagKeys.isEmpty {
                let names = ((s.tags as? Set<Tag>) ?? []).compactMap { $0.name?.lowercased() }
                for key in selectedTagKeys { if !names.contains(key) { return false } }
            }
            return true
        }
    }
}

// MARK: - Subviews
private struct TagPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(8)
    }
}

private struct SessionRow: View {
    let session: Session
    var body: some View {
        let attachCount = ((session.attachments as? Set<Attachment>) ?? []).count
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title?.isEmpty == false
                     ? session.title!
                     : (session.instrument?.isEmpty == false ? "\(session.instrument!) Practice" : "Practice Session"))
                    .font(.headline)
                Spacer()
                if attachCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text("\(attachCount)")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                // 🔄 Show eye.slash only if private
                if !session.isPublic {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Text(formatDuration(Int(session.durationSeconds)))
                if let ts = session.timestamp { Text(relative(ts)) }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            if let tags = (session.tags as? Set<Tag>)?.compactMap({ $0.name }).sorted(), !tags.isEmpty {
                Text(tags.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StatsBannerView: View {
    let sessions: [Session]
    var body: some View {
        let mins = Stats.minutesThisWeek(sessions: sessions)
        let cur  = Stats.currentStreakDays(sessions: sessions)
        let best = Stats.bestStreakDays(sessions: sessions)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("This week")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(mins)m • Streak \(cur)d • Best \(best)d")
                    .font(.headline)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
    }
}

// MARK: - Formatters
private func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    if s == 0 { return "\(m)m" }
    return String(format: "%dm %02ds", m, s)
}

private func relative(_ date: Date) -> String {
    let fmt = RelativeDateTimeFormatter()
    fmt.unitsStyle = .short
    return fmt.localizedString(for: date, relativeTo: Date())
}
