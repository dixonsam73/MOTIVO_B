//
//  APIConfigView.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-APIConfigView-cc84-fix2
//  SCOPE: v7.12D — Debug UI for base URL & token
//

import SwiftUI

public struct APIConfigView: View {
    @State private var baseURLText: String = (UserDefaults.standard.string(forKey: BackendConfigKeys.baseURL) ?? "")
    @State private var tokenText: String   = (UserDefaults.standard.string(forKey: BackendConfigKeys.token) ?? "")
    @State private var status: String = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Configuration").font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Base URL").font(.subheadline)
                TextField("https://api.example.com", text: $baseURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Token").font(.subheadline)
                SecureField("Bearer token", text: $tokenText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
            }

            HStack {
                Button("Save & Apply") {
                    UserDefaults.standard.set(baseURLText, forKey: BackendConfigKeys.baseURL)
                    UserDefaults.standard.set(tokenText,   forKey: BackendConfigKeys.token)
                    BackendConfig.apply()
                    status = "Saved. Applied to NetworkManager."
                    BackendLogger.notice("Saved API config • baseURL=\(BackendConfig.apiBaseURL?.absoluteString ?? "nil") • tokenSet=\(BackendConfig.apiToken?.isEmpty == false)")
                }
                Button("Test Handshake") {
                    BackendConfig.apply()
                    // ✅ Unified log (shows in Xcode 26 and Console.app)
                    BackendLogger.notice("Handshake • mode=\(String(describing: currentBackendMode())) • baseURL=\(BackendConfig.apiBaseURL?.absoluteString ?? "nil") • tokenSet=\(BackendConfig.apiToken?.isEmpty == false)")
                    Task { @MainActor in
                        await BackendDiagnostics.shared.simulatedCall("APIConfigView.testHandshake", meta: [
                            "baseURL": UserDefaults.standard.string(forKey: BackendConfigKeys.baseURL) ?? "",
                            "tokenSet": (UserDefaults.standard.string(forKey: BackendConfigKeys.token)?.isEmpty == false ? "yes" : "no")
                        ])
                        status = "Handshake invoked — check console / Console.app logs."
                    }
                }
            }

            if !status.isEmpty {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
