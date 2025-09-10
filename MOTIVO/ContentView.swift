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

    // Core Data fetches — string-key sort descriptors per convention
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        animation: .default
    ) private var sessions: FetchedResults<Session>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var allTags: FetchedResults<Tag>

    // Filters
    @State private var selectedTagKeys: Set<String> = [] // lowercased
    @State private var showPublicOnly: Bool = false
    @State private var selectedInstrument: String? = nil

    // Sheet routing
    @State private var showAddEdit: Bool = false
    @State private var showTimer: Bool = false
    @State private var showProfile: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Stats Banner
                StatsBannerView(sessions: Array(sessions))
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Filters: Tags + Public + Instrument
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Tag chips
                        ForEach(allTagsArray, id: \.self) { name in
                            Chip(label: name, isSelected: selectedTagKeys.contains(name.lowercased())) {
                                toggleTag(name)
                            }
                        }
                        Divider().frame(height: 20)

                        // Public toggle
                        ToggleChip(label: "Public", isOn: $showPublicOnly)

                        Divider().frame(height: 20)

                        // Instrument filter (built from existing sessions)
                        ForEach(instruments, id: \.self) { ins in
                            Chip(label: ins, isSelected: selectedInstrument == ins) {
                                selectedInstrument = (selectedInstrument == ins) ? nil : ins
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // List of sessions
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
                    // Record (icon)
                    Button {
                        showTimer = true
                    } label: {
                        Image(systemName: "record.circle")
                            .imageScale(.large)
                            .accessibilityLabel("Record")
                    }

                    // Add (icon)
                    Button {
                        showAddEdit = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                            .accessibilityLabel("Add Session")
                    }

                    // Profile (text for now; later swap to avatar)
                    Button("Profile") {
                        showProfile = true
                    }
                }
            }
        }
        .sheet(isPresented: $showTimer) {
            PracticeTimerView()
        }
        .sheet(isPresented: $showAddEdit) {
            AddEditSessionView()
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .onAppear {
            // Optional one-time cleanup to prevent duplicate Tags differing only by case
            try? TagCanonicalizer.dedupe(in: ctx)
        }
    }

    // MARK: - Derived
    private var allTagsArray: [String] {
        allTags
            .compactMap { $0.name }
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

    // MARK: - Actions
    private func toggleTag(_ name: String) {
        let key = name.lowercased()
        if selectedTagKeys.contains(key) { selectedTagKeys.remove(key) } else { selectedTagKeys.insert(key) }
    }
}

// MARK: - Subviews
private struct Chip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.08))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

private struct ToggleChip: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(label)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.08))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

private struct SessionRow: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title?.isEmpty == false
                     ? session.title!
                     : (session.instrument?.isEmpty == false ? "\(session.instrument!) Practice" : "Practice Session"))
                    .font(.headline)
                Spacer()
                if session.isPublic { Image(systemName: "globe") }
            }
            HStack(spacing: 12) {
                Text(formatDuration(Int(session.durationSeconds)))
                if let ts = session.timestamp {
                    Text(relative(ts))
                }
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
