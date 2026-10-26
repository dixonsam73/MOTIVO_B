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
import CoreData

struct SyncTestDiagnosticsView: View {
    @ObservedObject private var status = JournalSyncCoordinator.shared.status
    @State private var refreshTick = 0
    @State private var showInterruptConfirm = false
    @State private var showResetEngineConfirm = false

    private var state: JournalSyncPersistedState? { JournalSyncCoordinator.shared.store?.state }

    var body: some View {
        List {
            // Read so the body re-evaluates (the state file is not observable)
            // WITHOUT re-identifying the list, which would reset its scroll.
            let _ = refreshTick
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
                }
                // Own row and a confirmation: tapped twice by accident beside
                // Probe zone on 2026-10-21 (harmless, but it refetches the zone).
                Button("Reset engine state (refetches everything)") { showResetEngineConfirm = true }
                    .foregroundStyle(.orange)
                    .confirmationDialog("Discard the engine's change tokens and refetch the whole zone? Journal and outbox are kept.",
                                        isPresented: $showResetEngineConfirm, titleVisibility: .visible) {
                        Button("Reset engine state") { JournalSyncCoordinator.shared.resetEngineState(); refreshTick += 1 }
                    }
                Button("Delete server zone (trial reset)") { Task { await JournalSyncCoordinator.shared.engine?.deleteServerZone(); refreshTick += 1 } }
                    .foregroundStyle(.red)
            }
            Section("Account and link (stage E)") {
                row("Link", linkText)
                row("Local removal", state?.localRemovalInProgress == true ? "IN PROGRESS" : (state?.localCopyRemoved == true ? "done (\(state?.localRemovalReason ?? ""))" : "none"))
                row("History token", state?.historyToken == nil ? "none" : "set")
                row("Engine state", state?.engineState == nil ? "none (fresh engine on activation)" : "saved")
                row("Server records known", "\(state?.lastKnownRecords.count ?? 0)")
                row("Catch-up baseline", state?.catchUpToken == nil ? "none (set after the next fetch)" : "set")
                row("Metadata migration (stage F)", state?.metadataMigrationDone == true ? "done" : "pending")
                row("Meta record transition (stage G)", state?.metaTransitionDone == true ? "done" : "pending")
                row("Catch-up zone token", state?.catchUpZoneToken == nil ? "none" : "set")
                row("Catch-up totals", "\(state?.catchUpRecords ?? 0) record(s), \(state?.catchUpAssets ?? 0) file(s) fetched")
                row("Last catch-up", state?.lastCatchUp ?? "—")
                row("Held metadata records", "\(state?.awaitingMeta.count ?? 0)")
                row("Own-write echoes (C-134)", "\(state?.echoRecords ?? 0) record(s), \(bytes(state?.echoAssetBytes ?? 0)) delivered")
                // Solo has no privacy toggle in the UI (Connected only), so the
                // trial flips the newest attachment's choice from here.
                row("Newest attachment privacy", newestAttachmentPrivacyText)
                Button("Toggle privacy of newest attachment") {
                    if let id = newestAttachmentID() { AttachmentPrivacy.toggle(id: id, url: nil) }
                    refreshTick += 1
                }
                Button("Re-run metadata migration") {
                    JournalSyncCoordinator.shared.store?.update { $0.metadataMigrationDone = false }
                    JournalSyncCoordinator.shared.engine?.runMetadataMigrationIfNeeded(); refreshTick += 1
                }
                if state?.unlinked == true {
                    Button("Re-enable sync") { JournalSyncCoordinator.shared.reenable(); refreshTick += 1 }
                } else {
                    Button("Unlink this device (keep local journal)") { Task { await JournalSyncCoordinator.shared.unlink(); refreshTick += 1 } }
                        .foregroundStyle(.orange)
                }
                Button("Re-check account") { Task { await JournalSyncCoordinator.shared.engine?.reconcile(trigger: "manual"); refreshTick += 1 } }
                // The clean removal is the production erase: Profile → Erase All
                // Études Data on THIS Sync Test install (disposable data only).
                Button("Simulate interrupted local removal (exits app)") { showInterruptConfirm = true }
                    .foregroundStyle(.red)
                    .confirmationDialog("Delete this install's journal rows and exit before the removal finishes? Sync Test only.",
                                        isPresented: $showInterruptConfirm, titleVisibility: .visible) {
                        Button("Delete rows and exit", role: .destructive) { JournalSyncCoordinator.shared.simulateInterruptedLocalRemoval() }
                    }
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
            Section("Private profile (stage H)") {
                row("Profile here", profileValuesText)
                row("Profile clock", state?.profileStamp.map(format) ?? "none (predates this build, or never edited)")
                row("Last exchanged", state?.profileFingerprint == nil ? "nothing yet (transition pending)"
                    : (JournalProfileValues(fingerprint: state?.profileFingerprint)?.describe() ?? "?"))
                row("Avatar here", avatarHereText)
                row("Avatar the server holds", avatarServerText)
                row("Avatar uploads", "\(state?.avatarUploads ?? 0) file(s)")
                row("Avatar asset bytes delivered", bytes(state?.avatarAssetBytesDelivered ?? 0))
                // Every attempt at the four Connected write entry points since
                // launch, whatever the outcome. Private sync must leave these at 0.
                row("Connected writes attempted", connectedWritesText)
                let displaced = JournalProfileSync.displacedAvatars()
                if !displaced.isEmpty {
                    ForEach(displaced, id: \.self) { url in
                        Button("Restore displaced avatar \(url.deletingPathExtension().lastPathComponent.prefix(12))…") {
                            let scope = JournalSyncCoordinator.shared.engine?.profileScope ?? .local
                            _ = JournalProfileSync.restoreDisplacedAvatar(url, scope: scope)
                            JournalSyncCoordinator.shared.auth?.noteAvatarChangedBySync()
                            refreshTick += 1
                        }
                    }
                }
                Button("Re-send profile and avatar (re-run transition)") {
                    JournalSyncCoordinator.shared.engine?.rerunProfileTransition(); refreshTick += 1
                }
            }
            Section("Scores library (stage I)") {
                let library = ScoreLibraryStore.shared
                row("Items here", "\(library.items.count)\(library.indexDamaged ? " · INDEX UNREADABLE (C-139)" : "")")
                row("Items exchanged", "\(state?.scoreFingerprints.count ?? 0) (transition \(state?.scoreScanDone == true ? "done" : "pending"))")
                row("Score uploads", "\(state?.scoreUploads ?? 0) file(s)")
                row("Score asset bytes delivered", bytes(state?.scoreAssetBytesDelivered ?? 0))
                row("Score records sent, no file", "\(state?.scoreRecordsSentWithoutFile ?? 0)")
                row("Positions sent / displaced here", "\(state?.scorePositionsSent ?? 0) / \(state?.scorePositionsDisplaced ?? 0)")
                row("Held score records", "\(state?.awaitingScore.count ?? 0)")
                row("Newest score", newestScoreText)
                // No screen offers the cover page yet (the field has always
                // existed); the trial exercises it from here.
                Button("Cycle cover page of newest score") {
                    if let item = newestScore() {
                        let next = item.thumbnailPage >= item.pageCount ? 1 : item.thumbnailPage + 1
                        ScoreLibraryStore.shared.setThumbnailPage(next, for: item.id)
                    }
                    refreshTick += 1
                }
                let displaced = JournalScoreSync.displacedScores()
                if !displaced.isEmpty {
                    row("Displaced score files kept", "\(displaced.count)")
                }
                Button("Re-send scores (re-run transition)") {
                    JournalSyncCoordinator.shared.engine?.rerunScoreTransition(); refreshTick += 1
                }
            }
            Section("Counts") {
                row("Outbox (pending)", "\(status.outboxCount)")
                row("Held attachments", "\(status.heldCount)")
                row("Records sent", "\(status.recordsSent)")
                row("Records received", "\(status.recordsReceived)")
                row("Media uploads", "\(state?.assetUploads ?? 0) file(s), \(bytes(status.bytesSent))")
                row("Attachment records sent, metadata only", "\(state?.attachmentRecordsSentWithoutMedia ?? 0)")
                // Sum of the sizes of asset files CloudKit handed the app with
                // fetched attachment records, whether or not they were kept.
                // Not a network measurement.
                row("Asset bytes delivered by CloudKit", bytes(state?.assetBytesDownloaded ?? 0))
                row("Bytes written to media storage", bytes(status.bytesReceived))
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
        .navigationTitle("Sync Test")
        .onReceive(status.objectWillChange) { _ in refreshTick += 1 }
    }

    private func newestAttachmentID() -> UUID? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Attachment")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        return (try? PersistenceController.shared.container.viewContext.fetch(request))?.first?.value(forKey: "id") as? UUID
    }

    private var newestAttachmentPrivacyText: String {
        guard let id = newestAttachmentID() else { return "no attachments" }
        let choice = AttachmentPrivacy.currentMap()[AttachmentPrivacy.privacyKey(id: id, url: nil) ?? ""]
        return "\(id.uuidString.prefix(8))… \(choice.map { $0 ? "private" : "shared" } ?? "no choice (private by default)")"
    }

    private func newestScore() -> ScoreLibraryItem? {
        ScoreLibraryStore.shared.items.max { $0.createdAt < $1.createdAt }
    }

    private var newestScoreText: String {
        guard let item = newestScore() else { return "none" }
        return "“\(item.title)” · cover \(item.thumbnailPage)/\(item.pageCount) · page \(item.lastViewedPage.map(String.init) ?? "—")\(item.isFavourite ? " · ★" : "")"
    }

    private var profileValuesText: String {
        let ctx = PersistenceController.shared.container.viewContext
        let scope = JournalSyncCoordinator.shared.engine?.profileScope ?? .local
        return JournalProfileSync.currentValues(context: ctx, scope: scope).describe()
    }

    private var avatarHereText: String {
        guard let store = JournalSyncCoordinator.shared.store else { return "—" }
        let scope = JournalSyncCoordinator.shared.engine?.profileScope ?? .local
        let avatar = JournalProfileSync.currentAvatar(scope: scope, store: store)
        guard let url = avatar.url else { return "none\(state?.avatarRemovedAt.map { " (removed \(format($0)))" } ?? "")" }
        let size = JournalAssetHash.stamp(of: url)?.size ?? 0
        return "\(avatar.hash.prefix(12))… \(bytes(size)), \(avatar.modifiedAt.map(format) ?? "—")"
    }

    private var avatarServerText: String {
        guard let known = state?.assetHashes[JournalProfileSync.avatarName] else { return "unknown (nothing exchanged yet)" }
        return known.isEmpty ? "none (removed)" : "\(known.prefix(12))…"
    }

    private var connectedWritesText: String {
        let kinds = [ConnectedWriteWitness.directoryUpsert, ConnectedWriteWitness.directoryAvatarKey,
                     ConnectedWriteWitness.avatarUpload, ConnectedWriteWitness.avatarDelete]
        return "\(ConnectedWriteWitness.total) (" + kinds.map { "\($0) \(ConnectedWriteWitness.count($0))" }.joined(separator: ", ") + ")"
    }

    private var linkText: String {
        guard let state else { return "—" }
        if state.localRemovalInProgress { return "removal in progress" }
        if state.unlinked { return state.localCopyRemoved ? "off (local copy removed)" : "unlinked by the user" }
        return "linked"
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
