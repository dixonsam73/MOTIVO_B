//
//  MembershipTrace.swift
//  MOTIVO
//
//  TEMPORARY diagnostic instrumentation for the reinstall / reconnect
//  investigation. Remove before the RC — this file and its call sites are not
//  release code.
//
//  Release-capable by design. The open questions are about StoreKit entitlement
//  timing on a fresh install of an existing member, and Debug runs against the
//  local `Etudes.storekit` configuration, which resolves entitlements
//  synthetically and instantly (C-9). Only a Release/TestFlight build can
//  answer them, so this logging is deliberately not wrapped in `#if DEBUG`.
//
//  Privacy: booleans, enum names and counts only. Never identifiers, handles,
//  tokens, product IDs or transaction IDs — C-14 exists because release logging
//  leaked backend user IDs, and this must not repeat that.
//
//  Reading the trace: connect the device, open Console.app, filter on MTRACE.
//

import Foundation

enum MembershipTrace {

    /// Single switch for every call site. Set to `false` to silence the trace
    /// without unpicking the instrumentation.
    static let isEnabled = true

    static func log(_ event: String, _ fields: [String: String] = [:]) {
        guard isEnabled else { return }

        let rendered = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        if rendered.isEmpty {
            NSLog("[MTRACE] %@", event)
        } else {
            NSLog("[MTRACE] %@ %@", event, rendered)
        }
    }
}

extension ConnectedMembershipStore.MembershipState {

    /// Stable short name for the trace. Deliberately not `description` — this
    /// is diagnostic output, not a user-facing or persisted representation.
    var traceName: String {
        switch self {
        case .unknown: return "unknown"
        case .loading: return "loading"
        case .notEntitled: return "notEntitled"
        case .entitled: return "entitled"
        }
    }
}
