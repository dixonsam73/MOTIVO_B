-- B-6 — bind a visible post's attachment reference to the object's actual owner.
--
-- NOT YET APPLIED. Reviewed as a diff first, per supabase/README.md.
--
-- THE DEFECT
--
-- `attachments_select_via_visible_post` asks only whether *some* post references
-- this bucket/path. There is no predicate tying that post to the object's owner,
-- and `posts_insert_owner` validates only `owner_user_id` — never the
-- `attachments` jsonb. So a member can write an arbitrary path into their OWN
-- post and read the object:
--
--   the attacker's own post always satisfies `posts_select_public_or_owner`'s
--   owner clause, so the EXISTS is satisfied by a post they fully control, and
--   the jsonb they put in it is never checked against anything.
--
-- That is not a revocation bypass. It is read access to any attachment whose
-- path is known, which is privilege escalation across the whole bucket.
--
-- DEPENDENCY CHECK PERFORMED BEFORE PROPOSING THIS — the point was to find a
-- legitimate cross-owner reference that this predicate would break. There is
-- none.
--
-- 1. WRITERS. Exactly one in production: `BackendShim.publish…` →
--    `patchPostAttachments`. Its paths come from `storageObjectPath(owner:…)`
--    (`BackendShim:1151`), which is literally
--    `users/<owner>/<postID>/<attachmentID>.<ext>`, and `owner` is
--    `AuthManager.canonicalBackendUserID()` (`:829`) — the signed-in user, never
--    an input. The storage INSERT policy independently pins uploads to
--    `users/<auth.uid()>/…`, so the two agree.
--
-- 2. PATH SHAPES. That one shape. Nothing else can be produced by the shipping
--    app.
--
-- 3. CONNECTED / SHARED / ADOPTED FLOWS. None of them writes `posts.attachments`.
--    Connected sends live in `connected_attachments` and are read through
--    `connected_attachment_recipient_select`, a different policy this change does
--    not touch. Adoption into Scores copies the file locally and creates no
--    backend reference. `post_shares` carries post ids, not paths (and is empty).
--
-- 4. LEGACY / MIGRATION STATE. Measured, not assumed: across all 98 posts there
--    are **6 attachment references over 5 posts, and all 6 are under
--    `users/<that post's owner>/`**, all in the `attachments` bucket. Zero
--    cross-owner references exist today. There are also zero objects under any
--    `debug/` prefix in either bucket.
--
-- 5. READ PATHS. This is the subtlety the fix must respect. An approved follower
--    reading another member's post legitimately reads an object under the POST
--    OWNER's prefix — cross-owner from the viewer's seat, and correct. So the
--    binding must be object-owner = POST OWNER, and must never be
--    object-owner = auth.uid(), which would break every follower read.
--
-- THE ONE FLOW THIS DELIBERATELY BREAKS: `DebugViewerView` (`#if DEBUG`, absent
-- from Release) can PATCH arbitrary paths — including `debug/…` — into
-- `posts.attachments` against the real backend. Under this policy such objects
-- stop being readable through the post path. That is correct, it affects a
-- developer tool only, no such objects exist, and B-7's `debug/` escape hatch —
-- which existed to serve exactly that flow — was dropped earlier today.
--
-- WHAT CHANGES, MINIMALLY
--
-- One added conjunct binding the object's path owner to the referencing post's
-- owner, plus the `users/` shape check that the sibling owner-select policy
-- already uses. Visibility is NOT narrowed by any other means: which posts the
-- caller can see is still decided entirely by RLS on `posts`, unchanged. No
-- service-role broadening. No change to any other policy.

alter policy "attachments_select_via_visible_post"
    on storage.objects
    using (
        bucket_id = 'attachments'
        and (storage.foldername(name))[1] = 'users'
        and exists (
            select 1
            from posts p
            where lower((storage.foldername(objects.name))[2]) = lower(p.owner_user_id::text)
              and exists (
                  select 1
                  from jsonb_array_elements(p.attachments) a
                  where a.value ->> 'bucket' = objects.bucket_id
                    and a.value ->> 'path' = objects.name
              )
        )
    );
