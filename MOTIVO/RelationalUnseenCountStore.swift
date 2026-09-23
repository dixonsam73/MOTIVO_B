// CHANGE-ID: 20260715_ConnectedAttachmentNotifications_Aggregation
// SCOPE: Include unread received Connected attachments in the existing canonical relational
// unseen count. No badge UI, routing, follow, share, comment, or attachment lifecycle changes.
//
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
    private let receivedAttachmentStore = ReceivedConnectedAttachmentStore.shared
    private let blockList = BlockList.shared

    private var cancellables: Set<AnyCancellable> = []

    // Blocked accounts are excluded, matching what People shows: a hidden
    // request or send must not light the badge.
    var incomingFollowRequestCount: Int {
        followStore.requests.subtracting(followStore.outgoingRequests)
            .filter { !blockList.isBlocked($0) }
            .count
    }

    var relationalUnseenCount: Int {
        incomingFollowRequestCount
        + sharedWithYouStore.unreadShares.filter { !blockList.isBlocked($0.ownerUserID) }.count
        + unreadCommentsStore.unreadGroups.count
        + receivedAttachmentStore.unreadItems.filter { !blockList.isBlocked($0.senderUserID) }.count
    }

    private init() {
        self.sharedWithYouStore = SharedWithYouStore.shared

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

        receivedAttachmentStore.objectWillChange
            .sink { [weak self] _ in
                self?.refreshTick += 1
            }
            .store(in: &cancellables)

        blockList.objectWillChange
            .sink { [weak self] _ in
                self?.refreshTick += 1
            }
            .store(in: &cancellables)
    }
}
