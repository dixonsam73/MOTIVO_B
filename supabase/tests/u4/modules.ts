// U4 module battery — derivation rules and Apple API failure handling.
//
// Runs inside the real edge runtime, against the SHIPPING modules. Nothing here
// touches a database or a network: fetch is injected, which is the only way
// Q6's three failure modes can be exercised at all. They cannot be induced
// against Apple.
//
// EVERY API TEST ASSERTS THE SAME RULE FROM A DIFFERENT DIRECTION: A FAILED OR
// AMBIGUOUS READ IS NOT AN ANSWER. The dangerous mistake is not crashing on a
// 500 — it is quietly treating "Apple said nothing we could parse" as "nothing
// is entitled", which under U7 becomes a deletion.

import { verifyAppleJWS } from "./_shared/appstore/jws.ts";
import { readNotificationHistory } from "./_shared/appstore/history.ts";
import {
  deriveFromNotification,
  deriveFromReconciliation,
  entitledAt,
} from "./_shared/appstore/derive.ts";
import {
  AppleApiError,
  AppStoreServerApi,
  lastTransactionsOf,
  signAppleApiJWT,
} from "./_shared/appstore/api.ts";

const F = JSON.parse(await Deno.readTextFile("/probe/fixtures.json"));
const TEST_ROOT = Uint8Array.from(atob(F.test_root_der_b64), (c) => c.charCodeAt(0));

let pass = 0, fail = 0;
const lines: string[] = [];
const ok = (id: string, w: string) => { pass++; lines.push(`PASS ${id}  ${w}`); };
const bad = (id: string, w: string) => { fail++; lines.push(`FAIL ${id}  ${w}`); };
const is = (id: string, got: unknown, want: unknown, w: string) =>
  got === want ? ok(id, `${w} = ${JSON.stringify(want)}`)
               : bad(id, `${w}: expected ${JSON.stringify(want)}, got ${JSON.stringify(got)}`);

/** Verify a fixture and normalise it exactly as the endpoint does. */
async function normalise(name: string) {
  const body = await verifyAppleJWS(F[name], new Date(), TEST_ROOT);
  const data = (body.data ?? {}) as Record<string, unknown>;
  const tx = typeof data.signedTransactionInfo === "string"
    ? await verifyAppleJWS(data.signedTransactionInfo, new Date(), TEST_ROOT) : null;
  const ri = typeof data.signedRenewalInfo === "string"
    ? await verifyAppleJWS(data.signedRenewalInfo, new Date(), TEST_ROOT) : null;
  return deriveFromNotification({ payload: body, transaction: tx, renewal: ri });
}

Deno.serve(async () => {
  // ----------------------------------------------------------- derivation
  const good = await normalise("good");
  is("U4b-1", good.disposition, "state", "a complete notification yields state");
  is("U4b-2", good.environment, "Sandbox", "environment extracted from data");
  is("U4b-3", good.app_account_token, F.binding_token, "appAccountToken carried through");
  is("U4b-4", good.state?.is_in_billing_retry, false, "billing retry defaults false, never null");
  is("U4b-5", good.notification_uuid, "3f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77", "uuid normalised");

  // Apple's own test notification is ORDINARY TRAFFIC, not a reject (B-27).
  const test = await normalise("test_notification");
  is("U4b-6", test.disposition, "not_applicable", "TEST notification is not_applicable");
  is("U4b-7", test.notification_type, "TEST", "TEST notification still identified");

  // B-25 LIMB A — the whole point of the finding. renewalDate absent,
  // expiresDate present: this MUST still produce writable state, because
  // writing NULL would derive to "expired" and schedule cleanup on a live
  // subscription.
  const fb = await normalise("fallback_expires_date");
  is("U4b-8", fb.disposition, "state", "renewalDate absent falls back to expiresDate");
  is("U4b-9", fb.state?.renewal_date !== null, true, "...and renewal_date is populated");

  // B-25 LIMB B — not orderable, therefore not writable. Reconcile instead.
  const ni = await normalise("incomplete_no_renewal_info");
  is("U4b-10", ni.disposition, "incomplete", "no signedRenewalInfo -> incomplete");
  is("U4b-11", ni.state, null, "...and carries NO state to write");
  const nsd = await normalise("incomplete_no_signed_date");
  is("U4b-12", nsd.disposition, "incomplete", "no renewalInfo.signedDate -> incomplete");

  const unm = await normalise("good_unmapped");
  is("U4b-13", unm.app_account_token, "bbbbbbbb-0000-4000-8000-000000000009",
    "a foreign token is carried, not silently dropped");
  const notok = await normalise("good_no_token");
  is("U4b-14", notok.app_account_token, null, "absent appAccountToken normalises to null");
  const prod = await normalise("good_production_env");
  is("U4b-15", prod.environment, "Production", "Production environment is recognised");

  // Apple's formula, evaluated the same way the SQL does it. Billing retry alone
  // must NOT entitle.
  // AGAINST THE REAL CLOCK. The fixtures encode offsets from now, so freezing a
  // date here would silently invert these three the moment the constant aged --
  // which is exactly the false failure that a frozen fixture epoch produced.
  const grace = await normalise("good_grace");
  is("U4b-16", grace.state?.is_in_billing_retry, true, "grace fixture is in billing retry");
  is("U4b-17", entitledAt(grace.state!, new Date()), true, "retry + unexpired grace entitles");
  is("U4b-18", entitledAt({ ...grace.state!, grace_period_expires_date: null }, new Date()),
    false, "retry with NO grace date does NOT entitle");
  const exp = await normalise("good_expired");
  is("U4b-19", entitledAt(exp.state!, new Date()), false, "expired is not entitled");

  // Reconciliation derivation shares the rules rather than repeating them.
  const rec = deriveFromReconciliation({
    transaction: { productId: "p", expiresDate: 1755640000000, originalTransactionId: "T1",
                   environment: "Sandbox" },
    renewal: { signedDate: 1755640000000 }, status: 1,
  });
  is("U4b-20", rec.state !== null, true, "reconciliation derives from expiresDate alone");
  const recBad = deriveFromReconciliation({
    transaction: { productId: "p", expiresDate: 1755640000000 }, renewal: {}, status: 1 });
  is("U4b-21", recBad.state, null, "reconciliation refuses without renewalInfo.signedDate");

  is("U4b-22", lastTransactionsOf({
    data: [{ lastTransactions: [{ originalTransactionId: "T1" }] }] }).length, 1,
    "lastTransactionsOf tolerates the array shape");
  is("U4b-23", lastTransactionsOf({
    data: { subscriptionGroupIdentifierItems: [{ lastTransactions: [{ originalTransactionId: "T1" }] }] },
  }).length, 1, "...and the nested shape");
  is("U4b-24", lastTransactionsOf(null).length, 0, "...and invents nothing from nothing");

  // ------------------------------------------------------------ API auth
  // A throwaway P-256 key. NO APPLE PRIVATE MATERIAL IS INVOLVED ANYWHERE.
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true,
    ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  let bin = ""; for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;
  const creds = { keyId: "TESTKEYID1", issuerId: "11111111-2222-3333-4444-555555555555",
                  p8Base64: btoa(pem), bundleId: "com.sdsongs.etudes" };

  const now = new Date(1755640000000);
  const jwt = await signAppleApiJWT(creds, now);
  const [h, c, s] = jwt.split(".");
  const dec = (x: string) => JSON.parse(atob(x.replace(/-/g, "+").replace(/_/g, "/") +
    "===".slice((x.length + 3) % 4)));
  is("U4b-25", dec(h).alg, "ES256", "API JWT alg");
  is("U4b-26", dec(h).kid, "TESTKEYID1", "API JWT kid");
  is("U4b-27", dec(h).typ, "JWT", "API JWT typ");
  is("U4b-28", dec(c).aud, "appstoreconnect-v1", "API JWT aud");
  is("U4b-29", dec(c).bid, "com.sdsongs.etudes", "API JWT bid");
  is("U4b-30", dec(c).exp - dec(c).iat <= 3600, true, "API JWT life is within Apple's 60-minute cap");
  is("U4b-31", s.length, 86, "ES256 signature is raw r||s (64 bytes), not DER");

  // ------------------------------------------------- API failure modes (Q6)
  const mk = (fetchImpl: typeof fetch, timeoutMs = 5000) =>
    new AppStoreServerApi(creds, { fetchImpl, timeoutMs, now: () => now });
  const res = (status: number, body: string) =>
    () => Promise.resolve(new Response(body, { status }));

  const expectKind = async (id: string, api: AppStoreServerApi, kind: string, w: string) => {
    try {
      await api.getAllSubscriptionStatuses("Sandbox", "T1");
      bad(id, `${w}: call SUCCEEDED — a failed read must never look like an answer`);
    } catch (e) {
      const k = e instanceof AppleApiError ? e.kind : "not-an-AppleApiError";
      k === kind ? ok(id, `${w} -> ${kind}`) : bad(id, `${w}: expected ${kind}, got ${k}`);
    }
  };

  await expectKind("U4b-32", mk(res(500, "boom") as typeof fetch), "server_error", "500");
  await expectKind("U4b-33", mk(res(503, "") as typeof fetch), "server_error", "503");
  await expectKind("U4b-34", mk(res(401, "{}") as typeof fetch), "unauthorised", "401");
  await expectKind("U4b-35",
    mk(res(404, '{"errorCode":4040010,"errorMessage":"Transaction id not found."}') as typeof fetch),
    "not_found", "404 TransactionIdNotFound");
  await expectKind("U4b-36", mk(res(429, "{}") as typeof fetch), "rate_limited", "429");
  await expectKind("U4b-37", mk(res(200, "<html>not json</html>") as typeof fetch), "malformed",
    "200 with an unparseable body");
  await expectKind("U4b-38", mk(res(200, "") as typeof fetch), "malformed", "200 with an empty body");
  await expectKind("U4b-39",
    mk(() => Promise.reject(new TypeError("connection refused")) as never), "network",
    "transport failure");
  await expectKind("U4b-40",
    mk(((_u: string, init: RequestInit) =>
      new Promise((_r, rej) =>
        init.signal?.addEventListener("abort", () => rej(new DOMException("aborted", "AbortError")))
      )) as unknown as typeof fetch, 150), "timeout", "a request that never returns");

  // Retryability decides whether to try again. It never authorises a write.
  for (const [id, kind, want] of [
    ["U4b-41", "server_error", true], ["U4b-42", "timeout", true],
    ["U4b-43", "network", true], ["U4b-44", "rate_limited", true],
    ["U4b-45", "unauthorised", false], ["U4b-46", "not_found", false],
    ["U4b-47", "malformed", false],
  ] as const) {
    is(id, new AppleApiError(kind, "x").retryable, want, `${kind} retryable`);
  }

  // A successful read still goes through the same parsing path.
  const okApi = mk(res(200, JSON.stringify({
    environment: "Sandbox", bundleId: "com.sdsongs.etudes",
    data: [{ subscriptionGroupIdentifier: "22252441",
             lastTransactions: [{ originalTransactionId: "T1", status: 1 }] }],
  })) as typeof fetch);
  const statuses = await okApi.getAllSubscriptionStatuses("Sandbox", "T1");
  is("U4b-48", lastTransactionsOf(statuses).length, 1, "a 200 parses into one lastTransaction");

  // ============================================ B-32 · Notification History
  //
  // THE OLD IMPLEMENTATION COULD NOT HAVE FAILED THESE — IT COULD NOT HAVE
  // PASSED THEM EITHER. It read `item.notificationUUID`, which
  // NotificationHistoryResponseItem does not have, so it reported a confident
  // zero for any input at all. These assertions exist so that behaviour is
  // structurally impossible to reintroduce.
  const verify = (j: unknown) => verifyAppleJWS(j, new Date(), TEST_ROOT);
  const page = (items: unknown[], extra: Record<string, unknown> = {}) =>
    ({ notificationHistory: items, ...extra });

  // (1) A legitimate item yields its REAL uuid, recovered from the verified payload.
  const one = await readNotificationHistory(page([{ signedPayload: F.good }]), verify);
  is("U4b-49", one.items.length, 1, "one legitimate history item is read");
  is("U4b-50", one.items[0].notification_uuid, "3f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
     "...and its uuid comes from the VERIFIED payload");
  is("U4b-51", one.unverifiable, 0, "...with nothing unverifiable");
  is("U4b-52", one.items[0].notification_type, "SUBSCRIBED", "type recovered too");
  is("U4b-53", one.items[0].environment, "Sandbox", "environment recovered");

  // (4) The structurally-impossible zero is gone: a valid fixture CANNOT report 0.
  is("U4b-54", one.items.filter((i) => i.notification_uuid !== null).length > 0, true,
     "a valid fixture can no longer produce a count of zero");

  // (2) Multiple items produce the correct count AND the correct uuid SET.
  const many = await readNotificationHistory(
    page([
      { signedPayload: F.good, sendAttempts: [{}, {}] },
      { signedPayload: F.fallback_expires_date },
      { signedPayload: F.test_notification },
    ]), verify);
  is("U4b-55", many.items.length, 3, "three items read");
  is("U4b-56",
     many.items.map((i) => i.notification_uuid).filter(Boolean).sort().join(","),
     [
       "3f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
       "ef1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
       "bf1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
     ].sort().join(","),
     "the uuid SET is correct, not merely the count");
  is("U4b-57", many.unverifiable, 0, "all three verified");
  is("U4b-58", many.items[0].send_attempts, 2, "Apple's own delivery-attempt count is carried");

  // (3) Hostile: validly-SHAPED but not validly SIGNED. It must NOT masquerade
  // as Apple's history, and it must NOT vanish silently either.
  const tampered = await readNotificationHistory(
    page([{ signedPayload: F.tampered_payload }]), verify);
  is("U4b-59", tampered.items.length, 0, "a tampered payload yields NO history item");
  is("U4b-60", tampered.unverifiable, 1, "...and is COUNTED, never silently dropped");

  const foreign = await readNotificationHistory(
    page([{ signedPayload: F.substituted_root }]), verify);
  is("U4b-61", foreign.items.length, 0, "a chain rooted elsewhere yields no item");
  is("U4b-62", foreign.unverifiable, 1, "...and is counted");

  // A mixture must not let the bad one contaminate the good one, in EITHER
  // direction: the genuine item is still reported, the forgery still is not.
  const mixed = await readNotificationHistory(
    page([{ signedPayload: F.good }, { signedPayload: F.tampered_payload }]), verify);
  is("U4b-63", mixed.items.length, 1, "the genuine item survives a poisoned page");
  is("U4b-64", mixed.unverifiable, 1, "...and the forgery is still refused");
  is("U4b-65", mixed.items[0].notification_uuid, "3f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
     "...and it is the RIGHT item");

  // Missing or malformed payloads are counted, not ignored.
  const junk = await readNotificationHistory(
    page([{ sendAttempts: [] }, { signedPayload: "" }, { signedPayload: F.not_a_jws }]), verify);
  is("U4b-66", junk.items.length, 0, "items with no usable payload yield nothing");
  is("U4b-67", junk.unverifiable, 3, "...and all three are counted");

  // An genuinely EMPTY history is distinguishable from a broken read: zero items
  // AND zero unverifiable. That pair is what the old code could never express.
  const empty = await readNotificationHistory(page([]), verify);
  is("U4b-68", `${empty.items.length}/${empty.unverifiable}`, "0/0",
     "an empty history reads as 0/0 — distinguishable from a failed parse");

  // Pagination is surfaced, so a partial page cannot look like a complete one.
  const paged = await readNotificationHistory(
    page([{ signedPayload: F.good }], { hasMore: true, paginationToken: "TOKEN123" }), verify);
  is("U4b-69", paged.has_more, true, "hasMore is surfaced");
  is("U4b-70", paged.pagination_token, "TOKEN123", "...and so is the token");
  is("U4b-71", (await readNotificationHistory(page([]), verify)).pagination_token, null,
     "absent token reads as null");

  // Not an array / not an object at all.
  is("U4b-72", (await readNotificationHistory({}, verify)).items.length, 0, "missing history array -> 0 items");
  is("U4b-73", (await readNotificationHistory(null, verify)).unverifiable, 0, "a null response is not invented into items");

  return new Response(JSON.stringify({ pass, fail, lines }, null, 1), {
    status: fail === 0 ? 200 : 500,
    headers: { "content-type": "application/json" },
  });
});
