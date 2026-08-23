//
//  MOTIVOTests.swift
//  MOTIVOTests
//
//  Created by Samuel Dixon on 09/09/2025.
//
//  PHASE 3 · U5e — the first real tests in this target.
//
//  SCOPE IS DELIBERATELY NARROW: the PURE pieces of the membership client, and
//  nothing that needs a network, a session, StoreKit or a running app. Those are
//  covered where they can actually be exercised — the server suites for the
//  protocol, and genuine Sandbox for Apple. A test here that faked StoreKit would
//  assert the fake.
//
//  THE TESTS ARE @MainActor because both services are, so their static members
//  are main-actor-isolated. Annotating the tests keeps the shipping types'
//  concurrency surface untouched — the pure helpers could reasonably be
//  `nonisolated`, but that is a design change and not what this unit is for.
//

import Foundation
import Testing
// The app's Swift module is `Etudes` (PRODUCT_MODULE_NAME), not `MOTIVO`. The
// generated template said `MOTIVO` and has been wrong since the product rename —
// the SECOND half of C-54, and invisible for the same reason as the first: the
// target could never be built, so neither stale reference was ever reached.
@testable import Etudes

// MARK: - The attestation request body

@MainActor
@Test("the request body carries the JWS and NOTHING else")
func attestationBodyIsJwsOnly() throws {
    let jws = "header.payload.signature"
    let data = try #require(MembershipAttestationService.requestBody(jws: jws))
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    // THE LOAD-BEARING ASSERTION. No user id, no environment, no
    // originalTransactionId, no product. The server derives identity from the
    // verified JWT and every Apple fact from the verified claims; anything else
    // we sent would be the bare-identifier bypass B-24 exists to forbid.
    #expect(object.keys.sorted() == ["jws"])
    #expect(object["jws"] as? String == jws)
}

@MainActor
@Test("no client-supplied identity or Apple key can be smuggled into the body")
func attestationBodyHasNoIdentityFields() throws {
    let data = try #require(MembershipAttestationService.requestBody(jws: "a.b.c"))
    let text = String(decoding: data, as: UTF8.self)
    for forbidden in [
        "user_id", "uid", "environment", "original_transaction_id",
        "originalTransactionId", "product_id", "app_account_token",
    ] {
        #expect(!text.contains(forbidden), "body must not carry \(forbidden)")
    }
}

// MARK: - Outcome mapping

@MainActor
@Test("every server outcome maps to exactly one client outcome")
func outcomeMapping() {
    func parse(_ status: Int, _ body: String) -> MembershipAttestationService.Outcome {
        MembershipAttestationService.parseOutcome(status: status, data: Data(body.utf8))
    }

    #expect(parse(200, #"{"outcome":"established"}"#) == .established)
    #expect(parse(200, #"{"outcome":"already_established"}"#) == .alreadyEstablished)
    #expect(parse(200, #"{"outcome":"conflict"}"#) == .conflict)
    #expect(parse(200, #"{"outcome":"pending"}"#) == .pending)
    #expect(parse(502, #"{"error":"apple unavailable"}"#) == .appleUnavailable)

    #expect(
        parse(200, #"{"outcome":"terminal_refusal","reason":"family_transaction_not_supported"}"#)
            == .terminalRefusal(reason: "family_transaction_not_supported")
    )
    #expect(
        parse(422, #"{"category":"foreign_app","terminal":true}"#)
            == .claimRefused(category: "foreign_app", terminal: true)
    )
    #expect(
        parse(422, #"{"category":"environment","terminal":false}"#)
            == .claimRefused(category: "environment", terminal: false)
    )
}

@MainActor
@Test("an UNRECOGNISED 200 is never read as success")
func unknownOutcomeIsNotSuccess() {
    // Guessing that an unknown outcome means "established" is how a client starts
    // believing it is a member on evidence nobody produced.
    let unknown = MembershipAttestationService.parseOutcome(
        status: 200, data: Data(#"{"outcome":"something_new"}"#.utf8)
    )
    #expect(unknown == .serverError(status: 200))

    let empty = MembershipAttestationService.parseOutcome(status: 200, data: Data())
    #expect(empty == .serverError(status: 200))

    let garbage = MembershipAttestationService.parseOutcome(
        status: 200, data: Data("not json".utf8)
    )
    #expect(garbage == .serverError(status: 200))
}

// MARK: - Binding token decoding

@MainActor
@Test("a well-formed binding token decodes in both PostgREST shapes")
func bindingTokenDecodes() {
    let uuid = "aaaaaaaa-0000-4000-8000-000000000001"
    #expect(
        MembershipBindingService.decodeBindingToken(Data("\"\(uuid)\"".utf8))
            == UUID(uuidString: uuid)
    )
    // Bare, unquoted — tolerated because PostgREST's scalar shape has changed
    // before, and still parsed strictly as a UUID.
    #expect(
        MembershipBindingService.decodeBindingToken(Data(uuid.utf8))
            == UUID(uuidString: uuid)
    )
}

@MainActor
@Test("anything that is not a UUID is REFUSED, never coerced")
func bindingTokenRefusesJunk() {
    // A malformed token would travel into Product.PurchaseOption.appAccountToken
    // and then into Apple's own records, where it is not cheaply correctable.
    for junk in ["", "\"\"", "null", "\"not-a-uuid\"", "{\"token\":\"x\"}", "12345"] {
        #expect(
            MembershipBindingService.decodeBindingToken(Data(junk.utf8)) == nil,
            "must refuse \(junk)"
        )
    }
}

// MARK: - Endpoint construction

@MainActor
@Test("the attest endpoint resolves for both hosted and local shapes")
func endpointConstruction() throws {
    let hosted = MembershipAttestationService.endpointURL(
        baseURL: try #require(URL(string: "https://abcdefgh.supabase.co"))
    )
    #expect(hosted.absoluteString == "https://abcdefgh.functions.supabase.co/membership_attest_v1")

    let local = MembershipAttestationService.endpointURL(
        baseURL: try #require(URL(string: "http://127.0.0.1:54321"))
    )
    #expect(local.absoluteString == "http://127.0.0.1:54321/functions/v1/membership_attest_v1")
}

// MARK: - U5f · F10, the post-purchase notice
//
// THE PURCHASE SUCCEEDED IN EVERY CASE BELOW. These assert what the member is
// TOLD, and the most important assertion is the one that expects silence.

@MainActor
@Test("a successful purchase and establishment says NOTHING")
func establishedIsSilent() {
    // An alert here would be noise on the happy path.
    #expect(MembershipSelectionView.postPurchaseNotice(for: .established) == nil)
    #expect(MembershipSelectionView.postPurchaseNotice(for: .alreadyEstablished) == nil)
}

@MainActor
@Test("F10: propagation delay is NEVER presented as a failure")
func pendingIsCalmAndNotAFailure() throws {
    let notice = try #require(MembershipSelectionView.postPurchaseNotice(for: .pending))
    let text = (notice.title + " " + notice.message).lowercased()

    // The load-bearing assertion of F10. Apple took the money and the binding is
    // propagating; language implying loss, error or a required retry would be
    // both wrong and alarming.
    for forbidden in ["fail", "failed", "error", "unavailable", "problem",
                      "try again", "retry", "cancel", "refund", "lost"] {
        #expect(!text.contains(forbidden), "must not say '\(forbidden)' for a propagation delay")
    }
    // And it must tell them there is nothing to do.
    #expect(text.contains("no action needed") || text.contains("on its own"))
}

@MainActor
@Test("transient server or Apple trouble is silent, because the next foreground retries")
func transientIsSilent() {
    #expect(MembershipSelectionView.postPurchaseNotice(for: .appleUnavailable) == nil)
    #expect(MembershipSelectionView.postPurchaseNotice(for: .transport("offline")) == nil)
    #expect(MembershipSelectionView.postPurchaseNotice(for: .serverError(status: 500)) == nil)
    #expect(MembershipSelectionView.postPurchaseNotice(for: nil) == nil)
    #expect(MembershipSelectionView.postPurchaseNotice(for: .ineligible(.noVerifiedTransaction)) == nil)
}

@MainActor
@Test("conflict and terminal refusal are surfaced, and reassure that the purchase is safe")
func unresolvableIsSurfacedCalmly() throws {
    for outcome in [MembershipAttestationService.Outcome.conflict,
                    .terminalRefusal(reason: "family_transaction_not_supported"),
                    .claimRefused(category: "foreign_app", terminal: true)] {
        let notice = try #require(MembershipSelectionView.postPurchaseNotice(for: outcome))
        let text = (notice.title + " " + notice.message).lowercased()
        // The member cannot fix these alone, so they must not be told to retry —
        // and must be told their money is not at risk.
        #expect(text.contains("purchase is safe"))
        #expect(!text.contains("try again"))
    }
}

@MainActor
@Test("a NON-terminal claim refusal is not surfaced")
func nonTerminalClaimRefusalIsSilent() {
    // e.g. an environment this deployment does not attest. Nothing the member
    // can act on, and it resolves without them.
    #expect(
        MembershipSelectionView.postPurchaseNotice(
            for: .claimRefused(category: "environment", terminal: false)
        ) == nil
    )
}

// MARK: - U5f correction · a new purchase REQUIRES the binding token
//
// The legacy-claim path exists for subscriptions that PREDATE bound purchase.
// It is not a fallback for new ones: its safety argument is that the token-less
// population is finite and shrinking, and minting new members into it would make
// that population unbounded and permanent.

@MainActor
@Test("NO binding token means NO StoreKit purchase attempt")
func missingBindingTokenBlocksPurchase() {
    #expect(
        MembershipSelectionView.purchaseReadiness(bindingToken: nil)
            == .blockedNoBindingToken
    )
}

@MainActor
@Test("a server-issued token unblocks the purchase, and is passed through unchanged")
func bindingTokenUnblocksPurchase() throws {
    let token = try #require(UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001"))
    #expect(MembershipSelectionView.purchaseReadiness(bindingToken: token) == .ready(token))

    // The token that reaches StoreKit must be exactly the one the server issued —
    // not re-derived, not regenerated.
    guard case .ready(let carried) = MembershipSelectionView.purchaseReadiness(bindingToken: token) else {
        Issue.record("expected .ready"); return
    }
    #expect(carried == token)
}

@MainActor
@Test("the blocked state is calm, retryable, and says nothing was charged")
func bindingUnavailableNoticeIsCalm() {
    let notice = MembershipSelectionView.bindingUnavailableNotice()
    let text = (notice.title + " " + notice.message).lowercased()

    // No purchase was initiated, so the member must be told plainly that no
    // money moved — and invited to retry, because a retry genuinely fixes it.
    #expect(text.contains("nothing has been charged"))
    #expect(text.contains("try again"))

    // It is a transient setup problem, not a failed purchase or a lost payment.
    for forbidden in ["purchase failed", "payment", "refund", "declined", "error"] {
        #expect(!text.contains(forbidden), "must not say '\(forbidden)'")
    }
}
