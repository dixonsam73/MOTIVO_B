// CHANGE-ID: 20260303_103200_DeleteAccountV2_Stage4B_CoreDataResetFix
// SCOPE: Delete Account v2 Stage 4 — extend LocalFactoryReset to destroy + recreate Core Data store after Stage 3 file wipes. No other UI/logic changes.
// SEARCH-TOKEN: 20260303_103200-DELETE-ACCOUNT-V2-STAGE4B-LOCALFACTORYRESET

import Foundation

/// Delete Account v2 — Local Factory Reset coordinator.
/// Stage 4: invoked from delete-account success path; performs sign-out, stops publish queue, wipes backend config, wipes local files, and resets Core Data.
/// Subsequent stage adds deeper UserDefaults wipes (if needed beyond current evidence-based keys).
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
            NSLog("[LocalFactoryReset] completed (stage 4b) reason=\(reason)")
        }

        NSLog("[LocalFactoryReset] begin (stage 4b) reason=\(reason)")

        // Prevent any background publish attempts while we reset.
        SessionSyncQueue.shared.stopForFactoryReset()

        // Wipe backend config (base URL + anon key) so connected mode cannot resurrect.
        BackendConfig.wipePersistedConfigForFactoryReset()

        // Drop to signed-out state immediately and clear auth tokens.
        auth.signOut()

        // Wipe local files (Documents + Application Support stores + tmp).
        AttachmentStore.wipeDocumentsAttachmentsForFactoryReset()
        StagingStore.wipeOnDiskForFactoryReset()
        PracticeTimerStore.wipeOnDiskForFactoryReset()
        SessionSyncQueue.shared.wipeOnDiskForFactoryReset()
        AttachmentPrivacy.wipeOnDiskAndCacheForFactoryReset()
        wipeTemporaryMediaArtifactsBestEffort()

        // Reset Core Data persistent stores (destroy + recreate empty store).
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
