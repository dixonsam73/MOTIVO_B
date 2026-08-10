// CHANGE-ID: 20260518_212100_RelationalUnseenStaticChips
// SCOPE: Add one-time ContentView feed launch override state for relational unseen routing; no route enum or navigation architecture changes.
// SEARCH-TOKEN: 20260518_212100_RelationalUnseenStaticChips

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

enum AppRoute {
    case timer
    case content
}

final class AppRouteStore: ObservableObject {
    @Published var route: AppRoute = .timer
    @Published var isProfilePresented: Bool = false
    @Published var pendingContentLaunchScopeOverride: String? = nil
}

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
    @StateObject private var appRoute = AppRouteStore()
    @StateObject private var appModeManager: AppModeManager
    @StateObject private var connectedMembershipStore: ConnectedMembershipStore
    @Environment(\.scenePhase) private var scenePhase
    private let ephemeralMediaFlagKey = "ephemeralSessionHasMedia_v1"

    init() {
        // Step 7: ensure live HTTP configuration is applied before any backend services initialize
        // Phase 14.2: Non-DEBUG bootstrap of backend config for fresh installs (Info.plist / xcconfig injected)
        // Bootstrap bundled backend configuration for every build configuration.
        // Debug must also recover correctly on a clean install or after factory reset.
        BackendConfig.bootstrapFromBundleIfNeededForFactoryReset()

        // Milestone 6: AppMode activation is now the production owner of Connected runtime enablement.
        // Start from the local backend runtime before AuthManager initializes so stored Apple sign-in
        // state alone cannot establish Connected identity. The activation path below will re-enable
        // the Connected runtime when an existing Supabase-backed Connected presence is present.
        setBackendMode(.localSimulation)
        BackendConfig.apply()

        let identityService = LocalStubIdentityService()
        self.identityService = identityService
        let authManager = AuthManager(identityService: identityService)
        let membershipStore = ConnectedMembershipStore()
        _auth = StateObject(wrappedValue: authManager)
        _connectedMembershipStore = StateObject(wrappedValue: membershipStore)
        _appModeManager = StateObject(
            wrappedValue: AppModeManager(
                mode: AppModeManager.resolvedActivationMode(
                    auth: authManager,
                    isEntitled: membershipStore.isEntitled
                )
            )
        )

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
                #if DEBUG
                print("[App] Large UserDefaults key: \(key) size: \(data.count) bytes")
                #endif
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
            ZStack {
                Group {
                    switch appRoute.route {
                    case .timer:
                        PracticeTimerView(
                            isPresented: .constant(false),
                            presentationMode: .home
                        )
                    case .content:
                        ContentView()
                    }
                }

                if appRoute.isProfilePresented {
                    ProfileView(onClose: {
                        appRoute.isProfilePresented = false
                    })
                    .zIndex(1)
                    .transition(.identity)
                }
            }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(auth)
                .environmentObject(appRoute)
                .environmentObject(appModeManager)
                .environmentObject(connectedMembershipStore)
                .onAppear {
                    connectedMembershipStore.start()
                    appModeManager.applyActivation(auth: auth, isEntitled: connectedMembershipStore.isEntitled)

                    // M7B: AppMode activation must complete before a pending Études avatar can
                    // be promoted into the Connected namespace/backend. AuthManager may discover
                    // the identity before the runtime has switched to Connected, so retry here.
                    Task {
                        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "appOnAppearAfterActivation")
                    }

                    // Phase 14.2.2: Session liveness — refresh Supabase session only when the Connected runtime is allowed.
                    Task {
                        guard appModeManager.canViewFeed else { return }
                        if auth.isSigningIn {
                            #if DEBUG
                            NSLog("[App] launch: sign-in in flight; skipping ensureValidSession")
                            #endif
                        } else {
                            _ = await auth.ensureValidSession(reason: "launch")
                        }
                    }

                    // Ensure staging area exists early and exclude from backups
                    try? StagingStore.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Delete Account v2: avoid running liveness work during an in-progress local factory reset.
                    guard !LocalFactoryReset.isInProgress else { return }

                    Task {
                        // StoreKit remains the entitlement authority. Refresh whenever the app becomes active
                        // so a genuine expiry does not depend solely on a transaction update.
                        await connectedMembershipStore.refreshEntitlement()

                        // Phase 14.2: Connected-mode liveness trigger (idempotent apply + lightweight refresh/flush)
                        guard appModeManager.canViewFeed else { return }
                        BackendConfig.apply()
                        guard BackendEnvironment.shared.isConnected,
                              BackendConfig.isConfigured,
                              NetworkManager.shared.baseURL != nil else { return }

                        // Phase 14.3H (B5): Avoid racing foreground liveness refresh against an in-flight sign-in.
                        guard !auth.isSigningIn else {
                            #if DEBUG
                            NSLog("[App] foreground: sign-in in flight; skipping ensureValidSession")
                            #endif
                            return
                        }

                        // Phase 14.2.2: Session liveness — refresh before issuing connected requests.
                        let ok = await auth.ensureValidSession(reason: "foreground")
                        guard ok else { return }
                        _ = await BackendEnvironment.shared.publish.fetchFeed(scope: "all")
                        await SessionSyncQueue.shared.flushNow()
                    }
                }
                .onReceive(connectedMembershipStore.$membershipState.removeDuplicates()) { state in
                    handleMembershipState(state)
                }
                .onReceive(auth.$currentUserID.removeDuplicates()) { uid in
                    appModeManager.applyActivation(auth: auth, isEntitled: connectedMembershipStore.isEntitled)
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
                .onReceive(auth.$backendUserID.removeDuplicates()) { backendUserID in
                    appModeManager.applyActivation(auth: auth, isEntitled: connectedMembershipStore.isEntitled)

                    // M7B: backend identity publication is the sign-in transition where the
                    // Connected runtime becomes available. Run the pending avatar promotion only
                    // after activation so AuthManager's Connected guard can succeed.
                    guard backendUserID != nil else { return }
                    Task {
                        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "backendUserIDAfterActivation")
                    }
                }
                .preferredColorScheme(.light)
        }
    }

    @MainActor
    private func handleMembershipState(_ state: ConnectedMembershipStore.MembershipState) {
        // C-1: the client governs access, and only access. A negative entitlement
        // read withdraws the Connected experience and does nothing else — a
        // reversible decision, which the next read restores if the read was wrong.
        // Irreversible membership-expiry cleanup is the server's responsibility,
        // via App Store Server Notifications (Phase 3). The client no longer has
        // the authority to delete a Connected account on its own evidence.
        switch state {
        case .unknown, .loading:
            return

        case .entitled:
            appModeManager.applyActivation(auth: auth, isEntitled: true)

        case .notEntitled:
            appModeManager.applyActivation(auth: auth, isEntitled: false)
        }
    }
}
