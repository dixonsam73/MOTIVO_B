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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.timestamp, ascending: false)],
        animation: .default
    )
    private var sessions: FetchedResults<Session>

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        ForEach(sessions) { session in
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
            .navigationTitle("Motivo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton().disabled(sessions.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Add Session")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEditSessionView()
                    .environment(\.managedObjectContext, moc)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let s = sessions[index]
            moc.delete(s)
        }
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
            Image(systemName: "metronome.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
            Text("No sessions yet")
                .font(.headline)
            Text("Tap the + button to log your first practice session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
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

