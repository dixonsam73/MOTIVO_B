import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// c44_exchange_probe — TEMPORARY INSTRUMENTATION. C-44 gate (b2).
//
// DELETE AFTER ONE RUN. This function is not a draft of
// revoke_apple_identity_v1 and must not be evolved into it. Production gets
// written clean, from the verified requirements, once this has reported.
//
// THE ONE QUESTION IT ANSWERS
//
// Does a REAL native Sign in with Apple authorization code exchange
// successfully at POST https://appleid.apple.com/auth/token with
// client_id = com.sdsongs.etudes and NO redirect_uri?
//
// Gate (b1) established that the request is structurally accepted and that our
// Web Crypto ES256 client secret is valid (no invalid_client). It could not
// settle this, because Apple's validation order is unobserved and a garbage
// code cannot demonstrate a successful exchange. Only a real code can.
//
// WHAT IT DELIBERATELY DOES NOT DO
//
//   - No call to /auth/revoke. The string "revoke" does not appear in this
//     file outside these comments, and that is checkable with grep.
//   - No deletion of anything, anywhere.
//   - No write to any table, any bucket, or any storage path. The only
//     database access is a READ of the caller's identity list.
//   - No Apple token value, fragment, hash or LENGTH is returned or logged.
//   - The Apple `sub` is never returned. It is compared server-side and only
//     the boolean result leaves the function.
//   - No console.log of Apple's response body at any point. Edge Function logs
//     persist, so the response is never given the chance to reach them.
//   - delete_account_v1 is not imported, called or touched.
//
// The exchanged tokens go out of scope when the request ends and are never
// persisted. One live Apple refresh token is therefore minted and abandoned by
// this run — nobody holds it, so nobody can use it, and the eventual
// production end-to-end test revokes it. Stated plainly rather than buried.

const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";

// ---------------------------------------------------------------- utilities

function b64urlFromBytes(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlFromString(str: string): string {
  return b64urlFromBytes(new TextEncoder().encode(str));
}

/** PEM PKCS#8 → DER bytes for crypto.subtle.importKey. */
function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Claims only. See the note at the call site on why the signature is not verified. */
function decodeJwtPayload(jwt: string): Record<string, unknown> | null {
  const parts = jwt.split(".");
  if (parts.length !== 3) return null;
  const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
  try {
    return JSON.parse(atob(b64 + pad));
  } catch {
    return null;
  }
}

/**
 * Per Apple's "Creating a client secret": alg ES256, kid = Key ID, iss = Team
 * ID, aud = https://appleid.apple.com, sub = the client_id, exp at most
 * 15777000 seconds out. Five minutes is used here — this secret exists for one
 * request.
 *
 * Web Crypto's ECDSA output is raw r||s, which is what TN3107 requires when it
 * says the library must not "decode using ASN.1 DER byte format". This exact
 * code path was verified against Apple in gate (b1).
 */
async function mintClientSecret(
  p8Pem: string,
  keyId: string,
  teamId: string,
  clientId: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId };
  const payload = {
    iss: teamId,
    iat: now,
    exp: now + 300,
    aud: "https://appleid.apple.com",
    sub: clientId,
  };
  const signingInput =
    `${b64urlFromString(JSON.stringify(header))}.${b64urlFromString(JSON.stringify(payload))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(p8Pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${b64urlFromBytes(new Uint8Array(sig))}`;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ------------------------------------------------------------------ handler

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;

  // APPLE_CLIENT_ID is read from the environment and NEVER from the request.
  // A client-supplied client_id would let a caller aim the exchange at another
  // App ID; it is also the Debug/Release bundle-ID trap recorded in C-44.
  const APPLE_CLIENT_ID = Deno.env.get("APPLE_CLIENT_ID");
  const APPLE_SIWA_KEY_ID = Deno.env.get("APPLE_SIWA_KEY_ID");
  const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID");
  const APPLE_SIWA_P8_B64 = Deno.env.get("APPLE_SIWA_P8_B64");

  if (!APPLE_CLIENT_ID || !APPLE_SIWA_KEY_ID || !APPLE_TEAM_ID || !APPLE_SIWA_P8_B64) {
    // Names only. No value of any secret is ever named in a response.
    return json({ probe: "c44_exchange_probe", error: "missing_apple_configuration" }, 500);
  }

  // Same authorisation shape as delete_account_v1: the subject is derived from
  // the verified token and never from the request body.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ probe: "c44_exchange_probe", error: "missing_authorization" }, 401);
  const token = authHeader.replace("Bearer ", "");

  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: userErr } = await anon.auth.getUser(token);
  if (userErr || !userData?.user?.id) {
    return json({ probe: "c44_exchange_probe", error: "invalid_session" }, 401);
  }
  const uid = userData.user.id;

  let body: { authorization_code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ probe: "c44_exchange_probe", error: "malformed_body" }, 400);
  }
  const authorizationCode = body.authorization_code;
  if (!authorizationCode) {
    return json({ probe: "c44_exchange_probe", error: "missing_authorization_code" }, 400);
  }

  const clientSecret = await mintClientSecret(
    atob(APPLE_SIWA_P8_B64),
    APPLE_SIWA_KEY_ID,
    APPLE_TEAM_ID,
    APPLE_CLIENT_ID,
  );

  // NO redirect_uri. That omission is the hypothesis under test.
  const form = new URLSearchParams();
  form.set("client_id", APPLE_CLIENT_ID);
  form.set("client_secret", clientSecret);
  form.set("grant_type", "authorization_code");
  form.set("code", authorizationCode);

  const appleRes = await fetch(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });

  const appleText = await appleRes.text(); // never logged, never returned
  let appleJson: Record<string, unknown> = {};
  try {
    appleJson = JSON.parse(appleText);
  } catch { /* leave empty; reported via exchange_ok below */ }

  if (appleRes.status !== 200) {
    // Apple's error CODE only — a short enum like "invalid_grant". Never the
    // description, never the body.
    return json({
      probe: "c44_exchange_probe",
      apple_status: appleRes.status,
      sent_redirect_uri: false,
      exchange_ok: false,
      apple_error: typeof appleJson.error === "string" ? appleJson.error : "unparsable",
      revoke_attempted: false,
    });
  }

  const accessToken = appleJson.access_token;
  const refreshToken = appleJson.refresh_token;
  const idToken = appleJson.id_token;

  // The id_token's signature is deliberately NOT verified here. It was received
  // directly from Apple over TLS in the response to our own authenticated
  // request — it was not relayed by a client — so the channel authenticates it.
  // Apple's "Verifying a user" guidance addresses the case where the token
  // arrives FROM the app, which is not this case.
  const claims = typeof idToken === "string" ? decodeJwtPayload(idToken) : null;

  const { data: adminUser } = await createClient(SUPABASE_URL, SERVICE_ROLE)
    .auth.admin.getUserById(uid);
  const appleIdentity = adminUser?.user?.identities
    ?.find((i: { provider?: string }) => i.provider === "apple");
  const callerAppleSub =
    (appleIdentity?.identity_data?.sub as string | undefined) ??
    (appleIdentity?.id as string | undefined);

  const idTokenSub = typeof claims?.sub === "string" ? claims.sub : undefined;

  // Booleans only. Neither sub is returned, and neither is logged.
  return json({
    probe: "c44_exchange_probe",
    apple_status: appleRes.status,
    sent_redirect_uri: false,
    exchange_ok: true,
    access_token_present: typeof accessToken === "string" && accessToken.length > 0,
    refresh_token_present: typeof refreshToken === "string" && refreshToken.length > 0,
    id_token_present: typeof idToken === "string" && idToken.length > 0,
    token_type_is_bearer: appleJson.token_type === "Bearer",
    expires_in_present: typeof appleJson.expires_in === "number",
    id_token_claims_readable: claims !== null,
    id_token_iss_is_apple: claims?.iss === "https://appleid.apple.com",
    id_token_aud_matches_client_id: claims?.aud === APPLE_CLIENT_ID,
    caller_apple_identity_found: typeof callerAppleSub === "string",
    id_token_sub_matches_caller:
      typeof idTokenSub === "string" &&
      typeof callerAppleSub === "string" &&
      idTokenSub === callerAppleSub,
    revoke_attempted: false,
  });
});
