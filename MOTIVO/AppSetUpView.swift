//
//  AppSetUpView.swift
//  MOTIVO
//
//  // CHANGE-ID: 20260226_154500_AppSetupViewFix_73226c
//  // SCOPE: New blocking setup view to require display name + at least one instrument before entering the main app.
//  // NOTE: Uses existing Core Data Profile + Instrument sources-of-truth and mirrors instruments to UserInstrument via PersistenceController.
//
//  Created by Samuel Dixon on 2026-02-26.
//

import SwiftUI
import CoreData

struct AppSetUpView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var auth: AuthManager

    // Fetch the single local Profile row (create if missing).
    @FetchRequest(
        entity: Profile.entity(),
        sortDescriptors: [],
        animation: .default
    ) private var profiles: FetchedResults<Profile>

    // Fetch all instruments; we filter to the current profile in-memory.
    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default
    ) private var allInstruments: FetchedResults<Instrument>

    let onComplete: () -> Void

    @State private var name: String = ""
    @State private var newInstrumentName: String = ""
    @State private var statusMessage: String? = nil
    @State private var isEnsuringProfile: Bool = false
    @State private var isCompleting: Bool = false

    private var profile: Profile? {
        profiles.first
    }

    private var profileInstruments: [Instrument] {
        guard let p = profile else { return [] }
        return allInstruments.filter { $0.profile == p }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedInstrument: String {
        newInstrumentName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty && !profileInstruments.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                header

                nameCard

                instrumentCard

                if let msg = statusMessage, !msg.isEmpty {
                    Text(msg)
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.horizontal, Theme.Spacing.l)
                }

                primaryCTA
            }
            .padding(.vertical, Theme.Spacing.xl)
            .padding(.horizontal, Theme.Spacing.l)
        }
        .appBackground()
        .tint(Theme.Colors.accent)
        .onAppear {
            ensureProfileExistsIfNeeded()
            seedFieldsIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Set up Études")
                .font(Theme.Text.pageTitle)
                .foregroundStyle(Color.primary)

            Text("Add your name and your first instrument to start.")
                .font(Theme.Text.body)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            Text("Your name").sectionHeader()

            TextField("Display name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(Theme.Text.body)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Theme.Colors.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.Colors.stroke(scheme), lineWidth: 1)
                )
        }
        .cardSurface()
    }

    private var instrumentCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            Text("First instrument").sectionHeader()

            HStack(spacing: Theme.Spacing.s) {
                TextField("e.g. Piano, Bass, Clarinet", text: $newInstrumentName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(Theme.Text.body)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Theme.Colors.surface(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(Theme.Colors.stroke(scheme), lineWidth: 1)
                    )

                Button {
                    addInstrumentIfValid()
                } label: {
                    Text("Add")
                        .font(Theme.Text.body.weight(.semibold))
                        .frame(minWidth: 64, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .background(Theme.Colors.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.Colors.stroke(scheme), lineWidth: 1)
                )
                .disabled(trimmedInstrument.isEmpty)
                .opacity(trimmedInstrument.isEmpty ? 0.5 : 1.0)
            }

            if !profileInstruments.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Added")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    ForEach(profileInstruments.prefix(3), id: \.objectID) { inst in
                        Text(inst.name ?? "")
                            .font(Theme.Text.body)
                            .foregroundStyle(Color.primary)
                    }
                }
                .padding(.top, Theme.Spacing.s)
            }
        }
        .cardSurface()
    }

    private var primaryCTA: some View {
        Button {
            completeIfPossible()
        } label: {
            Text("Continue")
                .font(Theme.Text.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Colors.primaryAction)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.l)
        .disabled(!canContinue || isCompleting)
        .opacity((canContinue && !isCompleting) ? 1.0 : 0.5)
    }

    // MARK: - Actions

    private func ensureProfileExistsIfNeeded() {
        guard profiles.first == nil else { return }
        guard !isEnsuringProfile else { return }
        isEnsuringProfile = true

        let p = Profile(context: context)
        p.id = UUID()
        p.name = ""
        p.primaryInstrument = ""
        p.defaultPrivacy = false

        do {
            try context.save()
        } catch {
            statusMessage = "Couldn’t create your profile. Please try again."
            context.rollback()
        }

        isEnsuringProfile = false
    }

    private func seedFieldsIfNeeded() {
        guard let p = profiles.first else { return }
        // Only seed once (don’t overwrite user typing if view reappears).
        if name.isEmpty {
            name = p.name ?? ""
        }
    }

    private func addInstrumentIfValid() {
        statusMessage = nil
        guard let p = profiles.first else {
            statusMessage = "Profile not ready yet. Please try again."
            return
        }

        let candidate = trimmedInstrument
        guard !candidate.isEmpty else { return }

        // De-dupe against existing instruments for this profile (case-insensitive).
        if profileInstruments.contains(where: { ($0.name ?? "").caseInsensitiveCompare(candidate) == .orderedSame }) {
            newInstrumentName = ""
            statusMessage = "That instrument is already listed."
            return
        }

        let inst = Instrument(context: context)
        inst.id = UUID()
        inst.name = candidate
        inst.profile = p

        do {
            // Mirror into UserInstrument (owner-scoped) as per InstrumentListView behaviour.
            try PersistenceController.shared.fetchOrCreateUserInstrument(
                named: candidate,
                mapTo: inst,
                visibleOnProfile: true,
                in: context
            )
            try context.save()
            newInstrumentName = ""
        } catch {
            statusMessage = "Couldn’t save that instrument. Please try again."
            context.rollback()
        }
    }

    private func completeIfPossible() {
        guard !isCompleting else { return }
        isCompleting = true

        Task { @MainActor in
            await completeIfPossibleAsync()
            isCompleting = false
        }
    }

    @MainActor
    private func completeIfPossibleAsync() async {
        statusMessage = nil
        guard canContinue else { return }
        guard let p = profiles.first else {
            statusMessage = "Profile not ready yet. Please try again."
            return
        }

        p.name = trimmedName

        do {
            try context.save()
        } catch {
            statusMessage = "Couldn’t save your details. Please try again."
            context.rollback()
            return
        }

        if BackendEnvironment.shared.isConnected {
            guard auth.hasSupabaseAccessToken else {
                statusMessage = "Couldn’t finish setup right now. Please try again."
                return
            }

            guard let backendID = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !backendID.isEmpty else {
                statusMessage = "Couldn’t finish setup right now. Please try again."
                return
            }

            let instrumentsSorted = profileInstruments
                .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { a, b in
                    a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }

            let result = await AccountDirectoryService.shared.upsertSelfRow(
                userID: backendID,
                displayName: trimmedName,
                accountID: nil,
                lookupEnabled: false,
                followRequestsEnabled: true,
                location: nil,
                instruments: instrumentsSorted
            )

            switch result {
            case .success:
                if let generated = await AccountDirectoryService.shared.autoGenerateAccountIDIfMissing(
                    userID: backendID,
                    displayName: trimmedName,
                    localAccountID: ProfileStore.accountID(for: backendID),
                    lookupEnabled: false,
                    followRequestsEnabled: true,
                    location: nil,
                    instruments: instrumentsSorted
                ) {
                    ProfileStore.setAccountID(generated, for: backendID)
                }
            case .failure:
                statusMessage = "Couldn’t finish setup right now. Please try again."
                return
            }
        }

        onComplete()
    }
}
