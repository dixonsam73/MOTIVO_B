// CHANGE-ID: 20260714_ScoresLocalLibraryIdentityMigration
// SCOPE: Make the Scores library permanently device-local and independent of Études Connected identity. Migrate legacy identity-scoped score metadata non-destructively. No UI, PDF file, Core Data, backend, attachment, viewer, or unrelated behaviour changes.
// SEARCH-TOKEN: 20260714_SCORES_LOCAL_LIBRARY_IDENTITY_MIGRATION

import Foundation
import Combine
import CoreData

enum ScoreLibraryError: LocalizedError {
    /// C-139: the saved index could not be decoded. Nothing is replaced until
    /// a build that can read it runs; adding a score would persist over it.
    case indexDamaged

    var errorDescription: String? {
        switch self {
        case .indexDamaged: return "Your scores could not be read. Nothing has been replaced."
        }
    }
}

/// What a write to the library changed, for the private sync trial's scan
/// cadence: a reading position has its own.
enum ScoreLibraryChange { case library, position }

/// A value copy of the library for work off the main actor (hashing files,
/// building records).
struct ScoreLibrarySnapshot {
    let items: [ScoreLibraryItem]
    let indexDamaged: Bool
    let directory: URL
    func url(for item: ScoreLibraryItem) -> URL { directory.appendingPathComponent(item.fileName, isDirectory: false) }
}

@MainActor
final class ScoreLibraryStore: ObservableObject {
    static let shared = ScoreLibraryStore()

    @Published private(set) var items: [ScoreLibraryItem] = []
    @Published private(set) var activeScoreID: UUID?
    /// C-139: the index exists but could not be decoded. The library reads as
    /// empty, every write is refused, and the stored bytes are left exactly as
    /// they are so a later build can still read them.
    @Published private(set) var indexDamaged = false
    /// Items whose PDF is not on this device (the index entry exists, the
    /// file does not). Shown as unavailable; never silently "fully synced".
    /// Recomputed after every load and write, and on request.
    @Published private(set) var missingFileIDs: Set<UUID> = []

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let directoryOverride: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// C-138: whether a journal attachment still refers to a library PDF.
    /// Injected so the rule is unit-tested without the app's store.
    var attachmentContext: () -> NSManagedObjectContext? = { PersistenceController.shared.container.viewContext }

    private convenience init() {
        self.init(defaults: .standard, scoresDirectory: nil, fileManager: .default)
    }

    /// Tests pass their own defaults and directory; the app uses the shared store.
    init(defaults: UserDefaults, scoresDirectory: URL?, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.directoryOverride = scoresDirectory
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    var activeItem: ScoreLibraryItem? {
        guard let activeScoreID else { return nil }
        return items.first(where: { $0.id == activeScoreID })
    }

    func url(for item: ScoreLibraryItem) -> URL {
        scoresDirectory().appendingPathComponent(item.fileName, isDirectory: false)
    }

    func isFileMissing(_ item: ScoreLibraryItem) -> Bool { missingFileIDs.contains(item.id) }

    /// Re-checks which items have their file. Cheap (one stat per item).
    func refreshFileAvailability() {
        let missing = Set(items.filter { !fileManager.fileExists(atPath: url(for: $0).path) }.map(\.id))
        if missing != missingFileIDs { missingFileIDs = missing }
    }

    func filteredItems(matching query: String) -> [ScoreLibraryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = items.sorted { lhs, rhs in
            if lhs.isFavourite != rhs.isFavourite { return lhs.isFavourite && !rhs.isFavourite }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        guard !trimmed.isEmpty else { return source }
        return source.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    @discardableResult
    func importPDF(
        from sourceURL: URL,
        displayName: String? = nil,
        sourceAttachmentID: UUID? = nil
    ) throws -> ScoreLibraryItem {
        guard !indexDamaged else { throw ScoreLibraryError.indexDamaged }
        // C-5 — adopting the same received attachment again returns its Score untouched,
        // but only while that Score's file still exists: a Score (or file) the member
        // removed does not block re-adoption. Manual imports pass no id and are unchanged.
        if let sourceAttachmentID,
           let existing = items.first(where: {
               $0.sourceAttachmentID == sourceAttachmentID
                   && fileManager.fileExists(atPath: url(for: $0).path)
           }) {
            return existing
        }

        let didStartSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let title = cleanedTitle(
            displayName ?? sourceURL.deletingPathExtension().lastPathComponent,
            fallback: "Untitled Score"
        )
        let destination = try uniqueScoreFileURL()

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: sourceURL, to: destination)
        try excludeFromBackup(destination)

        let pageCount = max(PDFSelectedPagesStore.pageCount(for: destination), 1)
        let item = ScoreLibraryItem(
            title: title,
            fileName: destination.lastPathComponent,
            pageCount: pageCount,
            thumbnailPage: 1,
            isFavourite: false,
            createdAt: Date(),
            lastOpenedAt: nil,
            lastViewedPage: nil,
            sourceAttachmentID: sourceAttachmentID
        )

        items.append(item)
        persist(.library)
        return item
    }

    @discardableResult
    func addScannedPDF(data: Data, title: String) throws -> ScoreLibraryItem {
        guard !indexDamaged else { throw ScoreLibraryError.indexDamaged }
        let cleaned = cleanedTitle(title, fallback: "Scanned Score")
        let destination = try uniqueScoreFileURL()
        try data.write(to: destination, options: [.atomic])
        try excludeFromBackup(destination)

        let pageCount = max(PDFSelectedPagesStore.pageCount(for: destination), 1)
        let item = ScoreLibraryItem(
            title: cleaned,
            fileName: destination.lastPathComponent,
            pageCount: pageCount,
            thumbnailPage: 1,
            isFavourite: false,
            createdAt: Date(),
            lastOpenedAt: nil,
            lastViewedPage: nil
        )

        items.append(item)
        persist(.library)
        return item
    }

    func markOpened(_ item: ScoreLibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].lastOpenedAt = Date()
        activeScoreID = item.id
        persist(nil)
    }

    func clearActiveScore() {
        activeScoreID = nil
        persist(nil)
    }

    func updateLastViewedPage(for itemID: UUID, page: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let boundedPage = min(max(page, 1), max(items[index].pageCount, 1))
        guard items[index].lastViewedPage != boundedPage else { return }
        items[index].lastViewedPage = boundedPage
        persist(.position)
    }

    func rename(_ item: ScoreLibraryItem, to newTitle: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let cleaned = cleanedTitle(newTitle, fallback: items[index].title)
        guard !cleaned.isEmpty, cleaned != items[index].title else { return }
        items[index].title = cleaned
        persist(.library)
    }

    func toggleFavourite(_ item: ScoreLibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavourite.toggle()
        persist(.library)
    }

    /// The page the library's thumbnail shows. No screen offers this choice yet;
    /// the field has always existed and is kept within the document.
    func setThumbnailPage(_ page: Int, for itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let bounded = min(max(page, 1), max(items[index].pageCount, 1))
        guard items[index].thumbnailPage != bounded else { return }
        items[index].thumbnailPage = bounded
        persist(.library)
    }

    /// Removes the item from the library. C-138: a journal attachment made from
    /// this score points at the SAME file (`AttachmentStore.addAttachment` with
    /// the library path; no copy), so the file is deleted only when no
    /// attachment refers to it. The attachment deletion paths protect library
    /// files in the other direction (`isProtectedScoreLibraryURL`).
    func delete(_ item: ScoreLibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let url = self.url(for: items[index])
        if !isReferencedByAttachment(url) {
            try? fileManager.removeItem(at: url)
        }
        items.remove(at: index)
        if activeScoreID == item.id {
            activeScoreID = nil
        }
        persist(.library)
    }

    /// The score whose viewer is on screen right now (not persisted). While it
    /// is open, a reading position from another device is not written into
    /// its saved page: the page on screen is the truth, and it is published
    /// when the viewer is dismissed or the app goes to the background.
    private(set) var openViewerID: UUID?

    func viewerDidOpen(_ itemID: UUID) {
        openViewerID = itemID
    }

    /// The timer's score viewer was dismissed: the reading position is final
    /// for now. Production: nothing more; the private sync trial sends it.
    func viewerDidClose(_ itemID: UUID) {
        if openViewerID == itemID { openViewerID = nil }
        #if SYNCTEST
        JournalScoreMirror.viewerClosed(itemID)
        #endif
    }

    // MARK: - Private sync trial (imports write the library without firing a change)

    func snapshot() -> ScoreLibrarySnapshot {
        ScoreLibrarySnapshot(items: items, indexDamaged: indexDamaged, directory: scoresDirectory())
    }

    /// Appends the item or replaces the one with its id (keeping what is
    /// device-local: the last-opened date). False when the index is damaged.
    @discardableResult
    func applyImported(_ item: ScoreLibraryItem) -> Bool {
        guard !indexDamaged else { return false }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var merged = item
            merged.lastOpenedAt = items[index].lastOpenedAt
            items[index] = merged
        } else {
            items.append(item)
        }
        persist(nil)
        return true
    }

    @discardableResult
    func applyImportedMetadata(id: UUID, title: String, isFavourite: Bool, thumbnailPage: Int) -> Bool {
        guard !indexDamaged, let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let cleaned = cleanedTitle(title, fallback: items[index].title)
        items[index].title = cleaned
        items[index].isFavourite = isFavourite
        items[index].thumbnailPage = min(max(thumbnailPage, 1), max(items[index].pageCount, 1))
        persist(nil)
        return true
    }

    /// Writes a reading position from the other device, clamped to the
    /// document. Nil while that score's viewer is open: the page on screen
    /// stays the saved page and is published at the next boundary (seen on
    /// device 2026-10-26: imported pages overwrote the saved page under an
    /// open viewer, so the dismissal published the other device's page).
    /// Returns the page applied.
    @discardableResult
    func applyImportedPosition(id: UUID, page: Int) -> Int? {
        guard !indexDamaged, openViewerID != id, let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let bounded = min(max(page, 1), max(items[index].pageCount, 1))
        if items[index].lastViewedPage != bounded {
            items[index].lastViewedPage = bounded
            persist(nil)
        }
        return bounded
    }

    /// A deletion from the other device: the same rule as a local delete
    /// (C-138 keeps a file a journal attachment refers to).
    @discardableResult
    func removeImported(id: UUID) -> Bool {
        guard !indexDamaged, let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let url = self.url(for: items[index])
        if !isReferencedByAttachment(url) {
            try? fileManager.removeItem(at: url)
        }
        items.remove(at: index)
        if activeScoreID == id { activeScoreID = nil }
        persist(nil)
        return true
    }

    /// Whether any persisted attachment's stored path refers to `url`, resolved
    /// the way the deletion-safety guards resolve it (so a container move after
    /// a restore still matches). Unreadable store → treated as referenced, so a
    /// doubt never deletes.
    func isReferencedByAttachment(_ url: URL) -> Bool {
        guard let context = attachmentContext() else { return true }
        return Self.isReferencedByAttachment(url, in: context)
    }

    nonisolated static func isReferencedByAttachment(_ url: URL, in context: NSManagedObjectContext) -> Bool {
        var referenced = false
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Attachment")
            request.predicate = NSPredicate(format: "kind == %@", AttachmentKind.pdf.rawValue)
            guard let rows = try? context.fetch(request) else { referenced = true; return }
            referenced = rows.contains { AttachmentPathResolver.storedPath($0.value(forKey: "fileURL") as? String, refersTo: url) }
        }
        return referenced
    }

    // MARK: - Delete Account v2 (Local Factory Reset)

    /// Clears the Scores library completely: the on-disk PDFs, the persisted
    /// index, and the in-memory state.
    ///
    /// C-2: all three are required. The PDFs live in `Documents/Scores/`, which
    /// no other wipe reaches — `AttachmentStore` deliberately protects that tree
    /// (`isProtectedScoreLibraryURL`), so this store owns clearing it. The
    /// singleton outlives the reset, so leaving `items` populated lets the next
    /// mutation `persist()` the whole library straight back. And the legacy
    /// `scoreLibrary_v1::` keys must go too, because `load()` migrates them
    /// forward whenever `scoreLibrary_v2` is absent — the post-reset state
    /// exactly.
    func wipeOnDiskAndCacheForFactoryReset() {
        try? fileManager.removeItem(at: scoresDirectory())

        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: activeScoreKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("scoreLibrary_") {
            defaults.removeObject(forKey: key)
        }

        items = []
        activeScoreID = nil
        indexDamaged = false
    }

    private func load() {
        migrateLegacyIdentityScopedLibraryIfNeeded(in: defaults)

        if let data = defaults.data(forKey: storageKey) {
            if let decoded = try? decoder.decode([ScoreLibraryItem].self, from: data) {
                items = decoded
                indexDamaged = false
            } else {
                // C-139: an index this build cannot read is not an empty library.
                items = []
                indexDamaged = true
            }
        } else {
            items = []
            indexDamaged = false
        }

        if let rawActive = defaults.string(forKey: activeScoreKey),
           let id = UUID(uuidString: rawActive),
           items.contains(where: { $0.id == id }) {
            activeScoreID = id
        } else {
            activeScoreID = nil
        }
        refreshFileAvailability()
    }

    private func migrateLegacyIdentityScopedLibraryIfNeeded(in defaults: UserDefaults) {
        guard defaults.object(forKey: storageKey) == nil else { return }

        let legacyStoragePrefix = "scoreLibrary_v1::"
        let legacyActivePrefix = "scoreLibrary_activeScore_v1::"

        let legacyStorageKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(legacyStoragePrefix) }
            .sorted { lhs, rhs in
                let localKey = legacyStoragePrefix + "local"
                if lhs == localKey { return true }
                if rhs == localKey { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        var migratedItems: [ScoreLibraryItem] = []
        var migratedIDs = Set<UUID>()
        var migratedActiveScoreID: UUID?

        for legacyKey in legacyStorageKeys {
            guard let data = defaults.data(forKey: legacyKey),
                  let decoded = try? decoder.decode([ScoreLibraryItem].self, from: data) else {
                continue
            }

            for item in decoded where migratedIDs.insert(item.id).inserted {
                migratedItems.append(item)
            }

            if migratedActiveScoreID == nil {
                let scope = String(legacyKey.dropFirst(legacyStoragePrefix.count))
                let legacyActiveKey = legacyActivePrefix + scope
                if let rawActive = defaults.string(forKey: legacyActiveKey),
                   let id = UUID(uuidString: rawActive),
                   decoded.contains(where: { $0.id == id }) {
                    migratedActiveScoreID = id
                }
            }
        }

        if let data = try? encoder.encode(migratedItems) {
            defaults.set(data, forKey: storageKey)
        }

        if let migratedActiveScoreID,
           migratedItems.contains(where: { $0.id == migratedActiveScoreID }) {
            defaults.set(migratedActiveScoreID.uuidString, forKey: activeScoreKey)
        }
    }

    /// Writes the index. C-139: never over an index that could not be read.
    /// `change` names what a person changed (nil: device-local state or an
    /// import), so the private sync trial can scan at the right cadence.
    private func persist(_ change: ScoreLibraryChange?) {
        guard !indexDamaged else { return }
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: storageKey)
        }
        refreshFileAvailability()

        if let activeScoreID {
            defaults.set(activeScoreID.uuidString, forKey: activeScoreKey)
        } else {
            defaults.removeObject(forKey: activeScoreKey)
        }
        #if SYNCTEST
        if let change { JournalScoreMirror.changed(change) }
        #endif
    }

    private var storageKey: String {
        "scoreLibrary_v2"
    }

    private var activeScoreKey: String {
        "scoreLibrary_activeScore_v2"
    }

    private func scoresDirectory() -> URL {
        let directory = directoryOverride ?? Self.defaultScoresDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? excludeFromBackup(directory)
        }
        return directory
    }

    /// `Documents/Scores`, the one place library PDFs live (`AttachmentPathResolver`,
    /// `BackupPolicy` and the attachment deletion guards all name it).
    nonisolated static func defaultScoresDirectory(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return documents.appendingPathComponent("Scores", isDirectory: true)
    }

    private func uniqueScoreFileURL() throws -> URL {
        let directory = scoresDirectory()
        let filename = UUID().uuidString + ".pdf"
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private func cleanedTitle(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Phase 2 (C-4): score PDFs now participate in ordinary Apple device backup.
    ///
    /// Applied to the `Scores` directory *and* to each PDF, because the two are separate
    /// facts: the exclusion attribute lives only on the item it was set on, and a child's
    /// own attribute survives its parent being un-flagged. Clearing only the directory
    /// would leave every existing PDF excluded — and that failure is invisible until a
    /// real restore, which is the worst possible place to discover it.
    ///
    /// **Adopted received scores are the decisive case.** A score adopted from another
    /// member is recipient-owned permanent data and is *not* reconstructible: under the
    /// revised deletion rule the sender's account deletion removes the backend object. If
    /// adopted scores did not survive a restore, "adoption" would not mean what the
    /// product says it means.
    private func excludeFromBackup(_ url: URL) throws {
        BackupPolicy.include(url)
    }
}
