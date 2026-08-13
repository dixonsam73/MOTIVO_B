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
//   - Comments the departing member WROTE are DELETED (B-3, revised
//     2026-08-13). Third-party replies merely *addressed to* them are still
//     RETAINED (B-19) — those are another member's words on another member's
//     post, and deleting them was the original B-19 defect. The dividing line
//     is authorship: delete what this member wrote, never what was written to
//     them.
//   - The departing member's own received-attachment references are removed.
//   - Attachments they SENT are DELETED, rows and objects, even where a
//     recipient still holds a live reference (B-1, revised 2026-08-13).
//   - Consequently every connected_attachments row naming them on either side
//     is gone (B-9 subsumed).
//
// B-1 AND B-3 WERE REVISED, NOT FOUND WRONG. Both rules were correct given the
// architecture and the settled decisions as they stood. What changed is an
// input: Apple's account-deletion guidance treats content shared with others —
// photos, video, text posts, reviews — as user-generated content that account
// deletion should remove, and the deployed representation could not sustain the
// "that is the recipient's own copy" defence the old rule leaned on. See the
// note at step 2 for the structural reason. Do not "restore" the old behaviour
// on the strength of the earlier register wording.
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
    // Rows where they are the SENDER are handled by step 3 below, which now
    // removes all of them. This step is only the inbox half (B-9).
    //
    // ORDERING IS NOT LOAD-BEARING. This comment claimed the opposite until
    // 2026-08-11, on the grounds that a member could send an attachment to
    // themselves — making their received row the only reference to that asset,
    // so that computing liveness before deleting it would strand the object.
    // That state cannot exist. `connected_attachments_not_self` is
    // CHECK (sender_user_id <> recipient_user_id), and the RLS insert policy
    // `connected_attachments_insert_sender` independently requires
    // recipient_user_id <> auth.uid(). The sender-scoped and recipient-scoped
    // row sets are therefore disjoint. Both are verified in supabase/schema/.
    {
      const { error } = await admin
        .from("connected_attachments")
        .delete()
        .eq("recipient_user_id", uid);
      must("connected_attachments.received", error);
    }

    // 2. (REMOVED 2026-08-13.) This step computed the set of sent assets to
    //    PRESERVE — those with a live recipient reference — and step 3 skipped
    //    them. That was the B-1 guarantee, and it is deliberately gone.
    //
    //    B-1 IS REVISED, NOT OVERTURNED AS AN ERROR. Its rule — attachments a
    //    departing member sent survive for existing recipients — was correct
    //    given the architecture and the settled decisions as they stood. What
    //    changed on 2026-08-13 is an input, not the reasoning: Apple's
    //    account-deletion guidance treats shared photos, video and text posts
    //    as user-generated content that account deletion should remove, and the
    //    deployed representation could not support the "this is the recipient's
    //    own copy" defence that B-1's rule leaned on. `sender_user_id` is
    //    NOT NULL with no FK, and `connected_attachments_sender_storage_path`
    //    pins storage_path to users/<sender_user_id>/connected/<asset_id>.<ext>
    //    — so the object provably remains in the departing member's namespace,
    //    under their uid, with their uid on the row. That is the deleted
    //    account's data, whoever can read it.
    //
    //    Recipient copies already adopted into genuinely local, recipient-owned
    //    storage (Scores) are out of scope: they live on another device and no
    //    backend deletion can or should reach them. See the confirmation copy,
    //    which states this plainly rather than implying total recall.
    //
    //    A recipient-owned/delivered-copy representation — a neutral storage
    //    path with no sender uid — is a Phase 4 architecture question, tracked
    //    separately. It is NOT a reason to keep preserving assets meanwhile.

    // 3. Delete every storage object under users/<uid>/.
    //
    // Both producers write under this prefix and are distinguished by shape:
    //   users/<uid>/<postID>/<attachmentID>.<ext>   post attachments
    //   users/<uid>/connected/<assetID>.<ext>       Connected shares
    // Both are now swept unconditionally, so the shape does not matter.
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
        } else {
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

    // 3b. Delete ALL of the departing member's SENT rows.
    //
    //     REVISED 2026-08-13. This step previously deleted only sender rows
    //     that were already soft-deleted (`deleted_at IS NOT NULL`) — the
    //     tombstone cleanup added for B-9 — because rows with a live recipient
    //     reference were preserved under B-1. B-1 is now revised (see step 2),
    //     so the narrower predicate is subsumed: every sender row goes, live or
    //     soft-deleted, and the objects they name were removed by step 3.
    //
    //     B-9's own lesson still applies to how this is scoped, and it is the
    //     reason this delete is keyed on `sender_user_id` and nothing else.
    //     `connected_attachments_asset_recipient_unique` is
    //     UNIQUE (asset_id, recipient_user_id), so one asset sent to two
    //     recipients is TWO rows sharing ONE storage_path. Scoping by sender
    //     removes exactly this member's rows and cannot reach a row whose
    //     sender is somebody else — which is what a predicate written as
    //     "delete every soft-deleted row" would have done, destroying a third
    //     party's reference. That trap is now avoided by construction rather
    //     than by a predicate that happened to be right.
    //
    //     Idempotent: a second pass matches nothing.
    {
      const { error } = await admin
        .from("connected_attachments")
        .delete()
        .eq("sender_user_id", uid);
      must("connected_attachments.sent", error);
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

    // Comments the departing member AUTHORED, anywhere (B-3, revised
    // 2026-08-13). Previously nothing deleted post_comments explicitly and the
    // posts cascade did all the work; that retained this member's comments on
    // other members' posts, which is what the revision changes.
    //
    // SCOPED TO author_user_id ALONE. Two clauses must never be added here:
    //
    //   owner_user_id  — redundant. post_comments_post_id_fkey is
    //                    ON DELETE CASCADE, so deleting their posts below
    //                    already removes every comment on those posts.
    //
    //   recipient_user_id — THIS CLAUSE WAS B-19, a P1 defect. It matches
    //                    replies AUTHORED BY ANOTHER MEMBER, on that member's
    //                    OWN post, merely addressed to the departing member.
    //                    `reply_to_commenter` and `respond_to_commenters` both
    //                    write owner=postOwner, author=postOwner,
    //                    recipient=theCommenter, so this would destroy third-
    //                    party content because the departing member happened to
    //                    be the addressee. Verified in supabase/schema/.
    //
    // Ordering against the posts delete is immaterial — both are .eq()-scoped
    // and idempotent, and the overlap (their own comments on their own posts)
    // is deleted either way.
    {
      const { error } = await admin
        .from("post_comments")
        .delete()
        .eq("author_user_id", uid);
      must("post_comments.authored", error);
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
