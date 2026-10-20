//
//  SyncTestDiagnosticsView.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  The evidence screen for the trial: engine status, bound user, outbox and
//  held counts, records and bytes each way, conflicts with the losing text,
//  and the diagnostics log. Manual Fetch/Send for deterministic steps.
//

#if SYNCTEST
import SwiftUI

struct SyncTestDiagnosticsView: View {
    @ObservedObject private var status = JournalSyncCoordinator.shared.status
    @State private var refreshTick = 0

    private var state: JournalSyncPersistedState? { JournalSyncCoordinator.shared.store?.state }

    var body: some View {
        List {
            Section("Engine") {
                row("Phase", status.phase)
                if let reason = status.pausedReason { row("Paused", reason) }
                row("Bound iCloud user", status.boundUser ?? "—")
                row("Last event", status.lastEvent)
                row("Last fetch", status.lastFetchAt.map(format) ?? "—")
                row("Last send", status.lastSendAt.map(format) ?? "—")
                HStack {
                    Button("Fetch now") { Task { await JournalSyncCoordinator.shared.engine?.fetchNow(); refreshTick += 1 } }
                    Spacer()
                    Button("Send now") { Task { await JournalSyncCoordinator.shared.engine?.sendNow(); refreshTick += 1 } }
                }
                HStack {
                    Button("Probe zone") { Task { await JournalSyncCoordinator.shared.engine?.probeZone(); refreshTick += 1 } }
                    Spacer()
                    Button("Probe DB changes") { Task { await JournalSyncCoordinator.shared.engine?.probeDatabaseChanges(); refreshTick += 1 } }
                    Spacer()
                    Button("Reset engine state") { JournalSyncCoordinator.shared.resetEngineState(); refreshTick += 1 }
                        .foregroundStyle(.orange)
                }
                Button("Delete server zone (trial reset)") { Task { await JournalSyncCoordinator.shared.engine?.deleteServerZone(); refreshTick += 1 } }
                    .foregroundStyle(.red)
            }
            Section("Ownership (stage B)") {
                row("Owner key (K1)", ownerKeyText)
                row("Connected identity", JournalSyncCoordinator.shared.auth?.hasConnectedIdentity == true ? "yes" : "no")
                row("Assessment", state?.ownershipReport ?? "—")
                row("First complete fetch", state?.initialFetchComplete == true ? "yes" : "no")
                row("Held-back sends (other owner)", "\(state?.ineligibleCount ?? 0)")
                row("Owner differences kept", "\(state?.ownerConflicts ?? 0)")
                row("Pending adoption", state?.pendingOwnerAdoption.map { String($0.prefix(12)) + "…" } ?? "none")
                row("Synced lists", "\(state?.listFingerprints.count ?? 0)")
                if let refusal = JournalSyncCoordinator.shared.auth?.signInRefusal { row("Sign-in refused", refusal) }
                // Disposable owner ids only: the trial never runs Sign in with
                // Apple, so no real account and no backend are involved.
                Button("Sign-in owner step as Trial Owner A") { localSignIn("synctest.trial-owner-a") }
                Button("Sign-in owner step as Trial Owner B") { localSignIn("synctest.trial-owner-b") }
                Button("Leave Connected (C-114 withdrawal)") {
                    JournalSyncCoordinator.shared.auth?.leaveConnected(); refreshTick += 1
                }
                Button("Clear owner key (trial reset)") {
                    // Suspend first, or the cleared key is re-adopted from the journal.
                    JournalSyncCoordinator.shared.ownership?.suspendForReset()
                    _ = JournalSyncCoordinator.shared.auth?.clearOwnerForSyncTest(); refreshTick += 1
                }
                .foregroundStyle(.orange)
            }
            Section("Counts") {
                row("Outbox (pending)", "\(status.outboxCount)")
                row("Held attachments", "\(status.heldCount)")
                row("Records sent", "\(status.recordsSent)")
                row("Records received", "\(status.recordsReceived)")
                row("Media uploads", "\(state?.assetUploads ?? 0) file(s), \(bytes(status.bytesSent))")
                row("Attachment records sent, metadata only", "\(state?.attachmentRecordsSentWithoutMedia ?? 0)")
                row("Media downloaded (transport)", bytes(state?.assetBytesDownloaded ?? 0))
                row("Media written to this device", bytes(status.bytesReceived))
                row("Bootstrap queued", state?.bootstrapQueued == true ? "yes" : "no")
            }
            if let outbox = state?.outbox, !outbox.isEmpty {
                Section("Outbox") {
                    ForEach(outbox, id: \.self) { c in
                        Text("\(c.op.rawValue) \(c.recordType) \(c.recordName.prefix(8))…").font(.footnote.monospaced())
                    }
                }
            }
            if let conflicts = state?.conflicts, !conflicts.isEmpty {
                Section("Conflicts (\(conflicts.count))") {
                    ForEach(conflicts.reversed()) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(format(c.at)) · \(c.recordType) \(c.recordName.prefix(8))… · winner: \(c.winner)")
                                .font(.footnote.monospaced())
                            Text("local \(c.localUserModifiedAt.map(format) ?? "—") · server \(c.serverUserModifiedAt.map(format) ?? "—")")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let t = c.losingTitle { Text("lost title: \(t)").font(.caption) }
                            if let n = c.losingNotes, !n.isEmpty { Text("lost notes: \(n)").font(.caption) }
                        }
                    }
                }
            }
            Section("Log") {
                ForEach((state?.log ?? []).reversed().prefix(120)) { entry in
                    Text("\(format(entry.at))  \(entry.text)").font(.caption.monospaced())
                }
            }
        }
        .id(refreshTick)
        .navigationTitle("Sync Test")
        .onReceive(status.objectWillChange) { _ in refreshTick += 1 }
    }

    private var ownerKeyText: String {
        guard let k1 = Keychain.get("appleUserID"), !k1.isEmpty else { return "none" }
        return String(k1.prefix(24)) + (k1.count > 24 ? "…" : "")
    }

    /// The local half of a sign-in (`AuthManager.applyLocalSignIn`): the C-114
    /// refusal, the owner key, and ownerless entries given that owner.
    private func localSignIn(_ userID: String) {
        let accepted = JournalSyncCoordinator.shared.auth?.applyLocalSignIn(userID: userID) ?? false
        JournalSyncCoordinator.shared.store?.log("Sign-in owner step as \(userID): \(accepted ? "accepted" : "refused (C-114)")")
        JournalSyncCoordinator.shared.ownership?.evaluate(reason: "sign-in step")
        refreshTick += 1
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.footnote)
    }

    private func format(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }

    private func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
#endif
