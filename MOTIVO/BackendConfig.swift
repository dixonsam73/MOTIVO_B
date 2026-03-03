//
//  BackendConfig.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-BackendConfig-b31f
//  SCOPE: v7.12D — Centralized baseURL/token storage
//
//  CHANGE-ID: 20260303_092100_DeleteAccountV2_Stage2_BackendConfig_QueueStop
//  SCOPE: Delete Account v2 Stage 2 — add factory-reset wipe for backend config (no behavior change unless called)
//  SEARCH-TOKEN: 20260303_092100-DELETE-ACCOUNT-V2-STAGE2
//

//
//  CHANGE-ID: 20260303_173500_DeleteAccountV2_Stage6_RuntimeBootstrap
//  SCOPE: Delete Account v2 Stage 6 — add runtime backend config bootstrap helper used after factory reset to re-enable AppSetup gating without restart. No other behavior change.
//  SEARCH-TOKEN: 20260303_173500-DELETE-ACCOUNT-V2-STAGE6-RUNTIMEBOOTSTRAP
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

    public static func wipePersistedConfigForFactoryReset() {
        let d = UserDefaults.standard
        d.removeObject(forKey: BackendConfigKeys.baseURL)
        d.removeObject(forKey: BackendConfigKeys.token)
        apply()
    }



    // MARK: - Delete Account v2 (Local Factory Reset)

    /// Re-applies bundled backend configuration (SUPABASE_URL / SUPABASE_ANON_KEY) if config is missing.
    /// This mirrors MOTIVOApp.init() bootstrap, but is callable at runtime so AppSetup gating works immediately
    /// after a factory reset without requiring an app restart.
    ///
    /// Best-effort: if bundle keys are missing, this does nothing.
    public static func bootstrapFromBundleIfNeededForFactoryReset() {
        // If already configured, just ensure NetworkManager is in sync.
        if isConfigured {
            apply()
            return
        }

        let rawURL = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawURL.isEmpty, !rawKey.isEmpty else {
            NSLog("[BackendConfig] bootstrapFromBundleIfNeededForFactoryReset — skipped (missing bundle keys)")
            apply()
            return
        }

        let d = UserDefaults.standard
        d.set(rawURL, forKey: BackendConfigKeys.baseURL)
        d.set(rawKey, forKey: BackendConfigKeys.token)

        apply()
        NSLog("[BackendConfig] bootstrapFromBundleIfNeededForFactoryReset — applied bundled config")
    }

    public static func apply() {
        NetworkManager.shared.configure(baseURL: apiBaseURL, authToken: apiToken)
    }
}
