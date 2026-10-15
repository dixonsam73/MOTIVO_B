//
//  ConnectedAgeRefusalReport.swift
//  MOTIVO
//
//  The anonymous count of Connected joins the adult-only gate refused
//  (RELEASE.md section B; server: `record_connected_age_refusal_v1`, applied
//  2026-10-15). It sends the reason and nothing else.
//
//  - Always the PUBLIC anon key, never the member's session token, even when
//    signed in, so a count can't be tied to an account.
//  - Only refusals the person caused by trying to join or sign in (Continue,
//    Try Again, the sign-in check). Never the launch or foreground re-checks.
//  - Fire and forget. A failure (offline, server down) is logged and dropped:
//    the count is an indicator, not an audited figure, and nothing about the
//    person's experience depends on it.
//

import Foundation
import os

enum ConnectedAgeRefusalReport {

    private static let log = Logger(subsystem: "com.sdsongs.etudes", category: "ageGate")

    /// PURE. The request, so what leaves the device is testable.
    static func request(reason: ConnectedAgeGate.RefusalReason, baseURL: URL, anonKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL
            .appendingPathComponent("rest/v1/rpc/record_connected_age_refusal_v1"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_reason": reason.rawValue])
        return request
    }

    static func send(_ reason: ConnectedAgeGate.RefusalReason) {
        guard !UnitTestHost.isActive else { return }
        guard let baseURL = BackendConfig.apiBaseURL, let anonKey = BackendConfig.apiToken else {
            log.notice("refusal not counted reason=\(reason.rawValue, privacy: .public) backendNotConfigured")
            return
        }
        let request = request(reason: reason, baseURL: baseURL, anonKey: anonKey)
        Task.detached(priority: .utility) {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                log.notice("refusal counted reason=\(reason.rawValue, privacy: .public) status=\(status, privacy: .public)")
            } catch {
                log.notice("refusal not counted reason=\(reason.rawValue, privacy: .public) transport")
            }
        }
    }
}
