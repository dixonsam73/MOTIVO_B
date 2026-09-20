// CHANGE-ID: 20260428_153100_AccountIDRequireBackendRowForGeneration
// SCOPE: Account ID auto-generation requires an existing backend directory row before deriving a handle.
// SEARCH-TOKEN: 20260428_153100_AccountIDRequireBackendRowForGeneration


// CHANGE-ID: 20260309_205500_AvatarBootstrapSelfRow_6c1a
// SCOPE: Multi-device account bootstrap hardening — include account_directory.avatar_key in self-row fetch for owner avatar fallback.
// SEARCH-TOKEN: 20260309_205500_AvatarBootstrapSelfRow_6c1a

// CHANGE-ID: 20260221_142658_FollowInfraFix_9f2c
// SCOPE: Follow infra hardening — enforce requests-off (account_directory), fix decline/remove follower delete semantics, add follower revoke swipe.
// SEARCH-TOKEN: 20260221_142658_FollowInfraFix_9f2c

// CHANGE-ID: 20260211_141746_PPV_Instruments_Writeback_ADS_a3d9c1
// SCOPE: Owner instruments write-back to account_directory.instruments via upsertSelfRow payload + cache merge
// SEARCH-TOKEN: 20260211_141746_PPV_Instruments_Writeback_ADS_a3d9c1

// CHANGE-ID: 20260209_213700_Phase15_Step1_AvatarKeyPlumb_25a97d6f
// SCOPE: Phase 15 Step 1 — plumb account_directory.avatar_key through DirectoryAccount decode + caches (no UI)
// SEARCH-TOKEN: 20260209_213700_Phase15_Step1_AvatarKeyPlumb_25a97d6f

// CHANGE-ID: 20260205_072955_LiveIdentityCache_f1a8c7
// SCOPE: Live directory identity cache updates (merge on upsert + force-refresh on directory fetch)
// SEARCH-TOKEN: 20260205_072955_LiveIdentityCache_f1a8c7

// CHANGE-ID: 20260121_172500_Phase14_Step2_DirectoryBatchCache
// SCOPE: Phase 14 Step 2 — add batch account_directory RPC lookup + in-memory cache for DirectoryAccount (user_id, display_name, account_id)
// SEARCH-TOKEN: 20260121_172500_Phase14_Step2_DirectoryBatchCache

// CHANGE-ID: 20260120_133525_Phase12C_Hygiene
// SCOPE: Phase 12C hygiene — sanitize account_id; fix upsert request call
// CHANGE-ID: 20260120_124800_Phase12C_AccountDirectoryService_ReadWrite
// SCOPE: Phase 12C — RPC-backed People search + owner-only upsert of account_directory row (lookup opt-in + account_id + display_name). No profile sync.
// SEARCH-TOKEN: 20260120_124800_Phase12C_AccountDirectoryService_ReadWrite

//
//  AccountDirectoryService.swift
//  MOTIVO
//
//  CHANGE-ID: 20260120_113000_Phase12C_AccountDirectorySearch
//  SCOPE: Phase 12C (read path) — RPC-backed People search against account_directory via search_account_directory(); no profile sync; no discovery.
//  SEARCH-TOKEN: 20260120_113000_Phase12C_AccountDirectorySearch
//

// CHANGE-ID: 20260210_182200_Phase15_Step3A_AvatarKeyWrite
// SCOPE: Phase 15 Step 3A — add owner-only PATCH helper to update/clear account_directory.avatar_key and merge into live identity caches.
// SEARCH-TOKEN: 20260210_182200_Phase15_Step3A_AvatarKeyWrite

// CHANGE-ID: 20260302_093339_ProfileHydrateDirectory_3b1f
// SCOPE: Profile privacy hydration — fetch account_directory self row on sign-in to hydrate local ProfileStore discoveryMode/account_id (fresh install consistency). No UI changes.
// SEARCH-TOKEN: 20260302_093339_ProfileHydrateDirectory_3b1f

// CHANGE-ID: 20260308_194900_MultiDeviceBootstrap_ADS
// SCOPE: Multi-device bootstrap hardening foundation — extend owner self-row fetch to include canonical display_name/location/instruments for second-device hydration. No UI changes.
// SEARCH-TOKEN: 20260308_194900_MultiDeviceBootstrap_ADS

// CHANGE-ID: 20260920_130000_B37_SearchBudgetRefusal
// SCOPE: B-37 — surface the server's search-budget refusal as a typed error carrying
// the server-derived retry duration, so a throttle reads as a throttle and never as
// "No results." No change to what is searched or returned.
// SEARCH-TOKEN: 20260920_130000_B37_SearchBudgetRefusal

import Foundation

/// B-37. The directory search RPC refuses a caller who has exhausted their
/// per-account budget. The refusal arrives as **HTTP 429**, deliberately never
/// 401 — `NetworkManager` refreshes the session and retries on 401 only, and a
/// throttle must never be mistaken for an authentication challenge.
public enum DirectorySearchError: Error, Equatable {
    /// `retryAfterSeconds` is the server's own derivation from the end of the
    /// blocking window. It is optional because **the client must never invent
    /// one**: a missing or malformed value means the copy names no time at all.
    case rateLimited(retryAfterSeconds: Int?)
}

/// The refusal copy. A pure function so it can be tested without a view.
public enum DirectorySearchThrottleCopy {

    /// Deliberately NOT a countdown or a timer. The duration is server-derived,
    /// rounded once, and stated once.
    public static func message(retryAfterSeconds: Int?) -> String {
        let lead = "You've searched a lot just now."
        guard let s = retryAfterSeconds, s > 0, s <= 24 * 60 * 60 else {
            // No usable duration: say nothing about when, not even vaguely.
            // "shortly" would be the same invention in softer words.
            return "\(lead) Please try again later."
        }
        return "\(lead) Try again in \(roundedDuration(seconds: s))."
    }

    static func roundedDuration(seconds: Int) -> String {
        // Rounded UP throughout, so the member is never told to come back
        // before the window has actually ended: 61 seconds is "about 2
        // minutes", never "about a minute".
        let minutes = Int((Double(seconds) / 60.0).rounded(.up))
        if minutes <= 1 { return "about a minute" }
        if minutes < 55 { return "about \(minutes) minutes" }
        let hours = Int((Double(minutes) / 60.0).rounded(.up))
        if hours <= 1 { return "about an hour" }
        return "about \(hours) hours"
    }
}

public struct DirectoryAccount: Codable, Identifiable, Hashable {
    public var id: String { userID }

    public let userID: String
    public let accountID: String?
    public let displayName: String
    public let location: String?
    public let avatarKey: String?
    public let instruments: [String]?

    /// C-34 / P4-U5. Server-stamped whenever `avatar_key` is TARGETED by an
    /// update — including a replacement that writes the identical key, which is
    /// the case a value-change trigger would miss. It is a CACHE-IDENTITY hint
    /// and nothing else: it never reaches a storage request, and NULL is a valid
    /// value that every pre-U5 row still carries.
    public let avatarVersion: String?

    public enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accountID = "account_id"
        case displayName = "display_name"
        case location = "location"
        case avatarKey = "avatar_key"
        case avatarVersion = "avatar_version"
        case instruments = "instruments"
    }
}

public struct SelfDirectoryRow: Decodable, Hashable {
    public let accountID: String?
    public let displayName: String?
    public let location: String?
    public let avatarKey: String?
    public let instruments: [String]?
    public let lookupEnabled: Bool
    public let followRequestsEnabled: Bool
    /// P5-I / C-34 R2: the owner's own `avatar_version`, so a device can tell
    /// that the backend avatar was replaced from another device.
    public let avatarVersion: String?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case displayName = "display_name"
        case location = "location"
        case avatarKey = "avatar_key"
        case instruments = "instruments"
        case lookupEnabled = "lookup_enabled"
        case followRequestsEnabled = "follow_requests_enabled"
        case avatarVersion = "avatar_version"
    }
}

public final class AccountDirectoryService {
    // Phase 12C hygiene: never POST invalid account_id values.
    // Rule: accept only [a-z0-9_] and length 3–24. Blank/invalid account_id values are omitted from writes.
    private func sanitizedLocation(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private func sanitizedAccountID(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty else { return nil }
        if s.hasPrefix("@") { s = String(s.dropFirst()) }
        let filtered = s.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        guard filtered.count >= 3, filtered.count <= 24 else { return nil }
        return String(filtered)
    }

    private func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private func autoAccountIDBase(from displayName: String) -> String? {
        let folded = displayName
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let filtered = folded.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        let capped = String(filtered.prefix(24))
        guard capped.count >= 3 else { return nil }
        return capped
    }

    private func autoAccountIDCandidate(base: String, attempt: Int) -> String {
        guard attempt > 1 else { return String(base.prefix(24)) }

        let suffix = String(attempt)
        let prefixLimit = max(0, 24 - suffix.count)
        return String(base.prefix(prefixLimit)) + suffix
    }

    private func isUniqueAccountIDViolation(_ error: Error) -> Bool {
        func inspect(_ ns: NSError) -> Bool {
            if ns.code == 409 { return true }

            let haystack = ([ns.domain, ns.localizedDescription] + ns.userInfo.map { "\($0.key)=\($0.value)" })
                .joined(separator: " ")
                .lowercased()

            if haystack.contains("23505") { return true }
            if haystack.contains("409") && haystack.contains("account") { return true }
            if haystack.contains("account_directory_account_id_key") { return true }

            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                return inspect(underlying)
            }

            return false
        }

        return inspect(error as NSError)
    }

    public static let shared = AccountDirectoryService()
    private init() {}

    // Phase 14 Step 2 — batch directory lookup cache (viewer-local, in-memory only).
    // Note: This cache is intentionally ephemeral (clears on cold start).
    private actor DirectoryAccountCache {
        // P5-I / C-34 R1: each row remembers when it was fetched, so an expired
        // row is refetched and a new `avatar_version` reaches every site.
        private var store: [String: (account: DirectoryAccount, fetchedAt: Date)] = [:]

        func getMany(_ userIDs: [String]) -> [String: DirectoryAccount] {
            var out: [String: DirectoryAccount] = [:]
            for id in userIDs {
                if let v = store[id] { out[id] = v.account }
            }
            return out
        }

        func fetchedAt(_ userIDs: [String]) -> [String: Date] {
            var out: [String: Date] = [:]
            for id in userIDs {
                if let v = store[id] { out[id] = v.fetchedAt }
            }
            return out
        }

        func setMany(_ accounts: [DirectoryAccount], fetchedAt: Date = Date()) {
            for a in accounts {
                store[a.userID] = (a, fetchedAt)
            }
        }

        /// C-70. The last write epoch applied per key.
        private var lastWriteEpoch: [String: Int] = [:]


        /// Apply a directory-write result ONLY if it is newer than the last one
        /// applied to that key.
        ///
        /// **The ordering decision is taken INSIDE the actor, which is the only
        /// place it can be enforced.** A caller-side guard runs before the hop
        /// onto this actor, and the state it inspected can change during that
        /// suspension — so a check on the caller establishes what was true
        /// before the mutation was scheduled, never what is true when it runs.
        /// A monotonic epoch compared here cannot be overtaken that way.
        /// `validity` is consulted HERE, in the same synchronous segment as the
        /// mutation. Comparing only previously APPLIED epochs is not enough on
        /// its own: if a newer write has been submitted but has not yet applied
        /// anything, there is nothing for the older one to lose to and it would
        /// proceed. The token is invalidated synchronously at submission and at
        /// identity transitions, so it answers "is this still the current
        /// intent" rather than "did anything newer already land".
        func applyIfNewer(_ accounts: [DirectoryAccount],
                          owner: String,
                          generation: Int,
                          epoch: Int,
                          validity: DirectoryWriteValidity,
                          fetchedAt: Date = Date()) {
            // The check and the assignment happen under ONE hold of the token's
            // lock, so an invalidation cannot land between them.
            validity.withCurrent(owner: owner, generation: generation, seq: epoch) {
                for a in accounts {
                    if let seen = lastWriteEpoch[a.userID], seen >= epoch { continue }
                    lastWriteEpoch[a.userID] = epoch
                    store[a.userID] = (a, fetchedAt)
                }
            }
        }
    }

    private let cache = DirectoryAccountCache()

    /// P5-I / C-34 R1. How long a cached directory row is trusted before it is
    /// refetched. **20 minutes, for consistency with `CommentPresenceStore`** —
    /// the comparable viewer-local, in-memory cache of server state, with the
    /// same trade-off: short enough to avoid stale state, long enough not to
    /// spam requests. No polling: a row refreshes when it is next asked for.
    static let directoryCacheTTL: TimeInterval = 20 * 60

    /// PURE. The ids to fetch: every id when forced, otherwise those with no
    /// cached row and those whose row is older than `ttl`.
    static func idsNeedingFetch(requested: [String],
                                fetchedAt: [String: Date],
                                now: Date,
                                ttl: TimeInterval,
                                forceRefresh: Bool) -> [String] {
        if forceRefresh { return requested }
        return requested.filter { id in
            guard let at = fetchedAt[id] else { return true }
            return now.timeIntervalSince(at) > ttl
        }
    }

    /// Fetch the caller's own account_directory row via RLS (owner-only).
    /// Used to hydrate ProfileStore/Core Data defaults on fresh installs (e.g. lookup_enabled, display_name, location, instruments).
    func fetchSelfRow(userID: String) async -> Result<SelfDirectoryRow?, Error> {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }

        let query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "account_id,display_name,location,avatar_key,instruments,lookup_enabled,follow_requests_enabled,avatar_version"),
            URLQueryItem(name: "user_id", value: "eq.\(trimmed)"),
            URLQueryItem(name: "limit", value: "1")
        ]

        let result = await NetworkManager.shared.request(
            path: "rest/v1/account_directory",
            method: "GET",
            query: query,
            jsonBody: nil,
            headers: [:]
        )

        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            do {
                let rows = try JSONDecoder().decode([SelfDirectoryRow].self, from: data)
                return .success(rows.first)
            } catch {
                return .failure(error)
            }
        }
    }


    /// Resolve directory identity for a set of backend user IDs via SECURITY DEFINER RPC.
    /// - Returns: Map keyed by user_id (string UUID) for fast lookup in feed/profile-peek.
    /// - Important: This read path does NOT apply lookup_enabled filtering (People search only).
    public func resolveAccounts(userIDs: [String], forceRefresh: Bool = false) async -> Result<[String: DirectoryAccount], Error> {
        let trimmed = userIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmed.isEmpty else {
            return .success([:])
        }

        // Preserve first-seen order while de-duping.
        var orderedUnique: [String] = []
        var seen: Set<String> = []
        for id in trimmed {
            if !seen.contains(id) {
                seen.insert(id)
                orderedUnique.append(id)
            }
        }

        let cached = await cache.getMany(orderedUnique)
        let fetchedAt = await cache.fetchedAt(orderedUnique)
        let missing = Self.idsNeedingFetch(requested: orderedUnique,
                                           fetchedAt: fetchedAt,
                                           now: Date(),
                                           ttl: Self.directoryCacheTTL,
                                           forceRefresh: forceRefresh)
        // Expiry must not blank names that are showing today: if a refresh
        // fails but every requested row is cached, serve the cached rows.
        let everyRequestedRowIsCached = orderedUnique.allSatisfy { cached[$0] != nil }

        var merged = cached

        if !missing.isEmpty {
            let payload: [String: Any] = ["user_ids": missing]

            let body: Data
            do {
                body = try JSONSerialization.data(withJSONObject: payload, options: [])
            } catch {
                return .failure(error)
            }

            let path = "rest/v1/rpc/get_account_directory_by_user_ids"
            let result = await NetworkManager.shared.request(path: path, method: "POST", query: nil, jsonBody: body)

            switch result {
            case .success(let data):
                do {
                    let rows = try JSONDecoder().decode([DirectoryAccount].self, from: data)
                    await cache.setMany(rows)
                    for r in rows {
                        merged[r.userID] = r
                    }
                } catch {
                    if everyRequestedRowIsCached { return .success(cached) }
                    return .failure(error)
                }

            case .failure(let error):
                if everyRequestedRowIsCached { return .success(cached) }
                return .failure(error)
            }
        }

        return .success(merged)
    }


    /// Search the backend account directory via RPC.
    /// - Important: This is the only non-owner read surface by design.
    public func search(query: String) async -> Result<[DirectoryAccount], Error> {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = ["q": q]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failure(error)
        }

        let path = "rest/v1/rpc/search_account_directory"
        let result = await NetworkManager.shared.request(path: path, method: "POST", query: nil, jsonBody: body)

        switch result {
        case .success(let data):
            do {
                let rows = try JSONDecoder().decode([DirectoryAccount].self, from: data)
                return .success(rows)
            } catch {
                return .failure(error)
            }

        case .failure(let error):
            return .failure(Self.mapSearchFailure(error))
        }
    }

    /// B-37. Translate the server's budget refusal into a typed error, leaving
    /// every other failure exactly as it was.
    ///
    /// Matched on the PostgREST error code as well as the status, so a 429 from
    /// anywhere else in the stack still reads as a throttle while a body we do
    /// not recognise degrades to "no duration" rather than to a wrong one.
    static func mapSearchFailure(_ error: Error) -> Error {
        guard let network = error as? NetworkManager.NetworkError,
              case .httpError(let status, let body) = network,
              status == 429
        else { return error }

        // A 429 ALONE is enough to be a throttle, but it is NOT enough to trust
        // a duration. Only our own refusal shape carries one; any other 429 --
        // an edge proxy, a gateway -- yields a throttle with no time named.
        let payload = Self.parseRefusal(body)
        let isOurRefusal = payload.code == "PT429" && payload.message == "search_rate_limited"
        return DirectorySearchError.rateLimited(
            retryAfterSeconds: isOurRefusal ? payload.retryAfterSeconds : nil)
    }

    /// `retry_after_seconds` inside `details`, which arrives as a JSON **string**
    /// containing JSON.
    private struct RefusalDetail: Decodable { let retry_after_seconds: Int }

    /// Decoded with `JSONDecoder` rather than read out of an `Any` dictionary,
    /// because `JSONSerialization` bridges JSON `true` to `NSNumber` and
    /// `as? Int` would silently turn it into a one-second duration. `JSONDecoder`
    /// rejects a boolean, a fraction and a quoted number for an `Int` field.
    static func parseRefusal(_ body: String?) -> (code: String?, message: String?, retryAfterSeconds: Int?) {
        guard let body,
              let data = body.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return (nil, nil, nil) }

        let code = root["code"] as? String
        let message = root["message"] as? String

        var seconds: Int?
        if let detailString = root["details"] as? String,
           let detailData = detailString.data(using: .utf8) {
            seconds = (try? JSONDecoder().decode(RefusalDetail.self, from: detailData))?.retry_after_seconds
        }
        return (code, message, seconds)
    }

    // MARK: - C-70 · the directory write path

    /// The columns a write asks the server to return.
    ///
    /// **`avatar_key` and `avatar_version` are deliberately absent.** Once
    /// completions can race, a fetched avatar field is not automatically more
    /// current than the cached one, so adopting it would be a change of
    /// behaviour dressed as an improvement. C-34's caching is untouched here.
    ///
    /// **`lookup_enabled` and `follow_requests_enabled` are deliberately absent
    /// too** — CP-3 keeps them out of the payload, and keeping them out of the
    /// `select=` makes "ordinary profile publishing does not touch a privacy
    /// preference" structural on the response side as well.
    private static var writeSelect: String { DirectoryWriteEvidence.selectList }

    /// The row body, WITHOUT `user_id`.
    ///
    /// A PATCH never sends `user_id`: the owner is already pinned by the query
    /// filter and by the policy's `with_check`, and not sending it means this
    /// path cannot reassign a row's owner even though the column grant would
    /// permit it.
    private func directoryPayload(displayName: String,
                                  accountIDToWrite: String?,
                                  includeAccountID: Bool,
                                  location: String?,
                                  instruments: [String]?) -> [String: Any] {
        // CP-3: the two privacy columns are NOT sent. They are dead in the
        // directory (CP-2 stopped reading them) and authoritative in
        // account_privacy.
        var payload: [String: Any] = [
            "display_name": displayName,
            "location": sanitizedLocation(location) ?? NSNull()
        ]
        if includeAccountID, let accountIDToWrite = sanitizedAccountID(accountIDToWrite) {
            payload["account_id"] = accountIDToWrite
        }
        if let instruments = instruments {
            payload["instruments"] = instruments
        }
        return payload
    }

    /// Send one owner-bound directory write and score what came back.
    ///
    /// Every write goes through `NetworkManager.boundRequest`, so the OUTBOUND
    /// credential is bound to the owner — a response-side identity check cannot
    /// establish that, because by then the request has already been sent as
    /// whoever the ambient token belonged to. The receipt check below is a
    /// second, independent gate: the binding proves who we sent as, the receipt
    /// proves which row answered.
    @MainActor
    private func sendDirectoryWrite(method: String,
                                    query: [URLQueryItem],
                                    payload: [String: Any],
                                    owner: String,
                                    binding: OperationBinding) async -> DirectoryWriteOutcome {
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failed(error)
        }

        let result = await NetworkManager.shared.boundRequest(
            path: "rest/v1/account_directory",
            method: method,
            query: query,
            jsonBody: body,
            headers: ["Prefer": method == "POST"
                      ? "resolution=merge-duplicates,return=representation"
                      : "return=representation"],
            binding: binding
        )

        switch result {
        case .failure(let error):
            return DirectoryWriteEvidence.classify(error)
        case .success(let data):
            switch DirectoryWriteEvidence.resolve(data: data, owner: owner) {
            case .settled(let outcome):
                return outcome
            case .row(let receipt):
                let expectation = DirectoryWriteEvidence.expectation(from: payload)
                return DirectoryWriteEvidence.matches(expectation, receipt)
                    ? .applied(receipt)
                    : .notEvidenced(receipt)
            }
        }
    }

    /// Merge an EVIDENCED receipt into the live identity caches.
    ///
    /// Called only for `.applied`. A `.notEvidenced` receipt describes a row
    /// whose contents we cannot account for, and publishing it into the shared
    /// identity would be the original defect in a new place.
    ///
    /// **Ordering is enforced where the mutation happens, not where it is
    /// requested.** The caller-side checks below are real but insufficient on
    /// their own: `cache` is an actor, so every call to it is a suspension, and
    /// a guard taken before one describes the state the mutation was scheduled
    /// in rather than the state it runs in. `applyIfNewer` therefore carries a
    /// monotonic epoch that the actor itself compares. `BackendFeedStore` is
    /// `@MainActor` and its merge is synchronous, so on this actor the guard
    /// immediately before it genuinely is adjacent to the mutation.
    ///
    /// Every column in `writeSelect` is required to be present in the receipt
    /// (see `DirectoryWriteEvidence.resolve`), so the server's value is used
    /// directly for each of them — a missing key would otherwise read as nil
    /// and silently CLEAR a cached value the write never targeted, which is
    /// exactly what a handle-only generation write would have done to a cached
    /// location.
    @MainActor
    private func applyReceiptToCaches(_ receipt: DirectoryWriteReceipt,
                                      cacheKey: String,
                                      owner: String,
                                      capturedGeneration: Int,
                                      epoch: Int) async {
        let coordinator = DirectoryWriteCoordinator.shared
        guard coordinator.mayApplyEffects(owner: owner, capturedGeneration: capturedGeneration, seq: epoch) else { return }
        let existing = await cache.getMany([cacheKey])[cacheKey]
        guard coordinator.mayApplyEffects(owner: owner, capturedGeneration: capturedGeneration, seq: epoch) else { return }

        let merged = DirectoryAccount(userID: cacheKey,
                                      accountID: receipt.accountID,
                                      displayName: receipt.displayName ?? existing?.displayName ?? "",
                                      location: receipt.location,
                                      // Carried forward, NOT taken from the receipt — the
                                      // write never targeted avatar_key, the guard trigger
                                      // pins avatar_version on UPDATE, and C-70 does not
                                      // change C-34's caching. Neither column is even selected.
                                      avatarKey: existing?.avatarKey,
                                      instruments: receipt.instruments,
                                      avatarVersion: existing?.avatarVersion)
        await cache.applyIfNewer([merged], owner: owner, generation: capturedGeneration,
                                 epoch: epoch, validity: coordinator.validity)
        // The feed merge takes the same hold, for the same reason: the owner
        // check is advisory, the token check is the one that must be atomic
        // with the mutation it protects.
        guard coordinator.mayApplyEffects(owner: owner, capturedGeneration: capturedGeneration, seq: epoch) else { return }
        coordinator.validity.withCurrent(owner: owner, generation: capturedGeneration, seq: epoch) {
            BackendFeedStore.shared.mergeDirectoryAccounts([cacheKey: merged])
        }
    }

    /// Write the caller's `account_directory` row (owner-only via RLS).
    ///
    /// **PATCH FIRST, CREATE ONLY IF NOTHING MATCHED.** `account_directory` has
    /// a gated INSERT policy and an UNGATED owner-UPDATE policy, and Postgres
    /// evaluates the INSERT policy for `INSERT … ON CONFLICT DO UPDATE` — so the
    /// upsert this replaced required entitlement even when only an UPDATE would
    /// occur, and the owner-UPDATE carve-out D-U6-3 intends was unreachable from
    /// the client. Sending a PATCH for an existing row uses the policy surface
    /// as deployed: it weakens nothing and creates no carve-out.
    ///
    /// A prior existence check is not used: it would cost a round trip on every
    /// edit and still race. The zero-row answer IS the existence check, taken
    /// atomically with the attempted write.
    ///
    /// **Creation stays gated**, and the CP-1 band trigger is untouched — it is
    /// `BEFORE INSERT` only, and its own body returns early when a row already
    /// exists, so an existing-row PATCH and the old upsert reach the same
    /// outcome for a banded row and for the one pre-CP row alike (Q6/§B; Q6/B
    /// remains unauthorised).
    @MainActor
    public func upsertSelfRow(userID: String,
                              displayName: String,
                              accountID: String?,
                              location: String? = nil,
                              instruments: [String]? = nil) async -> DirectoryWriteResult {
        let uid = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            return DirectoryWriteResult(outcome: .failed(NSError(domain: "AccountDirectoryService", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "empty userID"])),
                                        seq: 0, generation: DirectoryWriteCoordinator.shared.identityGeneration)
        }
        let owner = uid.lowercased()

        // Blank/invalid account_id values are intentionally omitted. This preserves any existing
        // generated/backend account_id instead of clearing it back to NULL.
        let explicit = sanitizedAccountID(accountID)
        let payload = directoryPayload(displayName: displayName,
                                       accountIDToWrite: explicit,
                                       includeAccountID: explicit != nil,
                                       location: location,
                                       instruments: instruments)

        let coordinator = DirectoryWriteCoordinator.shared
        // The tokens travel back with the outcome so the CALLER can guard its
        // own effects by the same rule the writer guards its cache merge —
        // otherwise a write that is applied on the server but stale on this
        // screen would still post a message, latch a skip token or adopt a
        // generated handle.
        var resultSeq = 0
        var resultGeneration = coordinator.identityGeneration
        let outcome = await coordinator.submit(kind: .profileEdit,
                                               owner: owner,
                                               payloadKeys: Set(payload.keys)) { [weak self] seq, capturedGeneration in
            resultSeq = seq
            resultGeneration = capturedGeneration
            guard let self else { return .superseded }
            return await self.performProfileWrite(uid: uid, owner: owner, payload: payload,
                                                  seq: seq, capturedGeneration: capturedGeneration)
        }
        return DirectoryWriteResult(outcome: outcome, seq: resultSeq, generation: resultGeneration)
    }

    /// PATCH, then create, then at most one bounded probe. Local effects are
    /// applied on `.applied` ALONE.
    @MainActor
    private func performProfileWrite(uid: String,
                                     owner: String,
                                     payload: [String: Any],
                                     seq: Int,
                                     capturedGeneration: Int) async -> DirectoryWriteOutcome {
        let coordinator = DirectoryWriteCoordinator.shared
        guard let binding = coordinator.binding(owner: owner, capturedGeneration: capturedGeneration) else {
            return .supersededIdentity
        }

        let patchQuery = [URLQueryItem(name: "user_id", value: "eq.\(owner)"),
                          URLQueryItem(name: "select", value: Self.writeSelect)]

        var outcome = await sendDirectoryWrite(method: "PATCH", query: patchQuery,
                                               payload: payload, owner: owner, binding: binding)

        if case .noRowMatched = outcome {
            // No row matched: create one. Still gated, still band-checked.
            var creationPayload = payload
            creationPayload["user_id"] = owner
            let postQuery = [URLQueryItem(name: "on_conflict", value: "user_id"),
                             URLQueryItem(name: "select", value: Self.writeSelect)]
            let created = await sendDirectoryWrite(method: "POST", query: postQuery,
                                                   payload: creationPayload, owner: owner, binding: binding)

            switch created {
            case .refusedByPolicy, .rowConflict:
                // ONE bounded attempt at the existing-owner path, and it PROBES
                // rather than proves: a refusal does NOT establish that a row
                // now exists. If this PATCH also matches nothing, the write
                // stays unconfirmed and the refusal we actually observed is
                // what is reported.
                //
                // Not a loop, no auth refresh of its own (boundRequest owns the
                // 401 rule and never refreshes a 403), and ambiguous transport
                // is never probed — an unknown outcome must not be replayed.
                let probe = await sendDirectoryWrite(method: "PATCH", query: patchQuery,
                                                     payload: payload, owner: owner, binding: binding)
                if case .noRowMatched = probe {
                    outcome = created
                } else {
                    outcome = probe
                }
            default:
                outcome = created
            }
        }

        // MERGED ONLY WHEN EVIDENCED. A `.notEvidenced` receipt is a row we
        // cannot account for, and the shared identity cache is the last place
        // an unaccounted-for value belongs.
        if case .applied(let receipt) = outcome {
            await applyReceiptToCaches(receipt, cacheKey: uid, owner: owner,
                                       capturedGeneration: capturedGeneration, epoch: seq)
        }
        return outcome
    }

    /// Best-effort auto-generation/backfill for a missing account_id.
    /// Returns the generated account_id on success, or nil when generation is skipped/failed.
    @discardableResult
    @MainActor
    public func autoGenerateAccountIDIfMissing(userID: String,
                                               displayName: String,
                                               localAccountID: String?,
                                               location: String? = nil,
                                               instruments: [String]? = nil) async -> String? {
        let uid = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return nil }

        // Connected + authenticated owner only.
        // AuthManager.canonicalBackendUserID() is lowercased, while some callers pass
        // uppercase UUID strings from restored/profile state. UUID identity is
        // case-insensitive; normalize both sides so valid owners do not skip generation.
        guard BackendEnvironment.shared.isConnected else { return nil }
        guard let canonicalUID = AuthManager.canonicalBackendUserID()?.trimmingCharacters(in: .whitespacesAndNewlines),
              canonicalUID.caseInsensitiveCompare(uid) == .orderedSame else { return nil }

        // C-70. THE EPOCH IS CAPTURED BEFORE THE FIRST AWAIT, and carried
        // through every attempt. `fetchSelfRow` below is a suspension, and an
        // A→B→A switch across it would leave the owner and the token subject
        // both equal to A again — so a claim minted AFTER the fetch would look
        // current while resting on a row read in a session that has since been
        // torn down and rehydrated. Capturing first makes that claim stale by
        // construction.
        let generationCoordinator = DirectoryWriteCoordinator.shared
        let capturedGeneration = generationCoordinator.identityGeneration

        // Never overwrite a local/manual value.
        guard trimmedNonEmpty(localAccountID) == nil else { return nil }

        let currentRowResult = await fetchSelfRow(userID: uid)
        let currentRow: SelfDirectoryRow?
        switch currentRowResult {
        case .failure:
            return nil
        case .success(let row):
            currentRow = row
        }

        // Generation must be based on the per-user backend directory row.
        // If no row exists yet, onboarding/profile sync has not written the current user's
        // display name. Do not fall back to AuthManager/ProfileStore here, because those
        // values can be stale during sign-out/delete/recreate transitions.
        guard let currentRow else { return nil }

        // Never overwrite an existing backend value.
        guard trimmedNonEmpty(currentRow.accountID) == nil else { return nil }

        guard let effectiveDisplayName = trimmedNonEmpty(currentRow.displayName) else { return nil }
        guard let base = autoAccountIDBase(from: effectiveDisplayName) else { return nil }

        let owner = uid.lowercased()
        let coordinator = generationCoordinator
        guard coordinator.identityGeneration == capturedGeneration else { return nil }

        for attempt in 1...10 {
            let candidate = autoAccountIDCandidate(base: base, attempt: attempt)
            guard let sanitized = sanitizedAccountID(candidate) else { return nil }
            let payload: [String: Any] = ["account_id": sanitized]

            let outcome = await coordinator.submit(kind: .generation,
                                                   owner: owner,
                                                   payloadKeys: Set(payload.keys),
                                                   capturedGeneration: capturedGeneration) { [weak self] seq, generation in
                guard let self else { return .superseded }
                return await self.performGenerationWrite(uid: uid, owner: owner, payload: payload,
                                                         seq: seq, capturedGeneration: generation)
            }

            switch outcome {
            case .applied:
                return sanitized
            case .accountIDTaken:
                continue
            default:
                // Includes `.noRowMatched`, which is an OBSERVATION and not a
                // diagnosis: the filter matched nothing, which means EITHER the
                // row is absent OR the handle is already populated. Both mean
                // "do not generate", so nothing is inferred, logged as a cause,
                // or retried.
                return nil
            }
        }

        return nil
    }

    /// Generation writes `account_id` and nothing else.
    ///
    /// **Two changes, and both close races structurally rather than by
    /// ordering discipline.** The old path re-sent `display_name`, `location`
    /// and `instruments` read from the row it had fetched, so an edit landing
    /// between the fetch and the write was reverted — it can no longer revert a
    /// field it does not send. And the "do not overwrite an existing handle"
    /// rule was evaluated at FETCH time; `account_id=is.null` moves it into the
    /// database at WRITE time.
    ///
    /// `is.null` exhausts the missing-handle contract: `account_id_format`
    /// admits only NULL or 3-24 characters of `[a-z0-9_]`, so no empty or
    /// whitespace handle can exist in the table.
    @MainActor
    private func performGenerationWrite(uid: String,
                                        owner: String,
                                        payload: [String: Any],
                                        seq: Int,
                                        capturedGeneration: Int) async -> DirectoryWriteOutcome {
        let coordinator = DirectoryWriteCoordinator.shared
        guard let binding = coordinator.binding(owner: owner, capturedGeneration: capturedGeneration) else {
            return .supersededIdentity
        }

        let query = [URLQueryItem(name: "user_id", value: "eq.\(owner)"),
                     URLQueryItem(name: "account_id", value: "is.null"),
                     URLQueryItem(name: "select", value: Self.writeSelect)]

        let outcome = await sendDirectoryWrite(method: "PATCH", query: query,
                                               payload: payload, owner: owner, binding: binding)
        if case .applied(let receipt) = outcome {
            await applyReceiptToCaches(receipt, cacheKey: uid, owner: owner,
                                       capturedGeneration: capturedGeneration, epoch: seq)
        }
        return outcome
    }


    // MARK: - Phase 15 Step 3A (Avatars) — update self avatar_key

    /// Update the caller's `account_directory.avatar_key` (owner-only via RLS).
    /// - Parameter avatarKey: `users/<uid>/avatar.jpg` or nil to clear.
    /// - Important: This is an owner-only metadata update; no profile sync.
    public func updateSelfAvatarKey(userID: String, avatarKey: String?) async -> Result<Void, Error> {
        let uid = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            return .failure(NSError(domain: "AccountDirectoryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "empty userID"]))
        }

        let payload: [String: Any] = [
            "avatar_key": avatarKey ?? NSNull()
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failure(error)
        }

        let path = "rest/v1/account_directory?user_id=eq.\(uid)"
        let headers = [
            "Prefer": "return=minimal"
        ]

        let result = await NetworkManager.shared.request(path: path, method: "PATCH", query: nil, jsonBody: body, headers: headers)
        switch result {
        case .success:
            // Live identity cache update: patch avatar_key in-memory so UI refreshes immediately.
            if let existing = await cache.getMany([uid])[uid] {
                let updated = DirectoryAccount(userID: existing.userID,
                                               accountID: existing.accountID,
                                               displayName: existing.displayName,
                                               location: existing.location,
                                               avatarKey: avatarKey,
                                               instruments: existing.instruments,
                                               // Carried forward, not invented: the SERVER stamps the new
                                               // version and this device learns it on its next directory
                                               // read. The owner's own avatar renders from
                                               // auth.backendAvatarKey and invalidates explicitly, so it
                                               // does not depend on this value.
                                               avatarVersion: existing.avatarVersion)
                await cache.setMany([updated])
                await BackendFeedStore.shared.mergeDirectoryAccounts([uid: updated])
            }
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

}
