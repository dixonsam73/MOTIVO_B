// CHANGE-ID: 20260313_202600_RecorderHygiene_App_7c3e8c3a
// SCOPE: Recorder hygiene hardening — targeted launch sweep for motivo_rec_*.m4a and motivo_vid_*.mov; remove staging-wide ephemeral cleanup side effect.
// SEARCH-TOKEN: 20260313_202600_RecorderHygiene_App_7c3e8c3a

// CHANGE-ID: 20260303_090700_DeleteAccountV2_Stage1_ResetScaffold_9825aed1
// SCOPE: Delete Account v2 Stage 1 — add LocalFactoryReset scaffold + hook from ProfileView; gate foreground liveness; no wipe yet.
// SEARCH-TOKEN: 20260303_090700_DeleteAccountV2_Stage1_ResetScaffold_9825aed1

//
//  MOTIVOApp.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

// CHANGE-ID: 20260129_133308_14_3H_B5_ForegroundGuard
// SCOPE: Phase 14.3H (B5) — Skip launch/foreground liveness refresh while AuthManager sign-in is in-flight (prevents missing-refresh-token signOut race).
// SEARCH-TOKEN: 20260129_133308_14_3H_B5_ForegroundGuard

// CHANGE-ID: 20260129_213500_14_3H_B3_InitMirrorCurrentUserID
// SCOPE: Phase 14.3H (B3) — Mirror initial AuthManager.currentUserID into PersistenceController during app init (pre-onReceive).
// SEARCH-TOKEN: 20260129_213500_14_3H_B3_InitMirrorCurrentUserID
// SEARCH-TOKEN: 20260129_090937_14_3H_SignOutFeedReset_SignInReliability

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

// CHANGE-ID: 20260127_130352_AppAuthLiveness_LaunchForeground
// SCOPE: Phase 14.2.2 — Ensure Supabase session refresh on launch + foreground before connected liveness calls; no UI changes.
// SEARCH-TOKEN: 20260127_130352_AppAuthLiveness_LaunchForeground
// SCOPE: Step 7 — Apply BackendConfig at app launch so NetworkManager.baseURL/authToken are configured before backend services select simulated vs HTTP

// CHANGE-ID: 20260324_171200_app_root_to_practicetimer
// SCOPE: Visible root routing only — launch to PracticeTimerView in home mode while preserving all backend/bootstrap/liveness behavior.
// SEARCH-TOKEN: 20260324_171200_app_root_to_practicetimer

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
        let authManager = AuthManager(identityService: identityService)
        _auth = StateObject(wrappedValue: authManager)

        // Phase 14.3H (B3): Ensure PersistenceController mirrors the initial AuthManager.currentUserID
        // even when AuthManager initializes from Keychain before SwiftUI onReceive subscribers attach.
        let pc = persistenceController
        pc.currentUserID = authManager.currentUserID
        if let id = authManager.currentUserID {
            Task { await pc.runOneTimeBackfillIfNeeded(for: id) }
        }

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
        let didLaunchWithEphemeralFlag = d.bool(forKey: ephemeralMediaFlagKey)

        #if DEBUG
        if didLaunchWithEphemeralFlag {
            print("[EphemeralCleanup] Launch cleanup triggered")
        }
        #endif

        sweepAbandonedAudioRecorderFilesInTemporaryDirectory()
        VideoRecorderController.sweepAbandonedCaptureFilesInDocuments()

        if didLaunchWithEphemeralFlag {
            d.set(false, forKey: ephemeralMediaFlagKey)
            #if DEBUG
            print("[EphemeralCleanup] Flag reset to false")
            #endif
        }
    }

    private func sweepAbandonedAudioRecorderFilesInTemporaryDirectory() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory

        guard let urls = try? fm.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls {
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix("motivo_rec_"), url.pathExtension.lowercased() == "m4a" else { continue }
            try? fm.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            PracticeTimerView(
                isPresented: .constant(false),
                presentationMode: .home
            )
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(auth)
                .onAppear {
                    // Phase 14.2.2: Session liveness — refresh Supabase session on launch to prevent zombie auth.
                    Task {
                        if auth.isSigningIn {
                            NSLog("[App] launch: sign-in in flight; skipping ensureValidSession")
                        } else {
                            _ = await auth.ensureValidSession(reason: "launch")
                        }
                    }

                    // Ensure staging area exists early and exclude from backups
                    try? StagingStore.bootstrap()
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    // Delete Account v2: avoid running liveness work during an in-progress local factory reset.
                    guard !LocalFactoryReset.isInProgress else { return }
                    // Phase 14.2: Connected-mode liveness trigger (idempotent apply + lightweight refresh/flush)
                    BackendConfig.apply()
                    guard BackendEnvironment.shared.isConnected, BackendConfig.isConfigured, NetworkManager.shared.baseURL != nil else { return }
                    Task {
                        // Phase 14.3H (B5): Avoid racing foreground liveness refresh against an in-flight sign-in.
                        guard !auth.isSigningIn else {
                            NSLog("[App] foreground: sign-in in flight; skipping ensureValidSession")
                            return
                        }
                        // Phase 14.2.2: Session liveness — refresh before issuing connected requests.
                        let ok = await auth.ensureValidSession(reason: "foreground")
                        guard ok else { return }
                        _ = await BackendEnvironment.shared.publish.fetchFeed(scope: "all")
                        await SessionSyncQueue.shared.flushNow()
                    }
                }
                .onReceive(auth.$currentUserID.removeDuplicates()) { uid in
                    persistenceController.currentUserID = uid
                    if let id = uid {
                        Task { await persistenceController.runOneTimeBackfillIfNeeded(for: id) }
                    } else {
                        // Phase 14.3H (A): Connected-mode sign-out must clear any retained feed/follow state.
                        // Triggered by auth state transition (not UI navigation).
                        if BackendEnvironment.shared.isConnected {
                            BackendFeedStore.shared.resetForSignOut()
                            FollowStore.shared.resetForSignOut()
                        }
                    }
                }
                }
        }
    }
