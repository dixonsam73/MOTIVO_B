// CHANGE-ID: 20260406_095100_Ensembles_FollowingList_LocalEditor_b41a
// SCOPE: FollowingListView — add local-only Ensemble creation/edit/rename/delete using the existing Following list as the single member-selection surface; preserve follow graph and profile navigation outside editor mode.
// SEARCH-TOKEN: 20260406_095100_Ensembles_FollowingList_LocalEditor_b41a

import SwiftUI

struct FollowingListView: View {

    private enum EnsembleEditorMode: Equatable {
        case create
        case edit(String)
    }

    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var ensembleStore = EnsembleStore.shared

    @State private var directory: [String: DirectoryAccount] = [:]
    @State private var editorMode: EnsembleEditorMode? = nil
    @State private var draftName: String = ""
    @State private var selectedUserIDs: Set<String> = []
    @State private var pendingDeleteEnsembleID: String? = nil

    private func alphabeticalSortKey(for userID: String) -> String {
        let fallback = userID.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard let rawName = directory[userID]?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return fallback
        }

        let parts = rawName
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !parts.isEmpty else { return fallback }

        if parts.count >= 2 {
            let surname = parts.last ?? ""
            let givenNames = parts.dropLast().joined(separator: " ")
            return "\(surname.localizedLowercase) \(givenNames.localizedLowercase)"
        } else {
            return parts[0].localizedLowercase
        }
    }

    private var userIDs: [String] {
        Array(followStore.following).sorted {
            let lhsKey = alphabeticalSortKey(for: $0)
            let rhsKey = alphabeticalSortKey(for: $1)
            if lhsKey == rhsKey {
                return $0.localizedLowercase < $1.localizedLowercase
            }
            return lhsKey < rhsKey
        }
    }

    private var sortedEnsembles: [Ensemble] {
        ensembleStore.ensembles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canCreateEnsemble: Bool {
        userIDs.count >= 2
    }

    private var canShowEnsembleControls: Bool {
        canCreateEnsemble || !sortedEnsembles.isEmpty
    }

    private var editorTitle: String {
        switch editorMode {
        case .create:
            return "New Ensemble"
        case .edit:
            return "Edit Ensemble"
        case nil:
            return ""
        }
    }

    private var canSaveDraft: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedUserIDs.count >= 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                headerRow

                Group {
                    if userIDs.isEmpty {
                        Text("You're not following anyone yet.")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                    } else {
                        VStack(spacing: 0) {
                            if editorMode != nil {
                                editorPanel
                                if !userIDs.isEmpty {
                                    Divider()
                                }
                            }

                            ForEach(Array(userIDs.enumerated()), id: \.element) { index, userID in
                                userRow(for: userID)

                                if index < userIDs.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .appBackground()
        .task(id: userIDs) {
            let ids = userIDs
            guard !ids.isEmpty else {
                directory = [:]
                return
            }
            let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids)
            if case .success(let map) = result {
                directory = map
            }
        }
        .confirmationDialog("Delete Ensemble?", isPresented: Binding(
            get: { pendingDeleteEnsembleID != nil },
            set: { isPresented in
                if !isPresented { pendingDeleteEnsembleID = nil }
            }
        )) {
            Button("Delete Ensemble", role: .destructive) {
                guard let id = pendingDeleteEnsembleID else { return }
                ensembleStore.delete(id: id)
                cancelEditing()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEnsembleID = nil
            }
        } message: {
            Text("This removes only the local Ensemble and does not change any follows.")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text("Following")
                .sectionHeader()

            Spacer(minLength: 0)

            if canShowEnsembleControls {
                Menu {
                    Button("New Ensemble") {
                        beginCreate()
                    }
                    .disabled(!canCreateEnsemble)

                    if !sortedEnsembles.isEmpty {
                        Section("Edit Ensemble") {
                            ForEach(sortedEnsembles) { ensemble in
                                Button(ensemble.name) {
                                    beginEditing(ensemble)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Text(editorTitle)
                    .font(Theme.Text.meta.weight(.semibold))
                    .foregroundStyle(Color.primary)

                Spacer(minLength: 0)

                Button("Cancel") {
                    cancelEditing()
                }
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)
                .buttonStyle(.plain)
            }

            TextField("Ensemble name", text: $draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(Theme.Text.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )

            Text(selectedUserIDs.count >= 2 ? "Select the followed people you want in this Ensemble." : "Select at least 2 followed people.")
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)

            HStack(spacing: Theme.Spacing.s) {
                if case .edit = editorMode {
                    Button("Delete", role: .destructive) {
                        if case .edit(let id) = editorMode {
                            pendingDeleteEnsembleID = id
                        }
                    }
                    .font(Theme.Text.meta)
                }

                Spacer(minLength: 0)

                Button("Save") {
                    saveEditor()
                }
                .font(Theme.Text.meta.weight(.semibold))
                .disabled(!canSaveDraft)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func userRow(for userID: String) -> some View {
        let acct = directory[userID]
        let isSelected = selectedUserIDs.contains(userID)

        ZStack(alignment: .trailing) {
            PeopleUserRow(
                userID: userID,
                overrideDisplayName: acct?.displayName,
                overrideSubtitle: acct?.accountID.map { "@\($0)" },
                overrideAvatarKey: acct?.avatarKey
            ) {
                ProfilePeekView(
                    ownerID: userID,
                    directoryDisplayName: acct?.displayName,
                    directoryAccountID: acct?.accountID,
                    directoryLocation: acct?.location,
                    directoryAvatarKey: acct?.avatarKey,
                    directoryInstruments: acct?.instruments,
                )
            }
            .allowsHitTesting(editorMode == nil)

            if editorMode != nil {
                HStack {
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Theme.Colors.secondaryText.opacity(0.75))
                        .padding(.trailing, 18)
                }
                .allowsHitTesting(false)

                Button {
                    toggleSelection(for: userID)
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(editorMode != nil && isSelected ? Color.primary.opacity(0.05) : .clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        )
    }

    private func beginCreate() {
        guard canCreateEnsemble else { return }
        editorMode = .create
        draftName = ""
        selectedUserIDs = []
    }

    private func beginEditing(_ ensemble: Ensemble) {
        editorMode = .edit(ensemble.id)
        draftName = ensemble.name
        selectedUserIDs = Set(ensemble.memberUserIDs.filter { userIDs.contains($0) })
    }

    private func cancelEditing() {
        editorMode = nil
        draftName = ""
        selectedUserIDs = []
        pendingDeleteEnsembleID = nil
    }

    private func toggleSelection(for userID: String) {
        if selectedUserIDs.contains(userID) {
            selectedUserIDs.remove(userID)
        } else {
            selectedUserIDs.insert(userID)
        }
    }

    private func saveEditor() {
        let sanitizedMembers = userIDs.filter { selectedUserIDs.contains($0) }
        switch editorMode {
        case .create:
            guard let _ = ensembleStore.create(name: draftName, memberUserIDs: sanitizedMembers) else { return }
            cancelEditing()
        case .edit(let id):
            guard let _ = ensembleStore.update(id: id, name: draftName, memberUserIDs: sanitizedMembers) else { return }
            cancelEditing()
        case nil:
            break
        }
    }
}
