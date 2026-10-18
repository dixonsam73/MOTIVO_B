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
            }
            Section("Counts") {
                row("Outbox (pending)", "\(status.outboxCount)")
                row("Held attachments", "\(status.heldCount)")
                row("Records sent", "\(status.recordsSent)")
                row("Records received", "\(status.recordsReceived)")
                row("Media bytes sent", bytes(status.bytesSent))
                row("Media bytes received", bytes(status.bytesReceived))
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
