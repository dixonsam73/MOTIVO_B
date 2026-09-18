//
//  NetworkManager.swift
//  MOTIVO
//  CHANGE-ID: 20260210_182200_Phase15_Step3A_AvatarUploadDelete
//  SCOPE: Phase 15 Step 3A — add NetworkManager backend primitives to upsert/delete avatar JPEG in Supabase Storage (avatars bucket). No UI wiring.
//  SEARCH-TOKEN: 20260210_182200_Phase15_Step3A_AvatarUploadDelete
//
//  CHANGE-ID: 20260210_194800_Phase15_AvatarUIDLowercase_RLSFix
//  SCOPE: Phase 15 Step 3B — normalize backendUserID to lowercase when constructing avatar storage path to satisfy RLS policy users/<auth.uid()>/avatar.jpg; no other behavior changes.
//  SEARCH-TOKEN: 20260210_194800_Phase15_AvatarUIDLowercase_RLSFix
//

//  CHANGE-ID: 20260114_131900_9E_SignedURL_Debug
//  SCOPE: DEBUG-only logging for storage signed URLs (sign response -> final URL) to diagnose backend attachment playback; no logic changes.
//
//
//  CHANGE-ID: 20251230_Step7_NetworkManager_SupabaseHeaders_193205-1c21
//  SCOPE: Step 7 — add Supabase-ready header handling (apike...arer); keep legacy configure(baseURL:authToken:) compatibility
//
//  CHANGE-ID: 20251230-NetworkManager-minHTTP-a1
//  SCOPE: v7.13 — minimal HTTP JSON helper, offline-safe
//
//  CHANGE-ID: 20251112-NetworkManager-7c3d
//  SCOPE: v7.12C — placeholder singleton, no real networking
//
//  CHANGE-ID: 20260101_Step8A_NetworkManager_BearerNormalize_LocalizedError_124900
//  SCOPE: Step 8A — normalize bearer token (strip 'Bearer ')... bodies via LocalizedError; DEBUG log response body on non-2xx
//
//  CHANGE-ID: 20260101_Step8A_NetworkManager_ClearBearerTokenShim_130600
//  SCOPE: Step 8A — add clearBearerToken() shim for AuthManager compatibility (calls setBearerToken(nil))
//  SEARCH-TOKEN: 20260101_Step8A_NetworkManager_ClearBearerTokenShim_130600
//

//
//  CHANGE-ID: 20260101_Step8C1_NetworkManager_QueryItemsAndLegacyPath_150000
//  SCOPE: Step 8C.1 — support proper URL query parameters via URLQueryItem AND back-compat parsing for paths that include '?...'; prevents '%3F' encoding bug
//
//
//  CHANGE-ID: 20260113_9D_NetworkManager_DEBUG_JWT_164800
//  SCOPE: Step 9D — DEBUG-only helper to surface Supabase user access token (JWT) via NetworkManager bearer token setter for Edge Function testing
//  SEARCH-TOKEN: 20260113_9D_NetworkManager_DEBUG_JWT_164800
//


// CHANGE-ID: 20260114_103700_9E
// SCOPE: 9E signed storage URLs (no Edge Functions)

// CHANGE-ID: 20260127_130352_NetworkAuthChallenge_RefreshRetry
// SCOPE: Phase 14.2.2 — Add 401/403 auth-challenge hook and single retry to avoid zombie signed-in state; no behavioural changes beyond auth correctness.
// SEARCH-TOKEN: 20260127_130352_NetworkAuthChallenge_RefreshRetry

// CHANGE-ID: 20260303_105500_DeleteAccountV2_Stage5_RemoteAvatarCacheWipe
// SCOPE: Delete Account v2 Stage 5 — add resetForFactoryReset hooks to RemoteAvatarSignedURLCache and RemoteAvatarImageCache so LocalFactoryReset can clear remote avatar caches. No other behavior changes.
// SEARCH-TOKEN: 20260303_105500_DeleteAccountV2Stage5_RemoteAvatarCacheWipe

// CHANGE-ID: 20260129_140900_14_3H_B6c_BearerReason
// SCOPE: Phase 14.3H — Add clearBearerToken(reason:) overload + reason-tagged log; keep legacy clearBearerToken() shim; no networking behavior change.
// SEARCH-TOKEN: 20260129_140900_14_3H_B6c_BearerReason

import Foundation

public final class NetworkManager {
    public static let shared = NetworkManager()
    private init() {}

    // Base URL for API calls (e.g., https://<ref>.supabase.co)
    public var baseURL: URL? = nil

    // Legacy: project API key (publishable key). Kept for backward compatibility.
    public var authToken: String? = nil

    // Step 7: user session bearer token (access token from Supabase Auth)
    private var bearerToken: String? = nil

    /// Optional auth challenge handler used to refresh a session after a 401.
    /// NOT invoked for 403 -- see C-57: an authorisation denial is not an
    /// authentication failure, and refreshing on one destroys a valid session.
    /// If it returns true, the original request will be retried once.
    public var onAuthChallenge: (() async -> Bool)? = nil

    /// Legacy configure: treats `authToken` as the project API key (publishable key).
    public func configure(baseURL: URL?, authToken: String?) {
        self.baseURL = baseURL
        self.authToken = authToken
        #if DEBUG
        #endif
    }

    /// Step 7: set bearer token (Supabase access token).
    /// Accepts either raw JWT or "Bearer <JWT>" and normalizes to raw JWT.
    public func setBearerToken(_ token: String?) {
        var t = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tt = t, tt.lowercased().hasPrefix("bearer ") {
            t = String(tt.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        bearerToken = (t?.isEmpty == true) ? nil : t
        if bearerToken != nil {
            #if DEBUG
            #endif
        }

    }

    /// Compatibility shim: AuthManager expects this.
    public func clearBearerToken() {
        clearBearerToken(reason: "unspecified")
    }

    public func clearBearerToken(reason: String) {
        #if DEBUG
        #endif
        setBearerToken(nil)
    }

    public enum NetworkError: Error, LocalizedError, CustomStringConvertible {
        case notConfigured
        case invalidURL(String)
        case httpError(status: Int, body: String?)
        case transportError(String)
        case encodingError(String)
        case decodingError(String)

        public var description: String {
            switch self {
            case .notConfigured:
                return "NetworkManager not configured (missing baseURL)"
            case .invalidURL(let s):
                return "Invalid URL: \(s)"
            case .httpError(let status, let body):
                if let body, !body.isEmpty { return "HTTP error \(status) body=\(body)" }
                return "HTTP error \(status)"
            case .transportError(let s):
                return "Transport error: \(s)"
            case .encodingError(let s):
                return "Encoding error: \(s)"
            case .decodingError(let s):
                return "Decoding error: \(s)"
            }
        }

        // LocalizedError
        public var errorDescription: String? { description }
    }

    // Step 8C.1: Back-compat query parsing
    // If callers pass a PostgREST-style path containing a raw "?a=b&c=d" query string,
    // `appendingPathComponent` would percent-encode the "?" into "%3F" and Supabase would 404/401.
    // To preserve compatibility, we split on the first "?" and convert the query string into URLQueryItems
    // when `query` is nil/empty.
    private func splitPathAndLegacyQuery(_ path: String) -> (path: String, queryItems: [URLQueryItem]?) {
        guard let qIndex = path.firstIndex(of: "?") else {
            return (path, nil)
        }

        let pathPart = String(path[..<qIndex])
        let queryPart = String(path[path.index(after: qIndex)...])
        guard !queryPart.isEmpty else {
            return (pathPart, nil)
        }

        // URLComponents gives us correct decoding/handling of repeated keys.
        var tmp = URLComponents()
        tmp.query = queryPart
        let items = tmp.queryItems
        return (pathPart, items?.isEmpty == false ? items : nil)
    }

    
    /// URL construction shared by the ambient `request` and the bound path, so the
    /// two can never build a different URL for the same path. Extracted verbatim.
    private func buildURLRequest(path: String, method: String, query: [URLQueryItem]?,
                                 jsonBody: Data?) -> Result<URLRequest, Error> {
        guard let baseURL else {
            return .failure(NetworkError.notConfigured)
        }

        // Normalize path
        let trimmed0 = path.hasPrefix("/") ? String(path.dropFirst()) : path

        // Back-compat: if a caller passes a raw query string inside `path` (e.g. "posts?select=*")
        // and does not provide `query:` items, split it so the query becomes real URL query parameters.
        var effectivePath = trimmed0
        var effectiveQuery: [URLQueryItem]? = query
        if effectiveQuery == nil || effectiveQuery?.isEmpty == true {
            let split = splitPathAndLegacyQuery(trimmed0)
            effectivePath = split.path
            if let legacyItems = split.queryItems, !legacyItems.isEmpty {
                effectiveQuery = legacyItems
            }
        }

        guard var components = URLComponents(url: baseURL.appendingPathComponent(effectivePath), resolvingAgainstBaseURL: false) else {
            return .failure(NetworkError.invalidURL("base=\(baseURL.absoluteString) path=\(path)"))
        }

        if let effectiveQuery, !effectiveQuery.isEmpty {
            components.queryItems = effectiveQuery
        }

        guard let finalURL = components.url else {
            return .failure(NetworkError.invalidURL("components failed: \(components)"))
        }

        var baseRequest = URLRequest(url: finalURL)
        baseRequest.httpMethod = method
        if let jsonBody {
            baseRequest.httpBody = jsonBody
        }
        return .success(baseRequest)
    }

    public func request(
        path: String,
        method: String,
        query: [URLQueryItem]? = nil,
        jsonBody: Data? = nil,
        headers: [String:String] = [:]
    ) async -> Result<Data, Error> {

        let baseRequest: URLRequest
        switch buildURLRequest(path: path, method: method, query: query, jsonBody: jsonBody) {
        case .success(let built): baseRequest = built
        case .failure(let error): return .failure(error)
        }
        let finalURL = baseRequest.url!

        func performOnce() async -> Result<Data, Error> {
            var request = baseRequest

            // Headers
            var allHeaders: [String:String] = [:]

            // Supabase REST expects `apikey` for project key. Safe to include on all requests.
            if let apiKey = authToken, !apiKey.isEmpty {
                allHeaders["apikey"] = apiKey
            }

            // RLS-protected calls need a bearer access token.
            if let bearer = bearerToken, !bearer.isEmpty {
                allHeaders["Authorization"] = "Bearer \(bearer)"
            }

            if jsonBody != nil {
                allHeaders["Content-Type"] = "application/json"
            }

            // Merge custom headers (custom overrides defaults if key duplicates)
            for (k, v) in headers { allHeaders[k] = v }
            for (k, v) in allHeaders { request.setValue(v, forHTTPHeaderField: k) }

            #if DEBUG
            // DEBUG: Log POST /rest/v1/posts request details without exposing secrets
            if method.uppercased() == "POST", finalURL.path.contains("/rest/v1/posts") {
                print("[NetworkManager][DEBUG] ▶︎ POST Request: \(finalURL.absoluteString)")
                if let body = request.httpBody, !body.isEmpty {
                    if let bodyString = String(data: body, encoding: .utf8) {
                        print("[NetworkManager][DEBUG] body=\(bodyString)")
                    } else {
                        print("[NetworkManager][DEBUG] body=(non-UTF8, \(body.count) bytes)")
                    }
                    do {
                        let obj = try JSONSerialization.jsonObject(with: body, options: [])
                        print("[NetworkManager][DEBUG] json=\(obj)")
                    } catch {
                        // ignore
                    }
                }
            }
            #endif

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let bodyString = String(data: data, encoding: .utf8)
                    #if DEBUG
                    if let bodyString, !bodyString.isEmpty {
                        print("[NetworkManager] ◀︎ body=\(bodyString)")
                    }
                    #endif
                    return .failure(NetworkError.httpError(status: http.statusCode, body: bodyString))
                }
                return .success(data)
            } catch {
                return .failure(NetworkError.transportError(String(describing: error)))
            }
        }

        // First attempt
        let first = await performOnce()

        // Auth-challenge path: refresh session and retry once on 401 ONLY.
        //
        // C-57, 2026-09-02. THIS CONDITION USED TO INCLUDE 403 AND THAT DESTROYED
        // VALID SESSIONS. 401 is an AUTHENTICATION failure -- the token is bad, so
        // refreshing is exactly right. 403 is an AUTHORISATION denial -- the token
        // is fine and the caller is simply not permitted, so a refresh cannot
        // change the outcome, the retry is guaranteed to fail, and the only effect
        // is that `ensureValidSession` falls through to `signOut()` and DELETES the
        // Keychain tokens. `hasConnectedIdentity` then goes false and
        // ProductionAppModeActivation collapses the client to Solo -- irreversibly,
        // because the credentials are gone.
        //
        // Measured on Device A, 2026-09-02: after U6b enforcement was bound, the
        // observed post-bind requests produced 403 AUTHORISATION responses (32 of
        // them, and zero 401s anywhere), and the client treated them as
        // authentication challenges. The settled architecture says a legitimate
        // server-side denial must never collapse a locally entitled client into
        // Solo, and this was the path that did it.
        //
        // 403 now propagates through the ordinary denial/error path to the caller,
        // which is what an authorisation denial is.
        if case .failure(let err) = first,
           let ne = err as? NetworkError,
           case .httpError(let status, _) = ne,
           status == 401,
           let handler = onAuthChallenge {

            let refreshed = await handler()
            if refreshed {
                return await performOnce()
            }
        }

        return first
    }


    public func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, Error> {
        do {
            let obj = try JSONDecoder().decode(type, from: data)
            return .success(obj)
        } catch {
            return .failure(NetworkError.decodingError(String(describing: error)))
        }
    }

    public func encodeJSON<T: Encodable>(_ value: T) -> Result<Data, Error> {
        do {
            let data = try JSONEncoder().encode(value)
            return .success(data)
        } catch {
            return .failure(NetworkError.encodingError(String(describing: error)))
        }
    }

    // MARK: - Step 8G Phase 2 (Backend attachments)

    /// Builds an authenticated Supabase Storage object path for this project.
    /// Example:
    ///   storage/v1/object/authenticated/<bucket>/<path>
    public func authenticatedStorageObjectPath(bucket: String, path: String) -> String {
        let b = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)

        let bucketPart = percentEncodePathSegments(b)
        let pathPart = percentEncodePathSegments(p)

        // Intentionally no leading "/" — request() normalizes.
        return "storage/v1/object/authenticated/\(bucketPart)/\(pathPart)"
    }

    /// Downloads an object from Supabase Storage using the current bearer token (Authorization header).
    /// NOTE: This returns raw bytes; callers may write to a temp file for AVPlayer / Image rendering.
    public func downloadAuthenticatedStorageObject(bucket: String, path: String) async -> Result<Data, Error> {
        let storagePath = authenticatedStorageObjectPath(bucket: bucket, path: path)
        return await request(path: storagePath, method: "GET")
    }


    // MARK: - Step 9E (Signed URL playback, no Edge Functions)

    /// Creates a short-lived signed URL for a private object in Supabase Storage.
    /// Requires `SELECT` permission on `storage.objects` via RLS.
    ///
    /// NOTE: The returned signed URL must be treated as ephemeral. Do not persist it.
    public func createSignedStorageObjectURL(bucket: String, path: String, expiresInSeconds: Int) async -> Result<URL, Error> {
        guard let baseURL else {
            return .failure(NetworkError.notConfigured)
        }

        let b = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty, !p.isEmpty else {
            return .failure(NetworkError.invalidURL("Empty bucket/path"))
        }

        let bucketPart = percentEncodePathSegments(b)
        let pathPart = percentEncodePathSegments(p)

        let signPath = "storage/v1/object/sign/\(bucketPart)/\(pathPart)"

        let payload: [String: Any] = [
            "expiresIn": max(1, expiresInSeconds)
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failure(NetworkError.encodingError(String(describing: error)))
        }

        let result = await request(path: signPath, method: "POST", query: nil, jsonBody: body)

        switch result {
        case .success(let data):
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                let dict = obj as? [String: Any] ?? [:]

                // Common keys across SDK/REST variants.
                let signed = (dict["signedURL"] as? String)
                    ?? (dict["signedUrl"] as? String)
                    ?? (dict["signed_url"] as? String)
                    ?? (dict["url"] as? String)

                guard let signedStr = signed?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !signedStr.isEmpty else {
                    return .failure(NetworkError.decodingError("Missing signed URL in response"))
                }

                // Some deployments return a full URL; others return a path starting with "/".
                // Treat signed URLs as opaque. Do NOT rebuild with appendingPathComponent.
                if let u = URL(string: signedStr), u.scheme != nil {
    #if DEBUG
                    print("[SignedURL][DEBUG] bucket=\(bucket) path=\(path)")
                    print("[SignedURL][DEBUG] signedStr=\(signedStr)")
                    print("[SignedURL][DEBUG] finalURL=\(u.absoluteString)")
    #endif
                    return .success(u)
                }

                // Absolute path returned.
                if signedStr.hasPrefix("/") {
                    // Critical fix:
                    // Supabase may return "/object/sign/..." but the fetchable route is "/storage/v1/object/sign/..."
                    let pathWithStoragePrefix: String
                    if signedStr.hasPrefix("/object/sign/") {
                        pathWithStoragePrefix = "/storage/v1" + signedStr
                    } else {
                        pathWithStoragePrefix = signedStr
                    }

                    let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let full = base + pathWithStoragePrefix

                    guard let u = URL(string: full) else {
                        return .failure(NetworkError.invalidURL(full))
                    }
    #if DEBUG
                    print("[SignedURL][DEBUG] bucket=\(bucket) path=\(path)")
                    print("[SignedURL][DEBUG] signedStr=\(signedStr)")
                    print("[SignedURL][DEBUG] finalURL=\(u.absoluteString)")
    #endif
                    return .success(u)
                }

                // Relative (rare, but handle safely)
                let full = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    + "/"
                    + signedStr
                guard let u = URL(string: full) else {
                    return .failure(NetworkError.invalidURL(full))
                }
    #if DEBUG
                print("[SignedURL][DEBUG] bucket=\(bucket) path=\(path)")
                print("[SignedURL][DEBUG] signedStr=\(signedStr)")
                print("[SignedURL][DEBUG] finalURL=\(u.absoluteString)")
    #endif
                return .success(u)

            } catch {
                return .failure(NetworkError.decodingError(String(describing: error)))
            }

        case .failure(let e):
            return .failure(e)
        }
    }


    private func percentEncodePathSegments(_ raw: String) -> String {
        // Preserve "/" separators but percent-encode each segment.
        let trimmed = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        let encoded = parts.map { part -> String in
            // Keep empty segments as empty to preserve structure.
            if part.isEmpty { return "" }
            return String(part).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(part)
        }
        return encoded.joined(separator: "/")
    }



    // MARK: - Phase 15 Step 3A (Avatars) — backend primitives (upload/delete)

    /// Uploads (upserts) the caller's avatar JPEG to the `avatars` bucket.
    /// Storage key convention (locked): `users/<uid>/avatar.jpg`
    /// - Returns: The `avatar_key` string to store in `account_directory.avatar_key`.
    public func uploadAvatarJPEG(data: Data, backendUserID: String) async -> Result<String, Error> {
        guard let baseURL else {
            return .failure(NetworkError.notConfigured)
        }

        let uid = backendUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !uid.isEmpty else {
            return .failure(NetworkError.invalidURL("empty backendUserID"))
        }

        let key = "users/\(uid)/avatar.jpg"
        let encodedKey = percentEncodePathSegments(key)
        let path = "storage/v1/object/avatars/\(encodedKey)"

        guard let url = URL(string: path, relativeTo: baseURL) else {
            return .failure(NetworkError.invalidURL("base=\(baseURL.absoluteString) path=\(path)"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data

        // Headers (match request() behavior, but allow non-JSON bodies).
        if let apiKey = authToken, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
        }
        if let bearer = bearerToken, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }

        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")


        do {
            let (respData, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyString = String(data: respData, encoding: .utf8)
                #if DEBUG
                if let bodyString, !bodyString.isEmpty {
                    print("[NetworkManager] ◀︎ body=\(bodyString)")
                }
                #endif
                return .failure(NetworkError.httpError(status: http.statusCode, body: bodyString))
            }

            return .success(key)
        } catch {
            return .failure(NetworkError.transportError(String(describing: error)))
        }
    }

    /// Deletes the caller's avatar object from the `avatars` bucket.
    /// Storage key convention (locked): `users/<uid>/avatar.jpg`
    public func deleteAvatarObject(backendUserID: String) async -> Result<Void, Error> {
        guard let baseURL else {
            return .failure(NetworkError.notConfigured)
        }

        let uid = backendUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !uid.isEmpty else {
            return .failure(NetworkError.invalidURL("empty backendUserID"))
        }

        let key = "users/\(uid)/avatar.jpg"
        let encodedKey = percentEncodePathSegments(key)
        let path = "storage/v1/object/avatars/\(encodedKey)"

        guard let url = URL(string: path, relativeTo: baseURL) else {
            return .failure(NetworkError.invalidURL("base=\(baseURL.absoluteString) path=\(path)"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let apiKey = authToken, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
        }
        if let bearer = bearerToken, !bearer.isEmpty {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }


        do {
            let (respData, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyString = String(data: respData, encoding: .utf8)
                #if DEBUG
                if let bodyString, !bodyString.isEmpty {
                    print("[NetworkManager] ◀︎ body=\(bodyString)")
                }
                #endif
                return .failure(NetworkError.httpError(status: http.statusCode, body: bodyString))
            }

            return .success(())
        } catch {
            return .failure(NetworkError.transportError(String(describing: error)))
        }
    }

}


// CHANGE-ID: 20260210_181900_Phase15_Step2_AvatarRenderCache
// SCOPE: Phase 15 Step 2 — shared signed-URL + decoded image cache for directory avatars (read-only rendering). No upload/delete in this step.
// SEARCH-TOKEN: 20260210_181900_Phase15_Step2_AvatarRenderCache_AVATAR_CACHE

#if canImport(UIKit)
import UIKit
#endif

/// Shared cache/pipeline for remote directory avatars (bucket: 'avatars').
/// Path convention: `users/<uid>/avatar.jpg` stored in `account_directory.avatar_key`.
actor RemoteAvatarSignedURLCache {
    static let shared = RemoteAvatarSignedURLCache()

    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private var map: [String: Entry] = [:]

    func get(_ key: String) -> URL? {
        if let entry = map[key], entry.expiresAt > Date() {
            return entry.url
        }
        map.removeValue(forKey: key)
        return nil
    }

    func set(_ key: String, url: URL, ttlSeconds: Int) {
        map[key] = Entry(url: url, expiresAt: Date().addingTimeInterval(TimeInterval(ttlSeconds)))
    }

    func invalidate(_ key: String) {
        map.removeValue(forKey: key)
    }

    func resetForFactoryReset() {
        map.removeAll()
    }

}

#if canImport(UIKit)
enum RemoteAvatarImageCache {
    static let imageCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 256
        return c
    }()

    static func get(_ key: String) -> UIImage? {
        imageCache.object(forKey: key as NSString)
    }

    static func set(_ key: String, image: UIImage) {
        imageCache.setObject(image, forKey: key as NSString)
    }

    static func invalidate(_ key: String) {
        imageCache.removeObject(forKey: key as NSString)
    }

    static func resetForFactoryReset() {
        imageCache.removeAllObjects()
    }

}
#endif

/// C-34 / P4-U5. WHICH AVATAR VERSION THIS PROCESS HAS ALREADY APPLIED, PER KEY.
///
/// WHY A REGISTRY AND NOT A PARAMETER THREADED THROUGH THE VIEWS. Passing a
/// version beside every avatar key would have meant 25 call-site edits across 8
/// files, and **a missed one fails silently as a stale avatar** — which is
/// indistinguishable from the defect this exists to fix. There is no compile
/// error and no test failure for the site you forget. One lookup path cannot be
/// missed.
///
/// The key already encodes the subject (`users/<uid>/avatar.jpg`), so it is a
/// sufficient index on its own.
actor RemoteAvatarVersionRegistry {
    static let shared = RemoteAvatarVersionRegistry()

    private var applied: [String: String] = [:]

    /// Records `version` for `key` and reports whether the caches must be
    /// dropped first.
    ///
    /// FIRST SIGHT RETURNS FALSE ON PURPOSE. Nothing is cached under a key the
    /// process has never fetched, so invalidating would be a no-op that merely
    /// looked meaningful — and returning true would make every first render
    /// appear to be an invalidation.
    func shouldInvalidate(key: String, version: String?) -> Bool {
        let incoming = version ?? ""
        guard let previous = applied[key] else {
            applied[key] = incoming
            return false
        }
        guard previous != incoming else { return false }
        applied[key] = incoming
        return true
    }

    func resetForFactoryReset() { applied.removeAll() }
}

enum RemoteAvatarPipeline {
    /// Returns a decoded UIImage for a directory avatar, using shared signed URL + image caches.
    /// - Parameters:
    ///   - avatarKey: path within 'avatars' bucket (e.g. users/<uid>/avatar.jpg)
    ///   - expiresInSeconds: signed URL TTL (default mirrors remote attachment TTL used elsewhere)
    /// - Parameter version: `account_directory.avatar_version` for this key, when the
    ///   caller has it. **Optional so the four owner-side callers, which invalidate
    ///   explicitly, stay unchanged.** It is a cache-identity hint only and NEVER
    ///   reaches the storage request.
    static func fetchAvatarImageIfNeeded(avatarKey: String, version: String? = nil, expiresInSeconds: Int = 300) async -> UIImage? {
        let trimmed = avatarKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // THE CACHE-KEY FORMAT IS DELIBERATELY UNCHANGED. It is built in eight
        // other places, two of them the owner's own invalidation sites
        // (ProfileView, AuthManager); folding a version into the string would
        // have silently stopped those working. The version drops the entry
        // instead of renaming it.
        let cacheKey = "avatars|\(trimmed)"

        if await RemoteAvatarVersionRegistry.shared.shouldInvalidate(key: trimmed, version: version) {
            RemoteAvatarImageCache.invalidate(cacheKey)
            await RemoteAvatarSignedURLCache.shared.invalidate(cacheKey)
        }

        #if canImport(UIKit)
        if let cached = RemoteAvatarImageCache.get(cacheKey) {
            return cached
        }
        #endif

        let signedURL: URL
        if let cachedURL = await RemoteAvatarSignedURLCache.shared.get(cacheKey) {
            signedURL = cachedURL
        } else {
            let result = await NetworkManager.shared.createSignedStorageObjectURL(
                bucket: "avatars",
                path: trimmed,
                expiresInSeconds: expiresInSeconds
            )
            switch result {
            case .success(let url):
                await RemoteAvatarSignedURLCache.shared.set(cacheKey, url: url, ttlSeconds: expiresInSeconds)
                signedURL = url
            case .failure:
                return nil
            }
        }

        #if canImport(UIKit)
        do {
            let (data, _) = try await URLSession.shared.data(from: signedURL)
            if let ui = UIImage(data: data) {
                RemoteAvatarImageCache.set(cacheKey, image: ui)
                return ui
            }
        } catch {
            return nil
        }
        return nil
        #else
        return nil
        #endif
    }

    static func invalidateAvatarCaches(avatarKey: String) async {
        let trimmed = avatarKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cacheKey = "avatars|\(trimmed)"
        await RemoteAvatarSignedURLCache.shared.invalidate(cacheKey)
        #if canImport(UIKit)
        RemoteAvatarImageCache.invalidate(cacheKey)
        #endif
    }
}


// MARK: - Connected account deletion

@MainActor
enum ConnectedAccountDeletionService {
    enum DeletionError: LocalizedError {
        case sessionInvalid
        case missingAccessToken
        case invalidAccessToken(dotCount: Int)
        case backendNotConfigured
        case server(status: Int, body: String)
        case unexpectedResponse(String)

        var errorDescription: String? {
            switch self {
            case .sessionInvalid:
                return "Session is not valid. Please sign out, sign in, then try again."
            case .missingAccessToken:
                return "Missing Supabase session token. Please sign out and sign back in, then try again."
            case .invalidAccessToken(let dotCount):
                return "Invalid Supabase session token format (dotCount=\(dotCount)). Please sign out and sign back in, then try again."
            case .backendNotConfigured:
                return "Backend is not configured."
            case .server(let status, let body):
                return "Server returned \(status). \(body)"
            case .unexpectedResponse(let body):
                return "Unexpected response: \(body)"
            }
        }
    }

    static func deleteCurrentConnectedAccount(
        auth: AuthManager,
        reason: String
    ) async throws {
        let sessionOK = await auth.ensureValidSessionForConnectedAccountCleanup(reason: reason)
        guard sessionOK else {
            throw DeletionError.sessionInvalid
        }

        let tokenKey = "supabaseAccessToken_v1"
        guard let accessTokenRaw = Keychain.get(tokenKey), !accessTokenRaw.isEmpty else {
            throw DeletionError.missingAccessToken
        }

        let accessToken = accessTokenRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let dotCount = accessToken.filter { $0 == "." }.count
        guard dotCount == 2 else {
            throw DeletionError.invalidAccessToken(dotCount: dotCount)
        }

        guard let baseURL = BackendConfig.apiBaseURL,
              let anonKey = BackendConfig.apiToken else {
            throw DeletionError.backendNotConfigured
        }

        let functionURL: URL = {
            if let host = baseURL.host,
               host.hasSuffix(".supabase.co") {
                let projectRef = host.replacingOccurrences(of: ".supabase.co", with: "")
                if let url = URL(string: "https://\(projectRef).functions.supabase.co/delete_account_v1") {
                    return url
                }
            }

            return baseURL
                .appendingPathComponent("functions")
                .appendingPathComponent("v1")
                .appendingPathComponent("delete_account_v1")
        }()

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(anonKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DeletionError.server(status: status, body: body)
        }

        if let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let dictionary = object as? [String: Any],
           let success = dictionary["success"] as? Bool,
           success {
            return
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        throw DeletionError.unexpectedResponse(body)
    }
}

// MARK: - P6-I-02 Unit 2b — identity-bound transport

/// What a queued operation is bound to, for its whole life.
///
/// The EXPECTED OWNER comes from the queued payload and is normalised and
/// validated here, once, so no later phase can re-derive it from whoever happens
/// to be signed in. The GATE is re-evaluated before every send, every refresh and
/// every retry; it is how an operation learns that the identity beneath it has
/// changed.
public struct OperationBinding {
    public let expectedOwner: String
    public let isStillCurrent: @MainActor () -> Bool

    /// nil unless `rawOwner` is a UUID — the only shape a backend identity has.
    public init?(expectedOwner rawOwner: String?, isStillCurrent: @escaping @MainActor () -> Bool) {
        guard let owner = rawOwner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              UUID(uuidString: owner) != nil else { return nil }
        self.expectedOwner = owner
        self.isStillCurrent = isStillCurrent
    }
}

/// Why a bound request was not sent, or not retried. ALWAYS a hold for the
/// queue: never success, never "already absent", never a duplicate-409.
public enum TransportIdentityError: Error, Equatable, CustomStringConvertible {
    /// No token, a malformed token, or a token whose subject is not the owner.
    case subjectMismatch
    /// The operation's gate failed before a send, a refresh or a retry.
    case identityChanged
    /// A caller tried to supply its own Authorization header.
    case authorizationHeaderOverride

    public var description: String {
        switch self {
        case .subjectMismatch: return "TransportIdentityError.subjectMismatch"
        case .identityChanged: return "TransportIdentityError.identityChanged"
        case .authorizationHeaderOverride: return "TransportIdentityError.authorizationHeaderOverride"
        }
    }
}

/// ONE attempt's credential. Built immediately before one send and discarded
/// after it. It is OMITTED from the queue's persistence model — the payload
/// carries an owner, never a credential — and that is audited in source and
/// checked by test against the queue file; not conforming to `Codable` is not
/// itself what makes persistence impossible. Its description redacts the token,
/// which stops THIS value being interpolated into a log, and nothing more. The
/// token is `fileprivate`: nothing outside this file can read it.
struct RequestCredential: CustomStringConvertible, CustomDebugStringConvertible {
    let subject: String
    fileprivate let accessToken: String
    var description: String { "RequestCredential(subject: \(subject), token: <redacted>)" }
    var debugDescription: String { description }
}

/// Registers a URLSession task so a cancellation arriving from ANY thread, at ANY
/// moment — including before the task exists — cancels it. Cancelling a request
/// stops waiting for it; it does not undo whatever the server already did.
private final class InFlightRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    /// false if cancellation already arrived: the caller must not start the task.
    func register(_ task: URLSessionTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        self.task = task
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

extension NetworkManager {

    /// The subject of the token held RIGHT NOW, normalised, or nil.
    @MainActor
    fileprivate var currentSubject: String? {
        guard let token = bearerToken, !token.isEmpty else { return nil }
        return AuthManager.supabaseUserIDFromAccessToken(token)?.lowercased()
    }

    /// The token held now, IF its subject is `owner`. nil for no token, a
    /// malformed token, a non-UUID subject, or somebody else's token.
    @MainActor
    func credential(for owner: String) -> RequestCredential? {
        guard let token = bearerToken, !token.isEmpty,
              let subject = AuthManager.supabaseUserIDFromAccessToken(token)?.lowercased(),
              subject == owner else { return nil }
        return RequestCredential(subject: subject, accessToken: token)
    }

    /// A request sent AS `binding.expectedOwner`, or not at all.
    ///
    /// Differs from `request(...)` in exactly these ways, and in nothing else:
    ///  • every attempt takes a FRESH credential for the expected owner and never
    ///    reads the ambient token again while it is built and sent;
    ///  • the gate is checked immediately before every send, and around the
    ///    refresh — so a stale operation can neither send, nor refresh whichever
    ///    identity replaced its owner, nor retry under it;
    ///  • a caller-supplied Authorization header is refused;
    ///  • the refresh policy is otherwise UNCHANGED: 401 only, never 403, at most
    ///    one retry.
    @MainActor
    func boundRequest(path: String, method: String, query: [URLQueryItem]? = nil,
                      jsonBody: Data? = nil, headers: [String: String] = [:],
                      binding: OperationBinding) async -> Result<Data, Error> {
        if headers.keys.contains(where: { $0.caseInsensitiveCompare("Authorization") == .orderedSame }) {
            return .failure(TransportIdentityError.authorizationHeaderOverride)
        }
        let baseRequest: URLRequest
        switch buildURLRequest(path: path, method: method, query: query, jsonBody: jsonBody) {
        case .success(let built): baseRequest = built
        case .failure(let error): return .failure(error)
        }

        func attempt() async -> Result<Data, Error> {
            // THE FINAL CHECKS AND THE DISPATCH SHARE ONE SYNCHRONOUS SEGMENT.
            // `withTaskCancellationHandler` and `withCheckedContinuation` both run
            // their bodies immediately on the caller's actor, so `resume()` is
            // called on the main actor with no suspension after the cancellation
            // check, the gate and the credential.
            //
            // CANCELLATION IS PRESERVED. `URLSession.data(for:)` propagated a
            // cancelled task to the request; the continuation form does not by
            // itself, so the task is registered and cancelled explicitly — and a
            // task already cancelled starts nothing.
            if Task.isCancelled { return .failure(CancellationError()) }
            guard binding.isStillCurrent() else { return .failure(TransportIdentityError.identityChanged) }
            guard let credential = credential(for: binding.expectedOwner) else {
                return .failure(TransportIdentityError.subjectMismatch)
            }
            var request = baseRequest
            var allHeaders: [String: String] = [:]
            if let apiKey = authToken, !apiKey.isEmpty { allHeaders["apikey"] = apiKey }
            if jsonBody != nil { allHeaders["Content-Type"] = "application/json" }
            for (k, v) in headers { allHeaders[k] = v }
            // Set LAST, so nothing merged above can override it.
            allHeaders["Authorization"] = "Bearer \(credential.accessToken)"
            for (k, v) in allHeaders { request.setValue(v, forHTTPHeaderField: k) }

            let inFlight = InFlightRequest()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Result<Data, Error>, Never>) in
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        continuation.resume(returning: .failure(CancellationError()))
                        return
                    }
                    if let error {
                        continuation.resume(returning: .failure(NetworkError.transportError(String(describing: error))))
                        return
                    }
                    let body = data ?? Data()
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        continuation.resume(returning: .failure(NetworkError.httpError(status: http.statusCode,
                                                                                         body: String(data: body, encoding: .utf8))))
                        return
                    }
                    continuation.resume(returning: .success(body))
                }
                guard inFlight.register(task) else {
                    continuation.resume(returning: .failure(CancellationError()))
                    return
                }
                task.resume()
                }
            } onCancel: {
                inFlight.cancel()
            }
        }

        let first = await attempt()
        guard case .failure(let error) = first,
              let networkError = error as? NetworkError,
              case .httpError(let status, _) = networkError,
              status == 401 else {
            return first
        }

        // A cancelled operation neither refreshes nor retries.
        if Task.isCancelled { return .failure(CancellationError()) }

        // BEFORE THE REFRESH: a stale operation must not refresh whichever
        // identity replaced its owner. Checked on the gate AND on the token
        // actually held now.
        guard binding.isStillCurrent(), currentSubject == binding.expectedOwner else {
            return .failure(TransportIdentityError.identityChanged)
        }
        guard let handler = onAuthChallenge else { return first }
        let refreshed = await handler()

        // AFTER THE REFRESH, whatever it returned: an operation whose gate or
        // owner no longer holds is STALE, which is not the same outcome as a
        // genuine unchanged-owner 401 — though neither retries. A→B→A during the
        // refresh fails here on generation even though the subject is A again.
        guard binding.isStillCurrent(), currentSubject == binding.expectedOwner else {
            return .failure(TransportIdentityError.identityChanged)
        }
        guard refreshed else { return first }
        if Task.isCancelled { return .failure(CancellationError()) }
        // Exactly one retry. A second 401 is returned as it is: no second refresh.
        return await attempt()
    }
}
