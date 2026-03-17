// CHANGE-ID: 20260317_091500_AppSettings_AccountActions_Move
// SCOPE: Move Sign out + Delete account actions into AppSettingsView; remove Session Timer section; no auth/delete behavior changes.
// SEARCH-TOKEN: 20260317_091500_AppSettings_AccountActions_Move

import SwiftUI
import Foundation

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager

    // Global app UI toggles (UserDefaults-backed via AppStorage)
    @AppStorage("appSettings_showWelcomeSection") private var showWelcomeSection: Bool = true

    @State private var showDeleteAccountSheet: Bool = false
    @State private var deleteAccountConfirmText: String = ""
    @State private var deleteAccountInFlight: Bool = false
    @State private var deleteAccountErrorMessage: String? = nil
    @State private var showDeleteAccountErrorAlert: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Profile").sectionHeader()) {
                    Toggle(isOn: $showWelcomeSection) {
                        Text("Show Welcome Message")
                            .font(Theme.Text.body)
                    }
                    .tint(Theme.Colors.accent)
                }

                Section(header: Text("Account").sectionHeader()) {
                    Button {
                        auth.signOut()
                    } label: {
                        Text("Sign out")
                            .font(Theme.Text.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Button {
                        deleteAccountConfirmText = ""
                        showDeleteAccountSheet = true
                    } label: {
                        Text("Delete account")
                            .font(Theme.Text.body)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("App Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("App Settings")
                        .font(Theme.Text.pageTitle)
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Text("Close")
                            .font(Theme.Text.body)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .appBackground()
            .alert("Delete account failed", isPresented: $showDeleteAccountErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountErrorMessage ?? "Couldn’t delete your account. Please try again.")
            }
            .sheet(isPresented: $showDeleteAccountSheet) {
                deleteAccountSheet
            }
        }
    }

    private var deleteAccountSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes your account and removes your backend data. Local app data on this device will also be cleared.")
                        .font(Theme.Text.body)
                        .foregroundStyle(.primary)
                }

                Section(header: Text("Type DELETE to confirm").sectionHeader()) {
                    TextField("DELETE", text: $deleteAccountConfirmText)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await performDeleteAccount() }
                    } label: {
                        HStack {
                            Spacer()
                            if deleteAccountInFlight {
                                ProgressView()
                            }
                            Text(deleteAccountInFlight ? "Deleting…" : "Delete account")
                                .font(Theme.Text.body.weight(.semibold))
                            Spacer()
                        }
                    }
                    .disabled(deleteAccountInFlight || deleteAccountConfirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE")
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDeleteAccountSheet = false
                    }
                }
            }
        }
    }

    private func performDeleteAccount() async {
        guard BackendEnvironment.shared.isConnected else {
            deleteAccountErrorMessage = "Delete Account is only available in Connected mode."
            showDeleteAccountErrorAlert = true
            return
        }

        let sessionOK = await auth.ensureValidSession(reason: "delete-account")
        guard sessionOK else {
            deleteAccountErrorMessage = "Session is not valid. Please sign out, sign in, then try again."
            showDeleteAccountErrorAlert = true
            return
        }

        let tokenKey = "supabaseAccessToken_v1"
        guard let accessTokenRaw = Keychain.get(tokenKey), accessTokenRaw.isEmpty == false else {
            deleteAccountErrorMessage = "Missing Supabase session token. Please sign out and sign back in, then try again."
            showDeleteAccountErrorAlert = true
            return
        }

        let accessToken = accessTokenRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let dotCount = accessToken.filter { $0 == "." }.count
        guard dotCount == 2 else {
            deleteAccountErrorMessage = "Invalid Supabase session token format (dotCount=\(dotCount)). Please sign out and sign back in, then try again."
            showDeleteAccountErrorAlert = true
            return
        }

        guard let baseURL = BackendConfig.apiBaseURL, let anonKey = BackendConfig.apiToken else {
            deleteAccountErrorMessage = "Backend is not configured."
            showDeleteAccountErrorAlert = true
            return
        }

        deleteAccountInFlight = true
        defer { deleteAccountInFlight = false }

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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            if status != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                deleteAccountErrorMessage = "Server returned \(status). \(body)"
                showDeleteAccountErrorAlert = true
                return
            }

            if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
               let dict = obj as? [String: Any],
               let ok = dict["success"] as? Bool,
               ok == true {
                showDeleteAccountSheet = false
                await LocalFactoryReset.perform(reason: "delete-account-success", auth: auth)
                return
            }

            let body = String(data: data, encoding: .utf8) ?? ""
            deleteAccountErrorMessage = "Unexpected response: \(body)"
            showDeleteAccountErrorAlert = true
        } catch {
            deleteAccountErrorMessage = String(describing: error)
            showDeleteAccountErrorAlert = true
        }
    }
}
