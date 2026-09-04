-- P4-U2s — SHARED-ONLY, ENFORCED BY THE SERVER.
--
-- Adds ONE conjunct to the existing owner INSERT policy on public.posts. Every
-- pre-existing condition is preserved verbatim; nothing is rewritten for
-- tidiness.
--
--   before: (( SELECT enforcement_gate('posts.insert'::text) AS enforcement_gate)
--            AND (owner_user_id = auth.uid()))
--   after :  … AND (is_public = true)
--
-- WHY IT IS A TOP-LEVEL CONJUNCT AND NOT INSIDE THE GATE. `enforcement_gate`
-- returns TRUE whenever U6b enforcement is inactive, so a clause nested inside
-- it would evaporate the moment the membership kill switch was thrown. This is a
-- DOMAIN 3 PRIVACY INVARIANT, not membership enforcement: it must hold in both
-- switch positions. Do not "tidy" it into the gate.
--
-- WHY `= true` AND NOT `IS NOT FALSE`. `is_public` is NOT NULL, so `= true` is
-- strictly two-valued. It also rejects the column's own DEFAULT: the column
-- defaults to FALSE, so a client that OMITS is_public is refused too, which is
-- the case a payload-shaped check would miss.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. No UPDATE restriction on is_public: the
-- unshare model requires demotion-to-private to stay possible while deletion is
-- pending (C-61), and blocking it would leave content PUBLICLY VISIBLE after a
-- failed unshare. No schema-default change: the invariant is rejection of the
-- resulting false value, and nothing measured requires touching the default.

alter policy posts_insert_owner on public.posts
  with check (
    (select public.enforcement_gate('posts.insert'::text))
    and (owner_user_id = auth.uid())
    and (is_public = true)
  );
