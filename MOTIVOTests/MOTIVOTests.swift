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

import Foundation
import Testing
@testable import MOTIVO

// MARK: - The attestation request body

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
