//
//  ConnectedMembershipStore.swift
//  MOTIVO
//
//  M9A.1: StoreKit product loading foundation.
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
  

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            await loadProducts()
        }
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
