// CHANGE-ID: 20260212_090900_SharedWithYouStore_ResultAPI_GREEN
// SCOPE: Owner-Only Share — Shared-with-you pointers store (Result-based BackendPostShareService)

import Foundation
import Combine

/// Lightweight store for unread "shared with you" pointers.
/// This store is intentionally minimal and UI-agnostic:
/// - It does not fetch post payloads, only share pointers.
/// - It uses the existing Result-based BackendPostShareService contract.
@MainActor
final class SharedWithYouStore: ObservableObject {

    @Published private(set) var unreadShares: [BackendPostSharePointer] = []
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isLoading: Bool = false

    var hasUnreadShares: Bool { !unreadShares.isEmpty }

    private let backend: BackendPostShareService

    init(backend: BackendPostShareService = BackendEnvironment.shared.shares) {
        self.backend = backend
    }

    func refreshUnreadShares() async {
        isLoading = true
        lastError = nil

        let result = await backend.fetchUnreadShares()
        switch result {
        case .success(let shares):
            unreadShares = shares
        case .failure(let error):
            lastError = String(describing: error)
        }

        isLoading = false
    }

    /// Mark a share as viewed and locally remove it from `unreadShares` if successful.
    func markViewed(shareID: UUID) async {
        lastError = nil

        let result = await backend.markShareViewed(shareID: shareID)
        switch result {
        case .success:
            unreadShares.removeAll { $0.id == shareID }
        case .failure(let error):
            lastError = String(describing: error)
        }
    }

    /// Owner-only retraction. This does not affect posts visibility; it only removes the pointer row.
    func retractShare(shareID: UUID) async {
        lastError = nil

        let result = await backend.deleteShare(shareID: shareID)
        switch result {
        case .success:
            // If the local viewer is also the recipient, keep local state consistent.
            unreadShares.removeAll { $0.id == shareID }
        case .failure(let error):
            lastError = String(describing: error)
        }
    }
}
