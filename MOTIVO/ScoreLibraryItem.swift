// CHANGE-ID: 20260614_145200_ScoresPhase1_Item
// SCOPE: Scores V1 Phase 1 — local-only score library item model. No Core Data, backend, session attachment, or PDF viewer changes.
// SEARCH-TOKEN: 20260614_145200_SCORES_PHASE1_ITEM

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

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        pageCount: Int,
        thumbnailPage: Int = 1,
        isFavourite: Bool = false,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.thumbnailPage = max(thumbnailPage, 1)
        self.isFavourite = isFavourite
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
    }
}
