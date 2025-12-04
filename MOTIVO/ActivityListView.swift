//
//  ActivityListView.swift
//  MOTIVO_making sure github is working
//
//  v7.8 Stage 2 — Primary fallback + one-time notice flag
//
//  Changes:
//  - When a custom activity is deleted and it matches the current Primary (custom),
//    reset Primary to Practice ("core:0") and set a one-time notice flag for ProfileView.
//  - No schema/migrations. User-local customs only.
//

import SwiftUI
import CoreData

struct ActivityListView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    // [ROLLBACK ANCHOR] v7.8 Stage2 — pre

    // Custom activities are user-local (scoped by ownerUserID)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "displayName", ascending: true)],
        animation: .default
    ) private var activities: FetchedResults<UserActivity>

    @State private var newActivity: String = ""

    // Primary Activity (AppStorage)
    // Format: "core:<raw>" or "custom:<name>"
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"
    // One-time notice flag to be consumed by ProfileView
    @AppStorage("primaryActivityFallbackNoticeNeeded") private var primaryFallbackNoticeNeeded: Bool = false

    var body: some View {
        let isSignedIn = (PersistenceController.shared.currentUserID != nil)
        NavigationStack {
            Form {
                Section(header: Text("Add Activity").sectionHeader()) {
                    if !isSignedIn {
                        Text("Sign in to add custom activities.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .font(Theme.Text.body)
                    }
                    HStack {
                        TextField("e.g., Sight-reading", text: $newActivity)
                            .font(Theme.Text.body)
                            .textInputAutocapitalization(.words)
                        Button(action: { if isSignedIn { add() } }) {
                            Text("Add").font(Theme.Text.body)
                        }
                        .disabled(newActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section(header: Text("Your Activities").sectionHeader()) {
                    let items = Array(activities)
                    if items.isEmpty {
                        Text("No custom activities yet.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .font(Theme.Text.body)
                    } else {
                        ForEach(items, id: \.objectID) { a in
                            Text(a.displayName ?? "-")
                                .font(Theme.Text.body)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Activities")
                        .font(Theme.Text.pageTitle)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close activities")
                }
            }
            .appBackground()
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
            let activityObj = items[i]
            let name = (activityObj.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // If the deleted item is the current Primary (custom), reset to Practice and set one-time notice
            if !name.isEmpty && primaryActivityRef.caseInsensitiveCompare("custom:\(name)") == .orderedSame {
                primaryActivityRef = "core:0" // Practice
                primaryFallbackNoticeNeeded = true
            }

            moc.delete(activityObj)
        }
        do { try moc.save() } catch { print("Delete activity error: \(error)") }

        // [ROLLBACK ANCHOR] v7.8 Stage2 — post
    }
}
