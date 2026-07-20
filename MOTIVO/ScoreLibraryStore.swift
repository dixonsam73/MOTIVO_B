// CHANGE-ID: 20260714_ScoresLocalLibraryIdentityMigration
// SCOPE: Make the Scores library permanently device-local and independent of Études Connected identity. Migrate legacy identity-scoped score metadata non-destructively. No UI, PDF file, Core Data, backend, attachment, viewer, or unrelated behaviour changes.
// SEARCH-TOKEN: 20260714_SCORES_LOCAL_LIBRARY_IDENTITY_MIGRATION

import Foundation
import Combine

@MainActor
final class ScoreLibraryStore: ObservableObject {
    static let shared = ScoreLibraryStore()

    @Published private(set) var items: [ScoreLibraryItem] = []
    @Published private(set) var activeScoreID: UUID?

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        displayName: String? = nil
    ) throws -> ScoreLibraryItem {
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
            lastViewedPage: nil
        )

        items.append(item)
        persist()
        return item
    }

    @discardableResult
    func addScannedPDF(data: Data, title: String) throws -> ScoreLibraryItem {
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
        persist()
        return item
    }

    func markOpened(_ item: ScoreLibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].lastOpenedAt = Date()
        activeScoreID = item.id
        persist()
    }

    func clearActiveScore() {
        activeScoreID = nil
        persist()
    }


    func updateLastViewedPage(for itemID: UUID, page: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let boundedPage = min(max(page, 1), max(items[index].pageCount, 1))
        guard items[index].lastViewedPage != boundedPage else { return }
        items[index].lastViewedPage = boundedPage
        persist()
    }

    func rename(_ item: ScoreLibraryItem, to newTitle: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let cleaned = cleanedTitle(newTitle, fallback: items[index].title)
        guard !cleaned.isEmpty else { return }
        items[index].title = cleaned
        persist()
    }

    func toggleFavourite(_ item: ScoreLibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavourite.toggle()
        persist()
    }

    func delete(_ item: ScoreLibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let url = self.url(for: items[index])
        try? fileManager.removeItem(at: url)
        items.remove(at: index)
        if activeScoreID == item.id {
            activeScoreID = nil
        }
        persist()
    }

    private func load() {
        let defaults = UserDefaults.standard
        migrateLegacyIdentityScopedLibraryIfNeeded(in: defaults)

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode([ScoreLibraryItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }

        if let rawActive = defaults.string(forKey: activeScoreKey),
           let id = UUID(uuidString: rawActive),
           items.contains(where: { $0.id == id }) {
            activeScoreID = id
        } else {
            activeScoreID = nil
        }
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

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: storageKey)
        }

        if let activeScoreID {
            defaults.set(activeScoreID.uuidString, forKey: activeScoreKey)
        } else {
            defaults.removeObject(forKey: activeScoreKey)
        }
    }

    private var storageKey: String {
        "scoreLibrary_v2"
    }

    private var activeScoreKey: String {
        "scoreLibrary_activeScore_v2"
    }

    private func scoresDirectory() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = documents.appendingPathComponent("Scores", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? excludeFromBackup(directory)
        }
        return directory
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

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}
