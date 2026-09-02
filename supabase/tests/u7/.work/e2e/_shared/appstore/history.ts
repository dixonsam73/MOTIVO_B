// Get Notification History — reading Apple's own record of what it sent.
//
// B-32. THIS EXISTS BECAUSE THE FIRST IMPLEMENTATION REPORTED ZERO
// UNCONDITIONALLY, AND COULD NOT HAVE REPORTED ANYTHING ELSE.
//
// It read `item.notificationUUID`. **`NotificationHistoryResponseItem` has no
// such field.** Apple's reference gives it exactly three properties —
// `sendAttempts`, `signedPayload` and `firstSendAttemptResult` — and the UUID
// lives *inside* the signed payload. So every item mapped to "", every item was
// filtered out, and the count was the length of an always-empty array.
//
// Observed live on 2026-08-23: `apple_notification_count: 0` for a Sandbox window
// that provably contained Apple's own TEST notification, while
// `membership_notification` held fourteen rows from that same window.
//
// **THE FAILURE SHAPE IS THE POINT.** It did not error. It returned a confident,
// well-formed zero — which is the mirror image of the rule the reconciliation
// path already insists on, that an empty Apple result "must read as 'no answer'
// and not as 'not entitled'". A diagnostic that cannot distinguish "Apple sent
// nothing" from "we failed to parse Apple's reply" is worse than no diagnostic,
// because G3 is scored against it: G3 asks whether we LOST a notification, and
// sandbox never retries, so "we never received it" is otherwise unfalsifiable.
//
// ── VERIFICATION IS NOT OPTIONAL HERE ─────────────────────────────────────
//
// The UUID could be recovered by decoding the JWS payload without checking the
// signature, and that would be wrong. This function is the evidence G3 is scored
// against, so an item that Apple did not sign must never be able to masquerade as
// Apple's history — otherwise a malformed or hostile response could manufacture
// agreement with our own records, which is precisely the comparison G3 depends on
// being honest.
//
// So `verify` is a REQUIRED parameter rather than an internal detail: the caller
// supplies the same pinned-anchor verifier the notification path uses, and the
// test battery supplies one driven by its own CA. There is no decode-only route
// through this module.
//
// ── READ-ONLY ─────────────────────────────────────────────────────────────
//
// Nothing here writes, and nothing here replays. Reporting which notifications
// Apple believes it sent is a diagnostic; re-ingesting a payload we never
// received through the live endpoint would be the bare-transaction bypass B-24
// forbids. The remedy for a gap is a reconcile, never an import.

/** One notification Apple confirms it sent, recovered from its VERIFIED payload. */
export interface HistoryItem {
  notification_uuid: string | null;
  notification_type: string | null;
  subtype: string | null;
  environment: string | null;
  signed_date: string | null;
  original_transaction_id: string | null;
  /** How many delivery attempts Apple recorded. Diagnostics only. */
  send_attempts: number;
}

export interface HistoryPage {
  items: HistoryItem[];
  /** Items present in Apple's reply that FAILED verification, or carried no
   *  usable payload. **Never silently dropped** — a non-zero value here is the
   *  signal that this page's evidence is incomplete. */
  unverifiable: number;
  has_more: boolean;
  pagination_token: string | null;
}

const str = (v: unknown): string | null =>
  typeof v === "string" && v.length > 0 ? v : null;

const obj = (v: unknown): Record<string, unknown> =>
  v !== null && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};

/** Apple sends UNIX milliseconds. Anything else is treated as absent. */
function msToIso(v: unknown): string | null {
  if (typeof v !== "number" || !Number.isFinite(v) || v <= 0) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/**
 * Normalise one page of `GET /inApps/v1/notifications/history`.
 *
 * @param verify the pinned-anchor JWS verifier. **Required**, so no caller can
 *   obtain identities from an unverified decode.
 */
export async function readNotificationHistory(
  response: unknown,
  verify: (jws: unknown) => Promise<Record<string, unknown>>,
): Promise<HistoryPage> {
  const page = obj(response);
  const raw = page.notificationHistory;
  const items: HistoryItem[] = [];
  let unverifiable = 0;

  if (Array.isArray(raw)) {
    for (const entry of raw) {
      const item = obj(entry);
      const signed = item.signedPayload;
      if (typeof signed !== "string" || signed.length === 0) {
        unverifiable++;
        continue;
      }

      let payload: Record<string, unknown>;
      try {
        payload = await verify(signed);
      } catch {
        // Apple did not sign this, or we could not parse it. It is COUNTED but
        // never reported as history — the whole point of the fix is that an
        // item we cannot vouch for must not silently vanish either.
        unverifiable++;
        continue;
      }

      const data = obj(payload.data);
      const summary = obj(payload.summary);
      items.push({
        notification_uuid: str(payload.notificationUUID),
        notification_type: str(payload.notificationType),
        subtype: str(payload.subtype),
        environment: str(data.environment) ?? str(summary.environment),
        signed_date: msToIso(payload.signedDate),
        // Present on subscription notifications; absent on TEST and on the
        // summary shapes. Recovered from the ENVELOPE's data object, which is
        // signed — the nested transaction JWS is not decoded here because this
        // is a diagnostic about delivery, not about entitlement.
        original_transaction_id: str(data.originalTransactionId),
        send_attempts: Array.isArray(item.sendAttempts) ? item.sendAttempts.length : 0,
      });
    }
  }

  return {
    items,
    unverifiable,
    // SURFACED, where the first implementation dropped it. A history longer than
    // one page could not otherwise be followed, so a partial page would have
    // looked like a complete one — the same class of quiet incompleteness as the
    // bug this module exists to fix.
    has_more: page.hasMore === true,
    pagination_token: str(page.paginationToken),
  };
}
