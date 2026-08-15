// CHANGE-ID: 20260815_PHASE2_U1_BACKUP_POLICY_OWNER
// SCOPE: Phase 2 (C-4) unit 1 — single owner for every backup-exclusion decision Études
// makes. Behaviour-neutral: the same paths are excluded as before, from one place.
// SEARCH-TOKEN: 20260815_PHASE2_U1_BACKUP_POLICY_OWNER

import Foundation
import os

/// The one place that decides what Études excludes from Apple device backup.
///
/// **This type owns only filesystem resources where Études deliberately sets or clears
/// the exclusion flag.** It does not pretend to own storage whose backup behaviour is
/// provided by the platform:
///
/// - **Inherited from normal iOS backup** (Études sets nothing): the Core Data store at
///   `Application Support/MOTIVO.sqlite`, `UserDefaults`, `Application Support/Profiles/`
///   (local avatars), `Application Support/CommentsStore.json`, and the Keychain.
/// - **Platform-excluded / transient**: `Library/Caches` and `tmp`, which iOS already
///   omits from backup.
///
/// The full 17-row durability matrix lives in `docs/architecture.md`; this file is the
/// executable subset.
///
/// ## Why a single owner
///
/// Before Phase 2 the exclusion flag was set from five scattered call sites in four
/// files, and one of them — `PracticeTimerStore.bootstrap()` — flagged
/// `Application Support/MOTIVO/`, a directory it does not own, as a side effect of a
/// UserDefaults migration helper. That is how `AttachmentPrivacy.json` came to be
/// excluded from backup without any code saying so. Scattered policy is also how C-28's
/// two divergent extension lists happened. One declaration, one reader.
///
/// ## Directory semantics — established empirically, 2026-08-15
///
/// `isExcludedFromBackup` is resolved by **ancestor walk**, not attribute inheritance:
/// the extended attribute exists only on the item explicitly flagged, but every item
/// beneath a flagged directory reports excluded, whether it existed before the flag was
/// set or was created after. Consequences that matter here:
///
/// 1. **There is no per-item "include" override.** A child of an excluded directory
///    cannot be exempted. This is why `AttachmentPrivacy.json` had to move out of
///    `MOTIVO/` rather than be un-excluded in place.
/// 2. **A child's own flag survives its parent being un-flagged.** So clearing a
///    directory is not sufficient to make its contents backup-eligible if the contents
///    were individually flagged — which is exactly the state `Documents/Scores/` is in.
///
/// **Standing rule: never rely on ancestor resolution for the outcome we care about.**
/// Exclusion may lean on it; *inclusion* must guarantee both that no ancestor is flagged
/// and that no item flag remains.
///
/// Note that all of the above describes what the URL API reports. It is not evidence
/// about what Apple's backup daemon actually copies — only a genuine backup/restore
/// settles that (QA F1/F2).
enum BackupPolicy {

    private static let log = Logger(subsystem: "com.sdsongs.etudes", category: "backuppolicy")

    // MARK: - Locations Études controls

    /// `Application Support/MOTIVO/` — scratch and operational storage, excluded wholesale.
    ///
    /// Contains staging media, practice-timer scratch and the pending publish queue. As of
    /// Phase 2 unit 4 it contains nothing permanent: `AttachmentPrivacy.json` moved to the
    /// Application Support root precisely so that this directory's exclusion is an honest
    /// statement about everything inside it.
    static var operationalScratchDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MOTIVO", isDirectory: true)
    }

    /// The two directories that hold permanent, user-owned attachment media.
    ///
    /// This is deliberately the same set as `AttachmentPathResolver`'s eligible locations
    /// and the same set the reconciliation pass traverses. If one of the three ever needs
    /// to change, all three change together.
    static var permanentMediaDirectories: [URL] {
        guard let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        return [documents, documents.appendingPathComponent("Scores", isDirectory: true)]
    }

    // MARK: - Launch application

    /// Applies the directory-level policy. Called once from `MOTIVOApp.init()`.
    ///
    /// Previously this happened as a side effect of `PracticeTimerStore.loadStagedVideo()`,
    /// which runs at launch and so produced the right answer — but by accident of call
    /// ordering rather than by design.
    static func applyDirectoryPolicyAtLaunch() {
        guard let scratch = operationalScratchDirectory else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: scratch.path) {
            try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        }
        exclude(scratch)
    }

    // MARK: - Primitives

    /// Best-effort exclusion. Failure must never abort the caller's real work.
    static func exclude(_ url: URL) {
        setExcluded(url, true)
    }

    /// Best-effort inclusion — clears an exclusion flag this item carries in its own right.
    ///
    /// Clearing on an item that never carried the attribute is a clean no-op, so callers
    /// need not test first.
    static func include(_ url: URL) {
        setExcluded(url, false)
    }

    private static func setExcluded(_ url: URL, _ value: Bool) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = value
        do {
            try mutable.setResourceValues(values)
        } catch {
            log.notice("[BackupPolicy] setExcluded=\(value, privacy: .public) failed")
        }
    }

    /// Reads the flag as the platform currently resolves it.
    ///
    /// Always constructs a fresh `URL`: `NSURL` caches resource values once fetched, and a
    /// reused instance will happily return a stale answer. That confound produced an
    /// internally inconsistent first run of the directory-semantics experiment.
    static func isExcluded(_ url: URL) -> Bool? {
        let fresh = URL(fileURLWithPath: url.path)
        return try? fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    }
}
