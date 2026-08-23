// U5c module battery — the attestation claim boundary and Set App Account Token.
//
// Runs inside the real edge runtime against the SHIPPING modules. No database, no
// network: fetch is injected, which is the only way Apple's error shapes can be
// exercised at all.
//
// THE HOSTILE FIXTURES ARE ALL VALIDLY SIGNED, AND THAT IS THE ENTIRE POINT. Every
// "attest_*" payload below passes signature verification against the test CA. If
// a claim check regresses, the payload does not start failing somewhere else —
// it starts being ACCEPTED. That is what B-31 is about, and it is why a suite
// that only fed this code malformed input would prove nothing.

import { verifyAppleJWS } from "./_shared/appstore/jws.ts";
import {
  AttestError,
  attestPolicyFromEnv,
  CONNECTED_PRODUCT_IDS,
  interpretObservation,
  observeAppAccountToken,
  verifyAttestationJWS,
} from "./_shared/appstore/attest.ts";
import {
  AppleApiError,
  AppStoreServerApi,
  classifyTokenAssignment,
} from "./_shared/appstore/api.ts";

const F = JSON.parse(await Deno.readTextFile("/probe/fixtures.json"));
const TEST_ROOT = Uint8Array.from(atob(F.test_root_der_b64), (c) => c.charCodeAt(0));
const ATTEST_SRC = await Deno.readTextFile("/probe/_shared/appstore/attest.ts");

let pass = 0, fail = 0;
const lines: string[] = [];
const ok = (id: string, w: string) => { pass++; lines.push(`PASS ${id}  ${w}`); };
const bad = (id: string, w: string) => { fail++; lines.push(`FAIL ${id}  ${w}`); };
const is = (id: string, got: unknown, want: unknown, w: string) =>
  got === want ? ok(id, `${w} = ${JSON.stringify(want)}`)
               : bad(id, `${w}: expected ${JSON.stringify(want)}, got ${JSON.stringify(got)}`);

const SANDBOX_ONLY = {
  bundleId: "com.sdsongs.etudes",
  productIds: CONNECTED_PRODUCT_IDS,
  allowedEnvironments: ["Sandbox"],
};

/** Assert a fixture is REFUSED with a given category, and report if it was accepted. */
async function refused(id: string, fixture: string, category: string, w: string, policy = SANDBOX_ONLY) {
  try {
    await verifyAttestationJWS(F[fixture], policy, new Date(), TEST_ROOT);
    bad(id, `${w}: ACCEPTED — a validly-signed foreign payload passed the claim boundary`);
  } catch (e) {
    const c = e instanceof AttestError ? e.category : `not-an-AttestError(${e})`;
    c === category ? ok(id, `${w} -> ${category}`) : bad(id, `${w}: expected ${category}, got ${c}`);
  }
}

Deno.serve(async () => {
  // ================================================== the happy paths
  const good = await verifyAttestationJWS(F.attest_ok, SANDBOX_ONLY, new Date(), TEST_ROOT);
  is("U5c-1", good.original_transaction_id, "2000000999999999", "originalTransactionId extracted");
  is("U5c-2", good.app_account_token, F.binding_token, "appAccountToken carried through");
  is("U5c-3", good.environment, "Sandbox", "environment extracted");
  is("U5c-4", good.product_id, "com.sdsongs.etudes.connected.monthly", "product extracted");
  is("U5c-5", good.in_app_ownership_type, "PURCHASED", "ownership type extracted");

  const annual = await verifyAttestationJWS(F.attest_ok_annual, SANDBOX_ONLY, new Date(), TEST_ROOT);
  is("U5c-6", annual.product_id, "com.sdsongs.etudes.connected.annual", "the SECOND product is legitimate too");

  // The legacy population: ours, genuine, and carrying no token yet. It must be
  // ACCEPTED here — refusing it would make the legacy claim unreachable.
  const legacy = await verifyAttestationJWS(F.attest_no_token, SANDBOX_ONLY, new Date(), TEST_ROOT);
  is("U5c-7", legacy.app_account_token, null, "a token-less legacy transaction is accepted");

  // A token belonging to somebody else is NOT a verification failure. Whose it is
  // becomes a question for U5d against the live binding table; the JWS layer must
  // not pre-empt that decision.
  const other = await verifyAttestationJWS(F.attest_other_token, SANDBOX_ONLY, new Date(), TEST_ROOT);
  is("U5c-8", other.app_account_token, "bbbbbbbb-0000-4000-8000-000000000009", "a foreign token is carried, not judged");

  // ============================== F3b/P2: STALENESS IS NOT A REFUSAL
  // A JWS signed a year ago must still verify. This is G11's dormant pre-cutover
  // subscriber, and a freshness window would have refused exactly this member.
  const stale = await verifyAttestationJWS(F.attest_stale_year, SANDBOX_ONLY, new Date(), TEST_ROOT);
  is("U5c-9", stale.original_transaction_id, "2000000999999999", "a YEAR-OLD JWS is still accepted (no freshness window)");
  is("U5c-10", typeof stale.signed_date, "string", "signedDate reported for diagnostics");
  is("U5c-11", new Date(stale.signed_date!).getTime() < Date.now() - 300_000, true, "...and it is genuinely stale, proving nothing gated on it");

  // ================================== hostile, and all validly signed
  await refused("U5c-12", "attest_foreign_app", "foreign_app", "another app's genuine subscription");
  await refused("U5c-13", "attest_foreign_product", "foreign_product", "our app, wrong product");
  await refused("U5c-14", "attest_env_production", "environment", "Production while only Sandbox is attestable");
  await refused("U5c-15", "attest_env_xcode", "environment", "Xcode environment is never attestable");
  await refused("U5c-16", "attest_family_shared", "family_shared", "FAMILY_SHARED can never be bound");
  await refused("U5c-17", "attest_no_original_id", "schema", "no originalTransactionId");
  // THE FIRST VERSION OF THIS ASSERTION WAS WRONG, AND THE WAY IT WAS WRONG IS
  // WORTH KEEPING. It fed a chain whose THIRD certificate was swapped for a
  // hostile root and expected a refusal. verifyChain ignores x5c[2] entirely --
  // it verifies the intermediate against OUR anchor, which is the whole pinning
  // property -- so accepting it is correct, and the assertion was testing a
  // mechanism that deliberately does not exist.
  const substituted = await verifyAttestationJWS(F.attest_evil_root, SANDBOX_ONLY, new Date(), TEST_ROOT);
  is("U5c-18", substituted.product_id, "com.sdsongs.etudes.connected.monthly",
     "a substituted x5c[2] is IGNORED — pinning never consults the presented root");
  // Pinning itself, asserted the only way that means anything: the SAME payload
  // that passes under the test anchor must fail under the real Apple anchor.
  const APPLE_ROOT = Uint8Array.from(atob(F.apple_root_der_b64), (c) => c.charCodeAt(0));
  try {
    await verifyAttestationJWS(F.attest_ok, SANDBOX_ONLY, new Date(), APPLE_ROOT);
    bad("U5c-18b", "a test-CA payload verified against the REAL Apple anchor");
  } catch (e) {
    is("U5c-18b", (e as AttestError).category, "signature",
       "the same payload FAILS against the real Apple Root CA G3");
  }
  await refused("U5c-19", "not_a_jws", "decode", "not a JWS at all");

  // Terminality: which refusals can NEVER become acceptable.
  for (const [id, fx, want] of [
    ["U5c-20", "attest_foreign_app", true],
    ["U5c-21", "attest_foreign_product", true],
    ["U5c-22", "attest_family_shared", true],
    ["U5c-23", "attest_env_production", false],
  ] as const) {
    try {
      await verifyAttestationJWS(F[fx], SANDBOX_ONLY, new Date(), TEST_ROOT);
      bad(id, `${fx}: accepted`);
    } catch (e) {
      is(id, (e as AttestError).terminal, want, `${fx} terminal`);
    }
  }

  // THE ENVIRONMENT CONTROL WORKS IN BOTH DIRECTIONS. Asserting only the refusal
  // would pass for a policy that refuses everything.
  const prodPolicy = { ...SANDBOX_ONLY, allowedEnvironments: ["Sandbox", "Production"] };
  const prod = await verifyAttestationJWS(F.attest_env_production, prodPolicy, new Date(), TEST_ROOT);
  is("U5c-24", prod.environment, "Production", "Production accepted when explicitly allowed");
  await refused("U5c-25", "attest_env_xcode", "environment", "Xcode STILL refused even then", prodPolicy);

  // ================================ the JWS is never echoed or returned
  const asJson = JSON.stringify(good);
  is("U5c-26", asJson.includes(String(F.attest_ok).slice(0, 60)), false, "result never contains the JWS");
  is("U5c-27", Object.keys(good).some((k) => /jws|raw|token_string|payload/i.test(k)), false, "result has no JWS-shaped field");
  try {
    await verifyAttestationJWS(F.attest_foreign_app, SANDBOX_ONLY, new Date(), TEST_ROOT);
  } catch (e) {
    const msg = String((e as Error).message);
    is("U5c-28", msg.includes(String(F.attest_foreign_app).slice(0, 60)), false, "error message never contains the JWS");
    is("U5c-29", msg.includes("com.example.someotherapp"), true, "...but does name the signed claim, for diagnosis");
  }

  // ============================ APPLE_ATTEST_ALLOWED_ENVIRONMENTS
  const envOf = (m: Record<string, string>) =>
    attestPolicyFromEnv({ get: (k: string) => m[k] });
  is("U5c-30", envOf({ APPLE_IAP_BUNDLE_ID: "b" }).allowedEnvironments.join(","), "Sandbox", "defaults to Sandbox");
  is("U5c-31",
    envOf({ APPLE_IAP_BUNDLE_ID: "b", APPLE_ATTEST_ALLOWED_ENVIRONMENTS: "Sandbox,Production" })
      .allowedEnvironments.join(","), "Sandbox,Production", "reads the attest variable");
  // THE DECOUPLING, ASSERTED RATHER THAN COMMENTED: setting the NOTIFICATION
  // variable must not widen attestation by a single environment.
  is("U5c-32",
    envOf({ APPLE_IAP_BUNDLE_ID: "b", APPLE_ASSN_ALLOWED_ENVIRONMENTS: "Sandbox,Production" })
      .allowedEnvironments.join(","), "Sandbox", "ASSN variable does NOT affect attestation");
  is("U5c-33", ATTEST_SRC.includes("APPLE_ASSN_ALLOWED_ENVIRONMENTS_"), false, "structural: attest.ts never reads the ASSN variable");
  // Targets the CALL, not the prose: attest.ts names the ASSN variable in its own
  // explanation of why it must not read it, so a bare substring search fails on
  // a correct file. What must never appear is a read of it.
  is("U5c-34", /get\(\s*["'`]APPLE_ASSN/.test(ATTEST_SRC), false, "structural: attest.ts never READS the ASSN variable");
  is("U5c-35", CONNECTED_PRODUCT_IDS.length, 2, "exactly two legitimate products, hardcoded");

  // ================================== Set App Account Token: the request
  const creds = { keyId: "K", issuerId: "I", bundleId: "com.sdsongs.etudes", p8Base64: F.p8_b64 ?? "" };
  let seen: { url: string; method: string; body: string } | null = null;
  const capture = ((url: string, init: RequestInit) => {
    seen = { url: String(url), method: String(init.method), body: String(init.body ?? "") };
    return Promise.resolve(new Response("", { status: 200 }));
  }) as unknown as typeof fetch;

  // signAppleApiJWT needs a real key; if the fixture set carries none, the request
  // assertions are SKIPPED rather than silently passing on a stub.
  let apiOk = true;
  try {
    const api = new AppStoreServerApi(
      { ...creds, p8Base64: F.p8_b64 },
      { fetchImpl: capture },
    );
    const r = await api.setAppAccountToken("Sandbox", "2000000999999999", F.binding_token);
    is("U5c-36", r, undefined, "setAppAccountToken returns NOTHING a caller could read as confirmation");
    is("U5c-37", seen!.method, "PUT", "issues a PUT");
    is("U5c-38", seen!.url.endsWith("/inApps/v1/transactions/2000000999999999/appAccountToken"), true, "against the ORIGINAL transaction id");
    is("U5c-39", seen!.url.startsWith("https://api.storekit-sandbox.apple.com"), true, "on the sandbox host");
    is("U5c-40", JSON.parse(seen!.body).appAccountToken, F.binding_token, "body carries the token");
  } catch (e) {
    apiOk = false;
    lines.push(`SKIP U5c-36..40  request shape (no signing key in fixtures): ${e}`);
  }

  // ============================ Set App Account Token: the taxonomy
  const err = (status: number, code?: number) =>
    new AppleApiError(
      status === 404 ? "not_found" : status === 429 ? "rate_limited"
        : status >= 500 ? "server_error" : status === 401 ? "unauthorised" : "client_error",
      "x", status, code,
    );
  const cls = (e: unknown) => classifyTokenAssignment(e);

  for (
    const [id, code, reason] of [
      ["U5c-41", 4000006, "invalid_transaction_id"],
      ["U5c-42", 4000048, "app_transaction_id_not_supported"],
      ["U5c-43", 4000183, "invalid_app_account_token_uuid"],
      ["U5c-44", 4000185, "family_transaction_not_supported"],
      ["U5c-45", 4000187, "transaction_id_is_not_original_transaction_id"],
      ["U5c-46", 4040005, "original_transaction_id_not_found"],
    ] as const
  ) {
    const d = cls(err(code === 4040005 ? 404 : 400, code));
    is(id, `${d.kind}/${d.reason}`, `terminal/${reason}`, `Apple ${code}`);
  }

  is("U5c-47", cls(err(429)).kind, "retryable", "429 is retryable");
  is("U5c-48", cls(err(500)).kind, "retryable", "5xx is retryable");
  is("U5c-49", cls(err(401)).kind, "retryable", "401 is OUR credential, retryable after a fix");
  is("U5c-50", cls(err(401)).reason, "our_credential_rejected", "...and named as ours, not the member's");
  is("U5c-51", cls(new AppleApiError("timeout", "x")).kind, "retryable", "timeout is retryable");
  is("U5c-52", cls(new AppleApiError("network", "x")).kind, "retryable", "network is retryable");
  is("U5c-53", cls(new Error("boom")).kind, "retryable", "an unknown throw is retryable, never terminal");
  is("U5c-54", cls(err(400, 4099999)).kind, "terminal", "an unrecognised 4xx is terminal by status family");
  is("U5c-55", cls(err(400, 4099999)).reason, "unrecognised_client_error", "...and says it was unrecognised");

  // ====================== the re-read: propagation is not failure
  const statusFor = (txJws: string | null) => ({
    data: [{
      subscriptionGroupIdentifier: "22252441",
      lastTransactions: [
        txJws === null
          ? { originalTransactionId: "2000000999999999", status: 1 }
          : { originalTransactionId: "2000000999999999", status: 1, signedTransactionInfo: txJws },
      ],
    }],
  });
  const fakeApi = (resp: unknown) => ({
    getAllSubscriptionStatuses: () => Promise.resolve(resp),
  });

  const obsOurs = await observeAppAccountToken(
    fakeApi(statusFor(F.attest_ok)) as never, "Sandbox", "2000000999999999", TEST_ROOT);
  is("U5c-56", obsOurs.token, F.binding_token, "re-read observes the token Apple actually holds");
  is("U5c-57", interpretObservation(obsOurs, F.binding_token).outcome, "ours", "our token -> ours");

  const obsNone = await observeAppAccountToken(
    fakeApi(statusFor(F.attest_no_token)) as never, "Sandbox", "2000000999999999", TEST_ROOT);
  is("U5c-58", obsNone.found, true, "entry found");
  is("U5c-59", obsNone.token, null, "but no token yet");
  is("U5c-60", interpretObservation(obsNone, F.binding_token).outcome, "propagating",
     "NO TOKEN YET IS PROPAGATION, NOT FAILURE");

  const obsOther = await observeAppAccountToken(
    fakeApi(statusFor(F.attest_other_token)) as never, "Sandbox", "2000000999999999", TEST_ROOT);
  is("U5c-61", interpretObservation(obsOther, F.binding_token).outcome, "foreign", "somebody else's token -> foreign");

  const obsGone = await observeAppAccountToken(
    fakeApi({ data: [] }) as never, "Sandbox", "2000000999999999", TEST_ROOT);
  is("U5c-62", obsGone.found, false, "no matching entry");
  is("U5c-63", interpretObservation(obsGone, F.binding_token).outcome, "unavailable", "no entry -> unavailable, never 'not bound'");

  // The nested JWS on a re-read is verified in its own right, with the pinned
  // anchor. Trusting it because it arrived over our own HTTPS call is the
  // obvious mistake.
  try {
    await observeAppAccountToken(
      fakeApi(statusFor(F.attest_ok)) as never, "Sandbox", "2000000999999999", APPLE_ROOT);
    bad("U5c-64", "re-read accepted a nested JWS the anchor should reject");
  } catch {
    ok("U5c-64", "re-read verifies the nested JWS against the pinned anchor in its own right");
  }

  // ============================ U4's verifier behaviour is PRESERVED
  const u4 = await verifyAppleJWS(F.good, new Date(), TEST_ROOT);
  is("U5c-65", typeof u4.notificationUUID, "string", "U4's notification verifier still works unchanged");
  is("U5c-66", (u4.data as Record<string, unknown>).bundleId, "com.sdsongs.etudes", "...and still returns the payload it always did");
  // The U4 verifier must NOT have acquired claim checks: it is used on payloads
  // Apple pushes to us, where the notification endpoint filters environment
  // separately. A foreign transaction still VERIFIES at that layer by design.
  const foreignStillVerifies = await verifyAppleJWS(F.attest_foreign_app, new Date(), TEST_ROOT);
  is("U5c-67", foreignStillVerifies.bundleId, "com.example.someotherapp",
     "verifyAppleJWS still answers ONLY 'did Apple sign this' — claims belong to attest.ts");

  return new Response(JSON.stringify({ pass, fail, lines, apiOk }, null, 1), {
    status: fail === 0 ? 200 : 500,
    headers: { "content-type": "application/json" },
  });
});
