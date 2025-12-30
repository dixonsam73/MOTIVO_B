//
//  NetworkManager.swift
//  MOTIVO
//
//  CHANGE-ID: 20251230_Step7_NetworkManager_SupabaseHeaders_193205-1c21
//  SCOPE: Step 7 — add Supabase-ready header handling (apikey + bearer); keep legacy configure(baseURL:authToken:) compatibility
//
//  CHANGE-ID: 20251230-NetworkManager-minHTTP-a1
//  SCOPE: v7.13 — minimal HTTP JSON helper, offline-safe
//
//  CHANGE-ID: 20251112-NetworkManager-7c3d
//  SCOPE: v7.12C — placeholder singleton, no real networking
//

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

    /// Legacy configure: treats `authToken` as the project API key (publishable key).
    public func configure(baseURL: URL?, authToken: String?) {
        self.baseURL = baseURL
        self.authToken = authToken
        print("[NetworkManager] configured baseURL=\(String(describing: baseURL)) apiKey=\(authToken != nil ? "•••" : "nil")")
    }

    /// Step 7: apply/clear a bearer token used for RLS-protected requests.
    public func setBearerToken(_ token: String?) {
        bearerToken = (token?.isEmpty == true) ? nil : token
        print("[NetworkManager] bearer token \(bearerToken != nil ? "set" : "cleared")")
    }

    public func clearBearerToken() {
        setBearerToken(nil)
    }

    // MARK: - Errors

    public enum NetworkError: Error, CustomStringConvertible {
        case notConfigured
        case invalidURL(String)
        case httpError(status: Int, body: String?)
        case decodingError(String)
        case encodingError(String)
        case transportError(String)

        public var description: String {
            switch self {
            case .notConfigured:
                return "NetworkManager not configured: baseURL is nil."
            case .invalidURL(let s):
                return "Invalid URL: \(s)"
            case .httpError(let status, let body):
                return "HTTP error \(status) body=\(body ?? "<nil>")"
            case .decodingError(let msg):
                return "Decoding error: \(msg)"
            case .encodingError(let msg):
                return "Encoding error: \(msg)"
            case .transportError(let msg):
                return "Transport error: \(msg)"
            }
        }
    }

    // MARK: - Request

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
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL.appendingPathComponent(trimmed), resolvingAgainstBaseURL: false) else {
            return .failure(NetworkError.invalidURL("base=\(baseURL.absoluteString) path=\(path)"))
        }
        if let query, !query.isEmpty {
            components.queryItems = query
        }
        guard let finalURL = components.url else {
            return .failure(NetworkError.invalidURL("base=\(baseURL.absoluteString) path=\(path)"))
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method

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

        if let jsonBody {
            request.httpBody = jsonBody
            allHeaders["Content-Type"] = "application/json"
        }

        // Merge custom headers (custom overrides defaults if key duplicates)
        for (k, v) in headers { allHeaders[k] = v }
        for (k, v) in allHeaders { request.setValue(v, forHTTPHeaderField: k) }

        // Logging (no tokens printed)
        print("[NetworkManager] ▶︎ \(method) \(finalURL.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[NetworkManager] ◀︎ status=\(status) for \(finalURL.lastPathComponent)")

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyString = String(data: data, encoding: .utf8)
                return .failure(NetworkError.httpError(status: http.statusCode, body: bodyString))
            }
            return .success(data)
        } catch {
            return .failure(NetworkError.transportError(String(describing: error)))
        }
    }

    // MARK: - JSON Helpers

    public func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, Error> {
        do {
            let decoded = try JSONDecoder().decode(type, from: data)
            return .success(decoded)
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
}
