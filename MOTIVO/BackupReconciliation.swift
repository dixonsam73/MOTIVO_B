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
/// rule: every eligible file examined.** It is not an optimisation that may be taken
/// early. If enumeration cannot be started or is interrupted, the key is not written and a
/// later launch retries from scratch.
///
/// Individual per-item failures are counted and tolerated — they do not block completion.
/// That is a deliberate trade: a single permanently-unwritable file would otherwise make
/// the pass retry on every launch forever, and the counts are there to make such a file
/// visible rather than silent.
///
/// "Off the main actor" is about not blocking launch. It is **not** a licence to process a
/// capped number of files and declare victory.
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
            guard outcome.completed else {
                // Traversal did not reach its stopping rule. Leave the key unwritten so a
                // later launch retries; a partial pass must never look like a finished one.
                log.notice("[C-4] backupReconciliation incomplete — will retry on a later launch")
                return
            }
            UserDefaults.standard.set(true, forKey: completionKey)

            // Counts only, never a filename or a path. `examined` alone cannot distinguish
            // "ran and had nothing to do" from "ran and silently failed", which is the same
            // reasoning the C-28 wipe-outcome lines were written from.
            log.notice("""
                [C-4] backupReconciliation complete \
                examined=\(outcome.examined, privacy: .public) \
                alreadyEligible=\(outcome.alreadyEligible, privacy: .public) \
                cleared=\(outcome.cleared, privacy: .public) \
                failed=\(outcome.failed, privacy: .public)
                """)
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
