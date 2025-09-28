//
//  ActivityListView.swift
//  MOTIVO
//
//  Auto-generated for v7.8 prep
//

import SwiftUI
import CoreData

struct ActivityListView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    // Custom activities are user-local (scoped by ownerUserID)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "displayName", ascending: true)],
        animation: .default
    ) private var activities: FetchedResults<UserActivity>

    @State private var newActivity: String = ""

    var body: some View {
        let isSignedIn = (PersistenceController.shared.currentUserID != nil)
        NavigationView {
            List {
                Section(header: Text("Add Activity")) {
                    if !isSignedIn {
                        Text("Sign in to add custom activities.")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("e.g., Sight-reading", text: $newActivity)
                        Button("Add") { if isSignedIn { add() } }
                            .disabled(newActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section(header: Text("Your Activities")) {
                    let items = Array(activities)
                    if items.isEmpty {
                        Text("No custom activities yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items, id: \.objectID) { a in
                            Text(a.displayName ?? "-")
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Activities")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func add() {
        let name = newActivity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try PersistenceController.shared.fetchOrCreateUserActivity(named: name, mapTo: 0, in: moc)
            try moc.save()
            newActivity = ""
        } catch {
            print("Add activity error: \(error)")
        }
    }

    private func delete(at offsets: IndexSet) {
        let items = Array(activities)
        for i in offsets {
            moc.delete(items[i])
        }
        do { try moc.save() } catch { print("Delete activity error: \(error)") }
    }
}
