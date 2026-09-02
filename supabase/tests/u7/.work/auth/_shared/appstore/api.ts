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
    method: "GET" | "POST" | "PUT",
    path: string,
    body?: unknown,
    /** Set App Account Token answers 200 with NO BODY. Without this the generic
     *  "a 200 we cannot parse is not an answer" rule — which is right for every
     *  read endpoint — would make every SUCCESSFUL token assignment look like a
     *  malformed response. Caught by the U5c battery rather than in production,
     *  where it would have made the legacy claim path fail 100% of the time
     *  while Apple was accepting every call. */
    allowEmptyBody = false,
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

    if (allowEmptyBody && text.trim().length === 0) return {};

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
   * PUT /inApps/v1/transactions/{originalTransactionId}/appAccountToken
   *
   * Attaches an Etudes binding token to an EXISTING subscription — the legacy
   * claim and the orphan rebind. Apple applies it to "the current renewal
   * transaction and all subsequent renewals", and NOT to past transactions.
   *
   * **THE ORIGINAL TRANSACTION ID, NEVER ANY TRANSACTION ID.** Get All
   * Subscription Statuses accepts either and this endpoint does not:
   * TransactionIdIsNotOriginalTransactionIdError (4000187) is a permanent refusal
   * for passing the wrong one. The parameter is named for what it must be.
   *
   * **A 200 FROM THIS CALL IS NOT EVIDENCE OF BINDING, AND THE RETURN TYPE SAYS
   * SO BY CARRYING NOTHING.** Apple documents no read-after-write visibility
   * guarantee, and P12 already taught this project that Apple-side propagation is
   * real and looks exactly like misconfiguration. Ownership may be established
   * only after `observeAppAccountToken` sees our token on a fresh authoritative
   * read. Do not add a return value to this method that a caller could mistake
   * for confirmation.
   */
  async setAppAccountToken(
    env: AppleEnvironment,
    originalTransactionId: string,
    appAccountToken: string,
  ): Promise<void> {
    await this.request(
      env,
      "PUT",
      `/inApps/v1/transactions/${encodeURIComponent(originalTransactionId)}/appAccountToken`,
      { appAccountToken },
      true, // Apple answers 200 with an empty body on success.
    );
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


// ---------------------------------------------- Set App Account Token taxonomy
//
// EVERY NUMERIC CODE BELOW WAS READ FROM APPLE'S OWN REFERENCE ON 2026-08-23, not
// inferred from the error name. Inferring them was the alternative and it would
// have been guessing.
//
// THE DIVISION THAT MATTERS IS TERMINAL vs RETRYABLE, and it is not the same
// division as "did it work". A terminal refusal means NO retry by anyone can ever
// succeed for this transaction, so U5d must record it and stop — retrying forever
// against a FAMILY_SHARED transaction is the failure mode this taxonomy exists to
// prevent. A retryable outcome means write nothing and try again on a later
// attestation, which is free because attestation runs on every foreground.
export const APPLE_TOKEN_ERROR_CODES = {
  4000006: "invalid_transaction_id",
  4000048: "app_transaction_id_not_supported",
  4000183: "invalid_app_account_token_uuid",
  4000185: "family_transaction_not_supported",
  4000187: "transaction_id_is_not_original_transaction_id",
  4040005: "original_transaction_id_not_found",
} as const;

export type TokenAssignmentDisposition =
  | { kind: "terminal"; reason: string; appleErrorCode?: number }
  | { kind: "retryable"; reason: string; appleErrorCode?: number };

/**
 * Classify a failed setAppAccountToken call.
 *
 * 404 IS TREATED AS TERMINAL, AND THE CHOICE IS DELIBERATE RATHER THAN OBVIOUS.
 * OriginalTransactionIdNotFoundError means Apple does not know this subscription
 * in this environment — overwhelmingly an environment mismatch or a fabricated
 * identifier, neither of which a retry fixes. It is separated from the 4xx family
 * by its own reason string so that if it ever DOES appear at volume, the record
 * says which of the two it was rather than lumping it in.
 *
 * ANYTHING UNRECOGNISED IS RETRYABLE. Failing closed here would mean permanently
 * refusing a legitimate owner over an Apple error we have not met yet, and the
 * cost of the opposite mistake is one wasted call on a later foreground.
 */
export function classifyTokenAssignment(e: unknown): TokenAssignmentDisposition {
  if (!(e instanceof AppleApiError)) {
    return { kind: "retryable", reason: "unknown_failure" };
  }
  const code = e.appleErrorCode;
  const named = code !== undefined
    ? APPLE_TOKEN_ERROR_CODES[code as keyof typeof APPLE_TOKEN_ERROR_CODES]
    : undefined;
  if (named) return { kind: "terminal", reason: named, appleErrorCode: code };

  // No recognised code. Fall back to the status family, which Apple documents as
  // stable even where individual codes are not.
  if (e.kind === "client_error") {
    return { kind: "terminal", reason: "unrecognised_client_error", appleErrorCode: code };
  }
  if (e.kind === "not_found") {
    return { kind: "terminal", reason: "original_transaction_id_not_found", appleErrorCode: code };
  }
  if (e.kind === "unauthorised") {
    // OUR credential is wrong, not the customer's transaction. Retryable because
    // a secret fix repairs it without the member doing anything.
    return { kind: "retryable", reason: "our_credential_rejected", appleErrorCode: code };
  }
  return { kind: "retryable", reason: e.kind, appleErrorCode: code };
}
