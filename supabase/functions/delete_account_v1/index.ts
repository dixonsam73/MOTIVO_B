import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// delete_account_v1
//
// User-triggered "Erase All Études Data" for the Connected half of an account.
// This is the only client-initiated destructive backend action that remains;
// membership expiry no longer deletes anything (C-1), and irreversible
// expiry cleanup belongs to App Store Server Notifications in Phase 3.
//
// Guarantees, in the order they were agreed:
//
//   - Comments the departing member wrote on other members' posts are RETAINED
//     (B-3). Third-party replies merely *addressed to* them are also RETAINED
//     (B-19) — those are another member's words on another member's post.
//     Both fall out of deleting no post_comments rows explicitly: the
//     post_comments -> posts cascade already removes every comment on the
//     departing member's own posts.
//   - The departing member's own received-attachment references are removed.
//   - Attachments they SENT survive while any live recipient reference remains
//     (B-1). "Live" means connected_attachments.deleted_at IS NULL.
//   - Every operation checks its result and fails immediately and honestly
//     (B-4). Storage listing paginates (B-12).
//   - Cleanup steps are idempotent, so a retry after a failure safely
//     continues (B-13). The sequence is not transactional and does not pretend
//     to be: earlier steps may already have succeeded when a later one fails.
//   - auth.users is deleted strictly last, and success is reported only after
//     it succeeds.
//
// Not handled here, by decision: when the final recipient later soft-deletes
// their reference to a departed sender's asset, nothing removes the
// now-unreferenced object. That lifecycle belongs with B-8/B-10 in Phase 4.
//
// Note verify_jwt is false for this function, so the token check below is the
// only authorisation gate. The subject is always derived from the verified
// token and never from the request body.

const ATTACHMENTS_BUCKET = "attachments";
const AVATARS_BUCKET = "avatars";
const LIST_PAGE = 1000;
const REMOVE_CHUNK = 100;

class StepError extends Error {
  constructor(readonly step: string, message: string) {
    super(message);
  }
}

/** Throws with a step label if a supabase-js result carries an error. */
function must(step: string, error: { message?: string } | null): void {
  if (error) throw new StepError(step, error.message ?? String(error));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE_ROLE = Deno.env.get("SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response("Missing Authorization header", { status: 401 });
  }

  const token = authHeader.replace("Bearer ", "");

  const anon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: userData, error: userErr } = await anon.auth.getUser(token);
  if (userErr || !userData?.user?.id) {
    return new Response("Invalid session", { status: 401 });
  }

  const uid = userData.user.id;
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  try {
    // 1. Remove the departing member's own received-attachment references.
    //
    // ORDER IS LOAD-BEARING — do not move this below step 2, and do not merge
    // the two connected_attachments queries into one pass. Liveness in step 2
    // is computed from rows that survive this delete. If a member sent an
    // attachment to themselves (sender and recipient both this uid), their
    // received row is the only reference to that asset; deleting it first is
    // what allows step 2 to see the asset as unreferenced and step 3 to remove
    // it. Computing liveness first would see that row as live and strand the
    // object permanently, with no owner left to clean it up.
    //
    // Rows where they are the SENDER are deliberately left alone: those are
    // the recipients' references and must survive (B-1).
    {
      const { error } = await admin
        .from("connected_attachments")
        .delete()
        .eq("recipient_user_id", uid);
      must("connected_attachments.received", error);
    }

    // 2. Compute which of their sent assets must be preserved.
    //
    // The row carries storage_path directly, so no path parsing is needed and
    // the rule reduces to one sentence: preserve exactly those object paths
    // that appear as a live sent reference. Post attachments never appear in
    // connected_attachments, so they are not preserved — correct, because the
    // posts that reference them are being deleted.
    const livePaths = new Set<string>();
    {
      const { data, error } = await admin
        .from("connected_attachments")
        .select("storage_path")
        .eq("sender_user_id", uid)
        .eq("storage_bucket", ATTACHMENTS_BUCKET)
        .is("deleted_at", null);
      must("connected_attachments.live", error);
      for (const row of data ?? []) {
        if (row.storage_path) livePaths.add(row.storage_path as string);
      }
    }

    // 3. Delete storage objects under users/<uid>/ except the preserved paths.
    //
    // Both producers write under this prefix and are distinguished by shape:
    //   users/<uid>/<postID>/<attachmentID>.<ext>   post attachments
    //   users/<uid>/connected/<assetID>.<ext>       Connected shares
    // The livePaths set handles both without needing to inspect the shape.
    const doomed: string[] = [];

    async function collect(folder: string): Promise<void> {
      let offset = 0;
      for (;;) {
        const { data: items, error } = await admin.storage
          .from(ATTACHMENTS_BUCKET)
          .list(folder, { limit: LIST_PAGE, offset });
        must(`storage.list:${folder}`, error);

        const page = items ?? [];
        for (const item of page) {
          const fullPath = `${folder}/${item.name}`;
          // supabase-js reports folders as entries with null metadata.
          if ((item as { metadata?: unknown }).metadata == null) {
            await collect(fullPath);
          } else if (!livePaths.has(fullPath)) {
            doomed.push(fullPath);
          }
        }

        if (page.length < LIST_PAGE) break;
        offset += page.length;
      }
    }

    await collect(`users/${uid}`);

    for (let i = 0; i < doomed.length; i += REMOVE_CHUNK) {
      const chunk = doomed.slice(i, i + REMOVE_CHUNK);
      const { error } = await admin.storage.from(ATTACHMENTS_BUCKET).remove(chunk);
      must(`storage.remove:${i}`, error);
    }

    // 4. Avatar, read before the directory row that names it is removed.
    {
      const { data: acct, error } = await admin
        .from("account_directory")
        .select("avatar_key")
        .eq("user_id", uid)
        .maybeSingle();
      must("account_directory.read", error);

      if (acct?.avatar_key) {
        const { error: rmErr } = await admin.storage
          .from(AVATARS_BUCKET)
          .remove([acct.avatar_key as string]);
        must("storage.remove.avatar", rmErr);
      }
    }

    // 5. Relational rows.
    //
    // No post_comments statement, deliberately. The cascade from posts removes
    // every comment on this member's own posts, and anything it does not reach
    // is content we have decided to retain (B-3, B-19).
    {
      const { error } = await admin
        .from("post_comment_views")
        .delete()
        .eq("viewer_user_id", uid);
      must("post_comment_views", error);
    }

    // Shares of this member's own posts cascade with the posts below. Only the
    // ones where they are the recipient of someone else's post need removing.
    {
      const { error } = await admin
        .from("post_shares")
        .delete()
        .eq("recipient_user_id", uid);
      must("post_shares.received", error);
    }

    // posts has no FK to auth.users, so this must be explicit or the rows
    // become permanently unreachable by any RLS policy (B-4).
    {
      const { error } = await admin.from("posts").delete().eq("owner_user_id", uid);
      must("posts", error);
    }

    {
      const { error } = await admin
        .from("follows")
        .delete()
        .or(`follower_user_id.eq.${uid},followed_user_id.eq.${uid}`);
      must("follows", error);
    }

    {
      const { error } = await admin
        .from("account_directory")
        .delete()
        .eq("user_id", uid);
      must("account_directory", error);
    }

    // 6. Auth user strictly last. Until this succeeds the caller still holds a
    // valid session and can retry; every step above is idempotent.
    {
      const { error } = await admin.auth.admin.deleteUser(uid);
      must("auth.deleteUser", error);
    }

    return new Response(JSON.stringify({ success: true }), { status: 200 });
  } catch (err) {
    const step = err instanceof StepError ? err.step : "unknown";
    return new Response(
      JSON.stringify({ success: false, step, error: String(err) }),
      { status: 500 },
    );
  }
});
