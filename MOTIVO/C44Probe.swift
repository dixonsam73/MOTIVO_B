// TEMPORARY INSTRUMENTATION — C-44, empirical gate (b2). DELETE ON RESULT.
//
// Standing condition, as with gate (a): this file and its single call site come
// out the moment the question is answered, by `git restore` of ProfileView.swift
// and deletion of this file — never by hand-editing the call site back out.
//
// THE ONE QUESTION IT ANSWERS
//
// Does a REAL native authorization code exchange at Apple's /auth/token with
// client_id = com.sdsongs.etudes and no redirect_uri? Gate (b1) showed the
// request shape is accepted and our ES256 client secret is valid; only a real
// code can show an exchange actually succeeding.
//
// THE AUTHORIZATION CODE IS NEVER LOGGED, PRINTED, DISPLAYED OR PERSISTED.
// It goes straight from the credential into the request body of a single HTTPS
// call to our own Edge Function and is then dropped. What gets logged is the
// function's response, which by construction contains only booleans.
//
// NON-DESTRUCTIVE, as before: this does not route through AuthManager.handle /
// process. It writes no Keychain item, starts no Supabase session, adopts no
// sessions, and touches no entitlement, AppMode or BackendEnvironment state.
// It READS the Supabase access token from the Keychain to authenticate the
// call, exactly as ConnectedAccountDeletionService does, and reads appleUserID
// for the identity comparison.

import AuthenticationServices
import Foundation
import UIKit
import os

final class C44Probe: NSObject, ObservableObject {

    @MainActor static let shared = C44Probe()

    @Published var lastResult: String = "not run"

    private let log = Logger(subsystem: "com.sdsongs.etudes", category: "c44probe")
    private var controller: ASAuthorizationController?

    private func emit(_ line: String) {
        log.notice("[C44] \(line, privacy: .public)")
        Task { @MainActor in self.lastResult = line }
    }

    @MainActor
    func run() {
        // Scopes empty, mirroring the authorization the real deletion path
        // would perform. Verified in gate (a) to still return a code.
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        emit("b2.start scopes=none")
        controller.performRequests()
    }

    /// Posts the code to `c44_exchange_probe` and logs only the response.
    /// The `code` parameter is never logged, stored or echoed.
    private func exchange(code: String) async {
        guard let baseURL = BackendConfig.apiBaseURL,
              let anonKey = BackendConfig.apiToken else {
            emit("b2.result stage=preflight error=backendNotConfigured")
            return
        }
        guard let accessToken = Keychain.get("supabaseAccessToken_v1"),
              !accessToken.isEmpty else {
            emit("b2.result stage=preflight error=noSupabaseSession")
            return
        }

        // Same URL construction as ConnectedAccountDeletionService.
        let functionURL: URL = {
            if let host = baseURL.host, host.hasSuffix(".supabase.co") {
                let ref = host.replacingOccurrences(of: ".supabase.co", with: "")
                if let url = URL(string: "https://\(ref).functions.supabase.co/c44_exchange_probe") {
                    return url
                }
            }
            return baseURL
                .appendingPathComponent("functions")
                .appendingPathComponent("v1")
                .appendingPathComponent("c44_exchange_probe")
        }()

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["authorization_code": code]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            // The response body is booleans by construction, so it is safe to
            // log verbatim. Nothing else about this call is logged.
            let body = String(data: data, encoding: .utf8) ?? "<undecodable>"
            emit("b2.result httpStatus=\(status) body=\(body)")
        } catch {
            emit("b2.result stage=transport error=\((error as NSError).domain)/\((error as NSError).code)")
        }
    }
}

extension C44Probe: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { Task { @MainActor in self.controller = nil } }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            emit("b2.result authorization=success credential=unexpectedType")
            return
        }

        let stored = Keychain.get("appleUserID")
        let identityMatch: String
        if let stored, !stored.isEmpty {
            identityMatch = credential.user == stored ? "true" : "false"
        } else {
            identityMatch = "noStoredValue"
        }

        guard let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8), !code.isEmpty else {
            emit("b2.result authorization=success identityMatchesStored=\(identityMatch) authorizationCodePresent=false")
            return
        }

        emit("b2.authorized identityMatchesStored=\(identityMatch) authorizationCodePresent=true — exchanging")

        // Apple gives five minutes and one use. The hop is seconds.
        Task { await self.exchange(code: code) }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { Task { @MainActor in self.controller = nil } }
        let nsError = error as NSError
        let code = (error as? ASAuthorizationError).map { String($0.code.rawValue) } ?? "n/a"
        emit("b2.result authorization=failure asAuthorizationErrorCode=\(code) domain=\(nsError.domain) code=\(nsError.code)")
    }
}

extension C44Probe: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        return window ?? ASPresentationAnchor()
    }
}
