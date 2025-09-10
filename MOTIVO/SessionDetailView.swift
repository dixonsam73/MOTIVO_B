//
//  SessionDetailView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let session: Session

    var body: some View {
        List {
            // Summary
            Section(header: Text("Summary")) {
                HStack {
                    Text("When")
                    Spacer()
                    Text(dateTime(session.timestamp))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(formatDuration(Int(session.durationSeconds)))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Instrument")
                    Spacer()
                    Text(session.instrument?.isEmpty == false ? session.instrument! : "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Privacy")
                    Spacer()
                    Text(session.isPublic ? "Public" : "Private")
                        .foregroundStyle(.secondary)
                }
            }

            // Mood / Effort
            Section(header: Text("Feel")) {
                MeterRow(label: "Mood", value: Int(session.mood))
                MeterRow(label: "Effort", value: Int(session.effort))
            }

            // Tags
            if let tags = (session.tags as? Set<Tag>)?.compactMap({ $0.name }).sorted(), !tags.isEmpty {
                Section(header: Text("Tags")) {
                    Text(tags.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }

            // Notes
            if let notes = session.notes, !notes.isEmpty {
                Section(header: Text("Notes")) {
                    Text(notes)
                }
            }

            // Attachments (new)
            AttachmentsSectionView(attachments: attachmentsArray)
        }
        .navigationTitle(session.title?.isEmpty == false ? session.title! : "Practice Session")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink("Edit") {
                    AddEditSessionView(session: session)
                }
                Button(role: .destructive) {
                    deleteSession()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    // MARK: - Derived
    private var attachmentsArray: [Attachment] {
        ((session.attachments as? Set<Attachment>) ?? []).sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    // MARK: - Actions
    private func deleteSession() {
        ctx.delete(session)
        try? ctx.save()
        dismiss()
    }
}

// MARK: - Subviews
private struct MeterRow: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value)")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(value), total: 10)
        }
    }
}

// MARK: - Helpers
private func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    if s == 0 { return "\(m)m" }
    return String(format: "%dm %02ds", m, s)
}

private func dateTime(_ date: Date?) -> String {
    guard let date else { return "—" }
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df.string(from: date)
}
