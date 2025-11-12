//
//  BackendConfig.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-BackendConfig-b31f
//  SCOPE: v7.12D — Centralized baseURL/token storage
//

import Foundation

public enum BackendConfigKeys {
    public static let baseURL = "api_base_url_v1"
    public static let token   = "api_token_v1"
}

public enum BackendConfig {
    public static var apiBaseURL: URL? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: BackendConfigKeys.baseURL),
                  let url = URL(string: raw), !raw.isEmpty else { return nil }
            return url
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString ?? "", forKey: BackendConfigKeys.baseURL)
        }
    }

    public static var apiToken: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: BackendConfigKeys.token)
            return (raw?.isEmpty == true) ? nil : raw
        }
        set {
            UserDefaults.standard.set(newValue ?? "", forKey: BackendConfigKeys.token)
        }
    }

    public static var isConfigured: Bool {
        apiBaseURL != nil && (apiToken?.isEmpty == false)
    }

    public static func apply() {
        NetworkManager.shared.configure(baseURL: apiBaseURL, authToken: apiToken)
    }
}
