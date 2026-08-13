-- 2026-08-13 — B-14: the approver can rewrite follower_user_id while approving
--
-- Reviewed as a diff before being applied, per supabase/README.md.
-- Apply as one round trip so the transaction is real:
--     supabase db query --linked -f supabase/sql/2026-08-13-follows-update-column-privileges.sql
-- then immediately:
--     ./supabase/capture-schema.sh && git diff --stat supabase/schema
--
--
-- THE DEFECT, established from the deployed structure. No exploit was run.
--
--   follows_update_approve_by_followed (UPDATE, authenticated)
--     USING      (followed_user_id = auth.uid()) AND (status = 'requested')
--     WITH CHECK (followed_user_id = auth.uid())
--                AND (follower_user_id = follower_user_id)   <- tautology
--                AND (followed_user_id = followed_user_id)   <- tautology
--                AND (status = 'approved')
--
-- Four catalog facts, all read, and together they are conclusive:
--
--   1. `authenticated` holds UPDATE on the follower_user_id COLUMN.
--   2. USING admits any row where the caller is the followed party and the
--      status is 'requested' — i.e. any genuine pending request to them.
--   3. WITH CHECK constrains nothing about NEW.follower_user_id.
--      `col = col` is a tautology, and WITH CHECK has no access to OLD — there
--      is no previous value to compare against. The clause was never weak; it
--      was inert.
--   4. There is no trigger on this table that could compensate. Zero triggers.
--
-- So an approver holding one genuine pending request can rewrite
-- follower_user_id to any other real account and set status='approved',
-- fabricating an approved follow edge for someone who never requested one.
-- The constraints narrow the target without preventing it: the FK requires a
-- real auth.users id, follows_no_self excludes the approver, and the PK
-- requires that the victim does not already follow them.
--
-- Consequence, direction confirmed against posts_select_public_or_owner:
-- that policy requires `f.follower_user_id = auth.uid()`, so the forged edge
-- (follower=victim, followed=approver) pushes the APPROVER's public posts into
-- the VICTIM's feed. Injection, not exfiltration — nothing of the victim's is
-- exposed. That bounds severity and is why B-14 stays P3.
--
-- SECOND HARM, not recorded in B-14's cell: the row is rewritten, not copied.
-- The genuine requester's pending request is DESTROYED — no approval, and no
-- record they ever asked.
--
--
-- WHY THIS IS A PRIVILEGE FIX AND NOT A POLICY FIX
--
-- RLS cannot express "this column must keep its previous value", because
-- WITH CHECK sees only NEW. The only options are a trigger or a column
-- privilege. Column privileges are evaluated BEFORE RLS, so revoking UPDATE on
-- the participant columns removes the capability outright rather than
-- filtering it — and it needs no new code to maintain.
--
--
-- CALLER MAP — every authenticated mutation of public.follows, enumerated
-- before choosing the grant, because the revoke is global to the role:
--
--   request follow    POST   (insert)  follower_user_id, followed_user_id, status
--   APPROVE           PATCH            status, updated_at   <- the only UPDATE
--   decline           DELETE
--   remove follower   DELETE
--   unfollow          DELETE
--   withdraw request  DELETE  (deleteRelationship fires both directions)
--
-- That PATCH (BackendShim.swift:714) is the only UPDATE of follows anywhere in
-- the client; every other PATCH in the codebase targets posts, post_shares,
-- connected_attachments or account_directory. No deployed RPC updates follows,
-- and delete_account_v1 deletes from it as service_role.
--
-- THE PARTICIPANT IDS ARE NEVER LEGITIMATELY MUTABLE. They are the primary
-- key, and every state transition in the product except approval is expressed
-- by creating or destroying a row rather than by rewriting who it is about.
-- created_at is never written by the client either — the insert omits it and
-- takes the default — so it is revoked along with them.

begin;

-- 1. The fix.
--
--    status AND updated_at are both required: approveFollow PATCHes both, and
--    granting status alone would break approval in production.
--
--    Residual, accepted rather than overlooked: updated_at stays
--    client-writable, so an approver can set an arbitrary timestamp. No policy
--    reads it and it carries no authorisation meaning. Making it
--    server-maintained needs a trigger, which is more than this finding
--    warrants.
--
--    service_role is deliberately untouched. It is not the actor here, and
--    delete_account_v1 deletes from follows rather than updating it, so
--    narrowing it would add risk without addressing B-14.
--
--    INSERT and DELETE privileges are unaffected by this statement; the
--    request and unfollow/decline paths are untouched.

revoke update on public.follows from authenticated;
grant  update (status, updated_at) on public.follows to authenticated;

-- 2. Honesty fix. NOT the security fix — the grant above is.
--
--    The two tautological clauses read as though they pin the participant
--    columns. They never did. Left in place, a future maintainer could revoke
--    the column grant believing the policy still covers this, and reintroduce
--    the defect. The predicate below states exactly what the policy actually
--    enforces: only the followed party may approve, and only to 'approved'.
--
--    WHERE THE REAL PROTECTION LIVES: column privileges on public.follows.
--    See supabase/schema/column_grants.json.

alter policy follows_update_approve_by_followed on public.follows
  with check (
    followed_user_id = auth.uid()
    and status = 'approved'
  );

commit;
