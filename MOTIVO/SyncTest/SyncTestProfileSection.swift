//
//  SyncTestProfileSection.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  The person-facing Sync rows on the Profile screen (stage J): status, the
//  per-device "media over mobile data" option, what waits for Wi-Fi, the
//  recovery view for displaced text, scores without a file, and the
//  diagnostics screen. The full enable/disable control, first-sync progress
//  and actionable errors belong to the main-build integration.
//

#if SYNCTEST
import SwiftUI

struct SyncTestProfileSection: View {
    @ObservedObject private var status = JournalSyncCoordinator.shared.status
    @ObservedObject private var library = ScoreLibraryStore.shared
    @State private var allowMobileData = JournalMediaPreference.allowsMobileData()
    @State private var recoverable = 0

    var body: some View {
        Section(header: Text("Sync (trial)").sectionHeader()) {
            HStack {
                Text("Status").font(Theme.Text.body)
                Spacer()
                Text(statusText).font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText).multilineTextAlignment(.trailing)
            }
            Toggle(isOn: $allowMobileData) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Media over mobile data").font(Theme.Text.body)
                    Text("Photos, recordings, scores and your profile photo are sent and received over Wi-Fi only, unless this is on; on also allows a personal hotspot. Low Data Mode always pauses media. Text and settings sync on any connection. This device only.")
                        .font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .onChange(of: allowMobileData) { _, newValue in JournalMediaPreference.setAllowsMobileData(newValue) }
            if let waiting = status.mediaWaiting {
                Text(waiting).font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
            }
            if let full = status.storageFullSummary {
                Text(full).font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
            }
            if !library.missingFileIDs.isEmpty {
                Text("\(library.missingFileIDs.count) score\(library.missingFileIDs.count == 1 ? "" : "s") unavailable on this device (file missing; not synced from here)")
                    .font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
            }
            NavigationLink {
                SyncRecoveryView()
            } label: {
                HStack {
                    Text("Displaced by sync").font(Theme.Text.body)
                    Spacer()
                    Text(recoverable == 0 ? "none" : "\(recoverable)").font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            NavigationLink("Sync Test diagnostics") { SyncTestDiagnosticsView() }
        }
        .onAppear(perform: reload)
        .onReceive(status.objectWillChange) { _ in reload() }
    }

    private var statusText: String {
        var text = status.phase
        if let reason = status.pausedReason, !reason.isEmpty { text += " · \(reason)" }
        if let reason = status.mediaHold.reason { text += " · \(reason)" }
        if status.storageFull != nil { text += " · iCloud storage full" }
        return text
    }

    private func reload() {
        allowMobileData = JournalMediaPreference.allowsMobileData()
        if let store = JournalSyncCoordinator.shared.store { recoverable = JournalRecovery.entries(store: store).count }
    }
}

/// C-151: what the set-up screen shows ABOVE the name field. After a
/// device-only removal the binding is kept, so the restoration is offered
/// first; while the first complete fetch is pending the screen says so, and a
/// name typed meanwhile is provisional (kept on the Displaced by sync list if
/// a cloud profile arrives). The decision is `JournalRestoreOffer.decide`.
struct SyncTestRestoreCard: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var status = JournalSyncCoordinator.shared.status
    /// The Profile row's name as the set-up screen sees it.
    let profileName: String
    @State private var offer = JournalRestoreOffer.none

    var body: some View {
        Group {
            switch offer {
            case .none:
                EmptyView()
            case .offer(let removed):
                card("Restore from iCloud",
                     removed
                     ? "Études data was removed from this device, but your private iCloud journal and your other devices are unchanged. Restore it here first: your profile, journal, scores and settings come back and the name step is skipped."
                     : "Sync is off on this device. Turn it on to bring your iCloud profile and journal back here before choosing a name.",
                     button: "Restore from iCloud") {
                    JournalSyncCoordinator.shared.reenable()
                    reloadSoon()
                }
            case .restoring(let failure):
                card("Restoring from iCloud…",
                     "Looking for your journal in iCloud. If this device is offline you can set up now: your iCloud profile is restored when it connects, and a name typed here is kept on the Displaced by sync list."
                     + (failure.map { "\n\n\($0)" } ?? ""),
                     button: failure == nil ? nil : "Try again") {
                    Task { await JournalSyncCoordinator.shared.engine?.fetchNow(); reloadSoon() }
                }
            case .waiting(let reason):
                card("iCloud not available",
                     "Sync is paused: \(reason). You can set up now; your iCloud profile is restored once sync resumes, and a name typed here is kept on the Displaced by sync list.",
                     button: nil) {}
            case .nothingFound:
                card("Nothing to restore", "iCloud holds no profile for this journal yet. Set up below.", button: nil) {}
            }
        }
        .onAppear(perform: reload)
        .onChange(of: profileName) { _, _ in reload() }
        // `objectWillChange` fires before the value moves: read after the turn.
        .onReceive(status.objectWillChange) { _ in reloadSoon() }
        .onReceive(NotificationCenter.default.publisher(for: JournalProfileSync.didApplyNotification).receive(on: RunLoop.main)) { _ in reloadSoon() }
    }

    private func card(_ title: String, _ text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            Text(title).sectionHeader()
            Text(text).font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
            if let button {
                Button(button, action: action)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.Colors.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func reloadSoon() { DispatchQueue.main.async(execute: reload) }

    private func reload() {
        let state = JournalSyncCoordinator.shared.store?.state
        offer = JournalRestoreOffer.decide(started: state != nil, unlinked: state?.unlinked ?? false,
                                           localCopyRemoved: state?.localCopyRemoved ?? false,
                                           localRemovalInProgress: state?.localRemovalInProgress ?? false,
                                           pausedReason: status.pausedReason, initialFetchComplete: state?.initialFetchComplete ?? false,
                                           lastCatchUp: state?.lastCatchUp, profileName: profileName)
    }
}
#endif
