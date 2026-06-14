// CHANGE-ID: 20260614_171200_ScoresPhase3A_PageMemory_Store
// SCOPE: Scores V1 Phase 3A — persist last viewed page per library score for active score page restoration. No Core Data, backend, session attachment, zoom, or viewport changes.
// SEARCH-TOKEN: 20260614_171200_SCORES_PHASE3A_PAGE_MEMORY

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
    func importPDF(from sourceURL: URL) throws -> ScoreLibraryItem {
        let didStartSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let title = cleanedTitle(sourceURL.deletingPathExtension().lastPathComponent, fallback: "Untitled Score")
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

    private var ownerScope: String {
        if let id = PersistenceController.shared.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        return "local"
    }

    private var storageKey: String {
        "scoreLibrary_v1::\(ownerScope)"
    }

    private var activeScoreKey: String {
        "scoreLibrary_activeScore_v1::\(ownerScope)"
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
