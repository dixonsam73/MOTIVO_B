// TEMPORARY INSTRUMENTATION — C-44, empirical gate (a). DELETE ON RESULT.
//
// Standing condition, same as ActivationTrace.swift and MembershipTrace.swift
// before it: this file and its single call site come out the moment the
// question is answered. Nothing of it ships. Remove by `git restore` of
// ProfileView.swift plus deletion of this file, never by hand-editing the
// call site back out.
//
// THE ONE QUESTION IT ANSWERS
//
// Does a REPEAT native Sign in with Apple authorization — for an Apple Account
// that is already authorized for this client — return a non-nil
// `authorizationCode`?
//
// Apple does not state the answer anywhere. TN3194 confirms that repeat
// authorization is a normal flow and scopes the suppression to name and email
// ("they won't be presented with the initial authorization flow to enter their
// full name, email address, or both"), which implies the code is still issued.
// That is inference. The entire store-nothing revocation design rests on it:
// if the code is nil on a repeat authorization, there is nothing to exchange
// at deletion time and TN3194's stored-refresh-token flow becomes mandatory
// instead — a different, much larger piece of work touching the sign-in path.
//
// NON-DESTRUCTIVE BY CONSTRUCTION, WHICH IS THE POINT
//
// This deliberately does NOT route through `AuthManager.handle(_:)` or
// `process(_:)`. It owns its own `ASAuthorizationController` and drops the
// credential on the floor. Specifically it does not:
//
//   - write any Keychain item (the one Keychain access is a READ of
//     `appleUserID`, for the identity comparison);
//   - call `signInToSupabaseIfPossible`, or make any network request at all;
//   - touch `PersistenceController.currentUserID` or adopt any session;
//   - read or publish entitlement, `AppMode` or `BackendEnvironment` state.
//
// It therefore cannot consume Device B's lapsed-member fixture, which lives in
// the Supabase account and the Apple Account's subscription state — neither of
// which this code can reach.
//
// THE AUTHORIZATION CODE IS NEVER LOGGED, PRINTED, PERSISTED OR RETURNED.
// Only its presence and byte count leave this file. `credential.user` is
// compared against the stored value and only the boolean result is emitted;
// the identifier itself is never logged either.
//
// Readable in Release via os.Logger with `privacy: .public`, per the lesson
// recorded in CLAUDE.md — NSLog with %@ arrives as <private> off-device. Every
// line goes through the single `emit` funnel for that reason.

import AuthenticationServices
import Foundation
import UIKit
import os

final class C44Probe: NSObject, ObservableObject {

    @MainActor static let shared = C44Probe()

    /// Mirrored to the UI so the result is legible on the device itself, not
    /// only in the Xcode console. Belt and braces: the console is the record.
    @Published var lastResult: String = "not run"

    private let log = Logger(subsystem: "com.sdsongs.etudes", category: "c44probe")

    /// `ASAuthorizationController` is not retained by `performRequests()`.
    private var controller: ASAuthorizationController?

    private func emit(_ line: String) {
        log.notice("[C44] \(line, privacy: .public)")
        Task { @MainActor in self.lastResult = line }
    }

    @MainActor
    func run() {
        // Scopes deliberately EMPTY. This mirrors the authorization the real
        // deletion path would perform: we want the code, not the name, and
        // asking for personal details inside a deletion gesture would be both
        // pointless (Apple suppresses it for an authorized user) and wrong-
        // looking. No nonce either — the probe never uses the identity token.
        //
        // CONTINGENCY: if this reports `authorizationCodePresent=false`, re-run
        // once with `[.fullName, .email]` before concluding anything. That
        // discriminates "repeat authorizations carry no code" from "empty
        // scopes carry no code", and those have completely different
        // consequences for the design.
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        emit("probe.start scopes=none")
        controller.performRequests()
    }
}

extension C44Probe: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { Task { @MainActor in self.controller = nil } }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            emit("probe.result authorization=success credential=unexpectedType")
            return
        }

        // Read-only. Never written back.
        let stored = Keychain.get("appleUserID")
        let identityMatch: String
        if let stored, !stored.isEmpty {
            identityMatch = credential.user == stored ? "true" : "false"
        } else {
            identityMatch = "noStoredValue"
        }

        // Presence and length only. The value never leaves this scope.
        let code = credential.authorizationCode

        emit(
            "probe.result authorization=success"
            + " identityMatchesStored=\(identityMatch)"
            + " authorizationCodePresent=\(code != nil)"
            + " authorizationCodeBytes=\(code?.count ?? 0)"
            + " identityTokenPresent=\(credential.identityToken != nil)"
            + " fullNamePresent=\(credential.fullName != nil)"
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { Task { @MainActor in self.controller = nil } }

        // Code and domain only. `localizedDescription` is not emitted: it is
        // free-form text from the system and is not worth the risk of it
        // carrying an account identifier into a log we read in public.
        let nsError = error as NSError
        let code = (error as? ASAuthorizationError).map { String($0.code.rawValue) } ?? "n/a"
        emit("probe.result authorization=failure asAuthorizationErrorCode=\(code) domain=\(nsError.domain) code=\(nsError.code)")
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
