// CHANGE-ID: 20260303_165200_DeleteAccountV2_Stage5C_UserDefaultsDomainWipe
// SCOPE: Delete Account v2 Stage 5C — extend LocalFactoryReset to wipe ProfileStore (UserDefaults + local avatar files) and remote avatar caches. No other UI/logic changes.
// SEARCH-TOKEN: 20260303_165200-DELETE-ACCOUNT-V2-STAGE5C-LOCALFACTORYRESET

//
// CHANGE-ID: 20260303_173500_DeleteAccountV2_Stage6_RuntimeBootstrap
// SCOPE: Delete Account v2 Stage 6 — after wiping defaults/domain, re-bootstrap bundled backend config at runtime so immediate re-sign-in shows AppSetup without app restart. No other UI/logic changes.
// SEARCH-TOKEN: 20260303_173500-DELETE-ACCOUNT-V2-STAGE6-RUNTIMEBOOTSTRAP

import Foundation

/// Delete Account v2 — Local Factory Reset coordinator.
/// Stage 5: invoked from delete-account success path; performs sign-out, stops publish queue, wipes backend config,
/// wipes local identity artifacts (ProfileStore + avatar caches), wipes local files, and wipes Core Data (batch delete).
@MainActor
enum LocalFactoryReset {

    // In-memory gate is sufficient for current acceptance tests; no persistence across relaunch required.
    private(set) static var isInProgress: Bool = false

    static func perform(reason: String, auth: AuthManager) async {
        guard !isInProgress else {
            NSLog("[LocalFactoryReset] already in progress; ignoring request reason=\(reason)")
            return
        }

        isInProgress = true
        defer {
            isInProgress = false
            NSLog("[LocalFactoryReset] completed (stage 5c) reason=\(reason)")
        }

        NSLog("[LocalFactoryReset] begin (stage 5c) reason=\(reason)")

        // Prevent any background publish attempts while we reset.
        SessionSyncQueue.shared.stopForFactoryReset()

        // Wipe backend config (base URL + anon key) so connected mode cannot resurrect.
        BackendConfig.wipePersistedConfigForFactoryReset()

        // Drop to signed-out state immediately and clear auth tokens.
        auth.signOut()

        // Wipe entire UserDefaults domain to prevent any per-user keys (e.g. profile.*) or mode flags from surviving.
        // This is a factory reset: preferences should return to a fresh-install baseline.
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }

        // Re-apply bundled backend config (if present) so AppSetup gating can work immediately without restart.
        BackendConfig.bootstrapFromBundleIfNeededForFactoryReset()

        // Wipe local profile identity artifacts (UserDefaults profile.* keys + local avatar files).
        // We intentionally do not rely on a user id here; ProfileStore will purge any profile.* keys.
        ProfileStore.wipeLocalIdentityForFactoryReset(backendUserID: nil)

        // Wipe remote avatar caches (directory avatars).
        await RemoteAvatarSignedURLCache.shared.resetForFactoryReset()
        #if canImport(UIKit)
        RemoteAvatarImageCache.resetForFactoryReset()
        #endif

        // Wipe local files (Documents + Application Support stores + tmp).
        AttachmentStore.wipeDocumentsAttachmentsForFactoryReset()
        StagingStore.wipeOnDiskForFactoryReset()
        PracticeTimerStore.wipeOnDiskForFactoryReset()
        SessionSyncQueue.shared.wipeOnDiskForFactoryReset()
        AttachmentPrivacy.wipeOnDiskAndCacheForFactoryReset()
        wipeTemporaryMediaArtifactsBestEffort()

        // Reset Core Data persistent stores (store-safe wipe via batch delete).
        do {
            try PersistenceController.shared.destroyAndRebuildStoresForFactoryReset()
        } catch {
            // Best-effort; continue to avoid partial state.
            NSLog("[LocalFactoryReset] Core Data reset failed: \(error)")
        }

        // Belt + braces: ensure key in-memory stores are reset even if app-level sign-out observers change later.
        if BackendEnvironment.shared.isConnected {
            BackendFeedStore.shared.resetForSignOut()
            FollowStore.shared.resetForSignOut()
        }
    }

    private static func wipeTemporaryMediaArtifactsBestEffort() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        do {
            let urls = try fm.contentsOfDirectory(
                at: tmp,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let exts = Set(["m4a", "mov", "mp4", "jpg", "jpeg", "png"])
            for url in urls where exts.contains(url.pathExtension.lowercased()) {
                try? fm.removeItem(at: url)
            }
        } catch {
            // Best effort — ignore.
        }
    }
}
