//
//  NetworkManager.swift
//  MOTIVO
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

    // Placeholder properties for future handshake
    public var baseURL: URL? = nil
    public var authToken: String? = nil

    public func configure(baseURL: URL?, authToken: String?) {
        self.baseURL = baseURL
        self.authToken = authToken
        print("[NetworkManager] configured baseURL=\(String(describing: baseURL)) token=\(authToken != nil ? "•••" : "nil")")
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
                if let body, !body.isEmpty { return "HTTP \(status): \(body)" }
                return "HTTP \(status)"
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
        // Ensure configured
        guard let baseURL else {
            return .failure(NetworkError.notConfigured)
        }

        // Build URL
        // Join path safely whether it starts with "/" or not
        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var url = baseURL
        url.appendPathComponent(sanitizedPath)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let query, !query.isEmpty {
            components?.queryItems = query
        }
        guard let finalURL = components?.url else {
            return .failure(NetworkError.invalidURL("base=\(baseURL.absoluteString) path=\(path)"))
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method

        // Headers
        var allHeaders: [String:String] = [:]
        if let token = authToken, !token.isEmpty {
            allHeaders["Authorization"] = "Bearer \(token)"
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
            // Transport level
            return .failure(NetworkError.transportError(String(describing: error)))
        }
    }

    // MARK: - JSON Helpers
    public func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, Error> {
        do {
            let decoder = JSONDecoder()
            let value = try decoder.decode(T.self, from: data)
            return .success(value)
        } catch {
            return .failure(NetworkError.decodingError(String(describing: error)))
        }
    }

    public func encodeJSON<T: Encodable>(_ value: T) -> Result<Data, Error> {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = []
            let data = try encoder.encode(value)
            return .success(data)
        } catch {
            return .failure(NetworkError.encodingError(String(describing: error)))
        }
    }
}
