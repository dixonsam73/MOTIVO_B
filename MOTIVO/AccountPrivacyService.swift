//
//  AccountPrivacyService.swift
//  MOTIVO
//
//  PHASE 5 · CP-3 — the client half of `account_privacy` (CP-1 / CP-2).
//
//  ONE JOB: carry the derived band and the two privacy preferences to and from
//  the server-authoritative table. It decides nothing itself.
//
//  ── THE EFFECTIVE VALUES ARE READ, NEVER RECOMPUTED ────────────────────────
//
//  `account_privacy_self_v1` returns both the STORED preference and the
//  EFFECTIVE one. The override — a permissive choice made while classified as an
//  adult does not carry into a child classification — lives in exactly one place,
//  on the server, and is consulted by `search_account_directory` and
//  `follow_requests_open` through the same helpers. A client that recomputed it
//  could drift, and drift here fails PERMISSIVE.
//
//  ── NO ROW IS EVER CREATED BEFORE ELIGIBILITY IS ESTABLISHED ───────────────
//
//  `upsertBand` is the only writer of `age_band` and is called only after Apple
//  has returned a band. An under-13, a decline and an error all write nothing at
//  all, so the table can never become a register of children who tried to join.
//
//  ── AND IT NEVER WRITES A PREFERENCE AS A SIDE EFFECT ──────────────────────
//
//  The deployed writer touches `age_band` alone. Initial defaults are derived
//  server-side once, at row creation; after that only an explicit user action
//  reaches `setLookupEnabled` / `setFollowRequestsEnabled`. That separation is
//  what keeps "the default was applied" distinguishable from "the member chose".
//

import Foundation

@MainActor
enum AccountPrivacyService {

    nonisolated struct SelfState: Equatable {
        let ageBand: AgeBand
        /// What the member chose (or the initial default derived from the band).
        let lookupEnabled: Bool
        let followRequestsEnabled: Bool
        /// What the server will actually act on, after the child-safety override.
        let lookupEffective: Bool
        let followRequestsEffective: Bool
    }

    enum Failure: Error, Equatable {
        case notAuthenticated
        case notConfigured
        case sessionUnavailable
        case malformedResponse
        /// No `account_privacy` row — the fail-protective unknown state.
        case noBandEstablished
        case transport(String)
    }

    // MARK: - Writes

    /// Establishes or reconciles the band.
    ///
    /// **NOT insert-if-absent** — corrected P5-G, 2026-09-08. This was a THIRD
    /// instance of the same wrong description, missed when the other two were
    /// fixed. `account_privacy_upsert_v1` updates `age_band` on conflict and
    /// stamps `band_updated_at` only on a real change. So a retry after an
    /// ambiguous failure returns the existing row rather than writing a second
    /// one, and an unchanged band leaves `band_updated_at` exactly where it was —
    /// both true, but they follow from the `on conflict` clause, not from the
    /// writer declining to update.
    static func upsertBand(_ band: AgeBand, auth: AuthManager, reason: String) async -> Result<SelfState, Failure> {
        await call(rpc: "account_privacy_upsert_v1",
                   body: ["p_age_band": band.rawValue],
                   auth: auth, reason: reason)
    }

    /// The ONLY client writer of the discovery preference.
    static func setLookupEnabled(_ enabled: Bool, auth: AuthManager, reason: String) async -> Result<Void, Failure> {
        await callVoid(rpc: "account_privacy_set_lookup_v1",
                       body: ["p_enabled": enabled], auth: auth, reason: reason)
    }

    /// The ONLY client writer of the follow-request preference.
    ///
    /// ── IT HAS NO CALLER, AND THAT IS A DECISION — P5-G / Q2, 2026-09-08 ────
    ///
    /// **DO NOT "FINISH" THIS WIRING.** The account holder decided that a 13-17
    /// member **cannot enable inbound follow requests**, and that **no
    /// follow-request control is to be added**. Relationship initiation *by
    /// another member* stays closed; the young member may still initiate
    /// relationships themselves.
    ///
    /// The reason of record: Études has no moderation, no reporting surface and
    /// no guardian channel, so inbound contact from a stranger to a minor would
    /// have no mitigating control behind it.
    ///
    /// So this function and its deployed RPC are **dead by decision, not by
    /// omission**. An absent caller is exactly the shape that gets "helpfully"
    /// completed by a later reader, which is why the reason is recorded here
    /// rather than only in the register. See `docs/phase-5-g-decision-register.md`
    /// §A2. The function is retained rather than deleted so the decision stays
    /// visible at the place someone would otherwise re-add it.
    static func setFollowRequestsEnabled(_ enabled: Bool, auth: AuthManager, reason: String) async -> Result<Void, Failure> {
        await callVoid(rpc: "account_privacy_set_follow_requests_v1",
                       body: ["p_enabled": enabled], auth: auth, reason: reason)
    }

    // MARK: - Read

    /// Current state, or `.noBandEstablished` when the identity has no row.
    static func fetchSelf(auth: AuthManager, reason: String) async -> Result<SelfState, Failure> {
        await call(rpc: "account_privacy_self_v1", body: [:], auth: auth, reason: reason)
    }

    // MARK: - Transport

    private static func preflight(auth: AuthManager, reason: String) async -> Failure? {
        guard auth.hasConnectedIdentity else { return .notAuthenticated }
        guard BackendConfig.isConfigured else { return .notConfigured }
        guard await auth.ensureValidBackendSession(reason: "privacy:\(reason)") else {
            return .sessionUnavailable
        }
        return nil
    }

    private static func call(rpc: String, body: [String: Any], auth: AuthManager, reason: String) async -> Result<SelfState, Failure> {
        if let failure = await preflight(auth: auth, reason: reason) { return .failure(failure) }
        guard let payload = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return .failure(.malformedResponse)
        }
        let result = await NetworkManager.shared.request(
            path: "rest/v1/rpc/\(rpc)", method: "POST", query: nil, jsonBody: payload
        )
        switch result {
        case .failure(let error):
            return .failure(.transport(String(describing: error)))
        case .success(let data):
            guard let state = decodeSelfState(data) else {
                // An empty set-returning result means "no row", which is the
                // unknown state and must not be coerced into a band.
                return .failure(isEmptyRowSet(data) ? .noBandEstablished : .malformedResponse)
            }
            return .success(state)
        }
    }

    private static func callVoid(rpc: String, body: [String: Any], auth: AuthManager, reason: String) async -> Result<Void, Failure> {
        if let failure = await preflight(auth: auth, reason: reason) { return .failure(failure) }
        guard let payload = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return .failure(.malformedResponse)
        }
        let result = await NetworkManager.shared.request(
            path: "rest/v1/rpc/\(rpc)", method: "POST", query: nil, jsonBody: payload
        )
        switch result {
        case .failure(let error): return .failure(.transport(String(describing: error)))
        case .success: return .success(())
        }
    }

    // MARK: - Decoding (pure, so it is testable without a network)

    nonisolated static func isEmptyRowSet(_ data: Data) -> Bool {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return false }
        if let array = any as? [Any] { return array.isEmpty }
        return false
    }

    /// PostgREST returns a set-returning function as an array of objects. Strict
    /// on purpose: an unrecognised shape is refused rather than defaulted, since
    /// every default here would be a guess about a child's privacy.
    nonisolated static func decodeSelfState(_ data: Data) -> SelfState? {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let object: [String: Any]?
        if let array = any as? [[String: Any]] { object = array.first }
        else { object = any as? [String: Any] }
        guard let row = object,
              let bandRaw = row["o_age_band"] as? String,
              let band = AgeBand(rawValue: bandRaw),
              let lookup = row["o_lookup_enabled"] as? Bool,
              let lookupEffective = row["o_lookup_effective"] as? Bool,
              let requests = row["o_follow_requests_enabled"] as? Bool,
              let requestsEffective = row["o_follow_requests_effective"] as? Bool
        else { return nil }
        return SelfState(ageBand: band,
                         lookupEnabled: lookup,
                         followRequestsEnabled: requests,
                         lookupEffective: lookupEffective,
                         followRequestsEffective: requestsEffective)
    }
}
