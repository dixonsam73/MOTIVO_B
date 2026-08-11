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
        case entitlementMissingAfterVerifiedPurchase
        case unknownPurchaseResult

        var errorDescription: String? {
            switch self {
            case .unsupportedProduct(let productID):
                return "Unsupported StoreKit product: \(productID)"
            case .purchaseAlreadyInProgress:
                return "A StoreKit purchase is already in progress."
            case .entitlementMissingAfterVerifiedPurchase:
                return "The purchase was verified, but no active Études Connected entitlement was found."
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

    // TEMPORARY — C-38 diagnosis. Remove the didSet with ActivationTrace.swift.
    // Logs every write including same-value ones: `changed=false` marks exactly
    // the publications that $membershipState.removeDuplicates() swallows.
    @Published private(set) var membershipState: MembershipState = .unknown {
        didSet {
            ActivationTrace.membershipState(
                from: String(describing: oldValue),
                to: String(describing: membershipState),
                changed: oldValue != membershipState
            )
        }
    }
    @Published private(set) var isRefreshingEntitlement = false

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
    private var entitlementRefreshTask: Task<MembershipState, Never>?

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
                    await refreshEntitlement(forceAfterCurrent: true)

                    // TEMPORARY — C-38 diagnosis. Remove with ActivationTrace.swift.
                    ActivationTrace.purchaseGuard(isEntitled: isEntitled)

                    guard isEntitled else {
                        let error = MembershipStoreError.entitlementMissingAfterVerifiedPurchase
                        let outcome = PurchaseOutcome.failed(error)
                        purchaseOutcome = outcome
                        return outcome
                    }

                    let outcome = PurchaseOutcome.verified
                    purchaseOutcome = outcome

                    return outcome

                case .unverified:
                    let outcome = PurchaseOutcome.unverified
                    purchaseOutcome = outcome

                    return outcome
                }

            case .pending:
                let outcome = PurchaseOutcome.pending
                purchaseOutcome = outcome

                return outcome

            case .userCancelled:
                let outcome = PurchaseOutcome.userCancelled
                purchaseOutcome = outcome

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
            await refreshEntitlement(forceAfterCurrent: true)

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
            for await verificationResult in Transaction.updates {
                guard !Task.isCancelled else { return }

                guard case .verified(let transaction) = verificationResult else {
#if DEBUG
                    print("[Membership] Ignored unverified transaction update")
#endif
                    continue
                }

                await transaction.finish()
                await refreshEntitlement(forceAfterCurrent: true)
            }
        }
    }

    func refreshEntitlement(forceAfterCurrent: Bool = false) async {
        // TEMPORARY — C-38 diagnosis. Remove with ActivationTrace.swift.
        let traceWasInFlight = entitlementRefreshTask != nil

        if let inFlightTask = entitlementRefreshTask {
            let resolvedState = await inFlightTask.value
            membershipState = resolvedState

            guard forceAfterCurrent else { return }

            entitlementRefreshTask = nil
            await refreshEntitlement()
            return
        }

        isRefreshingEntitlement = true
        if membershipState == .unknown {
            membershipState = .loading
        }

        let refreshTask = Task { @MainActor in
            var resolvedState: MembershipState = .notEntitled

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

                resolvedState = .entitled
                break
            }

            return resolvedState
        }

        entitlementRefreshTask = refreshTask
        let resolvedState = await refreshTask.value

        // TEMPORARY — C-38 diagnosis. Remove with ActivationTrace.swift.
        ActivationTrace.entitlementRead(
            resolved: String(describing: resolvedState),
            forced: forceAfterCurrent,
            wasInFlight: traceWasInFlight
        )

        // A forced refresh may have taken ownership of the slot while this one
        // was finishing. It will publish its own, newer result.
        guard entitlementRefreshTask == refreshTask else { return }

        entitlementRefreshTask = nil
        isRefreshingEntitlement = false
        membershipState = resolvedState
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

        } catch {
            productLoadError = error

#if DEBUG
            print("[Membership] Failed to load StoreKit products: \(error)")
#endif
        }
    }
}
