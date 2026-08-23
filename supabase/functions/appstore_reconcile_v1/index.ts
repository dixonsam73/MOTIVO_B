import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AppleApiError,
  AppStoreServerApi,
  type AppleEnvironment,
  credentialsFromEnv,
  lastTransactionsOf,
} from "../_shared/appstore/api.ts";
import { verifyAppleJWS } from "../_shared/appstore/jws.ts";
import { deriveFromReconciliation } from "../_shared/appstore/derive.ts";
import { readNotificationHistory } from "../_shared/appstore/history.ts";

// appstore_reconcile_v1
//
// Authoritative reads from Apple, applied through the SAME canonical writer the
// notification path uses. OBSERVE-ONLY: it refreshes membership state and does
// nothing else. It deletes nothing and it never creates a membership row --
// creation belongs to U5, because binding_method and bound_at are statements
// about how ownership was proved and only the path that proved it may make them.
//
// WHY IT EXISTS IN U4 RATHER THAN LATER. Apple retries a failed V2 notification
// five times over 72 hours IN PRODUCTION ONLY; in sandbox it attempts delivery
// EXACTLY ONCE. Every Phase 3 gate runs in sandbox, so a single dropped response
// is unrecoverable by retry, and reconciliation is the only recovery path there
// is. It is also, unchanged, the live authoritative read U7 must perform
// immediately before any irreversible cleanup -- so U7 inherits proven code
// instead of writing a second implementation of the most dangerous call in the
// system.
//
// AUTHORISATION IS NOT THE NOTIFICATION ENDPOINT'S. This one is not public: it
// requires the service role key explicitly, compared in constant time. Note what
// verify_jwt = true would NOT have given us -- any valid user JWT would satisfy
// the gateway, and every authenticated Apple user can obtain one.
//
// A FAILED OR AMBIGUOUS READ WRITES NOTHING. Not a partial update, not a
// "probably expired", not a cleared schedule. Q6's three failure modes -- 5xx,
// timeout, malformed body -- all land on the same rule, and the local battery
// asserts zero writes under every one of them.

const json = (status: number, body: Record<string, unknown>): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

/** Constant-time comparison. Length is allowed to leak; content is not. */
function secretEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Exactly what membership_due_for_reconciliation_v1 returns — no Apple state,
 *  no scheduling state. Narrowed with the selector during the grant audit. */
interface Target {
  user_id: string;
  environment: string;
  original_transaction_id: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
  const presented = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!presented || !secretEquals(presented, SERVICE_ROLE)) {
    return json(401, { error: "service role credential required" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const mode = String(body.mode ?? "reconcile");
  const environment = (String(body.environment ?? "Sandbox")) as AppleEnvironment;
  if (environment !== "Sandbox" && environment !== "Production") {
    return json(400, { error: "environment must be Sandbox or Production" });
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const db = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let apple: AppStoreServerApi;
  try {
    // Base URL overrides exist for local stubs and for Q5/Q6. The deployment
    // package asserts both are UNSET in production, so the default hosts apply.
    const overrides: Partial<Record<AppleEnvironment, string>> = {};
    const sb = Deno.env.get("APPLE_API_BASE_URL_SANDBOX");
    const pr = Deno.env.get("APPLE_API_BASE_URL_PRODUCTION");
    if (sb) overrides.Sandbox = sb;
    if (pr) overrides.Production = pr;
    apple = new AppStoreServerApi(credentialsFromEnv(Deno.env), { baseUrls: overrides });
  } catch (e) {
    return json(500, { error: `credentials unavailable: ${String(e)}` });
  }

  const failure = (e: unknown): Response => {
    const err = e instanceof AppleApiError
      ? { kind: e.kind, status: e.status, code: e.appleErrorCode, retryable: e.retryable }
      : { kind: "unknown", detail: String(e).slice(0, 200) };
    console.error(`[U4] apple read failed mode=${mode}: ${JSON.stringify(err)}`);
    // NOTHING WAS WRITTEN. Say so explicitly in the response so a caller cannot
    // read a failure as a completed no-op.
    return json(502, { error: "apple read failed", wrote: false, apple: err });
  };

  // ------------------------------------------------ Apple's own test notification
  if (mode === "request_test_notification") {
    try {
      return json(200, { ok: true, apple: await apple.requestTestNotification(environment) });
    } catch (e) { return failure(e); }
  }
  if (mode === "test_notification_status") {
    const token = String(body.token ?? "");
    if (!token) return json(400, { error: "token required" });
    try {
      return json(200, { ok: true, apple: await apple.getTestNotificationStatus(environment, token) });
    } catch (e) { return failure(e); }
  }

  // ------------------------------------------------------- notification history
  // Diagnostic in U4, and the only honest way to score G3: sandbox never
  // retries, so "we never received it" is otherwise unfalsifiable.
  if (mode === "notification_history") {
    try {
      const window = {
        startDate: body.startDate ?? Date.now() - 24 * 3600 * 1000,
        endDate: body.endDate ?? Date.now(),
      };
      const page = await apple.getNotificationHistory(
        environment,
        window,
        body.paginationToken ? String(body.paginationToken) : undefined,
      );

      // B-32. THE UUID COMES FROM THE VERIFIED PAYLOAD, NOT FROM A FIELD THAT
      // DOES NOT EXIST. `NotificationHistoryResponseItem` carries only
      // `sendAttempts`, `signedPayload` and `firstSendAttemptResult`; reading
      // `item.notificationUUID` yielded undefined for every item and reported a
      // confident zero whatever Apple sent. The same pinned-anchor verifier the
      // notification path uses is passed in, so an item Apple did not sign can
      // never masquerade as Apple's history — which matters because G3 is scored
      // against exactly this comparison.
      const history = await readNotificationHistory(page, (j) => verifyAppleJWS(j));
      const uuids = history.items
        .map((i) => i.notification_uuid)
        .filter((u): u is string => typeof u === "string" && u.length > 0);

      // READ-ONLY, AND DELIBERATELY SO. This reports which notifications Apple
      // believes it sent; it does not replay them, because replaying a payload
      // we never verified would be exactly the bare-transaction bypass B-24
      // forbids. Comparing the list against membership_notification is an
      // operator step, and the remedy for a gap is a reconcile, not an import.
      return json(200, {
        ok: true,
        apple_notification_count: uuids.length,
        apple_notification_uuids: uuids,
        // Never silently dropped: a non-zero value means this page's evidence is
        // incomplete, and a zero count with unverifiable > 0 is NOT "Apple sent
        // nothing".
        unverifiable_items: history.unverifiable,
        // Surfaced so a multi-page history can actually be followed. Without
        // these a partial page looked exactly like a complete one.
        has_more: history.has_more,
        pagination_token: history.pagination_token,
        items: history.items,
        note: "compare apple_notification_uuids against membership_notification.notification_uuid; close gaps with mode=reconcile",
      });
    } catch (e) { return failure(e); }
  }

  // ------------------------------------------------------------- reconciliation
  if (mode !== "reconcile") return json(400, { error: `unknown mode ${mode}` });

  const { data: targets, error: targetErr } = await db.rpc(
    "membership_due_for_reconciliation_v1",
    {
      p_user_id: body.user_id ? String(body.user_id) : null,
      p_environment: body.only_environment ? String(body.only_environment) : null,
    },
  );
  if (targetErr) return json(500, { error: `target selection failed: ${targetErr.message}` });

  const results: Array<Record<string, unknown>> = [];
  for (const t of (targets ?? []) as Target[]) {
    let response: unknown;
    try {
      response = await apple.getAllSubscriptionStatuses(
        t.environment as AppleEnvironment,
        t.original_transaction_id,
      );
    } catch (e) {
      const err = e instanceof AppleApiError ? e : null;
      results.push({
        user_id: t.user_id,
        environment: t.environment,
        wrote: false,
        outcome: "unavailable",
        apple: err ? { kind: err.kind, status: err.status, retryable: err.retryable } : String(e),
      });
      continue; // A failed read is retried later. It NEVER becomes a write.
    }

    let applied: unknown = null;
    let outcome = "no_usable_entry";
    for (const entry of lastTransactionsOf(response)) {
      if (String(entry.originalTransactionId ?? "") !== t.original_transaction_id) continue;
      let tx: Record<string, unknown> | null = null;
      let ri: Record<string, unknown> | null = null;
      try {
        // Apple's API responses are signed too. Verified with the same pinned
        // anchor and the same code path as a notification -- there is one
        // verifier, not two.
        if (typeof entry.signedTransactionInfo === "string") {
          tx = await verifyAppleJWS(entry.signedTransactionInfo);
        }
        if (typeof entry.signedRenewalInfo === "string") {
          ri = await verifyAppleJWS(entry.signedRenewalInfo);
        }
      } catch (e) {
        outcome = "signature_failed";
        console.error(`[U4] reconcile inner JWS failed for ${t.user_id}: ${String(e)}`);
        break;
      }

      const derived = deriveFromReconciliation({ transaction: tx, renewal: ri, status: entry.status });
      if (derived.state === null) {
        outcome = `incomplete: ${derived.reason}`;
        break;
      }
      const { data: r, error } = await db.rpc("membership_apply_reconciliation_v1", {
        p_user_id: t.user_id,
        p_environment: t.environment,
        p_state: derived.state,
        p_original_transaction_id: derived.original_transaction_id ?? t.original_transaction_id,
      });
      if (error) {
        outcome = `write_failed: ${error.message}`;
      } else {
        applied = r;
        outcome = String((r as Record<string, unknown>)?.outcome ?? "unknown");
      }
      break;
    }

    results.push({
      user_id: t.user_id,
      environment: t.environment,
      wrote: outcome === "applied",
      outcome,
      applied,
    });
  }

  console.log(`[U4] reconcile env=${environment} targets=${results.length}`);
  return json(200, { ok: true, reconciled: results });
});
