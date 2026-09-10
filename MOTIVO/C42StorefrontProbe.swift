//
//  C42StorefrontProbe.swift
//  MOTIVO
//
//  TEMPORARY INSTRUMENTATION — C-42. DELETE THE MOMENT C-42 IS SCORED.
//
//  C-42: the membership screen once showed USD while Apple's sheet showed GBP
//  (TestFlight 131, Device B). The screen renders StoreKit's own
//  `displayPrice`, and the storefront-mismatch explanation is RULED OUT — the
//  device's App Store country and the Sandbox tester's are both United Kingdom.
//  This records what StoreKit actually returns, rather than guessing again.
//
//  It changes no behaviour and touches no purchase call. It logs through
//  `os.Logger` with `privacy: .public` so it is readable in Release (the
//  MembershipTrace lesson). Standing removal condition, as for ActivationTrace
//  and JWSFreshnessProbe: removed as a PURE DELETION once C-42 is scored.
//

import Foundation
import StoreKit
import os

enum C42StorefrontProbe {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MOTIVO", category: "C42Probe")

    static func record(products: [Product], context: String) async {
        let storefront = await Storefront.current
        log.notice("[C-42] \(context, privacy: .public) storefront country=\(storefront?.countryCode ?? "nil", privacy: .public) id=\(storefront?.id ?? "nil", privacy: .public) currency=\(storefront?.currency?.identifier ?? "nil", privacy: .public) products=\(products.count, privacy: .public)")
        for product in products {
            log.notice("[C-42] \(context, privacy: .public) product=\(product.id, privacy: .public) displayPrice=\(product.displayPrice, privacy: .public) price=\("\(product.price)", privacy: .public) formatCurrency=\(product.priceFormatStyle.currencyCode, privacy: .public) formatLocale=\(product.priceFormatStyle.locale.identifier, privacy: .public)")
        }
    }
}
