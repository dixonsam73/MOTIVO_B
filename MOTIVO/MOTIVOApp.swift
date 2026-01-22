//
//  MOTIVOApp.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData
import Foundation

// CHANGE-ID: 20251203_BackendIdentityHandshakeStep5
// SCOPE: Step 5 — Inject LocalStubIdentityService into AuthManager (no behaviour/UI changes)

// CHANGE-ID: 20251230_Step7_BackendConfigApplyAtLaunch

// CHANGE-ID: 20260122_113000_Phase142_ConnectedBootstrap_Liveness_Guardrails
// SCOPE: Phase 14.2 — Non-DEBUG backend config bootstrap, app-foreground connected liveness (apply+feed refresh+queue flush)
// SEARCH-TOKEN: 20260122_113000_Phase142_AppBootstrap_Liveness
// CHANGE-ID: 20260122_173200_Phase1421_DefaultConnectedMode
// SCOPE: Phase 14.2.1 — In non-DEBUG builds, default backendMode_v1 to backendConnected when missing (fresh install) so queue can flush without DebugViewer.
// SEARCH-TOKEN: 20260122_173200_Phase1421_DefaultConnectedMode
// SCOPE: Step 7 — Apply BackendConfig at app launch so NetworkManager.baseURL/authToken are configured before backend services select simulated vs HTTP

@main
struct MOTIVOApp: App {
    let persistenceController = PersistenceController.shared
    private let identityService: IdentityService
    @StateObject private var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    private let ephemeralMediaFlagKey = "ephemeralSessionHasMedia_v1"

    init() {
        // Step 7: ensure live HTTP configuration is applied before any backend services initialize
        // Phase 14.2: Non-DEBUG bootstrap of backend config for fresh installs (Info.plist / xcconfig injected)
#if !DEBUG
        let d = UserDefaults.standard
        if BackendConfig.isConfigured == false {
            let rawURL = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawURL.isEmpty, !rawKey.isEmpty {
                d.set(rawURL, forKey: BackendConfigKeys.baseURL)
                d.set(rawKey, forKey: BackendConfigKeys.token)
            }
        }
        // Phase 14.2.1: Fresh installs default backend mode to Connected in non-DEBUG builds when config is present.
        // Ignore-only: if a mode is already set in UserDefaults (e.g., from debug tooling), do not override it.
        if (d.string(forKey: BackendKeys.modeKey)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true), BackendConfig.isConfigured {
            d.set(BackendMode.backendConnected.rawValue, forKey: BackendKeys.modeKey)
        }
#endif
        BackendConfig.apply()
        let identityService = LocalStubIdentityService()
        self.identityService = identityService
        _auth = StateObject(wrappedValue: AuthManager(identityService: identityService))

        // [ROLLBACK ANCHOR] v7.8 pre-hotfix — launch stall (profile-id backfill)

        // Backfill: ensure all Profile rows have a non-nil UUID `id`
        let ctx = persistenceController.container.viewContext
        ctx.perform {
            let req = NSFetchRequest<NSManagedObject>(entityName: "Profile")
            req.predicate = NSPredicate(format: "id == nil")
            if let rows = try? ctx.fetch(req), !rows.isEmpty {
                for row in rows {
                    row.setValue(UUID(), forKey: "id")
                }
                do { try ctx.save() } catch {
                    // Non-fatal: we’ll also set IDs when creating a new Profile in ProfileView
                }
            }
        }

        LegacyDefaultsPurge.runOnce()

        // Migrate oversized PracticeTimer.stagedVideo from UserDefaults to file store (no-op if already migrated)
        _ = PracticeTimerStore.loadStagedVideo()

        cleanupEphemeralMediaIfNeeded()

        #if DEBUG
        logBigDefaults()
        #endif
    }

    #if DEBUG
    private func logBigDefaults(threshold: Int = 3_000_000) {
        let d = UserDefaults.standard.dictionaryRepresentation()
        for (key, value) in d {
            if let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0), data.count >= threshold {
                print("[App] Large UserDefaults key: \(key) size: \(data.count) bytes")
            }
        }
    }
    #endif

    private func cleanupEphemeralMediaIfNeeded() {
        let d = UserDefaults.standard
        guard d.bool(forKey: ephemeralMediaFlagKey) == true else { return }

        #if DEBUG
        print("[EphemeralCleanup] Launch cleanup triggered")
        #endif

        // Best-effort: ensure staging area exists so list/remove works
        do { try StagingStore.bootstrap() } catch { /* ignore */ }
        // Remove all staged refs and files
        let refs = StagingStore.list()
        var removedRefCount = 0
        if !refs.isEmpty {
            for ref in refs { StagingStore.remove(ref); removedRefCount += 1 }
            StagingStore.deleteFiles(for: refs)
            #if DEBUG
            print("[EphemeralCleanup] StagingStore refs removed: \(removedRefCount)")
            #endif
        }
        // Remove any temporary surrogate recorder files and posters matching known patterns
        let fm = FileManager.default
        let tmp = FileManager.default.temporaryDirectory
        // We remove files with our known extensions and naming patterns: <UUID>.m4a, <UUID>.jpg, <UUID>.mov, and <UUID>_poster.jpg
        if let urls = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            var removedTempCount = 0
            for url in urls {
                let name = url.lastPathComponent.lowercased()
                if name.hasSuffix(".m4a") || name.hasSuffix(".jpg") || name.hasSuffix(".mov") {
                    // Only remove files that look like our surrogates: UUID-based names, optionally with _poster suffix
                    let base = url.deletingPathExtension().lastPathComponent
                    let core = base.replacingOccurrences(of: "_poster", with: "")
                    if UUID(uuidString: core) != nil {
                        try? fm.removeItem(at: url)
                        removedTempCount += 1
                    }
                }
            }
            #if DEBUG
            print("[EphemeralCleanup] Temp files removed: \(removedTempCount)")
            #endif
        }
        // Reset flag
        d.set(false, forKey: ephemeralMediaFlagKey)
        #if DEBUG
        print("[EphemeralCleanup] Flag reset to false")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(auth)
                .onAppear {
                    // Ensure staging area exists early and exclude from backups
                    try? StagingStore.bootstrap()
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    // Phase 14.2: Connected-mode liveness trigger (idempotent apply + lightweight refresh/flush)
                    BackendConfig.apply()
                    guard BackendEnvironment.shared.isConnected, BackendConfig.isConfigured, NetworkManager.shared.baseURL != nil else { return }
                    Task {
                        _ = await BackendEnvironment.shared.publish.fetchFeed(scope: "all")
                        await SessionSyncQueue.shared.flushNow()
                    }
                }
                .onReceive(auth.$currentUserID.removeDuplicates()) { uid in
                    persistenceController.currentUserID = uid
                    if let id = uid {
                        Task { await persistenceController.runOneTimeBackfillIfNeeded(for: id) }
                    }
                }
        }
    }
}
