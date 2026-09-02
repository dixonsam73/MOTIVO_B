// Apple payload -> normalised membership event.
//
// PURE. No I/O, no clock beyond what the caller passes, no database. Everything
// here is exhaustively testable offline, which is the point: the derivation
// rules are where B-25 lives, and a rule that can only be exercised against
// Apple is a rule nobody exercises.
//
// B-25, AND WHY IT IS NOT DEFENSIVE PADDING. Every field of
// JWSRenewalInfoDecodedPayload is documented OPTIONAL, and data.signedRenewalInfo
// appears only for auto-renewable subscription notifications. Two consequences,
// both of which would have produced a live subscription deriving NOT ENTITLED —
// and under U7 that schedules cleanup on a paying member:
//
//   Limb A  renewalDate absent -> membership.renewal_date NULL ->
//           connected_member() evaluates coalesce(null > now(), false) = false.
//           The fallback is transactionInfo.expiresDate, which is the
//           authoritative paid-through instant for the current period.
//
//   Limb B  renewalInfo.signedDate absent, or no renewal info at all ->
//           membership.renewal_info_signed_date is NOT NULL and the row cannot
//           be written. U3's constraint is right and is not relaxed: a row that
//           cannot be ordered must not exist.
//
// THE REMEDY FOR BOTH IS THE SAME AND IT IS NOT "WRITE A NULL". Incomplete state
// yields disposition "incomplete", which writes nothing to membership and asks
// the caller for a live authoritative read. Refusing and reconciling is strictly
// safer than storing a null that derives to "expired".

export type Disposition = "state" | "incomplete" | "not_applicable" | "unsupported";

export interface MembershipState {
  product_id: string;
  apple_status: number | null;
  renewal_date: string | null;
  grace_period_expires_date: string | null;
  is_in_billing_retry: boolean;
  auto_renew_status: number | null;
  expiration_intent: number | null;
  revocation_date: string | null;
  renewal_info_signed_date: string;
}

export interface NormalisedEvent {
  notification_uuid: string | null;
  environment: string | null;
  notification_type: string | null;
  subtype: string | null;
  original_transaction_id: string | null;
  signed_date: string | null;
  app_account_token: string | null;
  disposition: Disposition;
  /** Present only when disposition === "state". */
  state: MembershipState | null;
  /** Why, when the disposition is not "state". Diagnostics, never authority. */
  reason: string | null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Apple sends UNIX milliseconds. Anything else is treated as absent. */
export function appleMsToIso(v: unknown): string | null {
  if (typeof v !== "number" || !Number.isFinite(v) || v <= 0) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

const str = (v: unknown): string | null =>
  typeof v === "string" && v.length > 0 ? v : null;

const uuid = (v: unknown): string | null =>
  typeof v === "string" && UUID_RE.test(v) ? v.toLowerCase() : null;

const smallint = (v: unknown, lo: number, hi: number): number | null =>
  typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi ? v : null;

const obj = (v: unknown): Record<string, unknown> =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};

/** 'Xcode' is deliberately absent — U3's CHECK excludes it and so does this. */
function environmentOf(v: unknown): string | null {
  const s = str(v);
  return s === "Sandbox" || s === "Production" ? s : null;
}

export interface DeriveInput {
  /** Verified responseBodyV2DecodedPayload. */
  payload: Record<string, unknown>;
  /** Verified JWSTransactionDecodedPayload, or null when the notification carried none. */
  transaction: Record<string, unknown> | null;
  /** Verified JWSRenewalInfoDecodedPayload, or null when the notification carried none. */
  renewal: Record<string, unknown> | null;
}

/**
 * Normalise a fully verified notification. Callers must have verified every
 * JWS — envelope and both nested payloads — before calling this.
 */
export function deriveFromNotification(input: DeriveInput): NormalisedEvent {
  const { payload, transaction, renewal } = input;
  const data = obj(payload.data);
  const summary = obj(payload.summary);
  const tx = obj(transaction);
  const ri = obj(renewal);

  const base = {
    notification_uuid: uuid(payload.notificationUUID),
    environment: environmentOf(data.environment) ?? environmentOf(summary.environment),
    notification_type: str(payload.notificationType),
    subtype: str(payload.subtype),
    original_transaction_id:
      str(tx.originalTransactionId) ?? str(ri.originalTransactionId) ?? null,
    signed_date: appleMsToIso(payload.signedDate),
    app_account_token: uuid(tx.appAccountToken) ?? uuid(ri.appAccountToken),
  };

  const na = (reason: string, disposition: Disposition = "not_applicable"): NormalisedEvent =>
    ({ ...base, disposition, state: null, reason });

  // Anything we accept must be identifiable and orderable —
  // membership_notification_accepted_is_complete says so as a constraint.
  if (!base.notification_uuid) return na("no notificationUUID", "unsupported");
  if (!base.signed_date) return na("no signedDate", "unsupported");

  // data, summary, appData and externalPurchaseToken are mutually exclusive, and
  // three of the four carry no subscription state at all. These are ordinary
  // Apple traffic, NOT rejects — B-27 exists so they stop being counted as
  // attacks.
  if (payload.externalPurchaseToken !== undefined) return na("externalPurchaseToken notification");
  if (payload.appData !== undefined) return na("appData notification");
  if (payload.summary !== undefined) return na("renewal-extension summary notification");
  if (payload.data === undefined) return na("notification carries no data object", "unsupported");

  // Apple's own test notification: a real, correctly signed delivery that
  // carries no transaction. It is the U4i keystone and must not look like a
  // failure in the record.
  if (base.notification_type === "TEST") return na("Apple test notification");

  if (!transaction) return na("no signedTransactionInfo");

  const product_id = str(tx.productId) ?? str(ri.productId) ?? str(ri.autoRenewProductId);
  const renewal_info_signed_date = appleMsToIso(ri.signedDate);
  // B-25 Limb A. renewalDate first because it is renewal info's own statement of
  // when this subscription next bills; expiresDate is the same instant seen from
  // the transaction, and is present when renewalDate is not.
  const renewal_date = appleMsToIso(ri.renewalDate) ?? appleMsToIso(tx.expiresDate);

  if (!product_id) return na("no productId in transaction or renewal info", "incomplete");
  // B-25 Limb B. Not orderable -> not writable. Reconcile instead.
  if (!renewal_info_signed_date) return na("no renewalInfo.signedDate", "incomplete");
  if (!renewal_date) return na("neither renewalInfo.renewalDate nor transaction.expiresDate", "incomplete");
  if (!base.environment) return na("no resolvable environment", "incomplete");
  if (!base.original_transaction_id) return na("no originalTransactionId", "incomplete");

  return {
    ...base,
    disposition: "state",
    reason: null,
    state: {
      product_id,
      apple_status: smallint(data.status, 1, 5),
      renewal_date,
      grace_period_expires_date: appleMsToIso(ri.gracePeriodExpiresDate),
      is_in_billing_retry: ri.isInBillingRetryPeriod === true,
      auto_renew_status: smallint(ri.autoRenewStatus, 0, 1),
      expiration_intent: smallint(ri.expirationIntent, 1, 5),
      revocation_date: appleMsToIso(tx.revocationDate),
      renewal_info_signed_date,
    },
  };
}

export interface ReconcileInput {
  /** Verified JWSTransactionDecodedPayload from a lastTransactions entry. */
  transaction: Record<string, unknown> | null;
  /** Verified JWSRenewalInfoDecodedPayload from the same entry. */
  renewal: Record<string, unknown> | null;
  /** The status integer Apple reported alongside them. */
  status: unknown;
}

/**
 * Normalise one lastTransactions entry from Get All Subscription Statuses.
 *
 * RECONCILIATION ALWAYS WINS AN ORDERING CONTEST, and not by special-casing:
 * Apple signs the renewal info at read time, so its signedDate is newer than any
 * notification's by construction. The ordering rule stays one rule.
 */
export function deriveFromReconciliation(
  input: ReconcileInput,
): { state: MembershipState; environment: string | null; original_transaction_id: string | null; app_account_token: string | null } | { state: null; reason: string } {
  const tx = obj(input.transaction);
  const ri = obj(input.renewal);

  const product_id = str(tx.productId) ?? str(ri.productId) ?? str(ri.autoRenewProductId);
  const renewal_info_signed_date = appleMsToIso(ri.signedDate);
  const renewal_date = appleMsToIso(ri.renewalDate) ?? appleMsToIso(tx.expiresDate);

  if (!product_id) return { state: null, reason: "no productId" };
  if (!renewal_info_signed_date) return { state: null, reason: "no renewalInfo.signedDate" };
  if (!renewal_date) return { state: null, reason: "no renewalDate or expiresDate" };

  return {
    environment: environmentOf(tx.environment) ?? environmentOf(ri.environment),
    original_transaction_id: str(tx.originalTransactionId) ?? str(ri.originalTransactionId),
    app_account_token: uuid(tx.appAccountToken) ?? uuid(ri.appAccountToken),
    state: {
      product_id,
      apple_status: smallint(input.status, 1, 5),
      renewal_date,
      grace_period_expires_date: appleMsToIso(ri.gracePeriodExpiresDate),
      is_in_billing_retry: ri.isInBillingRetryPeriod === true,
      auto_renew_status: smallint(ri.autoRenewStatus, 0, 1),
      expiration_intent: smallint(ri.expirationIntent, 1, 5),
      revocation_date: appleMsToIso(tx.revocationDate),
      renewal_info_signed_date,
    },
  };
}

/**
 * Apple's own service formula, evaluated client-side for diagnostics only.
 *
 * THE SERVER'S ANSWER IS connected_member(), NOT THIS. This exists so a local
 * run can assert that the TypeScript and the SQL agree; nothing in the request
 * path branches on it.
 */
export function entitledAt(s: MembershipState, now: Date): boolean {
  const renewal = s.renewal_date ? new Date(s.renewal_date) : null;
  const grace = s.grace_period_expires_date ? new Date(s.grace_period_expires_date) : null;
  return (renewal !== null && renewal > now) ||
    (s.is_in_billing_retry && grace !== null && grace > now);
}
