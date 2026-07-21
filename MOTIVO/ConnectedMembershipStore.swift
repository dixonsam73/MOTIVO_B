//
//  ConnectedMembershipStore.swift
//  MOTIVO
//
//  M9A.4: StoreKit membership foundation with purchase and restore APIs.
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

    enum PurchaseOutcome {
        case verified
        case unverified
        case pending
        case userCancelled
        case failed(Error)
    }

    private enum MembershipStoreError: LocalizedError {
        case unsupportedProduct(String)
        case purchaseAlreadyInProgress
        case unknownPurchaseResult

        var errorDescription: String? {
            switch self {
            case .unsupportedProduct(let productID):
                return "Unsupported StoreKit product: \(productID)"
            case .purchaseAlreadyInProgress:
                return "A StoreKit purchase is already in progress."
            case .unknownPurchaseResult:
                return "StoreKit returned an unknown purchase result."
            }
        }
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

    @Published private(set) var isPurchasing = false
    @Published private(set) var purchaseOutcome: PurchaseOutcome?

    @Published private(set) var isRestoringPurchases = false
    @Published private(set) var restoreError: Error?

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

    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard ProductID.all.contains(product.id) else {
            let error = MembershipStoreError.unsupportedProduct(product.id)
            let outcome = PurchaseOutcome.failed(error)
            purchaseOutcome = outcome
            return outcome
        }

        guard !isPurchasing else {
            let error = MembershipStoreError.purchaseAlreadyInProgress
            let outcome = PurchaseOutcome.failed(error)
            purchaseOutcome = outcome
            return outcome
        }

        isPurchasing = true
        purchaseOutcome = nil

        defer {
            isPurchasing = false
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()

                    let outcome = PurchaseOutcome.verified
                    purchaseOutcome = outcome

#if DEBUG
                    print("[Membership] Purchase verified (\(transaction.productID))")
#endif

                    return outcome

                case .unverified:
                    let outcome = PurchaseOutcome.unverified
                    purchaseOutcome = outcome

#if DEBUG
                    print("[Membership] Purchase succeeded but transaction was unverified")
#endif

                    return outcome
                }

            case .pending:
                let outcome = PurchaseOutcome.pending
                purchaseOutcome = outcome

#if DEBUG
                print("[Membership] Purchase pending")
#endif

                return outcome

            case .userCancelled:
                let outcome = PurchaseOutcome.userCancelled
                purchaseOutcome = outcome

#if DEBUG
                print("[Membership] Purchase cancelled by user")
#endif

                return outcome

            @unknown default:
                let error = MembershipStoreError.unknownPurchaseResult
                let outcome = PurchaseOutcome.failed(error)
                purchaseOutcome = outcome

#if DEBUG
                print("[Membership] Purchase failed: \(error.localizedDescription)")
#endif

                return outcome
            }
        } catch {
            let outcome = PurchaseOutcome.failed(error)
            purchaseOutcome = outcome

#if DEBUG
            print("[Membership] Purchase failed: \(error)")
#endif

            return outcome
        }
    }

    func restorePurchases() async {
        guard !isRestoringPurchases else { return }

        isRestoringPurchases = true
        restoreError = nil

        defer {
            isRestoringPurchases = false
        }

        do {
            try await AppStore.sync()
            await refreshEntitlement()

#if DEBUG
            print("[Membership] Restore purchases completed")
#endif
        } catch {
            restoreError = error

#if DEBUG
            print("[Membership] Restore purchases failed: \(error)")
#endif
        }
    }

    private func startTransactionObservation() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { @MainActor in
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
