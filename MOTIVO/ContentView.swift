//
//  ContentView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var moc

    // Feed sessions
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.timestamp, ascending: false)],
        animation: .default
    )
    private var sessions: FetchedResults<Session>

    // Single profile
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    )
    private var profiles: FetchedResults<Profile>

    @State private var showingAdd = false
    @State private var showingProfile = false
    @State private var showingTimer = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton().disabled(sessions.isEmpty)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        // Record (primary logging flow)
                        Button {
                            showingTimer = true
                        } label: {
                            Image(systemName: "record.circle.fill")
                                .imageScale(.large)
                        }
                        .accessibilityLabel("Record Practice")

                        // Manual entry
                        Button {
                            showingAdd = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .imageScale(.large)
                        }
                        .accessibilityLabel("Add Session Manually")

                        // Profile
                        Button {
                            showingProfile = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .imageScale(.large)
                        }
                        .accessibilityLabel("Profile")
                    }
                }
                .sheet(isPresented: $showingAdd) {
                    AddEditSessionView()
                        .environment(\.managedObjectContext, moc)
                }
                .sheet(isPresented: $showingProfile) {
                    ProfileView()
                        .environment(\.managedObjectContext, moc)
                }
                .sheet(isPresented: $showingTimer) {
                    PracticeTimerView()
                        .environment(\.managedObjectContext, moc)
                }
                .task { ensureProfileExists() }
        }
    }

    // MARK: - Computed

    private var navTitle: String {
        if let name = profiles.first?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Motivo · \(name)"
        }
        return "Motivo"
    }

    // MARK: - Composed content

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            EmptyStateView()
        } else {
            List {
                ForEach(sessions, id: \.objectID) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Actions

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let s = sessions[index]
            moc.delete(s)
        }
        try? moc.save()
    }

    private func ensureProfileExists() {
        guard profiles.first == nil else { return }
        let p = Profile(context: moc)
        p.id = UUID()
        p.name = ""
        p.primaryInstrument = ""
        try? moc.save()
    }
}

// MARK: - Row

fileprivate struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((session.title ?? "").isEmpty ? "Untitled" : (session.title ?? "Untitled"))
                .font(.headline)

            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(formatDuration(session.durationSeconds))
                Text("•")
                Text(relativeTimestamp(session.timestamp))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Empty State

fileprivate struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            Image(systemName: "metronome.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
            Text("No sessions yet")
                .font(.headline)
            Text("Tap the ● Record button to log a live session, or + to add one manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Format helpers

fileprivate func formatDuration(_ value: Int64) -> String {
    let total = Int(value)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

fileprivate func relativeTimestamp(_ date: Date?) -> String {
    let date = date ?? Date()
    let rel = RelativeDateTimeFormatter()
    rel.unitsStyle = .short
    return rel.localizedString(for: date, relativeTo: Date())
}
/*
#Preview {
    let context = PersistenceController.preview.container.viewContext
    return ContentView()
        .environment(\.managedObjectContext, context)
}
*/
