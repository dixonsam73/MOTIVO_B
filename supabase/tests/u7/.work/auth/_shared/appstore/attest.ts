// Client-supplied transaction JWS — claim-checked attestation input (B-31).
//
// WHY THIS EXISTS AS A SEPARATE ENTRY POINT RATHER THAN A CHANGE TO jws.ts.
//
// verifyAppleJWS answers exactly one question — "did Apple sign these bytes?" —
// and it must keep answering only that, because U4's notification path depends
// on it unchanged. For U4 that single question was sufficient: Apple only sends
// us our own app's notifications, so the set of payloads reaching the verifier
// was already constrained by who could deliver them.
//
// U5 INVERTS THAT COMPLETELY. The transaction JWS arrives FROM A CLIENT, so
// "Apple signed it" is nearly worthless on its own: ANY Apple-signed transaction
// from ANY app on ANY device satisfies it. A subscriber to an unrelated App Store
// app could present their own perfectly genuine JWS and, without the checks
// below, be treated as evidence of an Etudes Connected subscription.
//
// **THE CLAIM CHECKS ARE NOT HARDENING. THEY ARE THE DIFFERENCE BETWEEN THE
// ARTEFACT PROVING SOMETHING AND PROVING NOTHING.**
//
// ── WHAT THIS MODULE DELIBERATELY DOES NOT DO ─────────────────────────────
//
// NO FRESHNESS WINDOW, AND NO ONE-TIME CONSUMPTION. Settled by measurement, not
// preference: the F3b gate ran on Device A against a genuine Sandbox entitlement
// on 2026-08-20 and returned P2 -- Transaction.currentEntitlements serves a
// STORED HISTORICAL representation. signedDate is fixed at approximately the
// purchase instant and does not move across cold launches.
//
//   A window would BREAK G11. A dormant pre-cutover subscriber returns holding a
//   JWS signed months or years earlier, and that is the exact case U5 exists to
//   make self-healing.
//
//   One-time consumption fails differently: the legitimate client presents the
//   SAME bytes on every attestation, so consuming them would refuse the owner's
//   second call.
//
// So `signedDate` is read for diagnostics and is NEVER a gate. The residual is
// accepted explicitly and is bounded by membership_transaction_unique, the
// live-binding conflict rule, the self-extinguishing legacy branch, and the fact
// that new joins carry a token from purchase.
//
// ── THE BYTES ARE A BEARER ARTEFACT AND ARE TREATED AS ONE ────────────────
//
// **NOTHING HERE EVER RETURNS, LOGS, PERSISTS OR ECHOES THE JWS.** Under P2 it
// stays valid for the LIFE OF THE TRANSACTION, so a leak is permanent rather
// than expiring in minutes -- which makes the no-persist rule load-bearing
// rather than cautious. AttestedTransaction carries no jws field, and no error
// message below interpolates the input. The module tests assert both.
//
// Values that ARE echoed in errors -- bundleId, productId, environment -- are
// echoed only AFTER signature verification has passed, so they are claims APPLE
// SIGNED rather than arbitrary attacker text, and they are length-bounded anyway.

import { JwsError, verifyAppleJWS } from "./jws.ts";
import { type AppleEnvironment, lastTransactionsOf } from "./api.ts";
import { deriveFromReconciliation, type MembershipState } from "./derive.ts";

/** Maps onto what U5d will record. Every value is a refusal reason. */
export type AttestFailure =
  | "decode" // malformed before any signature work
  | "signature" // not signed by the pinned Apple anchor
  | "foreign_app" // Apple-signed, but for somebody else's app
  | "environment" // an environment this deployment does not attest
  | "foreign_product" // our app, but not a Connected subscription
  | "family_shared" // TERMINAL: can never receive an appAccountToken
  | "schema"; // our app, our product, but unusable

export class AttestError extends Error {
  constructor(readonly category: AttestFailure, message: string) {
    super(message);
    this.name = "AttestError";
  }
  /** True when no retry, by anyone, can ever make this payload acceptable. */
  get terminal(): boolean {
    return this.category === "foreign_app" ||
      this.category === "foreign_product" ||
      this.category === "family_shared";
  }
}

/**
 * THE TWO LEGITIMATE CONNECTED PRODUCTS, HARDCODED ON PURPOSE.
 *
 * bundleId comes from APPLE_IAP_BUNDLE_ID because that secret already exists and
 * must agree with the JWT `bid` claim we sign — one source, so they cannot drift.
 * The product list is deliberately NOT configurable, and the asymmetry is the
 * point: an environment variable is a WIDENING MECHANISM, and widening the set of
 * products that can buy Connected access should require a code change and a
 * review, not a secret edit.
 */
export const CONNECTED_PRODUCT_IDS = [
  "com.sdsongs.etudes.connected.monthly",
  "com.sdsongs.etudes.connected.annual",
] as const;

export interface AttestPolicy {
  bundleId: string;
  productIds: readonly string[];
  allowedEnvironments: readonly string[];
}

/**
 * APPLE_ATTEST_ALLOWED_ENVIRONMENTS, AND IT IS NOT THE NOTIFICATION VARIABLE.
 *
 * Reusing APPLE_ASSN_ALLOWED_ENVIRONMENTS would couple two questions that merely
 * happen to share an answer today: "which environments do we ingest notifications
 * from" and "which environments may a client attest ownership in". They will
 * diverge — production notifications get enabled at a different moment from
 * production attestation — and coupling them means one change silently alters the
 * other. Same reasoning that keeps APPLE_IAP_BUNDLE_ID separate from
 * APPLE_CLIENT_ID.
 *
 * Defaults to Sandbox: the safe direction, and the U5 window's intended state.
 */
export function attestPolicyFromEnv(env: { get(k: string): string | undefined }): AttestPolicy {
  const bundleId = env.get("APPLE_IAP_BUNDLE_ID");
  if (!bundleId) throw new Error("missing required secret APPLE_IAP_BUNDLE_ID");
  const allowed = (env.get("APPLE_ATTEST_ALLOWED_ENVIRONMENTS") ?? "Sandbox")
    .split(",").map((s) => s.trim()).filter(Boolean);
  return { bundleId, productIds: CONNECTED_PRODUCT_IDS, allowedEnvironments: allowed };
}

/**
 * What a verified attestation yields. NOTE WHAT IS ABSENT: the JWS itself, and
 * anything derived from it that would let a caller reconstruct it.
 *
 * `signed_date` is present for DIAGNOSTICS ONLY. Under F3b's P2 result it is
 * approximately the purchase instant and grows stale by design; nothing may gate
 * on it. It is here so an operator can see how old an artefact was, not so code
 * can decide.
 */
export interface AttestedTransaction {
  original_transaction_id: string;
  transaction_id: string | null;
  product_id: string;
  environment: string;
  /** The token Apple embedded at purchase. NULL for the legacy population. */
  app_account_token: string | null;
  in_app_ownership_type: string | null;
  /** Diagnostics only — never a gate. See P2. */
  signed_date: string | null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const str = (v: unknown): string | null =>
  typeof v === "string" && v.length > 0 ? v : null;
/** Bound anything echoed into an error, even post-verification. */
const safe = (v: unknown): string =>
  typeof v === "string" ? v.slice(0, 80).replace(/[^\x20-\x7e]/g, "?") : String(v);

/**
 * Verify a client-supplied transaction JWS and enforce the Etudes claims.
 *
 * ORDER MATTERS AND IS NOT ARBITRARY. Signature first, because nothing in the
 * payload means anything until Apple has vouched for it — reading a claim from an
 * unverified payload and acting on it is the whole class of bug this exists to
 * prevent. Then identity of the app, then the environment, then the product:
 * cheapest and most decisive first, so a foreign payload is dismissed before we
 * reason about its contents.
 *
 * @param anchorDer present ONLY so the local battery can drive the chain walk
 *   with its own test CA, exactly as verifyChain does. Nothing reachable in
 *   production can substitute an anchor: the attest endpoint calls this with two
 *   arguments and there is no env var or flag that changes it.
 */
export async function verifyAttestationJWS(
  jws: unknown,
  policy: AttestPolicy,
  at: Date = new Date(),
  anchorDer?: Uint8Array,
): Promise<AttestedTransaction> {
  // ---- 1. Apple signed these bytes. UNCHANGED U4 BEHAVIOUR, reused verbatim.
  let payload: Record<string, unknown>;
  try {
    payload = anchorDer
      ? await verifyAppleJWS(jws, at, anchorDer)
      : await verifyAppleJWS(jws, at);
  } catch (e) {
    // Categories pass through so 'decode' and 'signature' keep meaning exactly
    // what they mean everywhere else in this codebase.
    const category: AttestFailure = e instanceof JwsError ? e.category : "signature";
    throw new AttestError(category, `transaction JWS rejected: ${category}`);
  }

  // ---- 2. IS IT EVEN OUR APP? The single most important check here, because
  // without it every other field is a fact about a stranger's subscription.
  const bundleId = str(payload.bundleId);
  if (bundleId !== policy.bundleId) {
    throw new AttestError(
      "foreign_app",
      `transaction is for bundleId ${safe(bundleId)}, not this app`,
    );
  }

  // ---- 3. An environment this deployment is willing to attest in.
  const environment = str(payload.environment);
  if (environment === null || !policy.allowedEnvironments.includes(environment)) {
    throw new AttestError(
      "environment",
      `environment ${safe(environment)} is not attestable here`,
    );
  }

  // ---- 4. One of the two Connected subscriptions, and nothing else. A
  // consumable or a future unrelated product must never buy Connected access.
  const productId = str(payload.productId);
  if (productId === null || !policy.productIds.includes(productId)) {
    throw new AttestError(
      "foreign_product",
      `productId ${safe(productId)} is not a Connected subscription`,
    );
  }

  // ---- 5. FAMILY SHARING IS TERMINAL, AND IT IS REFUSED HERE RATHER THAN
  // DISCOVERED AT APPLE. Set App Account Token returns
  // FamilyTransactionNotSupportedError (4000185) for FAMILY_SHARED transactions
  // permanently — such a transaction can NEVER carry a binding, so it can never
  // establish ownership. Family Sharing is off for both products, so this should
  // not arise; "should not arise" is not "is handled", and refusing at the door
  // turns an unreachable Apple error into a clear local refusal.
  const ownership = str(payload.inAppOwnershipType);
  if (ownership === "FAMILY_SHARED") {
    throw new AttestError(
      "family_shared",
      "FAMILY_SHARED transactions can never carry an appAccountToken",
    );
  }

  // ---- 6. Usable at all. originalTransactionId is what every later Apple call
  // is keyed on, so its absence is not recoverable downstream.
  const originalTransactionId = str(payload.originalTransactionId);
  if (originalTransactionId === null) {
    throw new AttestError("schema", "transaction carries no originalTransactionId");
  }

  // REVOCATION IS DELIBERATELY NOT CHECKED HERE. The JWS answers WHO, never NOW —
  // that is the whole of B-24's three-artefact split, and F3b's P2 result is why
  // it has to be. A revoked transaction still proves possession; whether the
  // subscription is currently live is the live Apple read's question alone.

  const rawToken = payload.appAccountToken;
  return {
    original_transaction_id: originalTransactionId,
    transaction_id: str(payload.transactionId),
    product_id: productId,
    environment,
    app_account_token: typeof rawToken === "string" && UUID_RE.test(rawToken)
      ? rawToken.toLowerCase()
      : null,
    in_app_ownership_type: ownership,
    signed_date: typeof payload.signedDate === "number" && payload.signedDate > 0
      ? new Date(payload.signedDate).toISOString()
      : null,
  };
}

// ============================================ the re-read, as a code path
//
// U5a settled that a successful Set App Account Token call is NOT sufficient
// evidence of binding, and that the re-read must be independent. That was a rule
// somebody had to remember. THE FUNCTIONS BELOW MAKE IT A TYPE.
//
// setAppAccountToken returns void, so it cannot be mistaken for confirmation;
// observeAppAccountToken performs a fresh authoritative read and is the only
// thing that produces evidence; and interpretObservation names the four outcomes
// so the PROPAGATION case cannot be quietly collapsed into failure.


export interface TokenObservation {
  /** A lastTransactions entry for this originalTransactionId was present. */
  found: boolean;
  /** The token Apple reports for it RIGHT NOW. Null is meaningful, not missing. */
  token: string | null;
}

/**
 * Read back what Apple actually holds. THE ONLY ACCEPTABLE EVIDENCE OF BINDING.
 *
 * The nested JWS is verified in its own right, with the same pinned anchor and
 * the same code path as everywhere else — trusting it because it arrived over
 * our own authenticated HTTPS call would be the obvious mistake, and it is the
 * one the U4 battery already has a fixture for.
 */
export interface AuthoritativeRead extends TokenObservation {
  /** Apple's current state, or null when the entry is unusable for derivation. */
  state: MembershipState | null;
  /** Why state is null, when it is. Diagnostics, never authority. */
  reason: string | null;
}

/**
 * THE LIVE AUTHORITATIVE READ, verification included.
 *
 * WHY THIS LIVES HERE RATHER THAN IN THE ENDPOINT, and it is a security property
 * rather than tidiness: with the read and its nested-JWS verification behind this
 * function, **the attest endpoint never calls verifyAppleJWS at all**. That turns
 * B-31's requirement -- that client input goes through the claim boundary and
 * never through the bare verifier -- into a one-line structural assertion over
 * the endpoint source, instead of a reviewer's judgement about which variable
 * reached which call.
 *
 * EVERY NESTED JWS IS VERIFIED IN ITS OWN RIGHT. They arrive over our own
 * authenticated HTTPS call to Apple, and trusting them for that reason is the
 * obvious mistake -- the transport authenticates the host, not the payload.
 */
export async function readAuthoritativeState(
  api: { getAllSubscriptionStatuses(e: AppleEnvironment, id: string): Promise<unknown> },
  environment: AppleEnvironment,
  originalTransactionId: string,
  anchorDer?: Uint8Array,
): Promise<AuthoritativeRead> {
  const verify = (j: string) =>
    anchorDer ? verifyAppleJWS(j, new Date(), anchorDer) : verifyAppleJWS(j);

  const response = await api.getAllSubscriptionStatuses(environment, originalTransactionId);
  for (const entry of lastTransactionsOf(response)) {
    if (String(entry.originalTransactionId ?? "") !== originalTransactionId) continue;

    const tx = typeof entry.signedTransactionInfo === "string"
      ? await verify(entry.signedTransactionInfo) : null;
    const ri = typeof entry.signedRenewalInfo === "string"
      ? await verify(entry.signedRenewalInfo) : null;

    const raw = tx?.appAccountToken;
    const token = typeof raw === "string" && UUID_RE.test(raw) ? raw.toLowerCase() : null;

    const derived = deriveFromReconciliation({ transaction: tx, renewal: ri, status: entry.status });
    return derived.state === null
      ? { found: true, token, state: null, reason: derived.reason }
      : { found: true, token, state: derived.state, reason: null };
  }
  return { found: false, token: null, state: null, reason: "no matching lastTransactions entry" };
}

/** The token-only view of the same read — used for the post-PUT re-read. */
export async function observeAppAccountToken(
  api: { getAllSubscriptionStatuses(e: AppleEnvironment, id: string): Promise<unknown> },
  environment: AppleEnvironment,
  originalTransactionId: string,
  anchorDer?: Uint8Array,
): Promise<TokenObservation> {
  const r = await readAuthoritativeState(api, environment, originalTransactionId, anchorDer);
  return { found: r.found, token: r.token };
}

export type BindingObservation =
  | { outcome: "ours" }
  | { outcome: "propagating" }
  | { outcome: "foreign"; token: string }
  | { outcome: "unavailable" };

/**
 * Four outcomes, and the third and fourth are why this is a function.
 *
 * **'propagating' IS NOT FAILURE.** Apple applies the token to the current
 * renewal transaction and all subsequent renewals, and documents nothing about
 * read-after-write visibility. A re-read that does not yet show our token means
 * WRITE NOTHING AND RETRY ON A LATER ATTESTATION — never "the call failed", and
 * never "accept the 200 as sufficient". Attestation runs on every foreground, so
 * a legacy claim completing on the second pass is invisible to the member.
 * P12 already proved Apple-side propagation is real and indistinguishable from
 * misconfiguration while it lasts.
 *
 * 'foreign' is a security and account-recovery event (B-24): grant nothing,
 * change nothing, and never call Set App Account Token to overwrite it — Apple
 * would happily let us, which is exactly why our rule has to be the protection.
 */
export function interpretObservation(o: TokenObservation, ourToken: string): BindingObservation {
  if (!o.found) return { outcome: "unavailable" };
  if (o.token === null) return { outcome: "propagating" };
  return o.token.toLowerCase() === ourToken.toLowerCase()
    ? { outcome: "ours" }
    : { outcome: "foreign", token: o.token };
}
