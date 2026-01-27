//
//  NetworkManager.swift
//  MOTIVO
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

    /// Optional auth challenge handler used to refresh a session after a 401/403.
    /// If it returns true, the original request will be retried once.
    public var onAuthChallenge: (() async -> Bool)? = nil

    /// Legacy configure: treats `authToken` as the project API key (publishable key).
    public func configure(baseURL: URL?, authToken: String?) {
        self.baseURL = baseURL
        self.authToken = authToken
        print("[NetworkManager] configured baseURL=\(String(describing: baseURL)) apiKey=•••")
    }

    /// Step 7: set bearer token (Supabase access token).
    /// Accepts either raw JWT or "Bearer <JWT>" and normalizes to raw JWT.
    public func setBearerToken(_ token: String?) {
        var t = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tt = t, tt.lowercased().hasPrefix("bearer ") {
            t = String(tt.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        bearerToken = (t?.isEmpty == true) ? nil : t
        print("[NetworkManager] bearer token \(bearerToken != nil ? "set" : "cleared")")
#if DEBUG
        if let jwt = bearerToken {
            print("[Auth][DEBUG] access_token=\(jwt)")
        }
#endif
    }

    /// Compatibility shim: AuthManager expects this.
    public func clearBearerToken() {
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

    
    public func request(
        path: String,
        method: String,
        query: [URLQueryItem]? = nil,
        jsonBody: Data? = nil,
        headers: [String:String] = [:]
    ) async -> Result<Data, Error> {

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

            // Logging (no tokens printed)
            print("[NetworkManager] ▶︎ \(method) \(finalURL.absoluteString)")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[NetworkManager] ◀︎ status=\(status) for \(finalURL.lastPathComponent)")

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

        // Auth-challenge path: refresh session and retry once on 401/403.
        if case .failure(let err) = first,
           let ne = err as? NetworkError,
           case .httpError(let status, _) = ne,
           (status == 401 || status == 403),
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

}
