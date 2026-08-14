// CHANGE-ID: 20260815_PHASE2_U2_CANONICAL_ATTACHMENT_PATH_RESOLVER
// SCOPE: Phase 2 (C-4) unit 2 — one canonical resolver for the persisted
// Attachment.fileURL string, used by rendering, publishing, deletion and the two
// deletion-safety guards. No schema change and no attachment-identity redesign.
// SEARCH-TOKEN: 20260815_PHASE2_U2_CANONICAL_ATTACHMENT_PATH_RESOLVER

import Foundation

/// Resolves the absolute path string persisted in `Attachment.fileURL` to a file that
/// actually exists on this device, today.
///
/// ## Why this exists
///
/// `Attachment.fileURL` stores an **absolute path**, and the app container's UUID changes
/// on restore. Before Phase 2 that was invisible, because media was excluded from backup
/// and so never survived a restore at all. C-4 makes the media survive — which makes every
/// consumer of the stored path capable of aiming at a path that no longer exists.
///
/// Seven near-duplicate resolvers existed, five searching only `Documents` and two
/// searching six directories. They agreed in intent and differed in coverage, which is the
/// same drift shape as C-28's two extension lists and C-4's five exclusion sites.
///
/// **This is not stable attachment identity.** Replacing path-as-identity is M13/M14
/// groundwork (`docs/architecture.md`). This makes today's representation resolve safely.
///
/// ## Eligible locations — deliberately narrow
///
/// Only `Documents/` and `Documents/Scores/`. The wider list the old resolvers used
/// (Caches, Library, Application Support, tmp) is **unsafe for a canonical resolver**, and
/// the filename audit proved it rather than suspected it:
///
/// - Persisted attachment media has **always** been written to `Documents/` — the earliest
///   `AttachmentStore.saveData` (`7c54aae`, 2025-09-10) already used `.documentDirectory`
///   and it has never pointed elsewhere. So the wider directories cannot hold a legitimate
///   persisted attachment.
/// - `tmp/` is a **guaranteed collision source**. A persisted file is written as
///   `Documents/<stagedAttachmentID>.<ext>` while its viewer surrogate is written as
///   `tmp/<stagedAttachmentID>.<ext>` — same id, same stem, same extension, by
///   construction. Falling through to tmp could return an ephemeral, possibly pre-trim
///   copy. Once this resolver feeds publish and deletion, that means uploading stale bytes
///   or aiming a delete at the wrong file.
///
/// This eligible set is deliberately identical to `BackupPolicy.permanentMediaDirectories`
/// and to the set the Phase 2 reconciliation pass traverses. If one changes, all change.
///
/// ## Filename uniqueness — what is actually guaranteed
///
/// `AttachmentStore.uniqueFilename` guarantees uniqueness **within `Documents/`** only.
/// Score PDFs are `<UUID>.pdf` within `Documents/Scores/`. Across those two directories a
/// collision requires a UUID collision, but a legacy install predating `uniqueFilename`
/// could hold arbitrary user-derived stems, so ambiguity is not *provably* impossible.
/// Hence rule 4 below: ambiguity resolves deterministically or not at all — never
/// "whichever directory is searched first".
enum AttachmentPathResolver {

    /// The directories a persisted attachment may legitimately live in.
    private static var eligibleDirectories: [URL] {
        guard let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        return [documents, documents.appendingPathComponent("Scores", isDirectory: true)]
    }

    /// Resolves a stored `Attachment.fileURL` value to an existing file.
    ///
    /// 1. If the stored absolute path exists, use it.
    /// 2. Otherwise match by filename against the eligible permanent locations.
    /// 3. Zero matches → `nil`.
    /// 4. Matches in both locations → disambiguate by the stored path's own parent
    ///    directory; if it gives no hint, return `nil` rather than guess.
    static func resolve(_ stored: String?) -> URL? {
        guard let raw = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let fm = FileManager.default

        // 1 — the stored value, as a file URL string or as an absolute path.
        if let parsed = URL(string: raw), parsed.isFileURL, fm.fileExists(atPath: parsed.path) {
            return parsed
        }
        if raw.hasPrefix("/"), fm.fileExists(atPath: raw) {
            return URL(fileURLWithPath: raw)
        }

        // 2 — filename match against the eligible locations only.
        let filename = URL(fileURLWithPath: raw).lastPathComponent
        guard !filename.isEmpty else { return nil }

        let matches = eligibleDirectories
            .map { $0.appendingPathComponent(filename, isDirectory: false) }
            .filter { fm.fileExists(atPath: $0.path) }

        // 3
        if matches.isEmpty { return nil }
        if matches.count == 1 { return matches[0] }

        // 4 — ambiguous. The stored path's own parent is the only evidence available about
        // which of the two the record meant, and it survives a container change because it
        // is the trailing component, not the container prefix.
        let storedParentIsScores = URL(fileURLWithPath: raw)
            .deletingLastPathComponent()
            .lastPathComponent == "Scores"

        return matches.first { candidate in
            let candidateIsScores = candidate.deletingLastPathComponent().lastPathComponent == "Scores"
            return candidateIsScores == storedParentIsScores
        }
    }

    /// True when `url` is the file a stored path refers to.
    ///
    /// The deletion-safety guards need this rather than `resolve`: they hold a candidate
    /// URL and ask whether any persisted attachment already claims it. Comparing a live
    /// URL against a raw stored string is what made those guards fail *open* — after a
    /// container change the strings never match, the guard concludes "not protected", and
    /// a file a persisted attachment still references gets deleted.
    static func storedPath(_ stored: String?, refersTo url: URL) -> Bool {
        guard let resolved = resolve(stored) else { return false }
        return resolved.standardizedFileURL.path == url.standardizedFileURL.path
    }
}
