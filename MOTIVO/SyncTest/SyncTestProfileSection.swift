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
    @State private var allowCellular = JournalMediaPreference.allowsCellular()
    @State private var recoverable = 0

    var body: some View {
        Section(header: Text("Sync (trial)").sectionHeader()) {
            HStack {
                Text("Status").font(Theme.Text.body)
                Spacer()
                Text(statusText).font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText).multilineTextAlignment(.trailing)
            }
            Toggle(isOn: $allowCellular) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Media over mobile data").font(Theme.Text.body)
                    Text("Photos, recordings, scores and your profile photo are sent and received over Wi-Fi unless this is on. Text and settings always sync. This device only.")
                        .font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .onChange(of: allowCellular) { _, newValue in JournalMediaPreference.setAllowsCellular(newValue) }
            if let waiting = status.mediaWaiting {
                Text(waiting).font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
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
        if status.mediaGated { text += " · media waits for Wi-Fi" }
        return text
    }

    private func reload() {
        allowCellular = JournalMediaPreference.allowsCellular()
        if let store = JournalSyncCoordinator.shared.store { recoverable = JournalRecovery.entries(store: store).count }
    }
}
#endif
