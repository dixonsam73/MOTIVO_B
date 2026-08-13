import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// revoke_apple_identity_v1
//
// Revokes the caller's Sign in with Apple authorization, so that deleting an
// Études Connected account also ends the relationship on Apple's side. Called
// by the client IMMEDIATELY BEFORE delete_account_v1, and never by it.
//
// Written clean from the verified requirements. It is NOT c44_exchange_probe
// with a revoke bolted on; the probe was deleted before this was started.
//
// WHY THE ORDER IS FORCED
//
// delete_account_v1 removes the auth.users row, which invalidates the Supabase
// session this function authenticates with. Revocation must therefore happen
// first. Note the converse is safe and was checked: revoking at Apple does NOT
// invalidate the Supabase access token — Supabase's JWT is independent of
// Apple's grant — so delete_account_v1 still works afterwards.
//
// WHY FAILURE HERE MUST NEVER BLOCK DELETION
//
// TN3194: "If you don't have the user's refresh token, access token, or
// authorization code, you must still fulfill the user's account deletion
// request and meet the account deletion requirement."
//
// This function reports failure TRUTHFULLY, with real status codes, and does
// NOT disguise Apple errors as success. The non-blocking guarantee lives in the
// client instead, in the SIGNATURE of AppleRevocationService.attemptRevocation,
// which cannot throw and therefore cannot propagate into the deletion path's
// do/catch however carelessly it is called. Compiler-enforced, not conventional.
//
// EVIDENCE BEHIND THE SHAPE (all device-verified 2026-08-13, see C-44)
//
//   - /auth/revoke does not accept an authorization code. The /auth/token
//     exchange is mandatory. Its `token` takes a refresh or access token.
//   - A REAL native code exchanges with NO redirect_uri: apple_status 200,
//     sent_redirect_uri false.
//   - client_id is the bundle identifier; the exchanged id_token's `aud` came
//     back as com.sdsongs.etudes.
//   - Binding the exchanged `sub` to the caller's Supabase Apple identity works
//     against identities[].identity_data.sub.
//   - Web Crypto's ES256 output is accepted (raw r||s, not DER — TN3107).

const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";

// ---------------------------------------------------------------- utilities

function b64urlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
  const bin = atob(b64 + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function stringToB64url(str: string): string {
  return bytesToB64url(new TextEncoder().encode(str));
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  return b64urlToBytes(body.replace(/\+/g, "-").replace(/\//g, "_"));
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Apple's "Creating a client secret": alg ES256, kid = Key ID, iss = Team ID,
 * aud = https://appleid.apple.com, sub = client_id, exp at most 15777000s out.
 * Five minutes: it is used twice, seconds apart, within one request.
 *
 * Web Crypto's ECDSA output is raw r||s, which is what TN3107 requires when it
 * says the library must not "decode using ASN.1 DER byte format".
 */
async function mintClientSecret(
  p8Pem: string,
  keyId: string,
  teamId: string,
  clientId: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const signingInput =
    `${stringToB64url(JSON.stringify({ alg: "ES256", kid: keyId }))}.` +
    `${stringToB64url(JSON.stringify({
      iss: teamId,
      iat: now,
      exp: now + 300,
      aud: APPLE_ISSUER,
      sub: clientId,
    }))}`;

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
  return `${signingInput}.${bytesToB64url(new Uint8Array(sig))}`;
}

// ------------------------------------------------- id_token verification
// DECISION PENDING — see the proposal. If TLS-only claim parsing is chosen,
// delete verifyAppleIdToken entirely and replace its call site with a plain
// payload decode. Nothing else changes.

/** Verifies the JWS signature against Apple's published keys, then returns claims. */
async function verifyAppleIdToken(
  idToken: string,
  expectedAudience: string,
): Promise<Record<string, unknown> | null> {
  const parts = idToken.split(".");
  if (parts.length !== 3) return null;

  let header: { kid?: string; alg?: string };
  let payload: Record<string, unknown>;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));
  } catch {
    return null;
  }
  if (header.alg !== "RS256" || !header.kid) return null;

  const jwks = await fetch(APPLE_KEYS_URL).then((r) => r.json()).catch(() => null);
  const jwk = jwks?.keys?.find((k: { kid?: string }) => k.kid === header.kid);
  if (!jwk) return null;

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) return null;

  if (payload.iss !== APPLE_ISSUER) return null;
  if (payload.aud !== expectedAudience) return null;
  if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) return null;

  return payload;
}

// ------------------------------------------------------------------ handler

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;

  // Never from the request body. A client-supplied client_id would let a caller
  // aim the exchange at another App ID, and it is the Debug/Release bundle-ID
  // trap recorded in C-44 (a Debug-minted code cannot be revoked with the
  // Release client_id — TN3107 lists exactly that as an invalid_grant cause).
  const APPLE_CLIENT_ID = Deno.env.get("APPLE_CLIENT_ID");
  const APPLE_SIWA_KEY_ID = Deno.env.get("APPLE_SIWA_KEY_ID");
  const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID");
  const APPLE_SIWA_P8_B64 = Deno.env.get("APPLE_SIWA_P8_B64");

  if (!APPLE_CLIENT_ID || !APPLE_SIWA_KEY_ID || !APPLE_TEAM_ID || !APPLE_SIWA_P8_B64) {
    return json({ revoked: false, stage: "config", reason: "missing_apple_configuration" }, 500);
  }

  // Same authorisation story as delete_account_v1: verify_jwt is false and this
  // in-body check is the gate. The subject is derived from the verified token
  // and never from the request body.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ revoked: false, stage: "auth", reason: "missing_authorization" }, 401);
  const token = authHeader.replace("Bearer ", "");

  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: userErr } = await anon.auth.getUser(token);
  if (userErr || !userData?.user?.id) {
    return json({ revoked: false, stage: "auth", reason: "invalid_session" }, 401);
  }
  const uid = userData.user.id;

  let parsed: { authorization_code?: string };
  try {
    parsed = await req.json();
  } catch {
    return json({ revoked: false, stage: "request", reason: "malformed_body" }, 400);
  }
  const authorizationCode = parsed.authorization_code;
  if (!authorizationCode) {
    return json({ revoked: false, stage: "request", reason: "missing_authorization_code" }, 400);
  }

  const clientSecret = await mintClientSecret(
    atob(APPLE_SIWA_P8_B64),
    APPLE_SIWA_KEY_ID,
    APPLE_TEAM_ID,
    APPLE_CLIENT_ID,
  );

  // ---- exchange. No redirect_uri: verified unnecessary for a native code.
  const exchangeForm = new URLSearchParams({
    client_id: APPLE_CLIENT_ID,
    client_secret: clientSecret,
    grant_type: "authorization_code",
    code: authorizationCode,
  });

  let exchangeRes: Response;
  try {
    exchangeRes = await fetch(APPLE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: exchangeForm,
    });
  } catch {
    return json({ revoked: false, stage: "exchange", reason: "apple_unreachable" }, 502);
  }

  const exchangeBody = await exchangeRes.json().catch(() => ({}));
  if (exchangeRes.status !== 200) {
    // Apple's short error enum only. Never the description, never the body.
    return json({
      revoked: false,
      stage: "exchange",
      reason: typeof exchangeBody.error === "string" ? exchangeBody.error : "unparsable",
    }, exchangeRes.status >= 500 ? 502 : 422);
  }

  const refreshToken = exchangeBody.refresh_token;
  const idToken = exchangeBody.id_token;
  if (typeof refreshToken !== "string" || typeof idToken !== "string") {
    return json({ revoked: false, stage: "exchange", reason: "unexpected_token_response" }, 502);
  }

  // ---- bind the Apple identity to the authenticated caller before revoking.
  const claims = await verifyAppleIdToken(idToken, APPLE_CLIENT_ID);
  if (!claims) {
    return json({ revoked: false, stage: "verify", reason: "id_token_rejected" }, 422);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
  const { data: adminUser } = await admin.auth.admin.getUserById(uid);
  const appleIdentity = adminUser?.user?.identities
    ?.find((i: { provider?: string }) => i.provider === "apple");
  const callerAppleSub =
    (appleIdentity?.identity_data?.sub as string | undefined) ??
    (appleIdentity?.id as string | undefined);

  if (typeof claims.sub !== "string" || !callerAppleSub || claims.sub !== callerAppleSub) {
    // Refuse to revoke an authorization that is not the caller's own.
    return json({ revoked: false, stage: "bind", reason: "subject_mismatch" }, 403);
  }

  // ---- revoke. 200 also means "was previously invalid", so this is idempotent.
  const revokeForm = new URLSearchParams({
    client_id: APPLE_CLIENT_ID,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: "refresh_token",
  });

  let revokeRes: Response;
  try {
    revokeRes = await fetch(APPLE_REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: revokeForm,
    });
  } catch {
    return json({ revoked: false, stage: "revoke", reason: "apple_unreachable" }, 502);
  }

  if (revokeRes.status !== 200) {
    const revokeBody = await revokeRes.json().catch(() => ({}));
    return json({
      revoked: false,
      stage: "revoke",
      reason: typeof revokeBody.error === "string" ? revokeBody.error : "unparsable",
    }, revokeRes.status >= 500 ? 502 : 422);
  }

  // Tokens go out of scope here. Nothing is stored and nothing is logged: this
  // function contains no console call at all, because Edge Function logs
  // persist and an Apple credential must never be given the chance to reach one.
  return json({ revoked: true, stage: "revoke" }, 200);
});
