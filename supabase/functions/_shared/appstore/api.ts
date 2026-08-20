// App Store Server API client — authoritative reads from Apple.
//
// WHY THIS EXISTS IN U4 AT ALL, given U4 is observe-only. Sandbox delivers each
// V2 notification EXACTLY ONCE and never retries; production retries five times
// over 72 hours. So in the environment every Phase 3 gate runs in, a single
// dropped response is unrecoverable by retry, and reconciliation is not an
// optimisation to add later — it is the only recovery path there is. It is also
// the same live read U7's cleanup worker must perform immediately before any
// irreversible action, so building it here means U7 inherits proven code.
//
// FETCH IS INJECTABLE, AND THAT IS THE TEST SEAM. Q6's three failure modes —
// 5xx, timeout, malformed body — cannot be induced against Apple at all, so they
// are induced here instead, deterministically, with no network and no stub
// server. The rule every one of them proves is the same: A FAILED OR AMBIGUOUS
// READ WRITES NOTHING.

const PRODUCTION_BASE = "https://api.storekit.apple.com";
const SANDBOX_BASE = "https://api.storekit-sandbox.apple.com";

/** Apple caps a token's life at 60 minutes after iat. We use well under it. */
const TOKEN_TTL_SECONDS = 900;
const DEFAULT_TIMEOUT_MS = 10_000;

export type AppleEnvironment = "Sandbox" | "Production";

export interface AppleCredentials {
  keyId: string;
  issuerId: string;
  /** base64 of the .p8 file. Base64 because a multi-line PEM in an env var gets
   *  its newlines mangled and the resulting importKey failure looks nothing
   *  like its cause — the APPLE_SIWA_P8_B64 lesson, applied. */
  p8Base64: string;
  bundleId: string;
}

export interface ClientOptions {
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  /** Base URL overrides. Present for local stubs and for Q5/Q6; the deployment
   *  package asserts both are unset in production. */
  baseUrls?: Partial<Record<AppleEnvironment, string>>;
  now?: () => Date;
}

/** Every non-success outcome is one of these. None of them may cause a write. */
export type AppleFailureKind =
  | "network"        // unreachable, DNS, TLS, aborted
  | "timeout"
  | "unauthorised"   // 401 — our JWT is wrong; never Apple saying "not entitled"
  | "not_found"      // 404 TransactionIdNotFoundError — wrong environment, or gone
  | "rate_limited"   // 429
  | "server_error"   // 5xx
  | "client_error"   // other 4xx
  | "malformed";     // 200 with a body we cannot parse

export class AppleApiError extends Error {
  constructor(
    readonly kind: AppleFailureKind,
    message: string,
    readonly status?: number,
    readonly appleErrorCode?: number,
  ) {
    super(message);
    this.name = "AppleApiError";
  }
  /** True when a later attempt might plausibly succeed. Nothing here ever
   *  authorises a write; it only decides whether to try again. */
  get retryable(): boolean {
    return this.kind === "network" || this.kind === "timeout" ||
      this.kind === "server_error" || this.kind === "rate_limited";
  }
}

// ------------------------------------------------------------------ signing

const enc = new TextEncoder();

function b64urlOfBytes(b: Uint8Array): string {
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const b64urlOfString = (s: string): string => b64urlOfBytes(enc.encode(s));

/** base64(.p8 PEM text) -> pkcs8 DER bytes. */
function pkcs8FromP8Base64(p8Base64: string): Uint8Array {
  let pem: string;
  try {
    pem = atob(p8Base64.trim());
  } catch {
    throw new Error("APPLE_IAP_P8_B64 is not valid base64");
  }
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  if (body.length === 0) throw new Error("APPLE_IAP_P8_B64 decoded to an empty key");
  try {
    return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  } catch {
    throw new Error("APPLE_IAP_P8_B64 does not decode to a PKCS#8 body");
  }
}

/**
 * Apple's "Generating JSON Web Tokens for API requests".
 *
 * Web Crypto emits raw r||s for ECDSA, which is exactly what JWS wants — the
 * TN3107 lesson already learned by revoke_apple_identity_v1. Do not add DER
 * conversion.
 */
export async function signAppleApiJWT(
  creds: AppleCredentials,
  now: Date = new Date(),
): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000);
  const header = { alg: "ES256", kid: creds.keyId, typ: "JWT" };
  const claims = {
    iss: creds.issuerId,
    iat,
    exp: iat + TOKEN_TTL_SECONDS,
    aud: "appstoreconnect-v1",
    bid: creds.bundleId,
  };
  const signingInput =
    `${b64urlOfString(JSON.stringify(header))}.${b64urlOfString(JSON.stringify(claims))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8FromP8Base64(creds.p8Base64),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    enc.encode(signingInput),
  );
  return `${signingInput}.${b64urlOfBytes(new Uint8Array(sig))}`;
}

// ------------------------------------------------------------------- client

export class AppStoreServerApi {
  private readonly fetchImpl: typeof fetch;
  private readonly timeoutMs: number;
  private readonly baseUrls: Record<AppleEnvironment, string>;
  private readonly now: () => Date;

  constructor(private readonly creds: AppleCredentials, opts: ClientOptions = {}) {
    this.fetchImpl = opts.fetchImpl ?? fetch;
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.now = opts.now ?? (() => new Date());
    this.baseUrls = {
      Production: opts.baseUrls?.Production ?? PRODUCTION_BASE,
      Sandbox: opts.baseUrls?.Sandbox ?? SANDBOX_BASE,
    };
  }

  private async request(
    env: AppleEnvironment,
    method: "GET" | "POST",
    path: string,
    body?: unknown,
  ): Promise<unknown> {
    const token = await signAppleApiJWT(this.creds, this.now());
    const url = `${this.baseUrls[env]}${path}`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    let res: Response;
    try {
      res = await this.fetchImpl(url, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (e) {
      const aborted = (e as Error)?.name === "AbortError" ||
        String(e).includes("aborted") || String(e).includes("timeout");
      throw new AppleApiError(
        aborted ? "timeout" : "network",
        `App Store Server API ${method} ${path}: ${String(e).slice(0, 200)}`,
      );
    } finally {
      clearTimeout(timer);
    }

    const text = await res.text().catch(() => "");
    let parsed: unknown = undefined;
    try {
      parsed = text.length > 0 ? JSON.parse(text) : undefined;
    } catch {
      parsed = undefined;
    }

    if (!res.ok) {
      const code = (parsed as { errorCode?: number } | undefined)?.errorCode;
      const kind: AppleFailureKind = res.status === 401
        ? "unauthorised"
        : res.status === 404
        ? "not_found"
        : res.status === 429
        ? "rate_limited"
        : res.status >= 500
        ? "server_error"
        : "client_error";
      throw new AppleApiError(kind, `App Store Server API ${res.status} on ${path}`, res.status, code);
    }

    if (parsed === undefined || typeof parsed !== "object" || parsed === null) {
      // A 200 whose body we cannot read is NOT an authoritative answer, and the
      // single most dangerous way to get this wrong is to treat it as "Apple
      // said nothing, so nothing is entitled".
      throw new AppleApiError("malformed", `App Store Server API 200 with an unparseable body on ${path}`);
    }
    return parsed;
  }

  /** GET /inApps/v1/subscriptions/{transactionId} — the authoritative read. */
  getAllSubscriptionStatuses(
    env: AppleEnvironment,
    anyTransactionId: string,
  ): Promise<unknown> {
    return this.request(env, "GET", `/inApps/v1/subscriptions/${encodeURIComponent(anyTransactionId)}`);
  }

  /** POST /inApps/v1/notifications/test — the U4i keystone. */
  requestTestNotification(env: AppleEnvironment): Promise<unknown> {
    return this.request(env, "POST", "/inApps/v1/notifications/test");
  }

  /** GET /inApps/v1/notifications/test/{token} — what Apple thinks it delivered. */
  getTestNotificationStatus(env: AppleEnvironment, token: string): Promise<unknown> {
    return this.request(env, "GET", `/inApps/v1/notifications/test/${encodeURIComponent(token)}`);
  }

  /**
   * POST /inApps/v1/notifications/history — the only honest way to score G3.
   * Sandbox never retries, so "we never received it" is otherwise unfalsifiable.
   */
  getNotificationHistory(
    env: AppleEnvironment,
    body: Record<string, unknown>,
    paginationToken?: string,
  ): Promise<unknown> {
    const q = paginationToken ? `?paginationToken=${encodeURIComponent(paginationToken)}` : "";
    return this.request(env, "POST", `/inApps/v1/notifications/history${q}`, body);
  }
}

/**
 * Pull the lastTransactions entries out of a StatusResponse.
 *
 * TOLERANT OF SHAPE, STRICT ABOUT CONTENT. Apple has changed the nesting of this
 * response before; what must never be tolerated is inventing an entry that is
 * not there, because an empty result must read as "no answer" and not as
 * "not entitled".
 */
export function lastTransactionsOf(response: unknown): Array<Record<string, unknown>> {
  const r = response as Record<string, unknown> | null;
  if (!r || typeof r !== "object") return [];
  const data = r.data;
  const groups: unknown[] = Array.isArray(data)
    ? data
    : Array.isArray((data as Record<string, unknown>)?.subscriptionGroupIdentifierItems)
    ? (data as Record<string, unknown>).subscriptionGroupIdentifierItems as unknown[]
    : [];
  const out: Array<Record<string, unknown>> = [];
  for (const g of groups) {
    const lt = (g as Record<string, unknown>)?.lastTransactions;
    if (Array.isArray(lt)) {
      for (const e of lt) if (e && typeof e === "object") out.push(e as Record<string, unknown>);
    }
  }
  return out;
}

export function credentialsFromEnv(env: {
  get(k: string): string | undefined;
}): AppleCredentials {
  const need = (k: string): string => {
    const v = env.get(k);
    if (!v) throw new Error(`missing required secret ${k}`);
    return v;
  };
  return {
    keyId: need("APPLE_IAP_KEY_ID"),
    issuerId: need("APPLE_IAP_ISSUER_ID"),
    p8Base64: need("APPLE_IAP_P8_B64"),
    bundleId: need("APPLE_IAP_BUNDLE_ID"),
  };
}
