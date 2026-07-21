//
//  ConnectedMembershipStore.swift
//  MOTIVO
//
//  M9A.0: Application-scoped StoreKit membership service skeleton.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class ConnectedMembershipStore: ObservableObject {
    enum MembershipState: Equatable {
        case unknown
        case loading
        case notEntitled
        case entitled
    }

    @Published private(set) var membershipState: MembershipState = .unknown

    var isEntitled: Bool {
        membershipState == .entitled
    }

    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
    }
}
