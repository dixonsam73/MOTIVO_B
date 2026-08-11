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
//   - The avatar is removed by prefix as well as by pointer (B-20), because
//     the directory column is not a reliable pointer to it.
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

  /**
   * Every entry in one storage folder, paginated (B-12). Not recursive — the
   * one caller that needs recursion does it itself, because what counts as a
   * folder is only meaningful to that caller.
   */
  async function listFolder(
    bucket: string,
    folder: string,
    step: string,
  ): Promise<{ name: string; metadata?: unknown }[]> {
    const all: { name: string; metadata?: unknown }[] = [];
    let offset = 0;
    for (;;) {
      const { data: items, error } = await admin.storage
        .from(bucket)
        .list(folder, { limit: LIST_PAGE, offset });
      must(step, error);

      const page = (items ?? []) as { name: string; metadata?: unknown }[];
      all.push(...page);

      if (page.length < LIST_PAGE) break;
      offset += page.length;
    }
    return all;
  }

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
      const entries = await listFolder(
        ATTACHMENTS_BUCKET,
        folder,
        `storage.list:${folder}`,
      );
      for (const item of entries) {
        const fullPath = `${folder}/${item.name}`;
        // supabase-js reports folders as entries with null metadata.
        if (item.metadata == null) {
          await collect(fullPath);
        } else if (!livePaths.has(fullPath)) {
          doomed.push(fullPath);
        }
      }
    }

    await collect(`users/${uid}`);

    for (let i = 0; i < doomed.length; i += REMOVE_CHUNK) {
      const chunk = doomed.slice(i, i + REMOVE_CHUNK);
      const { error } = await admin.storage.from(ATTACHMENTS_BUCKET).remove(chunk);
      must(`storage.remove:${i}`, error);
    }

    // 4. Avatar — BY PREFIX AND BY POINTER, not by pointer alone (B-20).
    //
    // account_directory.avatar_key is not a reliable pointer to the object.
    // Three routes lead to a null or stale key with the photo still present:
    // both of C-33's (a failed object delete followed by a successful patch to
    // null; an upload followed by a failed directory patch) and a missing
    // directory row, where maybeSingle() returns null and a pointer-driven step
    // silently skips. Anything left behind is unreachable forever after step 6:
    // avatars_delete_owner_only requires auth.uid() to equal a user that no
    // longer exists, so there is no owner, no client path and no policy path.
    // Permanently orphaned personal data, and precisely the data the erase
    // promises to remove.
    //
    // The union is deliberate in both directions. The prefix catches an object
    // the column does not name; the keyed object catches a stale key pointing
    // outside the prefix.
    //
    // Bounded and safe: avatars_insert_owner_only pins every client write to
    // exactly users/<uid>/avatar.jpg, so the sweep can reach one object and
    // cannot touch anyone else's. The listing is flat for the same reason — a
    // nested name is not writable through any client path, so recursing here
    // would guard against nothing.
    //
    // Read before step 5 deletes the directory row that names it.
    {
      const { data: acct, error } = await admin
        .from("account_directory")
        .select("avatar_key")
        .eq("user_id", uid)
        .maybeSingle();
      must("account_directory.read", error);

      const avatarPaths = new Set<string>();

      const folder = `users/${uid}`;
      for (
        const item of await listFolder(
          AVATARS_BUCKET,
          folder,
          "storage.list.avatars",
        )
      ) {
        if (item.metadata != null) avatarPaths.add(`${folder}/${item.name}`);
      }

      if (acct?.avatar_key) avatarPaths.add(acct.avatar_key as string);

      if (avatarPaths.size > 0) {
        const { error: rmErr } = await admin.storage
          .from(AVATARS_BUCKET)
          .remove([...avatarPaths]);
        must("storage.remove.avatar", rmErr);
      }
    }

    // 5. Relational rows.
    //
    // THERE IS NO post_comments STATEMENT HERE, AND THAT IS THE FIX — do not
    // add one back. Deleting a statement to repair two findings looks like an
    // omission, so the reasoning is spelled out.
    //
    // `post_comments_post_id_fkey` is ON DELETE CASCADE (verified in
    // supabase/schema/constraints.json), so removing this member's posts
    // already removes every comment on them. What a delete here would reach in
    // addition is exactly the content we decided to keep:
    //
    //   author_user_id = uid     their comments on OTHER members' posts (B-3)
    //   recipient_user_id = uid  replies written BY another member, on that
    //                            member's own post, merely addressed to this
    //                            one (B-19) — someone else's words entirely
    //   owner_user_id = uid      redundant; the cascade above covers it
    //
    // Retained comments will hold author/recipient IDs pointing at a deleted
    // account, and account_directory cascades from auth.users, so those names
    // will not resolve. That is a client rendering concern, not a reason to
    // delete conversation history.
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
