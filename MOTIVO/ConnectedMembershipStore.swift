//
//  ConnectedMembershipStore.swift
//  MOTIVO
//
//  M9A.3: StoreKit product loading, entitlement derivation and transaction observation.
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

    private enum ProductID {
        static let monthly = "com.sdsongs.etudes.connected.monthly"
        static let annual = "com.sdsongs.etudes.connected.annual"

        static let all = [
            monthly,
            annual
        ]
    }

    @Published private(set) var membershipState: MembershipState = .unknown

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productLoadError: Error?

    var isEntitled: Bool {
        membershipState == .entitled
    }

    var monthlyProduct: Product? {
        products.first { $0.id == ProductID.monthly }
    }

    var annualProduct: Product? {
        products.first { $0.id == ProductID.annual }
    }

    private var hasStarted = false
    private var transactionUpdatesTask: Task<Void, Never>?

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        startTransactionObservation()

        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    private func startTransactionObservation() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task {
#if DEBUG
            print("[Membership] Transaction listener started")
#endif

            for await verificationResult in Transaction.updates {
                guard !Task.isCancelled else { return }

                guard case .verified(let transaction) = verificationResult else {
#if DEBUG
                    print("[Membership] Ignored unverified transaction update")
#endif
                    continue
                }

#if DEBUG
                print("[Membership] Verified transaction update received (\(transaction.productID))")
#endif

                await transaction.finish()
                await refreshEntitlement()
            }
        }
    }

    func refreshEntitlement() async {
        membershipState = .loading

        for await verificationResult in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult else {
#if DEBUG
                print("[Membership] Ignored unverified current entitlement")
#endif
                continue
            }

            guard ProductID.all.contains(transaction.productID) else {
                continue
            }

            membershipState = .entitled

#if DEBUG
            print("[Membership] Entitlement: entitled (\(transaction.productID))")
#endif
            return
        }

        membershipState = .notEntitled

#if DEBUG
        print("[Membership] Entitlement: not entitled")
#endif
    }

    private func loadProducts() async {
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        productLoadError = nil

        defer {
            isLoadingProducts = false
        }

        do {
            let loadedProducts = try await Product.products(for: ProductID.all)

            products = loadedProducts.sorted { lhs, rhs in
                switch (lhs.id, rhs.id) {
                case (ProductID.monthly, ProductID.annual):
                    return true
                case (ProductID.annual, ProductID.monthly):
                    return false
                default:
                    return lhs.id < rhs.id
                }
            }

#if DEBUG
            print("[Membership] Loaded \(products.count) StoreKit products")

            for product in products {
                print("[Membership] \(product.id) • \(product.displayPrice)")
            }

            let missing = Set(ProductID.all).subtracting(products.map(\.id))
            if !missing.isEmpty {
                print("[Membership] Missing StoreKit products: \(missing)")
            }
#endif

        } catch {
            productLoadError = error

#if DEBUG
            print("[Membership] Failed to load StoreKit products: \(error)")
#endif
        }
    }
}
