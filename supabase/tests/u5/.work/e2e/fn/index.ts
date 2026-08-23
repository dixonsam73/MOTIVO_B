import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AppleApiError,
  AppStoreServerApi,
  type AppleEnvironment,
  classifyTokenAssignment,
  credentialsFromEnv,
} from "../_shared/appstore/api.ts";
import {
  AttestError,
  attestPolicyFromEnv,
  interpretObservation,
  observeAppAccountToken,
  readAuthoritativeState,
  verifyAttestationJWS,
} from "../_shared/appstore/attest.ts";

// membership_attest_v1 — B-24's ownership protocol, end to end.
//
//   authenticated Etudes identity
//     -> verified client JWS            (WHO — possession, claim-checked)
//     -> live server->Apple read        (NOW — current authoritative state)
//     -> appAccountToken comparison     (THE DURABLE BINDING)
//     -> atomic establishment           (U5b's writer, the only INSERT)
//
// THE THREE ARTEFACTS ARE NOT INTERCHANGEABLE AND THIS FUNCTION NEVER SUBSTITUTES
// ONE FOR ANOTHER. The JWS proves possession and is NEVER read as current
// entitlement — F3b proved it is a stored historical representation whose
// signedDate is fixed at approximately the purchase instant, so treating it as
// evidence of "now" would entitle a subscriber who lapsed years ago. Apple's live
// read proves "now" and says nothing about who. The token binds the two.
//
// ── AUTHORISATION ─────────────────────────────────────────────────────────
//
// verify_jwt = false plus our OWN auth.getUser(token), which is stricter than the
// gateway: the Etudes identity is derived from the verified session and NEVER
// from the request body. There is no user_id parameter to tamper with. The body
// carries exactly one field, and it is an artefact Apple signed.
//
// ── THE CLIENT JWS IS A LONG-LIVED BEARER ARTEFACT ────────────────────────
//
// NEVER LOGGED, NEVER PERSISTED, NEVER ECHOED. Under F3b's P2 result it stays
// valid for the LIFE OF THE TRANSACTION, so a leak is permanent rather than
// expiring in minutes. It is read once, handed to verifyAttestationJWS, and never
// stored, returned, or included in any log line or error body.
//
// **THIS FUNCTION NEVER CALLS verifyAppleJWS.** Client input goes through
// verifyAttestationJWS, which applies the B-31 claim boundary; Apple's own
// responses are verified inside readAuthoritativeState. Both are in _shared, so
// "the endpoint enforces the claim boundary" is a structural assertion over this
// file rather than a reviewer's judgement — see E5d-STRUCT.
//
// ── WHAT IT MAY NOT DO ────────────────────────────────────────────────────
//
// No second membership writer: establishment goes only through
// membership_establish_v1, so provenance immutability, the conflict rule and F11
// (establishment never schedules cleanup) are inherited rather than reimplemented.
// No table privilege is used or needed. No policy, no enforcement, no cleanup.

const json = (status: number, body: Record<string, unknown>): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;
  const ANON_KEY = Deno.env.get("ANON_KEY") ?? SERVICE_ROLE;

  // ------------------------------------------------------------------ auth
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(401, { error: "authentication required" });

  // The caller's OWN client. Two things come from it and nothing else does: the
  // verified identity, and the binding token, which ensure_membership_binding()
  // derives from auth.uid() and therefore cannot be aimed at another identity.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser(token);
  const uid = userData?.user?.id;
  if (userErr || !uid) return json(401, { error: "authentication required" });

  // ------------------------------------------------------------------ body
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body is not JSON" });
  }
  const clientJws = body.jws;
  if (typeof clientJws !== "string" || clientJws.length === 0) {
    return json(400, { error: "jws required" });
  }

  // ---------------------------------------------- WHO: the claim boundary
  //
  // B-31. "Apple signed it" is nearly worthless on its own here, because the
  // payload arrives from a client: any Apple-signed transaction from any app
  // satisfies it. verifyAttestationJWS additionally requires our bundleId, an
  // attestable environment, one of the two Connected products, a non-Family-Shared
  // ownership type and a usable originalTransactionId.
  let attested;
  try {
    attested = await verifyAttestationJWS(clientJws, attestPolicyFromEnv(Deno.env));
  } catch (e) {
    if (e instanceof AttestError) {
      // The category and the terminal flag are safe to return: they name OUR
      // decision, and the message names only claims Apple itself signed. The JWS
      // is not echoed and is not logged.
      console.error(`[U5] attest refused req=${requestId} category=${e.category}`);
      return json(422, {
        error: "attestation refused",
        category: e.category,
        terminal: e.terminal,
        request_id: requestId,
      });
    }
    throw e;
  }

  // ENVIRONMENT AND ORIGINAL TRANSACTION ID COME FROM THE VERIFIED CLAIMS, never
  // from the body. A body-supplied environment would let a caller aim the Apple
  // read at the wrong host, and a body-supplied transaction id is precisely the
  // bare-identifier bypass B-24 exists to prevent.
  const environment = attested.environment as AppleEnvironment;
  const originalTransactionId = attested.original_transaction_id;

  // -------------------------------------------------------- our binding token
  // Idempotent, derived from auth.uid() inside the database, and created on the
  // caller's first attestation. Called AS THE USER, which is why it is safe.
  const { data: bindingToken, error: bindErr } = await asUser.rpc("ensure_membership_binding");
  if (bindErr || typeof bindingToken !== "string") {
    console.error(`[U5] binding unavailable req=${requestId}: ${bindErr?.message}`);
    return json(500, { error: "binding unavailable", request_id: requestId });
  }

  // ------------------------------------------------------------- Apple client
  let apple: AppStoreServerApi;
  try {
    const overrides: Partial<Record<AppleEnvironment, string>> = {};
    const sb = Deno.env.get("APPLE_API_BASE_URL_SANDBOX");
    const pr = Deno.env.get("APPLE_API_BASE_URL_PRODUCTION");
    if (sb) overrides.Sandbox = sb;
    if (pr) overrides.Production = pr;
    apple = new AppStoreServerApi(credentialsFromEnv(Deno.env), { baseUrls: overrides });
  } catch (e) {
    return json(500, { error: `credentials unavailable: ${String(e)}` });
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const appleUnavailable = (e: unknown, stage: string): Response => {
    const err = e instanceof AppleApiError
      ? { kind: e.kind, status: e.status, retryable: e.retryable }
      : { kind: "unknown" };
    console.error(`[U5] apple read failed req=${requestId} stage=${stage}: ${JSON.stringify(err)}`);
    // A FAILED OR AMBIGUOUS READ WRITES NOTHING, and says so explicitly so a
    // caller cannot read a failure as a completed no-op.
    return json(502, { error: "apple unavailable", wrote: false, stage, apple: err, request_id: requestId });
  };

  // ------------------------------------------------- NOW: the live Apple read
  let live;
  try {
    live = await readAuthoritativeState(apple, environment, originalTransactionId);
  } catch (e) {
    return appleUnavailable(e, "status");
  }
  if (!live.found) {
    return json(502, {
      error: "apple returned no matching subscription",
      wrote: false, stage: "status", request_id: requestId,
    });
  }
  if (live.state === null) {
    // Apple answered, but not with something we can order or derive from. B-25's
    // rule: refuse and reconcile later rather than store a null that derives to
    // "expired".
    return json(502, {
      error: "apple state incomplete", wrote: false, stage: "status",
      reason: live.reason, request_id: requestId,
    });
  }

  // -------------------------------------- THE BINDING DECISION, made in SQL
  //
  // The comparison that authorises a write happens INSIDE the write transaction,
  // against the live binding table. Deciding here and trusting it afterwards
  // would be a TOCTOU race: a concurrent binding change between this read and the
  // write would be invisible. So the token Apple reports is passed in, and
  // membership_establish_v1 resolves, decides and writes atomically.
  const establish = async (appleToken: string | null, state: unknown) =>
    await db.rpc("membership_establish_v1", {
      p_user_id: uid,
      p_environment: environment,
      p_original_transaction_id: originalTransactionId,
      p_apple_token: appleToken,
      p_jws_token: attested.app_account_token,
      p_state: state,
    });

  let { data: result, error: estErr } = await establish(live.token, live.state);
  if (estErr) {
    console.error(`[U5] establish failed req=${requestId}: ${estErr.message}`);
    return json(500, { error: "establishment failed", wrote: false, request_id: requestId });
  }

  let outcome = String((result as Record<string, unknown>)?.outcome ?? "unknown");
  let claimed = false;

  // ------------------------------------------- the legacy claim / orphan rebind
  //
  // 'requires_claim' covers BOTH shapes and the database distinguishes them: Apple
  // reports no token at all (the legacy population), or reports one matching no
  // live binding (an orphan, typically left by an explicit account deletion). Both
  // need the same outbound sequence, and the ORDER IS THE PROTOCOL:
  //
  //     Set App Account Token  ->  INDEPENDENT Apple re-read  ->  establishment
  //
  // A correct final row reached in the wrong order is a FAILURE, not a pass:
  // establishing on the strength of the PUT's own 200 is exactly the mistake U5a
  // ruled out, because Apple documents no read-after-write guarantee and P12
  // already proved Apple-side propagation looks identical to misconfiguration.
  if (outcome === "requires_claim") {
    try {
      await apple.setAppAccountToken(environment, originalTransactionId, bindingToken);
    } catch (e) {
      const d = classifyTokenAssignment(e);
      console.error(`[U5] token assignment ${d.kind} req=${requestId} reason=${d.reason}`);
      if (d.kind === "terminal") {
        // Permanent. Family Sharing, a non-original transaction id, an unknown
        // transaction. Record the refusal and STOP -- retrying forever against a
        // FAMILY_SHARED transaction is the failure mode the taxonomy prevents.
        return json(200, {
          outcome: "terminal_refusal", wrote: false,
          reason: d.reason, apple_error_code: d.appleErrorCode, request_id: requestId,
        });
      }
      return json(502, {
        error: "token assignment failed", wrote: false, stage: "set_token",
        retryable: true, reason: d.reason, request_id: requestId,
      });
    }
    claimed = true;

    // A SUCCESSFUL PUT IS NOT EVIDENCE. Independent re-read, or nothing.
    let observation;
    try {
      observation = await observeAppAccountToken(apple, environment, originalTransactionId);
    } catch (e) {
      return appleUnavailable(e, "reread");
    }
    const verdict = interpretObservation(observation, bindingToken);

    if (verdict.outcome === "propagating") {
      // NOT A FAILURE. Apple accepted the assignment and has not surfaced it yet.
      // Write nothing and let a later attestation finish the job -- attestation
      // runs on every foreground, so this is invisible to the member.
      return json(200, {
        outcome: "pending", wrote: false, retry: true,
        reason: "apple has not yet surfaced the binding token", request_id: requestId,
      });
    }
    if (verdict.outcome === "unavailable") {
      return json(502, { error: "apple unavailable", wrote: false, stage: "reread", request_id: requestId });
    }
    if (verdict.outcome === "foreign") {
      // Somebody bound this subscription between our PUT and our re-read. Grant
      // nothing; the database records the conflict on the next line.
      const { data: c } = await establish(verdict.token, live.state);
      return json(200, {
        outcome: String((c as Record<string, unknown>)?.outcome ?? "conflict"),
        wrote: false, request_id: requestId,
      });
    }

    // Apple now reports OUR token. Re-derive from a fresh authoritative read so
    // the row carries Apple's current state rather than the pre-claim snapshot.
    let after;
    try {
      after = await readAuthoritativeState(apple, environment, originalTransactionId);
    } catch (e) {
      return appleUnavailable(e, "post_claim_status");
    }
    if (after.state === null) {
      return json(502, {
        error: "apple state incomplete after claim", wrote: false,
        stage: "post_claim_status", reason: after.reason, request_id: requestId,
      });
    }
    ({ data: result, error: estErr } = await establish(after.token, after.state));
    if (estErr) {
      console.error(`[U5] establish-after-claim failed req=${requestId}: ${estErr.message}`);
      return json(500, { error: "establishment failed", wrote: false, request_id: requestId });
    }
    outcome = String((result as Record<string, unknown>)?.outcome ?? "unknown");
  }

  console.log(
    `[U5] attest req=${requestId} env=${environment} outcome=${outcome} claimed=${claimed}`,
  );

  return json(200, {
    ok: true,
    outcome,
    claimed,
    environment,
    request_id: requestId,
    result,
  });
});
