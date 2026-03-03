// CHANGE-ID: 20260303_092100_DeleteAccountV2_Stage2_BackendConfig_QueueStop
// SCOPE: Delete Account v2 Stage 2 — stop publish queue + wipe backend config after delete success; no files/CoreData wipe yet.
// SEARCH-TOKEN: 20260303_092100-DELETE-ACCOUNT-V2-STAGE2

import Foundation

/// Delete Account v2 — Local Factory Reset coordinator.
/// Stage 2: invoked from delete-account success path; performs sign-out + stops publish queue and wipes backend config. Subsequent stages add file/Core Data wipes.
/// and provides an in-progress gate for foreground liveness. Subsequent stages add persisted wipes (UserDefaults/files/Core Data).
@MainActor
enum LocalFactoryReset {

    // Note: in-memory gate is sufficient for current acceptance tests; no persistence across relaunch needed for Stage 1.
    private(set) static var isInProgress: Bool = false

    static func perform(reason: String, auth: AuthManager) async {
        guard !isInProgress else {
            NSLog("[LocalFactoryReset] already in progress; ignoring request reason=\(reason)")
            return
        }

        isInProgress = true
        defer {
            isInProgress = false
            NSLog("[LocalFactoryReset] completed (stage 2) reason=\(reason)")
        }

        NSLog("[LocalFactoryReset] begin (stage 2) reason=\(reason)")

        // Stage 2: prevent any background publish attempts while we reset.
        SessionSyncQueue.shared.stopForFactoryReset()

        // Stage 2: wipe backend config (base URL + anon key) so connected mode cannot resurrect.
        BackendConfig.wipePersistedConfigForFactoryReset()

        // Stage 2: make the UI drop to signed-out state immediately and clear auth tokens.

        // Subsequent stages extend this to a full local wipe (UserDefaults/files/Core Data).
        auth.signOut()

        // Belt + braces: ensure key in-memory stores are reset even if app-level sign-out observers change later.
        if BackendEnvironment.shared.isConnected {
            BackendFeedStore.shared.resetForSignOut()
            FollowStore.shared.resetForSignOut()
        }
    }
}
