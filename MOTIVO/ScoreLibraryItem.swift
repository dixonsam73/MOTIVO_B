// CHANGE-ID: 20260614_171200_ScoresPhase3A_PageMemory_Item
// SCOPE: Scores V1 Phase 3A — add per-score last viewed page storage for active score page restoration. No Core Data, backend, session attachment, zoom, or viewport changes.
// SEARCH-TOKEN: 20260614_171200_SCORES_PHASE3A_PAGE_MEMORY

import Foundation

struct ScoreLibraryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var fileName: String
    var pageCount: Int
    var thumbnailPage: Int
    var isFavourite: Bool
    var createdAt: Date
    var lastOpenedAt: Date?
    var lastViewedPage: Int?

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        pageCount: Int,
        thumbnailPage: Int = 1,
        isFavourite: Bool = false,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        lastViewedPage: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.thumbnailPage = max(thumbnailPage, 1)
        self.isFavourite = isFavourite
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        if let lastViewedPage {
            self.lastViewedPage = max(lastViewedPage, 1)
        } else {
            self.lastViewedPage = nil
        }
    }
}
