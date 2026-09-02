import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AppleApiError,
  AppStoreServerApi,
  type AppleEnvironment,
  credentialsFromEnv,
  lastTransactionsOf,
} from "../_shared/appstore/api.ts";
import { verifyAppleJWS } from "../_shared/appstore/jws.ts";
import { deriveFromReconciliation } from "../_shared/appstore/derive.ts";

// membership_cleanup_v1 — U7's expiry cleanup worker.
//
// THE ONLY IRREVERSIBLE PATH IN PHASE 3 THAT NO HUMAN CONFIRMS AT THE MOMENT IT
// RUNS. Everything about its structure follows from that.
//
// CLEANUP AUTHORITY, the standing rule this function exists to obey:
//
//   No stored membership record, notification, scheduled timestamp, client state
//   or local cache is sufficient authority for irreversible expiry cleanup.
//   Immediately before cleanup, Etudes must obtain current authoritative
//   subscription status from Apple. If that authority cannot be obtained,
//   cleanup does not run and is retried later.
//
// So pending_cleanup_at SELECTS. It never AUTHORISES. The authority is a live
// Apple read, applied through the canonical writer, followed by
// connected_member() -- the same predicate the API enforces with.
//
// EXPIRY IS NOT ACCOUNT DELETION, and this function is not delete_account_v1.
// The retention matrix diverges deliberately: comments the member authored on
// other members' surviving posts are RETAINED, sent attachments with a live
// recipient reference are RETAINED (row AND object), the account_directory row
// is RETAINED so retained comments still render a name, and auth.users is
// RETAINED. There is no auth.admin.deleteUser call in this file and there must
// never be one.
//
// LOCAL DATA IS NEVER TOUCHED BY ANYTHING HERE. Invariant 1. This is a server
// worker; the musician's journal is not reachable from it and no lifecycle event
// may reset it.

const ATTACHMENTS = "attachments";
const AVATARS = "avatars";
const LIST_PAGE = 1000;
const REMOVE_CHUNK = 100;

type Mode = "dry_run" | "execute";

interface Row { user_id: string; environment: string; original_transaction_id: string }

class StepError extends Error {
  constructor(readonly step: string, message: string) { super(message); }
}
function must(step: string, error: { message?: string } | null): void {
  if (error) throw new StepError(step, error.message ?? String(error));
}

const json = (status: number, body: Record<string, unknown>): Response =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** Constant-time. Length may leak; content may not. */
function secretEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/** Every entry in one storage folder, paginated (B-12). Not recursive. */
async function listFolder(
  admin: SupabaseClient, bucket: string, folder: string, step: string,
): Promise<{ name: string; metadata?: unknown }[]> {
  const all: { name: string; metadata?: unknown }[] = [];
  let offset = 0;
  for (;;) {
    const { data, error } = await admin.storage.from(bucket).list(folder, { limit: LIST_PAGE, offset });
    must(step, error);
    const page = (data ?? []) as { name: string; metadata?: unknown }[];
    all.push(...page);
    if (page.length < LIST_PAGE) break;
    offset += page.length;
  }
  return all;
}

/** Every OBJECT (not folder) under a prefix, recursively. */
async function listTree(admin: SupabaseClient, bucket: string, folder: string): Promise<string[]> {
  const out: string[] = [];
  for (const item of await listFolder(admin, bucket, folder, `storage.list:${folder}`)) {
    const full = `${folder}/${item.name}`;
    // supabase-js reports folders as entries with null metadata.
    if (item.metadata == null) out.push(...await listTree(admin, bucket, full));
    else out.push(full);
  }
  return out;
}

// ---------------------------------------------------------------- doomed set
//
// THE SELECTIVE SWEEP. delete_account_v1 removes everything under users/<uid>/
// unconditionally, and copying that here would be the single most likely defect
// in U7: retained sent attachments live at users/<uid>/connected/<asset>.<ext>,
// INSIDE the subject's own prefix. Every assertion about rows would still pass
// while the objects those rows point at were destroyed.
//
// Reference counting is on asset_id with deleted_at IS NULL, because
// connected_attachments_asset_recipient_unique is UNIQUE(asset_id,
// recipient_user_id): one asset sent to two recipients is TWO rows sharing ONE
// storage_path. An asset survives while ANY recipient reference is live.
async function computeDoomed(admin: SupabaseClient, uid: string) {
  const { data: sent, error } = await admin
    .from("connected_attachments")
    .select("asset_id, storage_path, deleted_at")
    .eq("sender_user_id", uid);
  must("connected_attachments.sent.read", error);

  const live = new Set<string>();
  const paths = new Map<string, string>();
  for (const r of (sent ?? []) as { asset_id: string; storage_path: string; deleted_at: string | null }[]) {
    paths.set(r.asset_id, r.storage_path);
    if (r.deleted_at == null) live.add(r.asset_id);
  }
  const retainedPaths = new Set<string>();
  const doomedAssets: string[] = [];
  for (const [asset, path] of paths) {
    if (live.has(asset)) retainedPaths.add(path);
    else doomedAssets.push(asset);
  }

  const all = await listTree(admin, ATTACHMENTS, `users/${uid}`);
  const doomedObjects = all.filter((p) => !retainedPaths.has(p));

  return { doomedAssets, doomedObjects, retainedPaths: [...retainedPaths] };
}

/**
 * Remove objects and PROVE they are gone by re-listing.
 *
 * MEASURED 2026-09-02, and this function exists because of what was measured:
 * storage.remove() returns error:null for keys it did NOT delete. A key that
 * never existed, a key already removed and a key removed just now are
 * indistinguishable from the return value -- absent-key removal is not an error,
 * which makes retries safe, and simultaneously makes success meaningless as
 * evidence.
 *
 * So a WRONG path would report success, delete nothing, and let the caller go on
 * to delete the rows -- orphaning the real objects permanently, with no row left
 * to find them by and no policy path able to reach them. That is B-8's
 * unreachable-orphan state arriving through a success message, and it is the
 * same shape as `supabase storage rm` no-oping at exit 0 and the U6a apply
 * reporting "Success. No rows returned."
 *
 * ANY PROCEDURE WHOSE SUCCESS IS REPORTED BY THE THING BEING ASKED TO ACT IS
 * UNVERIFIED. The re-list is the independent check.
 */
async function removeVerified(
  admin: SupabaseClient, bucket: string, prefix: string, doomed: string[], step: string,
): Promise<void> {
  if (doomed.length === 0) return;
  for (let i = 0; i < doomed.length; i += REMOVE_CHUNK) {
    const { error } = await admin.storage.from(bucket).remove(doomed.slice(i, i + REMOVE_CHUNK));
    must(`${step}.remove:${i}`, error);
  }
  const still = new Set(await listTree(admin, bucket, prefix));
  const survivors = doomed.filter((p) => still.has(p));
  if (survivors.length > 0) {
    throw new StepError(
      `${step}.verify`,
      `${survivors.length} object(s) still present after removal: ${survivors.slice(0, 3).join(", ")}`,
    );
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;

  const presented = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!presented || !secretEquals(presented, SERVICE_ROLE)) {
    return json(401, { error: "service role credential required" });
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { body = {}; }

  // DRY RUN IS THE DEFAULT. Destructive execution requires naming itself, so a
  // replayed or malformed invocation previews instead of destroying. This
  // remains true after U7e: the scheduler must name the mode in its own body.
  const mode: Mode = body.mode === "execute" ? "execute" : "dry_run";
  const limit = Number.isFinite(body.limit) ? Math.max(1, Number(body.limit)) : 25;
  const only = body.user_id ? String(body.user_id) : null;

  const db = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ------------------------------------------------------------- selection
  //
  // ONE ELIGIBILITY DEFINITION, TWO BEHAVIOURS. The preview path is STABLE and
  // therefore structurally unable to claim; the execute path claims. Both derive
  // their candidates from membership_cleanup_eligible_v1, so they cannot drift.
  const selector = mode === "execute"
    ? "membership_due_for_cleanup_v1"
    : "membership_cleanup_eligible_v1";
  const { data: rows, error: selErr } = await db.rpc(selector, { p_limit: limit });
  if (selErr) return json(500, { error: `selection failed: ${selErr.message}`, mode });

  const byUser = new Map<string, Row[]>();
  for (const r of (rows ?? []) as Row[]) {
    if (only && r.user_id !== only) continue;
    (byUser.get(r.user_id) ?? byUser.set(r.user_id, []).get(r.user_id)!).push(r);
  }

  const results: Record<string, unknown>[] = [];

  // ================================================================ DRY RUN
  //
  // NON-MUTATING, AND IT DOES NOT CONTACT APPLE.
  //
  // Answering "will this proceed" requires APPLYING Apple's state through the
  // canonical writer, which is a mutation; and deriving entitlement here without
  // applying would be a THIRD implementation of Apple's formula, after
  // connected_member() and membership_apply_state_v1. Both were rejected.
  //
  // So the honest contract is that a dry run answers the BLAST RADIUS question
  // and says so. Whether Apple authorises is answered at execution, by the
  // cleanup-authority rule -- and an execution that declines because Apple
  // reports the member entitled is correct behaviour, not a surprise.
  if (mode === "dry_run") {
    for (const [uid, userRows] of byUser) {
      try {
        const { doomedAssets, doomedObjects, retainedPaths } = await computeDoomed(db, uid);
        const counts: Record<string, number> = {};
        const count = async (table: string, col: string) => {
          const { count: n, error } = await db.from(table).select("*", { count: "exact", head: true }).eq(col, uid);
          must(`count.${table}`, error);
          counts[`${table}.${col}`] = n ?? 0;
        };
        await count("posts", "owner_user_id");
        await count("post_shares", "recipient_user_id");
        await count("post_comment_views", "viewer_user_id");
        await count("connected_attachments", "recipient_user_id");

        const avatarObjects = (await listFolder(db, AVATARS, `users/${uid}`, "storage.list.avatars"))
          .filter((i) => i.metadata != null).map((i) => `users/${uid}/${i.name}`);

        results.push({
          user_id: uid,
          environments: userRows.map((r) => r.environment),
          would_delete: {
            ...counts,
            connected_attachments_sent_assets: doomedAssets.length,
            storage_objects: doomedObjects.length,
            avatar_objects: avatarObjects.length,
          },
          would_delete_objects: doomedObjects,
          would_retain_objects: retainedPaths,
          note: "BLAST RADIUS ONLY. Authority is NOT evaluated in dry_run: no Apple read was made and no membership state was written. A dry run is never authority for an execution.",
        });
      } catch (e) {
        results.push({ user_id: uid, error: String(e), step: e instanceof StepError ? e.step : "unknown" });
      }
    }
    return json(200, {
      ok: true, mode, claimed: false, deleted: false,
      identities: results.length, results,
      note: "dry_run is non-mutating and acquires no lease.",
    });
  }

  // ================================================================ EXECUTE
  let apple: AppStoreServerApi;
  try {
    const overrides: Partial<Record<AppleEnvironment, string>> = {};
    const sb = Deno.env.get("APPLE_API_BASE_URL_SANDBOX");
    const pr = Deno.env.get("APPLE_API_BASE_URL_PRODUCTION");
    if (sb) overrides.Sandbox = sb;
    if (pr) overrides.Production = pr;
    apple = new AppStoreServerApi(credentialsFromEnv(Deno.env), { baseUrls: overrides });
  } catch (e) {
    return json(500, { error: `credentials unavailable: ${String(e)}`, deleted: false });
  }

  for (const [uid, userRows] of byUser) {
    // ---- step 2. REFRESH EVERY ROW OF THIS IDENTITY.
    //
    // Not only the due one. connected_member() reads every row, and cleanup
    // destroys IDENTITY-scoped material, so authority computed from a partly
    // stale identity is authority computed from stale state -- on exactly the
    // half not looked at. The concrete failure is a lapsed Sandbox row causing
    // the destruction of a live Production member's content.
    let refreshFailed: string | null = null;
    for (const row of userRows) {
      try {
        const resp = await apple.getAllSubscriptionStatuses(
          row.environment as AppleEnvironment, row.original_transaction_id,
        );
        let applied = false;
        for (const entry of lastTransactionsOf(resp)) {
          if (String(entry.originalTransactionId ?? "") !== row.original_transaction_id) continue;
          let tx: Record<string, unknown> | null = null;
          let ri: Record<string, unknown> | null = null;
          if (typeof entry.signedTransactionInfo === "string") tx = await verifyAppleJWS(entry.signedTransactionInfo);
          if (typeof entry.signedRenewalInfo === "string") ri = await verifyAppleJWS(entry.signedRenewalInfo);
          const derived = deriveFromReconciliation({ transaction: tx, renewal: ri, status: entry.status });
          if (derived.state === null) { refreshFailed = `incomplete: ${derived.reason}`; break; }
          const { error } = await db.rpc("membership_apply_reconciliation_v1", {
            p_user_id: uid,
            p_environment: row.environment,
            p_state: derived.state,
            p_original_transaction_id: derived.original_transaction_id ?? row.original_transaction_id,
          });
          if (error) { refreshFailed = `write_failed: ${error.message}`; break; }
          applied = true;
          break;
        }
        if (!refreshFailed && !applied) refreshFailed = "no usable Apple entry for this transaction";
      } catch (e) {
        const err = e instanceof AppleApiError ? `${e.kind}/${e.status}` : String(e).slice(0, 120);
        refreshFailed = `apple_read_failed: ${err}`;
      }
      if (refreshFailed) break;
    }

    // A FAILED OR AMBIGUOUS READ IS NEVER A DELETION. There is no "N failures
    // then proceed": a member's content is never destroyed because Apple was
    // unreachable for long enough. The lease simply expires and the identity is
    // retried. An identity that can never be read stays a visible candidate,
    // which is an operator problem with a queue to look at rather than a silent
    // deletion.
    if (refreshFailed) {
      results.push({ user_id: uid, decision: "abort", reason: refreshFailed, deleted: false });
      continue;
    }

    // ---- step 3. AUTHORITY, DECIDED BY THE DATABASE IN ONE STATEMENT.
    //
    // NOT composed here. An earlier version asked connected_member() and
    // "is a schedule still due" as two round trips and combined them itself --
    // which put the authority decision in the caller, where it can be got half
    // right, and which ALSO could not run at all: connected_member(uuid) is
    // ungranted to every role including service_role (B-33, so the membership
    // oracle is structurally unbuildable), and service_role holds zero table
    // privilege on membership. Two violations, the second hidden behind the
    // first until the first was fixed.
    //
    // The gate reads the row REFRESHED IMMEDIATELY ABOVE. It cannot itself know
    // whether that refresh happened, so calling it only after a successful Apple
    // read is this function's obligation -- which is why the refresh failure
    // above `continue`s rather than falling through.
    const { data: auth, error: authErr } = await db.rpc(
      "membership_cleanup_authorised_v1", { p_user_id: uid },
    );
    if (authErr) {
      results.push({ user_id: uid, decision: "abort", reason: `authority gate failed: ${authErr.message}`, deleted: false });
      continue;
    }
    const gate = auth as { authorised: boolean; reason: string; connected_member: boolean };
    if (!gate.authorised) {
      // Either the member is entitled again -- QA C5's server half, and the
      // guard that stops a stale Sandbox candidate destroying a live Production
      // member's content -- or reconciliation cleared the schedule. Neither is
      // an error and neither deletes anything.
      results.push({ user_id: uid, decision: "refused", reason: gate.reason, deleted: false });
      continue;
    }

    // ---- step 4. DESTRUCTIVE CLEANUP.
    //
    // OBJECTS BEFORE ROWS, EVERYWHERE. Rows are the only liveness evidence there
    // is: if a row is deleted first and the object removal then fails, nothing
    // can find that object again -- B-8's lesson is that a users/<uid>/ path
    // prefix carries the SENDER's uid and cannot establish liveness, so a later
    // sweep cannot tell a retained asset from an abandoned one. Reversed, a
    // failure between the two leaves a row pointing at a missing object, which
    // the next run recomputes and completes.
    try {
      const { doomedAssets, doomedObjects } = await computeDoomed(db, uid);

      // 4a. post-attachment and doomed connected OBJECTS, verified absent.
      await removeVerified(db, ATTACHMENTS, `users/${uid}`, doomedObjects, "attachments");

      // 4b. the sent rows whose objects have just been proven gone.
      if (doomedAssets.length > 0) {
        const { error } = await db.from("connected_attachments")
          .delete().eq("sender_user_id", uid).in("asset_id", doomedAssets);
        must("connected_attachments.sent", error);
      }

      // 4c. received references. DISJOINT from 4b by constraint, not by luck:
      // connected_attachments_not_self is CHECK (sender <> recipient), so the
      // sender-scoped and recipient-scoped row sets cannot overlap and their
      // ordering is immaterial.
      must("connected_attachments.received",
        (await db.from("connected_attachments").delete().eq("recipient_user_id", uid)).error);

      must("post_shares.received",
        (await db.from("post_shares").delete().eq("recipient_user_id", uid)).error);
      must("post_comment_views",
        (await db.from("post_comment_views").delete().eq("viewer_user_id", uid)).error);
      must("follows",
        (await db.from("follows").delete().or(`follower_user_id.eq.${uid},followed_user_id.eq.${uid}`)).error);

      // 4d. own posts. Sent shares and comments ON these posts cascade
      // (post_shares_post_id_fkey, post_comments_post_id_fkey, both ON DELETE
      // CASCADE) -- RATIFIED 2026-09-02 as a decision rather than an inherited
      // cascade: after the post is gone a preserved comment has no render site.
      //
      // post_comments IS NOT DELETED BY AUTHOR HERE, and that is the whole
      // divergence from delete_account_v1. Comments this member authored on OTHER
      // members' surviving posts are RETAINED, attributed, forever.
      must("posts", (await db.from("posts").delete().eq("owner_user_id", uid)).error);

      // 4e. avatar. OBJECT FIRST, POINTER SECOND, AND ONLY ON SUCCESS -- C-33's
      // ordering. Clearing avatar_key first would strand a real photo behind a
      // null pointer. Swept by PREFIX and by POINTER (B-20's union): the prefix
      // catches an object the column does not name, the pointer catches a stale
      // key outside the prefix.
      const { data: acct, error: acctErr } = await db
        .from("account_directory").select("avatar_key").eq("user_id", uid).maybeSingle();
      must("account_directory.read", acctErr);
      const avatarPaths = new Set<string>();
      for (const i of await listFolder(db, AVATARS, `users/${uid}`, "storage.list.avatars")) {
        if (i.metadata != null) avatarPaths.add(`users/${uid}/${i.name}`);
      }
      if (acct?.avatar_key) avatarPaths.add(acct.avatar_key as string);
      if (avatarPaths.size > 0) {
        await removeVerified(db, AVATARS, `users/${uid}`, [...avatarPaths], "avatars");
        // Reached only if every avatar object is verifiably gone.
        must("account_directory.clear_avatar",
          (await db.from("account_directory").update({ avatar_key: null }).eq("user_id", uid)).error);
      }

      // ---- step 5. COMPLETION, LAST. Until this lands the identity stays a
      // candidate, so an interrupted run resumes rather than being forgotten.
      const { data: done, error: doneErr } = await db.rpc("membership_cleanup_complete_v1", { p_user_id: uid });
      must("cleanup_complete", doneErr);

      results.push({ user_id: uid, decision: "cleaned", deleted: true, completion: done });
    } catch (e) {
      // ABORT LEAVES NO COMPLETION MARKER. The lease expires and the next run
      // re-authorises from scratch: a partially-completed cleanup acquires no
      // right to finish itself, because that would be deletion on stale
      // authority -- the one thing this whole unit exists to prevent.
      results.push({
        user_id: uid, decision: "abort", deleted: "partial",
        step: e instanceof StepError ? e.step : "unknown", reason: String(e),
      });
    }
  }

  return json(200, { ok: true, mode, identities: results.length, results });
});
