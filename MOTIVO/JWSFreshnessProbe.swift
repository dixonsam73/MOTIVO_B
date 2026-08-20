//
//  JWSFreshnessProbe.swift
//  MOTIVO
//
//  PHASE 3 · U5a · F3b — TEMPORARY INSTRUMENTATION.
//
//  STANDING REMOVAL CONDITION: delete this file and its two call sites in
//  MOTIVOApp.swift the moment F3b is scored, exactly as ActivationTrace and
//  MembershipTrace were deleted. Removal is a pure deletion — nothing else
//  references this type. One UserDefaults key is left behind by design while
//  the gate runs (`u5a_jwsProbe_v1`); remove it with the file.
//
//  ── WHAT QUESTION THIS EXISTS TO ANSWER ────────────────────────────────────
//
//  U5 must decide whether a short freshness window on a client-supplied
//  transaction JWS is a viable replay control (finding F3 / decision D3). That
//  turns entirely on whether `Transaction.currentEntitlements` hands back a
//  FRESHLY SIGNED representation per read, or a STORED historical one.
//
//  APPLE'S DOCUMENTATION DOES NOT SAY. Checked 2026-08-20 against the reference
//  for `VerificationResult`, `jwsRepresentation`, `signedDate` and
//  `currentEntitlements`: none of them states when the App Store produced the
//  signature, whether a read contacts the App Store, or whether any refresh is
//  possible. The one hint points the other way — jwsRepresentation is described
//  as "the same as its counterpart in the App Store server APIs", which reads
//  like a stored artefact. A hint is not a result, which is why this is a gate
//  and not a paragraph.
//
//  ── WHAT IT MUST NOT DO ────────────────────────────────────────────────────
//
//  READ-ONLY, AND STRUCTURALLY SO. No network call, no purchase, no
//  `AppStore.sync()`, no membership establishment, no binding, no token. It
//  reads an existing local entitlement and writes log lines. It cannot mutate
//  Apple state, Supabase state, or Études state beyond its own scratch key.
//
//  ── WHY NOTHING HERE IS `#if DEBUG` ────────────────────────────────────────
//
//  Debug carries `com.samueldixon.motivo.dev`, which App Store Connect does not
//  know, so `Product.products(for:)` returns empty and no sandbox entitlement
//  can exist in that build. The ONLY build that can hold the thing this probe
//  measures is Release — which is exactly why the C-44 run could not be
//  diagnosed. `os.Logger` with `privacy: .public`, through one funnel.
//
//  ── WHAT IT LOGS, AND THE ONE THING IT DELIBERATELY DOES NOT ───────────────
//
//  NEVER THE JWS. That string is a bearer artefact: under the U5 protocol
//  possession of it is possession of the ownership proof (F3), so writing one
//  into a device log — readable over a cable, and collected wholesale by
//  `log collect` — would manufacture the exact leak U5 is designed around. Only
//  a 12-hex-character SHA-256 prefix is emitted: sufficient to answer "same
//  bytes or different bytes", useless as a credential.
//
//  `originalTransactionId` IS logged in full, deliberately. B-24 settled that it
//  carries no secrecy property — it appears in receipts, support mail and
//  Apple's own email — and correlation across launches needs it.
//

import Foundation
import StoreKit
import CryptoKit
import os

enum JWSFreshnessProbe {

    private static let log = Logger(subsystem: "com.sdsongs.etudes", category: "u5a")

    /// Survives across launches so the cold-launch comparison is a LOGGED FACT
    /// rather than something the tester reconstructs by diffing console lines by
    /// eye. Three device runs in this project have already been misread because
    /// the first observation involved a cache; a self-scoring probe removes one
    /// way to do that again.
    private static let stateKey = "u5a_jwsProbe_v1"

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// One read of `currentEntitlements`, one log line per entitlement, plus a
    /// verdict line comparing against the previous read.
    ///
    /// `reason` is a short closed-set label — `launch1`, `launch2`, `foreground`
    /// — so the log is greppable and no free text reaches it.
    static func run(reason: String) async {
        let now = Date()
        var seen = 0

        for await result in Transaction.currentEntitlements {
            seen += 1

            let jws = result.jwsRepresentation
            let signedDate = result.signedDate
            let tx = result.unsafePayloadValue      // shape only; never trusted
            let verified: Bool
            switch result {
            case .verified:   verified = true
            case .unverified: verified = false
            @unknown default: verified = false
            }

            let digest = SHA256.hash(data: Data(jws.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            let short = String(digest.prefix(12))
            let ageSeconds = Int(now.timeIntervalSince(signedDate))

            // `environment` is load-bearing rather than decorative. A run that
            // reports `Xcode` was made against a pinned StoreKit configuration
            // and is signed by Xcode's local test certificate, not Apple's — so
            // its freshness behaviour says nothing about Apple's. That is the
            // F1 trap, and this line is how a reader catches it in the evidence
            // instead of trusting the tester's memory of Run → Options.
            let environment = tx.environment.rawValue

            // `Transaction.originalID` is a UInt64 on device; the server-side
            // payload field `originalTransactionId` is its decimal string. Keep
            // the string form so the log correlates directly against
            // membership.original_transaction_id without a mental conversion.
            let originalID = String(tx.originalID)

            // THE RENEWAL CONFOUND, AND WHY THIS FIELD DECIDES THE GATE.
            //
            // `originalID` is stable across the whole subscription, so on its
            // own it CANNOT tell a re-signature apart from a renewal — and the
            // development sandbox honours the tester's accelerated renewal
            // rate, so a Monthly cycle can complete inside this gate's own
            // ten-minute step. A renewal legitimately produces a new
            // transaction with a new signature, which would read as
            // `RESIGNED` and would have been scored as "StoreKit re-signs on
            // read". That is a wrong answer arrived at honestly, and it would
            // have selected a freshness window the design cannot support.
            //
            // `Transaction.id` changes on renewal and does not change on a
            // re-signature, so it separates the two. A step whose `txID` moved
            // is a RENEWAL and is not evidence about freshness at all.
            let txID = String(tx.id)
            let expires = tx.expirationDate.map { iso.string(from: $0) } ?? "-"

            let previous = load(for: originalID)
            let verdict: String
            if let previous {
                let sameBytes = previous.digest == short
                let sameDate = abs(previous.signedDate.timeIntervalSince(signedDate)) < 0.5
                if previous.txID != txID {
                    // Checked FIRST. Everything below assumes one transaction.
                    verdict = "RENEWED_notEvidence"
                } else {
                    switch (sameBytes, sameDate) {
                    case (true, true):   verdict = "UNCHANGED"
                    case (false, false): verdict = "RESIGNED"
                    case (false, true):  verdict = "ANOMALY_bytesChangedDateSame"
                    case (true, false):  verdict = "ANOMALY_dateChangedBytesSame"
                    }
                }
            } else {
                verdict = "FIRST"
            }

            log.notice("""
                [U5a/F3b] reason=\(reason, privacy: .public) \
                env=\(environment, privacy: .public) \
                verified=\(verified, privacy: .public) \
                product=\(tx.productID, privacy: .public) \
                originalID=\(originalID, privacy: .public) \
                txID=\(txID, privacy: .public) \
                expires=\(expires, privacy: .public) \
                now=\(iso.string(from: now), privacy: .public) \
                signedDate=\(iso.string(from: signedDate), privacy: .public) \
                ageSeconds=\(ageSeconds, privacy: .public) \
                jwsSha256=\(short, privacy: .public) \
                jwsBytes=\(jws.utf8.count, privacy: .public) \
                vsPrevious=\(verdict, privacy: .public)
                """)

            save(originalID: originalID, txID: txID, digest: short, signedDate: signedDate)
        }

        if seen == 0 {
            // NOT A PASS AND NOT A FAILURE — an absent fixture. Logged so the
            // run cannot be silently scored against an empty sequence, which is
            // the U4 `E0` lesson: an uncreated fixture is not a result.
            log.notice("""
                [U5a/F3b] reason=\(reason, privacy: .public) \
                entitlements=0 NOFIXTURE \
                now=\(iso.string(from: now), privacy: .public)
                """)
        }
    }

    // MARK: - Cross-launch scratch

    private struct Snapshot {
        let txID: String
        let digest: String
        let signedDate: Date
    }

    private static func load(for originalID: String) -> Snapshot? {
        guard let all = UserDefaults.standard.dictionary(forKey: stateKey),
              let row = all[originalID] as? [String: Any],
              let digest = row["digest"] as? String,
              let txID = row["txID"] as? String,
              let signed = row["signedDate"] as? Double else { return nil }
        return Snapshot(txID: txID, digest: digest,
                        signedDate: Date(timeIntervalSince1970: signed))
    }

    private static func save(originalID: String, txID: String,
                             digest: String, signedDate: Date) {
        var all = UserDefaults.standard.dictionary(forKey: stateKey) ?? [:]
        all[originalID] = ["txID": txID, "digest": digest,
                           "signedDate": signedDate.timeIntervalSince1970]
        UserDefaults.standard.set(all, forKey: stateKey)
    }
}
