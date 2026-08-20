import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  JwsError,
  sha256Hex,
  structurallyPlausible,
  verifyAppleJWS,
} from "../_shared/appstore/jws.ts";
import { deriveFromNotification } from "../_shared/appstore/derive.ts";

// appstore_notifications_v1
//
// App Store Server Notifications V2 ingestion. OBSERVE-ONLY: this function
// records what Apple says and updates server-authoritative membership state. It
// deletes nothing, hides nothing, enforces nothing and schedules no worker.
//
// THIS IS THE PROJECT'S FIRST GENUINELY UNAUTHENTICATED ENDPOINT, AND THE
// DISTINCTION MATTERS. delete_account_v1 and revoke_apple_identity_v1 also set
// verify_jwt = false, but each then performs its own auth.getUser(token) and is
// stricter than the gateway would have been. Apple sends no Supabase JWT. There
// is no token to check, and the JWS signature is the entire authorisation story.
// Do not read the config.toml comments for those two functions as covering this
// one.
//
// B-29 — THREE TIERS, AND THE PRINCIPLE IS THAT DURABLE PER-ROW PERSISTENCE IS A
// PRIVILEGE EARNED BY PASSING SIGNATURE VERIFICATION.
//
//   Tier 1  structural rejects write NOTHING -- not a row, not a counter. An
//           unauthenticated caller must not reach the database at all on input
//           this cheap to dismiss.
//   Tier 2  signature failures increment a fixed-cardinality aggregate whose row
//           count is bounded by hours x categories however large the flood.
//   Tier 3  verified notifications persist per-row, bounded by Apple's own
//           sending rate.
//
// STATUS CODES, AMENDED 2026-08-19 AND THE REASONING IS THE POINT. G2 used to
// require 200 for an unsigned payload, on the grounds that it will never become
// valid so retrying achieves nothing. THE U4a GATE FALSIFIED THE PREMISE: the
// catastrophic case is not a forgery but a verifier that rejects everything,
// which is exactly what the official Apple library does on this runtime while
// reporting it identically to an attack. Under 200 every legitimate notification
// lost to such a defect is lost permanently; under 5xx, production retries five
// times across 72 hours and a fix inside that window recovers them. Sandbox
// never retries either way, so the choice costs nothing there.
//
//   400  structural reject, nothing written
//   5xx  signature verification failed, or we could not durably record
//   200  verified and durably handled -- INCLUDING outcomes we refused
//        downstream, because those are decisions rather than failures
//
// SANDBOX DELIVERS EACH NOTIFICATION EXACTLY ONCE AND NEVER RETRIES. Every
// Phase 3 gate runs in sandbox, so a single dropped response is unrecoverable by
// retry there. That is why appstore_reconcile_v1 exists from the first run
// rather than being deferred.

/** Apple's own payloads run a few KB. Anything larger is not a notification. */
const MAX_BODY_BYTES = 64 * 1024;

const json = (status: number, body: Record<string, unknown>): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();

  // ------------------------------------------------------------------ Tier 1
  // Every check here is O(1) and touches no database.
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const declared = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return json(400, { error: "payload too large" });
  }

  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return json(400, { error: "unreadable body" });
  }
  if (raw.length > MAX_BODY_BYTES) return json(400, { error: "payload too large" });

  let signedPayload: unknown;
  try {
    const body = JSON.parse(raw);
    signedPayload = (body as Record<string, unknown>)?.signedPayload;
  } catch {
    return json(400, { error: "body is not JSON" });
  }
  if (!structurallyPlausible(signedPayload)) {
    return json(400, { error: "not a plausible App Store Server Notification" });
  }

  // Credentials are read only once we are past Tier 1, so a flood of junk never
  // even constructs a client.
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
  const db = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const recordReject = async (category: string, digest: string | null): Promise<void> => {
    const { error } = await db.rpc("membership_record_reject_v1", {
      p_failure_category: category,
      p_sha256: digest,
    });
    if (error) console.error(`[U4] reject-stat write failed: ${error.message}`);
  };

  // ------------------------------------------------------------------ Tier 2
  const payloadSha256 = await sha256Hex(raw);
  let notification: Record<string, unknown>;
  try {
    notification = await verifyAppleJWS(signedPayload);
  } catch (e) {
    const category = e instanceof JwsError ? e.category : "signature";
    await recordReject(category, payloadSha256);
    console.error(`[U4] verification failed req=${requestId} category=${category}: ${String(e)}`);
    // 503 rather than 401: see the status-code note above. A verifier defect and
    // a forgery are indistinguishable here, and only one of them is recoverable.
    return json(503, { error: "signature verification failed", request_id: requestId });
  }

  // ------------------------------------------------------------------ Tier 3
  // EVERY NESTED JWS IS VERIFIED IN ITS OWN RIGHT. They are separately signed by
  // Apple, and trusting them because the envelope verified is the obvious
  // mistake -- the local battery includes a fixture whose envelope is correctly
  // re-signed around a tampered inner payload precisely to catch it.
  const data = (notification.data ?? {}) as Record<string, unknown>;
  let transaction: Record<string, unknown> | null = null;
  let renewal: Record<string, unknown> | null = null;
  let innerFailure: string | null = null;

  for (
    const [field, assign] of [
      ["signedTransactionInfo", (v: Record<string, unknown>) => (transaction = v)],
      ["signedRenewalInfo", (v: Record<string, unknown>) => (renewal = v)],
    ] as const
  ) {
    if (typeof data[field] !== "string") continue;
    try {
      assign(await verifyAppleJWS(data[field]));
    } catch (e) {
      // An inner JWS failing AFTER the envelope verified is a genuine and
      // serious anomaly rather than routine hostile traffic: Apple signed the
      // envelope and its contents disagree. It keeps a durable per-row home.
      innerFailure = e instanceof JwsError ? e.category : "signature";
      console.error(`[U4] inner ${field} failed req=${requestId}: ${String(e)}`);
    }
  }

  const event = deriveFromNotification({ payload: notification, transaction, renewal });

  const allowed = (Deno.env.get("APPLE_ASSN_ALLOWED_ENVIRONMENTS") ?? "Sandbox")
    .split(",").map((s) => s.trim()).filter(Boolean);

  const base = {
    notification_uuid: event.notification_uuid,
    environment: event.environment,
    notification_type: event.notification_type,
    subtype: event.subtype,
    original_transaction_id: event.original_transaction_id,
    signed_date: event.signed_date,
    request_id: requestId,
    payload_bytes: raw.length,
    payload_sha256: payloadSha256,
  };

  let rpcArgs: Record<string, unknown>;
  if (innerFailure) {
    rpcArgs = { ...base, disposition: "unsupported", app_account_token: null, state: null };
  } else if (event.environment !== null && !allowed.includes(event.environment)) {
    // A verified notification for an environment this deployment does not serve.
    // Recorded, refused, and answered 200 -- it is a decision, not a failure.
    rpcArgs = { ...base, disposition: "unsupported", app_account_token: null, state: null };
  } else {
    rpcArgs = {
      ...base,
      disposition: event.disposition,
      app_account_token: event.app_account_token,
      state: event.state,
    };
  }

  const { data: result, error } = await db.rpc("membership_ingest_notification_v1", {
    p_event: rpcArgs,
  });
  if (error) {
    // We could not durably record. 5xx so production retries; sandbox cannot,
    // which is what reconciliation is for.
    console.error(`[U4] ingest RPC failed req=${requestId}: ${error.message}`);
    return json(503, { error: "could not record notification", request_id: requestId });
  }

  console.log(
    `[U4] ingest req=${requestId} type=${event.notification_type}/${event.subtype ?? "-"} ` +
      `env=${event.environment} outcome=${(result as Record<string, unknown>)?.outcome} ` +
      `mapped=${(result as Record<string, unknown>)?.mapped} disposition=${event.disposition}`,
  );

  return json(200, { ok: true, request_id: requestId, result });
});
