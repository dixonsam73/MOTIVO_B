// CHANGE-ID: 20260428_111500_DeleteAccountV2_RuntimeConnectedModeRestore
// SCOPE: Delete Account v2 runtime reset — restore non-DEBUG Connected backend mode after bundled config bootstrap so immediate re-onboarding matches fresh install. No UI/layout or unrelated logic changes.
// SEARCH-TOKEN: 20260428_111500-DELETE-ACCOUNT-V2-RUNTIME-CONNECTED-MODE-RESTORE

// CHANGE-ID: 20260303_165200_DeleteAccountV2_Stage5C_UserDefaultsDomainWipe
// SCOPE: Delete Account v2 Stage 5C — extend LocalFactoryReset to wipe ProfileStore (UserDefaults + local avatar files) and remote avatar caches. No other UI/logic changes.
// SEARCH-TOKEN: 20260303_165200-DELETE-ACCOUNT-V2-STAGE5C-LOCALFACTORYRESET

//
// CHANGE-ID: 20260303_173500_DeleteAccountV2_Stage6_RuntimeBootstrap
// SCOPE: Delete Account v2 Stage 6 — after wiping defaults/domain, re-bootstrap bundled backend config at runtime so immediate re-sign-in shows AppSetup without app restart. No other UI/logic changes.
// SEARCH-TOKEN: 20260303_173500-DELETE-ACCOUNT-V2-STAGE6-RUNTIMEBOOTSTRAP

import Foundation
import os

/// Delete Account v2 — Local Factory Reset coordinator.
/// Stage 5: invoked from delete-account success path; performs sign-out, stops publish queue, wipes backend config,
/// wipes local identity artifacts (ProfileStore + avatar caches), wipes local files, and wipes Core Data (batch delete).
@MainActor
enum LocalFactoryReset {

    // In-memory gate is sufficient for current acceptance tests; no persistence across relaunch required.
    private(set) static var isInProgress: Bool = false

    private static let log = Logger(subsystem: "com.sdsongs.etudes", category: "factoryreset")

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

        UserDefaults.standard.removeObject(forKey: AttachmentTitlePersistenceKeys.legacyAudioTitlesKey)
        UserDefaults.standard.removeObject(forKey: AttachmentTitlePersistenceKeys.legacyVideoTitlesKey)
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if key.hasPrefix(AttachmentTitlePersistenceKeys.audioPrefix) ||
                key.hasPrefix(AttachmentTitlePersistenceKeys.videoPrefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        // Re-apply bundled backend config (if present) so AppSetup gating can work immediately without restart.
        BackendConfig.bootstrapFromBundleIfNeededForFactoryReset()

        #if !DEBUG
        // Mirror MOTIVOApp.init() fresh-install default after a runtime factory reset.
        // UserDefaults domain wipe removes backendMode_v1, but app init does not rerun before immediate re-onboarding.
        if BackendConfig.isConfigured {
            UserDefaults.standard.set(BackendMode.backendConnected.rawValue, forKey: BackendKeys.modeKey)
            BackendConfig.apply()
            NSLog("[LocalFactoryReset] restored Connected backend mode after factory reset bootstrap")
        }
        #endif

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
        // C-2: Documents/Scores is a directory, so the extension-filtered sweep above
        // never reaches the PDFs inside it. The Scores store owns its own wipe.
        ScoreLibraryStore.shared.wipeOnDiskAndCacheForFactoryReset()
        // C-28: Application Support/ReceivedConnectedAttachments is outside every
        // sweep above — not under MOTIVO/, not extension-filtered Documents — so
        // media other members sent survived an explicit full erase. Note an
        // adopted PDF exists TWICE: the Scores copy above, and the inbox original
        // here. Wiping only the first is what made this look fixed.
        let receivedRemoved = ReceivedConnectedAttachmentStore.shared.wipeOnDiskAndCacheForFactoryReset()
        // C-48: CommentsStore.json sits at the Application Support ROOT rather
        // than under MOTIVO/, and was likewise never reached.
        let commentsFileExisted = CommentsStore.shared.wipeOnDiskAndCacheForFactoryReset()
        StagingStore.wipeOnDiskForFactoryReset()
        PracticeTimerStore.wipeOnDiskForFactoryReset()
        SessionSyncQueue.shared.wipeOnDiskForFactoryReset()
        AttachmentPrivacy.wipeOnDiskAndCacheForFactoryReset()
        let temporaryRemoved = wipeTemporaryMediaArtifactsBestEffort()

        // Release-readable outcome for the three C-28/C-48 sweeps, through one
        // funnel, deliberately NOT `#if DEBUG` — the rig runs Release, and
        // CLAUDE.md already carries this lesson twice (MembershipTrace, then
        // C-44 run 1, where the one line that would have named the cause was
        // compiled out of the only build that could execute the path).
        //
        // This is an outcome line on a destructive path, not temporary
        // instrumentation, so the standing removal condition does not apply.
        //
        // WHY COUNTS RATHER THAN "ran": an empty directory afterwards is
        // produced equally by "the wipe ran", "the wipe threw" and "this build
        // predates the wipe". Only a count taken before removal separates them,
        // and the run that raises the question destroys the fixture that could
        // answer it. Counts and booleans only — never a filename or a path.
        log.notice("[C-28] localReset receivedAttachmentsRemoved=\(receivedRemoved, privacy: .public) temporaryFilesRemoved=\(temporaryRemoved, privacy: .public)")
        log.notice("[C-48] localReset commentsStoreFileExisted=\(commentsFileExisted, privacy: .public)")

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

    @discardableResult
    private static func wipeTemporaryMediaArtifactsBestEffort() -> Int {
        var removed = 0
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        do {
            let urls = try fm.contentsOfDirectory(
                at: tmp,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            // C-28: this was its own shorter literal — no `pdf`, no
            // `wav/aif/aiff/caf/heic/m4v/dat` — while the Documents sweep
            // covered all of them. "Save to Files" copies a received attachment
            // into tmp/ before presenting the exporter, and PDFSubsetExporter
            // writes there too, so exported PDFs outlived the reset. One
            // authoritative set now serves both sweeps.
            let exts = AttachmentStore.factoryResetSweepExtensions
            for url in urls where exts.contains(url.pathExtension.lowercased()) {
                do {
                    try fm.removeItem(at: url)
                    removed += 1
                } catch {
                    // Best effort — ignore.
                }
            }
        } catch {
            // Best effort — ignore.
        }
        return removed
    }
}
