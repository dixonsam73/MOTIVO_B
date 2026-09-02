// Apple JWS verification — x5c certificate chain, pinned anchor, ES256.
//
// ROUTE CHOSEN BY THE U4a EMPIRICAL GATE, 2026-08-19, not by preference. Two
// alternatives were run inside the real edge runtime and both failed:
//
//   node:crypto X509Certificate  — the class exists and a capability probe
//     reports hasX509 true, but .verify and .toString both throw
//     ERR_NOT_IMPLEMENTED. Capability presence is not capability.
//
//   @apple/app-store-server-library@1.6.0 — imports cleanly and then rejects
//     EVERYTHING, including payloads it should accept, returning
//     VerificationException status 1 (VERIFICATION_FAILURE) whose cause is
//     "Not implemented: crypto.X509Certificate.prototype.toString". IT REPORTS
//     ITS OWN RUNTIME INCAPACITY WITH THE SAME STATUS AS A GENUINE FORGERY.
//     Deployed here it would have rejected 100% of real Apple traffic while the
//     audit table filled with rows that read exactly like an attack.
//
// Full evidence in docs/qa-plan.md, "U4a — GATE RESULT"; the reproducible probe
// is supabase/tests/u4a/.
//
// THE TRUST ANCHOR IS A PARAMETER OF verifyChain() AND A CONSTANT OF THE
// EXPORTED ENTRY POINT. That split is deliberate: the test harness exercises
// chain walking against its own CA by calling the internal function with an
// explicit anchor, while nothing reachable in production can substitute one.
// There is no environment variable, no flag and no argument on verifyAppleJWS
// that could relax it.

import {
  X509Certificate,
  cryptoProvider,
} from "@peculiar/x509";
import {
  APPLE_OID_INTERMEDIATE,
  APPLE_OID_LEAF,
  APPLE_ROOT_CA_G3_B64,
} from "./apple_root_ca_g3.ts";

cryptoProvider.set(crypto as unknown as Crypto);

/** Why a payload was refused. Maps 1:1 onto membership_notification.failure_category. */
export type JwsFailure = "decode" | "signature";

export class JwsError extends Error {
  constructor(readonly category: JwsFailure, message: string) {
    super(message);
    this.name = "JwsError";
  }
}

const b64 = (s: string): Uint8Array =>
  Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

function b64url(s: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) {
    throw new JwsError("decode", "segment is not base64url");
  }
  const p = s.replace(/-/g, "+").replace(/_/g, "/");
  return b64(p + "===".slice((p.length + 3) % 4));
}

/** Decode a JWS segment as JSON without verifying anything. Never trust the result. */
function decodeSegment(seg: string): Record<string, unknown> {
  let text: string;
  try {
    text = new TextDecoder().decode(b64url(seg));
  } catch (e) {
    throw e instanceof JwsError ? e : new JwsError("decode", "segment is not valid base64url");
  }
  try {
    const v = JSON.parse(text);
    if (v === null || typeof v !== "object" || Array.isArray(v)) {
      throw new Error("not a JSON object");
    }
    return v as Record<string, unknown>;
  } catch {
    throw new JwsError("decode", "segment is not a JSON object");
  }
}

/**
 * Walk and validate an x5c chain against `anchorDer`, returning the leaf's key.
 *
 * INTERNAL. Takes the anchor as an argument SOLELY so the U4 harness can drive
 * it with a test CA. Production callers use verifyAppleJWS, which supplies
 * Apple Root CA G3 and nothing else.
 */
export async function verifyChain(
  x5c: unknown,
  anchorDer: Uint8Array,
  at: Date,
): Promise<CryptoKey> {
  if (!Array.isArray(x5c) || x5c.length < 3) {
    throw new JwsError("signature", "x5c missing or shorter than three certificates");
  }
  if (x5c.length > 10) {
    // Bounded before any parsing: a chain longer than Apple ever sends is an
    // attempt to make us do unbounded asymmetric work per request.
    throw new JwsError("signature", "x5c longer than ten certificates");
  }

  let certs: X509Certificate[];
  try {
    certs = (x5c as string[]).map((c) => {
      if (typeof c !== "string") throw new Error("x5c entry is not a string");
      return new X509Certificate(b64(c));
    });
  } catch {
    throw new JwsError("signature", "x5c entry is not a parseable certificate");
  }

  const [leaf, intermediate] = certs;
  const anchor = new X509Certificate(anchorDer);

  // Apple's marker OIDs. Checked before any signature work because they are
  // free, and because a chain lacking them is not an App Store Server chain
  // whatever it is signed by.
  if (!intermediate.getExtension(APPLE_OID_INTERMEDIATE)) {
    throw new JwsError("signature", "intermediate lacks the Apple intermediate OID");
  }
  if (!leaf.getExtension(APPLE_OID_LEAF)) {
    throw new JwsError("signature", "leaf lacks the Apple leaf OID");
  }

  for (const [name, c] of [["leaf", leaf], ["intermediate", intermediate], ["anchor", anchor]] as const) {
    if (at < c.notBefore || at > c.notAfter) {
      throw new JwsError("signature", `${name} certificate is not valid at ${at.toISOString()}`);
    }
  }

  // THE PINNING STEP. x5c[2] is ignored entirely; the intermediate is verified
  // against OUR anchor. A payload whose chain is internally consistent but
  // rooted elsewhere fails here, which is the assertion that carries the
  // security property.
  const anchorKey = await anchor.publicKey.export(crypto as unknown as Crypto);
  if (!await intermediate.verify({ publicKey: anchorKey, signatureOnly: true })) {
    throw new JwsError("signature", "intermediate is not signed by the pinned anchor");
  }

  const intermediateKey = await intermediate.publicKey.export(crypto as unknown as Crypto);
  if (!await leaf.verify({ publicKey: intermediateKey, signatureOnly: true })) {
    throw new JwsError("signature", "leaf is not signed by the intermediate");
  }

  return await leaf.publicKey.export(crypto as unknown as Crypto);
}

/**
 * Verify one Apple-signed JWS and return its decoded payload.
 *
 * EVERY JWS IS VERIFIED IN ITS OWN RIGHT, including the signedTransactionInfo
 * and signedRenewalInfo nested inside a notification. They are separately
 * signed by Apple, and trusting them because the envelope verified is the
 * obvious mistake — the U4 battery includes a fixture whose envelope is
 * correctly re-signed around a tampered inner payload, precisely to catch it.
 */
export async function verifyAppleJWS(
  jws: unknown,
  at: Date = new Date(),
  anchorDer: Uint8Array = b64(APPLE_ROOT_CA_G3_B64),
): Promise<Record<string, unknown>> {
  if (typeof jws !== "string" || jws.length === 0) {
    throw new JwsError("decode", "value is not a JWS string");
  }
  const parts = jws.split(".");
  if (parts.length !== 3) {
    throw new JwsError("decode", "value is not a three-part JWS");
  }

  const header = decodeSegment(parts[0]);
  if (header.alg !== "ES256") {
    throw new JwsError("signature", `alg is not ES256: ${String(header.alg)}`);
  }

  const key = await verifyChain(header.x5c, anchorDer, at);

  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64url(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new JwsError("signature", "JWS signature is invalid");

  return decodeSegment(parts[1]);
}

/** Lowercase hex sha256 of a string, for the bounded reject diagnostics. */
export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Tier 1 of B-29: cheap structural checks that must pass before ANY database
 * work happens. A caller that fails here writes nothing at all — not a row, not
 * a counter — because an unauthenticated endpoint must not hand an arbitrary
 * caller a durable write primitive of any shape.
 */
export function structurallyPlausible(jws: unknown): boolean {
  if (typeof jws !== "string") return false;
  const parts = jws.split(".");
  if (parts.length !== 3 || parts[0].length === 0 || parts[1].length === 0 || parts[2].length === 0) {
    return false;
  }
  if (!parts.every((p) => /^[A-Za-z0-9_-]+$/.test(p))) return false;
  try {
    const h = JSON.parse(new TextDecoder().decode(b64url(parts[0])));
    return h?.alg === "ES256" && Array.isArray(h?.x5c) && h.x5c.length >= 3;
  } catch {
    return false;
  }
}
