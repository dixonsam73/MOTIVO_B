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


// CHANGE-ID: 20260119_203800_IdentityScopeSignOut_Activities
// CHANGE-ID: 20260228_225000_ActivityList_KeyboardDismiss
// CHANGE-ID: 20260316_194800_ActivityPrimarySelectorMove
// CHANGE-ID: 20260316_195500_ActivityHelperTextParity
// SCOPE: Add helper text matching InstrumentListView style/placement to the Activities section; no other UI or logic changes.
// SEARCH-TOKEN: 20260316_195500_ActivityHelperTextParity

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

    @FocusState private var isAddActivityFocused: Bool

    // Primary Activity (AppStorage)
    // Format: "core:<raw>" or "custom:<name>"
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

    // One-time notice flag to be consumed by ProfileView
    @AppStorage("primaryActivityFallbackNoticeNeeded") private var primaryActivityFallbackNoticeNeeded: Bool = false

    private var isSignedIn: Bool {
        PersistenceController.shared.currentUserID != nil
    }

    private var coreActivityTypes: [SessionActivityType] {
        SessionActivityType.allCases
    }

    private func scopedActivities() -> [UserActivity] {
        guard let owner = PersistenceController.shared.currentUserID else { return [] }
        return Array(activities).filter { ($0.ownerUserID ?? "") == owner }
    }

    var body: some View {
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
                            .focused($isAddActivityFocused)

                        Button(action: { if isSignedIn { add() } }) {
                            Text("Add")
                                .font(Theme.Text.body)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSignedIn || newActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section(header: Text("Your Activities").sectionHeader()) {
                    Text("Tap to set the default activity.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))

                    ForEach(coreActivityTypes) { type in
                        activityRow(
                            title: type.label,
                            ref: "core:\(type.rawValue)"
                        )
                    }

                    let items = scopedActivities()
                    if items.isEmpty {
                        if isSignedIn {
                            Text("No custom activities yet.")
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .font(Theme.Text.body)
                        }
                    } else {
                        ForEach(items, id: \.objectID) { activity in
                            let name = (activity.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                activityRow(
                                    title: name,
                                    ref: "custom:\(name)"
                                )
                            }
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

    @ViewBuilder
    private func activityRow(title: String, ref: String) -> some View {
        Button {
            guard primaryActivityRef != ref else { return }
            primaryActivityRef = ref
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(Theme.Text.body)
                    .foregroundStyle(.primary)

                Spacer()

                if primaryActivityRef == ref {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add() {
        guard PersistenceController.shared.currentUserID != nil else { return }

        let name = newActivity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            _ = try PersistenceController.shared.fetchOrCreateUserActivity(named: name, mapTo: 0, in: moc)
            try moc.save()
            newActivity = ""
            isAddActivityFocused = false
        } catch {
            print("Add activity error: \(error)")
        }
    }

    private func delete(at offsets: IndexSet) {
        guard isSignedIn else { return }

        let items = scopedActivities()
        for i in offsets {
            let activityObj = items[i]
            let name = (activityObj.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !name.isEmpty && primaryActivityRef.caseInsensitiveCompare("custom:\(name)") == .orderedSame {
                primaryActivityRef = "core:0"
                primaryActivityFallbackNoticeNeeded = true
            }

            moc.delete(activityObj)
        }

        do {
            try moc.save()
        } catch {
            print("Delete activity error: \(error)")
        }

        // [ROLLBACK ANCHOR] v7.8 Stage2 — post
    }
}
