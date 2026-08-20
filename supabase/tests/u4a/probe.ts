// U4a route gate — runs INSIDE the real Supabase Edge Runtime image.
//
// Answers one question: can this runtime verify an App Store Server
// Notifications V2 payload — ES256 JWS carrying an x5c chain — against a pinned
// Apple Root CA G3?
//
// IT EXERCISES THE SHIPPING MODULE, not a reimplementation of it. jws.ts below
// is the same file appstore_notifications_v1 imports, so this doubles as a
// regression gate: a change that breaks verification fails here.
//
// The two rejected routes are re-run every time rather than recorded as history,
// because "the official library does not work here" is a claim with a shelf life
// and a future runtime may change it.

import { JwsError, verifyAppleJWS, verifyChain } from "./_shared/appstore/jws.ts";
import { APPLE_ROOT_CA_G3_B64 } from "./_shared/appstore/apple_root_ca_g3.ts";
import { deriveFromNotification } from "./_shared/appstore/derive.ts";

// ABSOLUTE PATH, DELIBERATELY. The runtime compiles the service into
// /var/tmp/sb-compile-edge-runtime/, so a relative path resolves somewhere the
// mounted fixtures are not — the same relocation that forces the production
// anchor to be an embedded constant rather than a file read.
const F = JSON.parse(await Deno.readTextFile("/probe/fixtures.json"));
const der = (b: string) => Uint8Array.from(atob(b), (c) => c.charCodeAt(0));
const TEST_ROOT = der(F.test_root_der_b64);
const APPLE_ROOT = der(APPLE_ROOT_CA_G3_B64);

let pass = 0, fail = 0;
const lines: string[] = [];
const ok = (id: string, what: string) => { pass++; lines.push(`PASS ${id}  ${what}`); };
const bad = (id: string, what: string) => { fail++; lines.push(`FAIL ${id}  ${what}`); };
const is = (id: string, got: unknown, want: unknown, what: string) =>
  got === want ? ok(id, `${what} = ${want}`) : bad(id, `${what}: expected ${want}, got ${got}`);

/** A negative case passes only by being REFUSED, and the reason is reported. */
async function refuses(id: string, name: string) {
  try {
    await verifyAppleJWS(F[name], new Date(), TEST_ROOT);
    bad(id, `${name}: ACCEPTED — must be refused`);
  } catch (e) {
    ok(id, `${name}: refused (${(e as Error).message.slice(0, 55)})`);
  }
}

Deno.serve(async () => {
  const results: Record<string, unknown> = {};

  results.runtime = {
    deno: (globalThis as { Deno?: { version?: unknown } }).Deno?.version ?? null,
    userAgent: (globalThis as { navigator?: { userAgent?: string } }).navigator?.userAgent ?? null,
  };

  // ---------------------------------------------------------------- route A
  // node:crypto X509Certificate. The class EXISTS and a naive capability probe
  // reports hasX509 true — which is why this asserts the METHOD, not the class.
  const routeA: Record<string, unknown> = {};
  try {
    const m = await import("node:crypto");
    routeA.hasX509Class = typeof m.X509Certificate === "function";
    const c = new m.X509Certificate(APPLE_ROOT);
    try {
      c.verify(c.publicKey);
      routeA.verifyWorks = true;
    } catch (e) {
      routeA.verifyWorks = false;
      routeA.verifyError = String(e).slice(0, 140);
    }
  } catch (e) {
    routeA.importError = String(e).slice(0, 140);
  }
  results.route_A_node_crypto = routeA;
  is("U4a-1", routeA.hasX509Class, true, "node:crypto exposes an X509Certificate class");
  is("U4a-2", routeA.verifyWorks, false,
    "node:crypto X509Certificate.verify is UNUSABLE (capability presence is not capability)");

  // ---------------------------------------------------------------- route C
  // The official Apple library, against a fixture built to Apple's own shape
  // INCLUDING both marker OIDs — without them its rejection would be correct
  // and therefore uninformative.
  const routeC: Record<string, unknown> = {};
  try {
    const lib = await import("npm:@apple/app-store-server-library@1.6.0");
    const v = new lib.SignedDataVerifier([TEST_ROOT], false, lib.Environment.SANDBOX,
      "com.sdsongs.etudes");
    try {
      const d = await v.verifyAndDecodeNotification(F.good);
      routeC.verifiedGoodPayload = true;
      routeC.notificationType = d.notificationType;
    } catch (e) {
      routeC.verifiedGoodPayload = false;
      routeC.status = (e as { status?: number }).status;
      routeC.cause = String((e as { cause?: unknown }).cause ?? "").slice(0, 160);
    }
  } catch (e) {
    routeC.importError = String(e).slice(0, 160);
  }
  results.route_C_apple_library = routeC;
  is("U4a-3", routeC.verifiedGoodPayload, false,
    "@apple/app-store-server-library REJECTS a payload it should accept");
  // The finding is not that it fails but that it CANNOT BE TOLD APART from a
  // forgery: status 1 is VERIFICATION_FAILURE either way.
  is("U4a-4", routeC.status, 1,
    "...and reports runtime incapacity with the SAME status as a genuine forgery");

  // ---------------------------------------------------------------- route B
  // The adopted route, exercised through the shipping module.
  const body = await verifyAppleJWS(F.good, new Date(), TEST_ROOT);
  is("U4a-5", (body as Record<string, unknown>).notificationType, "SUBSCRIBED",
    "shipping verifier accepts a well-formed payload");

  const data = (body as Record<string, Record<string, string>>).data;
  const tx = await verifyAppleJWS(data.signedTransactionInfo, new Date(), TEST_ROOT);
  const ri = await verifyAppleJWS(data.signedRenewalInfo, new Date(), TEST_ROOT);
  is("U4a-6", (tx as Record<string, unknown>).originalTransactionId, "2000000999999999",
    "nested signedTransactionInfo verifies in its own right");
  is("U4a-7", typeof (ri as Record<string, unknown>).renewalDate, "number",
    "nested signedRenewalInfo verifies in its own right");

  const ev = deriveFromNotification({ payload: body, transaction: tx, renewal: ri });
  is("U4a-8", ev.disposition, "state", "derivation yields writable state");

  await refuses("U4a-9", "tampered_payload");
  await refuses("U4a-10", "substituted_root");
  await refuses("U4a-11", "alg_none");
  await refuses("U4a-12", "alg_rs256");
  await refuses("U4a-13", "no_x5c");
  await refuses("U4a-14", "chain_too_short");
  await refuses("U4a-15", "chain_reordered");
  await refuses("U4a-16", "leaf_without_apple_oid");
  await refuses("U4a-17", "not_a_jws");
  await refuses("U4a-18", "two_parts");

  // The envelope is correctly signed; the INNER payload is not. Trusting an
  // inner JWS because the outer one verified is the obvious mistake.
  const outer = await verifyAppleJWS(F.tampered_nested_tx, new Date(), TEST_ROOT);
  try {
    await verifyAppleJWS(
      (outer as Record<string, Record<string, string>>).data.signedTransactionInfo,
      new Date(), TEST_ROOT);
    bad("U4a-19", "tampered nested transaction was ACCEPTED");
  } catch {
    ok("U4a-19", "tampered nested transaction refused although its envelope verified");
  }

  // PINNING. The assertion that actually carries the security property: x5c[2]
  // is ignored and OUR anchor decides.
  try {
    await verifyAppleJWS(F.good, new Date(), APPLE_ROOT);
    bad("U4a-20", "a non-Apple chain verified under the Apple anchor");
  } catch (e) {
    is("U4a-20", (e as JwsError).message, "intermediate is not signed by the pinned anchor",
      "pinning refuses a chain rooted elsewhere");
  }

  // Certificate validity is checked at the verification instant.
  try {
    await verifyAppleJWS(F.good, new Date(Date.now() + 500 * 864e5), TEST_ROOT);
    bad("U4a-21", "an expired leaf was accepted");
  } catch (e) {
    ok("U4a-21", `expired leaf refused (${(e as Error).message.slice(0, 45)})`);
  }

  // ------------------------------------------------- the REAL Apple chain link
  // Root -> intermediate, with Apple's own certificates. P-384 / SHA-384, which
  // an all-P-256 fixture could never have exercised.
  if (F.apple_wwdr_der_b64) {
    const x509 = await import("@peculiar/x509");
    x509.cryptoProvider.set(crypto as unknown as Crypto);
    const root = new x509.X509Certificate(APPLE_ROOT);
    const wwdr = new x509.X509Certificate(der(F.apple_wwdr_der_b64));
    const rootKey = await root.publicKey.export(crypto as unknown as Crypto);
    is("U4a-22", await wwdr.verify({ publicKey: rootKey, signatureOnly: true }), true,
      "REAL Apple WWDR G6 verifies against the pinned REAL Apple Root CA G3");
    is("U4a-23",
      await wwdr.verify({
        publicKey: await new x509.X509Certificate(TEST_ROOT).publicKey.export(crypto as unknown as Crypto),
        signatureOnly: true,
      }).catch(() => false), false,
      "...and does NOT verify against an unrelated root");
    is("U4a-24", (root.publicKey.algorithm as { namedCurve?: string }).namedCurve, "P-384",
      "pinned anchor is P-384");
    is("U4a-25", !!wwdr.getExtension("1.2.840.113635.100.6.2.1"), true,
      "real WWDR G6 carries Apple's intermediate OID");
    results.apple_root_subject = root.subject;
    results.apple_wwdr_subject = wwdr.subject;
  } else {
    lines.push("SKIP U4a-22..25  real Apple chain (WWDR G6 not fetched — no network?)");
  }

  // Cost, so a regression in verification time is visible rather than felt.
  const t0 = performance.now();
  for (let i = 0; i < 20; i++) await verifyAppleJWS(F.good, new Date(), TEST_ROOT);
  results.verify_ms_avg = Math.round((performance.now() - t0) / 20 * 100) / 100;

  return new Response(
    JSON.stringify({ ...results, pass, fail, lines }, null, 1),
    { status: fail === 0 ? 200 : 500, headers: { "content-type": "application/json" } },
  );
});
