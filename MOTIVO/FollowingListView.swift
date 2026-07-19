// CHANGE-ID: 20260719_Ensembles_DedicatedNavigation
// SCOPE: Replace the Following Ensembles popup/editor workflow with dedicated Ensemble list, detail and editor pages while preserving the existing local EnsembleStore behaviour, member rules, follow graph and profile navigation. No backend, sharing, transport, notification or persistence changes.
// SEARCH-TOKEN: 20260719_Ensembles_DedicatedNavigation

import SwiftUI

struct FollowingListView: View {

    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var ensembleStore = EnsembleStore.shared

    @State private var directory: [String: DirectoryAccount] = [:]

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

    private var canShowEnsembles: Bool {
        userIDs.count >= 2 || !ensembleStore.ensembles.isEmpty
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text("Following")
                .sectionHeader()

            Spacer(minLength: 0)

            if canShowEnsembles {
                NavigationLink {
                    EnsembleListView()
                } label: {
                    HStack(spacing: 4) {
                        Text("Ensembles")
                            .font(.callout.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func userRow(for userID: String) -> some View {
        let account = directory[userID]

        return PeopleUserRow(
            userID: userID,
            overrideDisplayName: account?.displayName,
            overrideSubtitle: account?.accountID.map { "@\($0)" },
            overrideAvatarKey: account?.avatarKey
        ) {
            ProfilePeekView(
                ownerID: userID,
                directoryDisplayName: account?.displayName,
                directoryAccountID: account?.accountID,
                directoryLocation: account?.location,
                directoryAvatarKey: account?.avatarKey,
                directoryInstruments: account?.instruments,
            )
        }
    }
}

private struct EnsembleListView: View {

    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var ensembleStore = EnsembleStore.shared

    private var sortedEnsembles: [Ensemble] {
        ensembleStore.ensembles.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var canCreateEnsemble: Bool {
        followStore.following.count >= 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Ensembles")
                    .sectionHeader()

                VStack(spacing: 0) {
                    ForEach(Array(sortedEnsembles.enumerated()), id: \.element.id) { index, ensemble in
                        ensembleRow(ensemble)

                        if index < sortedEnsembles.count - 1 || canCreateEnsemble {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }

                    if canCreateEnsemble {
                        NavigationLink {
                            EnsembleEditorView(mode: .create)
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .frame(width: 36, height: 36)

                                Text("New Ensemble")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Color.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                            }
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.s + 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if sortedEnsembles.isEmpty && !canCreateEnsemble {
                        Text("Follow at least two people to create an Ensemble.")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.l)
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
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ensembleRow(_ ensemble: Ensemble) -> some View {
        PeopleUserRow(
            userID: "ensemble:\(ensemble.id)",
            overrideDisplayName: ensemble.name,
            overrideSubtitle: "\(ensemble.memberUserIDs.count) " + (ensemble.memberUserIDs.count == 1 ? "person" : "people"),
            overrideAvatarKey: nil
        ) {
            EnsembleEditorView(mode: .edit(ensemble.id))
        } trailing: {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
        }
    }
}

private struct EnsembleEditorView: View {

    enum Mode: Equatable {
        case create
        case edit(String)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var ensembleStore = EnsembleStore.shared

    @State private var directory: [String: DirectoryAccount] = [:]
    @State private var draftName: String = ""
    @State private var selectedUserIDs: Set<String> = []
    @State private var pendingDelete = false
    @State private var hasLoadedDraft = false

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

    private var title: String {
        switch mode {
        case .create: return "New Ensemble"
        case .edit: return "Edit Ensemble"
        }
    }

    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedUserIDs.count >= 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(title)
                    .sectionHeader()

                editorCard

                membersCard

                if case .edit = mode {
                    Spacer(minLength: Theme.Spacing.xl)

                    Button {
                        pendingDelete = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Ensemble")
                                .font(Theme.Text.body)
                                .foregroundStyle(Color.primary)
                            Spacer()
                        }
                        .padding(.vertical, Theme.Spacing.l)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .appBackground()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.Colors.secondaryText)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(canSave ? Theme.Colors.primaryAction : Theme.Colors.secondaryText)
                .disabled(!canSave)
            }
        }
        .task(id: userIDs) {
            loadDraftIfNeeded()

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
        .confirmationDialog("Delete Ensemble?", isPresented: $pendingDelete) {
            Button("Delete Ensemble", role: .destructive) {
                guard case .edit(let id) = mode else { return }
                ensembleStore.delete(id: id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes only the local Ensemble and does not change any follows.")
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("Ensemble name", text: $draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(Theme.Text.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )


        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var membersCard: some View {
        VStack(spacing: 0) {

            ForEach(Array(userIDs.enumerated()), id: \.element) { index, userID in
                memberRow(for: userID)

                if index < userIDs.count - 1 {
                    Divider()
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

    private func memberRow(for userID: String) -> some View {
        let account = directory[userID]
        let isSelected = selectedUserIDs.contains(userID)

        return ZStack(alignment: .trailing) {
            PeopleUserRow(
                userID: userID,
                overrideDisplayName: account?.displayName,
                overrideSubtitle: account?.accountID.map { "@\($0)" },
                overrideAvatarKey: account?.avatarKey
            ) {
                EmptyView()
            }
            .allowsHitTesting(false)

            HStack {
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.78) : Theme.Colors.secondaryText.opacity(0.68))
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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.05) : .clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        )
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true

        switch mode {
        case .create:
            draftName = ""
            selectedUserIDs = []

        case .edit(let id):
            guard let ensemble = ensembleStore.ensemble(id: id) else { return }
            draftName = ensemble.name
            selectedUserIDs = Set(ensemble.memberUserIDs.filter { userIDs.contains($0) })
        }
    }

    private func toggleSelection(for userID: String) {
        if selectedUserIDs.contains(userID) {
            selectedUserIDs.remove(userID)
        } else {
            selectedUserIDs.insert(userID)
        }
    }

    private func save() {
        let sanitizedMembers = userIDs.filter { selectedUserIDs.contains($0) }

        switch mode {
        case .create:
            guard ensembleStore.create(name: draftName, memberUserIDs: sanitizedMembers) != nil else { return }
            dismiss()

        case .edit(let id):
            guard ensembleStore.update(id: id, name: draftName, memberUserIDs: sanitizedMembers) != nil else { return }
            dismiss()
        }
    }
}
