// CHANGE-ID: 20260518_223800_RelationalUnseenCountStore
// SCOPE: Centralize canonical relational unseen count derivation and shared unread-share ownership. No UI, routing, lifecycle, or semantics changes.

import Foundation
import Combine

@MainActor
final class RelationalUnseenCountStore: ObservableObject {

    static let shared = RelationalUnseenCountStore()

    @Published private(set) var refreshTick: Int = 0

    let sharedWithYouStore: SharedWithYouStore

    private let followStore = FollowStore.shared
    private let unreadCommentsStore = UnreadCommentsStore.shared

    private var cancellables: Set<AnyCancellable> = []

    var incomingFollowRequestCount: Int {
        followStore.requests.subtracting(followStore.outgoingRequests).count
    }

    var relationalUnseenCount: Int {
        incomingFollowRequestCount
        + sharedWithYouStore.unreadShares.count
        + unreadCommentsStore.unreadGroups.count
    }

    private init(sharedWithYouStore: SharedWithYouStore = .shared) {
        self.sharedWithYouStore = sharedWithYouStore

        followStore.objectWillChange
            .sink { [weak self] _ in
                self?.refreshTick += 1
            }
            .store(in: &cancellables)

        unreadCommentsStore.objectWillChange
            .sink { [weak self] _ in
                self?.refreshTick += 1
            }
            .store(in: &cancellables)

        sharedWithYouStore.objectWillChange
            .sink { [weak self] _ in
                self?.refreshTick += 1
            }
            .store(in: &cancellables)
    }
}
