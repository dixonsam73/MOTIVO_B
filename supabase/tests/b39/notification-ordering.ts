// B-39 follow-up — NOTIFICATION → DERIVATION → INGESTION coverage, and the
// ORDERING CONTRACT. LOCAL ONLY. Run through notification-ordering.sh.
//
// WHAT IS EXERCISED. Notification-shaped, already-decoded payloads go through
// the SHIPPING deriveFromNotification and then the SHIPPING
// membership_ingest_notification_v1, exactly as appstore_notifications_v1 wires
// them. JWS signature verification is NOT exercised here (U4's e2e suite and
// Apple's own test notification own that); these payloads are what the verifier
// would hand over.
//
// THE ORDERING QUESTION, stated from Apple's reference (fetched 2026-09-14):
//   - notification signedDate: "The notification payload contains a snapshot of
//     the state of the transaction at this time … If you process multiple
//     notifications for the same transaction ID, use the notification with the
//     most recent signedDate."  `data.status` is "current as of the signedDate".
//   - renewalInfo signedDate: only "the time that the App Store signed the JWS
//     data". Apple does NOT say whether renewal info inside a notification is
//     re-signed per notification.
// The writer orders by renewalInfo.signedDate (renewal_info_signed_date). So a
// NEWER notification is rejected as `stale` whenever its renewal info carries a
// signature no newer than the stored row's -- for example after an operator
// reconciliation, which stores renewal info signed at read time.
//
// N4 and N5 ASSERT APPLE'S DOCUMENTED ORDERING and are PREDICTED TO FAIL at the
// current writer. That establishes the MECHANISM only. Whether Apple ever sends
// a notification whose renewal info is signed earlier than a stored row's is
// NOT documented and NOT observed here, so this is a coverage result, not a
// reproduced production defect.

import { deriveFromNotification } from "../../functions/_shared/appstore/derive.ts";

const DB = Deno.env.get("DB");
if (!DB) { console.error("DB container not provided (run via notification-ordering.sh)"); Deno.exit(2); }

async function psq(sql: string): Promise<string> {
  const out = await new Deno.Command("docker", {
    args: ["exec", "-i", DB!, "psql", "-U", "postgres", "-d", "postgres", "-At", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
  }).output();
  const text = new TextDecoder().decode(out.stdout).trim();
  if (!out.success) throw new Error(`psql failed: ${new TextDecoder().decode(out.stderr)}\nSQL: ${sql}`);
  return text;
}
const q = (s: string) => `$b39$${s}$b39$`;

const T0 = Date.now();
const at = (minutes: number) => T0 + minutes * 60_000;
const iso = (ms: number) => new Date(ms).toISOString();
const PREFIX = "00000000-0000-0000-0000-0000000b39";
const ids: string[] = [];

async function identity(n: string, stored: { signedMs: number; status: number; revokedMs?: number }) {
  const uid = `${PREFIX}${n}`;
  const token = `b3900000-0000-4000-8000-0000000000${n}`;
  ids.push(uid);
  await psq(`insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at)
             values ('${uid}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b39n-${n}@local.invalid',now(),now());`);
  await psq(`insert into public.membership_binding (user_id, binding_token) values ('${uid}','${token}');`);
  await psq(`insert into public.membership (user_id,environment,original_transaction_id,product_id,apple_status,
               renewal_date,is_in_billing_retry,revocation_date,renewal_info_signed_date,binding_method,bound_at)
             values ('${uid}','Production','b39n-otid-${n}','com.sdsongs.etudes.connected.monthly',${stored.status},
               '${iso(at(60 * 24 * 20))}',false,${stored.revokedMs ? `'${iso(stored.revokedMs)}'` : "null"},
               '${iso(stored.signedMs)}','purchase',now());`);
  return { uid, token, otid: `b39n-otid-${n}` };
}

interface Notif {
  type: string; subtype?: string; notificationSignedMs: number; status: number;
  tx: { expiresMs: number; revocationMs?: number };
  renewal: { signedMs: number; renewalMs: number };
}

async function ingest(who: { token: string; otid: string }, n: Notif) {
  const uuid = crypto.randomUUID();
  const payload = {
    notificationType: n.type, subtype: n.subtype, notificationUUID: uuid, version: "2.0",
    signedDate: n.notificationSignedMs,
    data: { environment: "Production", status: n.status, bundleId: "com.sdsongs.etudes" },
  };
  const transaction: Record<string, unknown> = {
    originalTransactionId: who.otid, productId: "com.sdsongs.etudes.connected.monthly",
    expiresDate: n.tx.expiresMs, appAccountToken: who.token, environment: "Production",
  };
  if (n.tx.revocationMs) transaction.revocationDate = n.tx.revocationMs;
  const renewal = {
    originalTransactionId: who.otid, productId: "com.sdsongs.etudes.connected.monthly",
    signedDate: n.renewal.signedMs, renewalDate: n.renewal.renewalMs, autoRenewStatus: 1,
    appAccountToken: who.token, environment: "Production",
  };
  const event = deriveFromNotification({ payload, transaction, renewal });
  const rpcArgs = {
    notification_uuid: event.notification_uuid, environment: event.environment,
    notification_type: event.notification_type, subtype: event.subtype,
    original_transaction_id: event.original_transaction_id, signed_date: event.signed_date,
    request_id: `b39n-${uuid.slice(0, 8)}`, payload_bytes: 1200, payload_sha256: "0".repeat(64),
    disposition: event.disposition, app_account_token: event.app_account_token, state: event.state,
  };
  const out = await psq(`select public.membership_ingest_notification_v1(${q(JSON.stringify(rpcArgs))}::jsonb);`);
  return { disposition: event.disposition, result: JSON.parse(out) };
}

const row = (uid: string, expr: string) =>
  psq(`select ${expr} from public.membership where user_id='${uid}' and environment='Production';`);
const member = (uid: string) => psq(`select public.connected_member('${uid}')::text;`);

let pass = 0; const failed: string[] = [];
const is = (id: string, got: string, want: string, what: string) => {
  if (got === want) { pass++; console.log(`  PASS  ${id.padEnd(7)} ${what} = ${want}`); }
  else { failed.push(id); console.log(`  FAIL  ${id.padEnd(7)} ${what}: expected '${want}', got '${got}'`); }
};
const PRED_FAIL = new Set(["B39-N4a", "B39-N4b", "B39-N5a", "B39-N5b"]);

async function cleanup() {
  if (ids.length === 0) return;
  const list = ids.map((i) => `'${i}'`).join(",");
  await psq(`delete from public.membership_notification where original_transaction_id like 'b39n-otid-%';`);
  await psq(`delete from public.membership where user_id in (${list});`);
  await psq(`delete from public.membership_binding where user_id in (${list});`);
  await psq(`delete from auth.users where id in (${list});`);
}

try {
  // stale leftovers from an interrupted run must not change outcomes
  await psq(`delete from public.membership_notification where original_transaction_id like 'b39n-otid-%';`);
  await psq(`delete from public.membership where original_transaction_id like 'b39n-otid-%';`);
  await psq(`delete from public.membership_binding where user_id::text like '${PREFIX}%';`);
  await psq(`delete from auth.users where id::text like '${PREFIX}%';`);

  console.log("\nB-39 follow-up — notification → derivation → ingestion, and ordering\n");

  // N0 CONTROL — a genuinely OLDER notification (both signatures older than the
  // stored row) must stay stale, or ordering protection is gone.
  const i0 = await identity("f0", { signedMs: at(60), status: 1 });
  const n0 = await ingest(i0, { type: "REFUND", notificationSignedMs: at(-60), status: 5,
    tx: { expiresMs: at(60 * 24 * 20), revocationMs: at(-61) }, renewal: { signedMs: at(-60), renewalMs: at(60 * 24 * 20) } });
  is("B39-N0a", n0.result.outcome, "stale", "control: an older notification is refused as stale");
  is("B39-N0b", await member(i0.uid), "true", "control: and changes nothing");

  // N1 — CURRENT subscription revoked (status 5), everything signed now.
  const i1 = await identity("f1", { signedMs: at(-60 * 24), status: 1 });
  const n1 = await ingest(i1, { type: "REFUND", notificationSignedMs: at(0), status: 5,
    tx: { expiresMs: at(60 * 24 * 20), revocationMs: at(-1) }, renewal: { signedMs: at(0), renewalMs: at(60 * 24 * 20) } });
  is("B39-N1a", `${n1.disposition}/${n1.result.outcome}`, "state/applied", "REFUND of the current period derives state and applies");
  is("B39-N1b", await member(i1.uid), "false", "access ends");
  is("B39-N1c", await row(i1.uid, "coalesce(pending_cleanup_at = revocation_date + interval '60 days', false)::text"), "true", "quarantine = revocation + 60 days");

  // N3 — REFUND_REVERSED on the same identity, signed later: restores.
  const n3 = await ingest(i1, { type: "REFUND_REVERSED", notificationSignedMs: at(5), status: 1,
    tx: { expiresMs: at(60 * 24 * 20) }, renewal: { signedMs: at(5), renewalMs: at(60 * 24 * 20) } });
  is("B39-N3a", n3.result.outcome, "applied", "REFUND_REVERSED applies");
  is("B39-N3b", await member(i1.uid), "true", "access is restored");
  is("B39-N3c", await row(i1.uid, "(pending_cleanup_at is null and entitlement_ended_at is null and revocation_date is null)::text"), "true", "pending cleanup is cancelled");

  // N2 — REFUND of an EARLIER period: the notification's transaction is the old
  // one (expired, revoked) while Apple's subscription status is still active.
  const i2 = await identity("f2", { signedMs: at(-60 * 24), status: 1 });
  const n2 = await ingest(i2, { type: "REFUND", notificationSignedMs: at(0), status: 1,
    tx: { expiresMs: at(-60 * 24 * 10), revocationMs: at(-60 * 24 * 5) }, renewal: { signedMs: at(0), renewalMs: at(60 * 24 * 20) } });
  is("B39-N2a", n2.result.outcome, "applied", "an earlier period's REFUND applies");
  is("B39-N2b", await member(i2.uid), "true", "the active subscription keeps access");
  is("B39-N2c", await row(i2.uid, "(pending_cleanup_at is null)::text"), "true", "nothing is scheduled");

  // N4 — ORDERING CONTRACT. The row was last refreshed by a reconciliation at
  // T0 (renewal info signed at read time). A REFUND notification signed five
  // minutes LATER carries renewal info signed an hour EARLIER.
  const i4 = await identity("f4", { signedMs: at(0), status: 1 });
  const n4 = await ingest(i4, { type: "REFUND", notificationSignedMs: at(5), status: 5,
    tx: { expiresMs: at(60 * 24 * 20), revocationMs: at(4) }, renewal: { signedMs: at(-60), renewalMs: at(60 * 24 * 20) } });
  console.log(`        N4 observed outcome: ${n4.result.outcome}`);
  is("B39-N4a", n4.result.outcome, "applied", "documented ordering: the newer notification's snapshot applies");
  is("B39-N4b", await member(i4.uid), "false", "…so the refunded member loses access");

  // N5 — the same shape for a REVERSAL: a revoked row, then a newer
  // REFUND_REVERSED whose renewal info is older than the stored signature.
  const i5 = await identity("f5", { signedMs: at(0), status: 5, revokedMs: at(-120) });
  const n5 = await ingest(i5, { type: "REFUND_REVERSED", notificationSignedMs: at(5), status: 1,
    tx: { expiresMs: at(60 * 24 * 20) }, renewal: { signedMs: at(-60), renewalMs: at(60 * 24 * 20) } });
  console.log(`        N5 observed outcome: ${n5.result.outcome}`);
  is("B39-N5a", n5.result.outcome, "applied", "documented ordering: the newer reversal's snapshot applies");
  is("B39-N5b", await member(i5.uid), "true", "…so the reinstated member regains access");
} finally {
  await cleanup();
}

const obs = [...failed].sort().join(" "), prd = [...PRED_FAIL].sort().join(" ");
console.log(`\nB-39 ordering tally: ${pass} passed, ${failed.length} failed`);
if (obs === prd) { console.log("PREDICTION MATCHED"); Deno.exit(0); }
console.log(`PREDICTION DEVIATION\n  predicted: ${prd}\n  observed:  ${obs}`);
Deno.exit(1);
