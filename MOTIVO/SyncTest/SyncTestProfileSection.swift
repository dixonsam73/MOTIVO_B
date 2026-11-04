//
//  SyncTestProfileSection.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  The person-facing Sync rows on the Profile screen: the on/off control
//  (off by default; on creates the state file, off is the stage E unlink),
//  status, the per-device "media over mobile data" option, what waits for
//  Wi-Fi, the recovery view for displaced text, scores without a file, and
//  (DEBUG) the diagnostics screen. Shown only by a build that can sync
//  (`JournalSyncCapability`). First-sync progress and actionable errors are
//  still to come.
//

import SwiftUI

struct SyncTestProfileSection: View {
    @ObservedObject private var status = JournalSyncCoordinator.shared.status
    @ObservedObject private var library = ScoreLibraryStore.shared
    @State private var syncOn = JournalSyncCoordinator.shared.isEnabled
    @State private var allowMobileData = JournalMediaPreference.allowsMobileData()
    @State private var recoverable = 0

    var body: some View {
        Section(header: Text("iCloud sync (trial)").sectionHeader()) {
            Toggle(isOn: $syncOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync this journal with iCloud").font(Theme.Text.body)
                    Text("Off: everything stays on this device only. On: your journal, scores, profile and settings are kept the same on every device signed in to this iCloud account. Turning it off keeps everything here and stops sending and receiving.")
                        .font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .onChange(of: syncOn) { was, now in
                guard was != now else { return }
                if now {
                    if !JournalSyncCoordinator.shared.enable(persistence: PersistenceController.shared.container) { syncOn = false }
                } else if JournalSyncCoordinator.shared.isEnabled {
                    Task { await JournalSyncCoordinator.shared.disable(); reload() }
                }
            }
            if syncOn { syncRows }
            #if DEBUG
            NavigationLink("Sync Test diagnostics") { SyncTestDiagnosticsView() }
            #endif
        }
        .onAppear(perform: reload)
        .onReceive(status.objectWillChange) { _ in reload() }
    }

    @ViewBuilder
    private var syncRows: some View {
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
    }

    private var statusText: String {
        var text = status.phase
        if let reason = status.pausedReason, !reason.isEmpty { text += " · \(reason)" }
        if let reason = status.mediaHold.reason { text += " · \(reason)" }
        if status.storageFull != nil { text += " · iCloud storage full" }
        return text
    }

    private func reload() {
        let enabled = JournalSyncCoordinator.shared.isEnabled
        if syncOn != enabled { syncOn = enabled }
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
    @State private var offer: JournalRestoreOffer

    /// C-175: decided at creation. A `.none` start renders an empty view, and
    /// SwiftUI never calls `onAppear` for one, so a reload there never ran
    /// and a fresh install got no "turn on" card (seen on the iPad and the
    /// simulator, 2026-11-04). The trial never noticed because a running
    /// sync's status changes triggered the reload instead.
    init(profileName: String) {
        self.profileName = profileName
        _offer = State(initialValue: Self.currentOffer(profileName: profileName, pausedReason: JournalSyncCoordinator.shared.status.pausedReason))
    }

    var body: some View {
        Group {
            switch offer {
            case .none:
                EmptyView()
            case .turnOn:
                card("Already using Études on another device?",
                     "Turn on iCloud sync to bring your profile, journal, scores and settings here from your other devices before choosing a name. Off by default; you can turn it on later in Profile.",
                     button: "Turn on iCloud sync") {
                    JournalSyncCoordinator.shared.enable(persistence: PersistenceController.shared.container)
                    reloadSoon()
                }
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

    private func reload() { offer = Self.currentOffer(profileName: profileName, pausedReason: status.pausedReason) }

    static func currentOffer(profileName: String, pausedReason: String?) -> JournalRestoreOffer {
        let state = JournalSyncCoordinator.shared.store?.state
        return JournalRestoreOffer.decide(started: state != nil, unlinked: state?.unlinked ?? false,
                                          localCopyRemoved: state?.localCopyRemoved ?? false,
                                          localRemovalInProgress: state?.localRemovalInProgress ?? false,
                                          pausedReason: pausedReason, initialFetchComplete: state?.initialFetchComplete ?? false,
                                          lastCatchUp: state?.lastCatchUp, profileName: profileName)
    }
}
