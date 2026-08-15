// CHANGE-ID: 20260815_PHASE2_U5_EXISTING_INSTALL_RECONCILIATION
// SCOPE: Phase 2 (C-4) unit 5 — one-time pass clearing the backup-exclusion attribute
// from permanent media already on disk. U3 only affects files written from now on.
// SEARCH-TOKEN: 20260815_PHASE2_U5_EXISTING_INSTALL_RECONCILIATION

import Foundation
import os

/// Makes permanent media that already exists on an installed device backup-eligible.
///
/// U3 stopped *new* writes from being excluded. Every file already on disk still carries
/// the attribute, so without this pass an existing user's entire library would stay
/// excluded forever and C-4 would be fixed only for people who install after it. QA F2
/// exists to prove exactly this half.
///
/// ## Why it must clear item-level flags and not just the directory
///
/// The exclusion attribute lives only on the item it was set on, and a child's own
/// attribute **survives its parent being un-flagged**. `Documents/Scores/` was flagged at
/// the directory level *and* every PDF was flagged individually. A pass that cleared only
/// the directory would leave every score PDF excluded — and that failure is invisible
/// until a real restore, months later, with no diagnostic to explain it.
///
/// ## Completion semantics
///
/// **The completion key is written only when the traversal reaches its defined stopping
/// rule — every eligible file examined — AND every examined file ended up eligible.**
/// It is not an optimisation that may be taken early, and there is no processing cap:
/// "off the main actor" is about not blocking launch, never a licence to process a capped
/// number of files and declare victory.
///
/// Two distinct incomplete outcomes, both retried on a later launch:
///
/// - **Traversal interrupted** — enumeration could not be started, or failed partway.
/// - **`failed > 0`** — the traversal finished, but at least one file could not be made
///   backup-eligible.
///
/// The second case used to record completion, on the reasoning that a permanently
/// unwritable file would otherwise retry forever. **That trade is withdrawn: a known
/// incomplete durability migration must not be recorded as complete.** Retrying costs one
/// directory scan per launch; the alternative is a file that silently never participates
/// in backup, with a single log line as the only evidence it ever existed. Operationally
/// the pass stays best-effort — a per-item failure never becomes fatal launch behaviour,
/// it only withholds the completion record.
///
/// Repeated traversal after a partial failure is safe and idempotent: an already-eligible
/// file is counted `alreadyEligible` and skipped without a write, and clearing the flag on
/// an item that never carried it is a clean no-op.
enum BackupReconciliation {

    private static let log = Logger(subsystem: "com.sdsongs.etudes", category: "backuppolicy")

    /// Versioned so a future policy change can define its own pass without colliding.
    private static let completionKey = "backupReconciliation_v1_complete"

    /// Files that must stay excluded even though they live in a reconciled directory.
    private static let transientCapturePrefix = "motivo_vid_"

    /// Runs the pass once per install, off the main actor.
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: completionKey) else { return }

        Task.detached(priority: .utility) {
            let outcome = reconcile()

            // Counts only, never a filename or a path. `examined` alone cannot distinguish
            // "ran and had nothing to do" from "ran and silently failed", which is the same
            // reasoning the C-28 wipe-outcome lines were written from.
            let recorded = outcome.completed && outcome.failed == 0
            log.notice("""
                [C-4] backupReconciliation \
                traversalComplete=\(outcome.completed, privacy: .public) \
                recordedComplete=\(recorded, privacy: .public) \
                examined=\(outcome.examined, privacy: .public) \
                alreadyEligible=\(outcome.alreadyEligible, privacy: .public) \
                cleared=\(outcome.cleared, privacy: .public) \
                failed=\(outcome.failed, privacy: .public)
                """)

            // Record completion only when the migration is genuinely finished. An
            // interrupted traversal and a traversal with per-item failures are both
            // incomplete durability migrations, and neither may be recorded as done.
            guard recorded else { return }
            UserDefaults.standard.set(true, forKey: completionKey)
        }
    }

    struct Outcome {
        var completed = false
        var examined = 0
        var alreadyEligible = 0
        var cleared = 0
        var failed = 0
    }

    /// Visible for verification: performs the traversal and reports what it found.
    @discardableResult
    static func reconcile() -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default

        // The same two directories the canonical resolver treats as eligible and that
        // BackupPolicy names as permanent media. If one of the three changes, all change.
        let directories = BackupPolicy.permanentMediaDirectories
        guard !directories.isEmpty else { return outcome }

        for directory in directories {
            guard fm.fileExists(atPath: directory.path) else { continue }

            // Clear the directory's own flag first. Necessary but not sufficient — see the
            // per-file loop below.
            BackupPolicy.include(directory)

            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                // Enumeration failed for a directory that exists: the traversal has not
                // reached its stopping rule, so the whole pass stays incomplete.
                return outcome
            }

            for url in contents {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                    continue
                }
                // An in-flight capture is transient and stays excluded.
                if url.lastPathComponent.hasPrefix(transientCapturePrefix) { continue }

                outcome.examined += 1

                if BackupPolicy.isExcluded(url) == false {
                    outcome.alreadyEligible += 1
                    continue
                }

                BackupPolicy.include(url)

                // Read back rather than assume. `BackupPolicy.include` is best-effort and
                // swallows its error, so the only honest way to count a clear is to check.
                if BackupPolicy.isExcluded(url) == false {
                    outcome.cleared += 1
                } else {
                    outcome.failed += 1
                }
            }
        }

        outcome.completed = true
        return outcome
    }
}
