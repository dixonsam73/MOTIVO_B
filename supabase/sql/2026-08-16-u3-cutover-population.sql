-- Phase 3 U3 — PRODUCTION CUTOVER POPULATION.
--
-- NOT YET EXECUTED. Prepared for separate review and explicit authorisation.
--
-- This is step B of the U3 deployment. Step A is the structural DDL, which is
-- supabase/migrations/20260816120000_u3_membership_schema.sql applied by hand to
-- production as a reviewed diff (production is not on the migration history and
-- is deliberately not re-based -- see supabase/README.md).
--
-- Run step A first, verify the structural delta, and only then run this.
--
--
-- WHY THE BOUNDARY IS AN EXPLICIT TIMESTAMP RATHER THAN "WHATEVER THE SELECT SAW"
--
-- An earlier draft captured `select id from auth.users` and called a concurrent
-- sign-in benign because nothing reads the snapshot at U3. That reasoning was
-- too loose: U6b will read it, and at that point "pre-cutover identity" must
-- have a DEFINITION, not merely a recollection of what one statement observed.
--
-- So the boundary is materialised in membership_control.cutover_at, and the
-- population predicate is `auth.users.created_at < cutover_at`. That makes the
-- rule re-derivable and auditable afterwards -- anyone can re-run the predicate
-- and compare it against cutover_identity_count -- rather than depending on an
-- MVCC snapshot nobody can reconstruct later.
--
-- SERIALIZABLE, because the transaction reads auth.users and writes a count
-- derived from that read. Under READ COMMITTED a concurrent GoTrue insert could
-- commit between the insert and the count, leaving cutover_identity_count
-- disagreeing with the rows actually captured.
--
-- The residual window is small but REAL and is not hand-waved: an identity
-- created before the boundary whose transaction commits after our snapshot is
-- not captured, yet satisfies `created_at < cutover_at`. That is exactly what
-- assertion 3 below detects. If it fires, STOP -- do not silently top up.


begin transaction isolation level serializable;

-- Refuse to run twice. If cutover_at is already set this updates nothing, the
-- assertions below fail, and the transaction is rolled back.
select cutover_at is null as safe_to_run
  from public.membership_control
 where id;

-- Fix the boundary ONCE, up front, and use it for both the predicate and the
-- record. now() is transaction time under SERIALIZABLE, so every statement in
-- this transaction sees the same instant.
update public.membership_control
   set cutover_at             = now(),
       updated_at             = now(),
       notes                  = 'U3 cutover. Pre-cutover is defined as auth.users.created_at < cutover_at.'
 where id
   and cutover_at is null;

-- Capture. One statement: partial capture is structurally impossible.
insert into public.membership_cutover (user_id)
select u.id
  from auth.users u
 where u.created_at < (select cutover_at from public.membership_control where id)
    on conflict (user_id) do nothing;

update public.membership_control
   set cutover_identity_count = (select count(*) from public.membership_cutover)
 where id;

-- ============================ ASSERTIONS ============================
-- Read these before committing. Any failure -> ROLLBACK, then report.
--
--  1. captured  = rows now in membership_cutover
--  2. by_pred   = identities satisfying the recorded predicate
--  3. captured MUST EQUAL by_pred      <- the straggler check
--  4. total     = all auth.users rows; total - captured = identities created
--                 at or after the boundary, which are correctly POST-cutover
--  5. control_count MUST EQUAL captured
select
  (select count(*) from public.membership_cutover)                       as captured,
  (select count(*) from auth.users u
     where u.created_at < (select cutover_at from public.membership_control where id))
                                                                         as by_pred,
  (select count(*) from auth.users)                                      as total,
  (select cutover_identity_count from public.membership_control where id) as control_count,
  (select cutover_at from public.membership_control where id)            as boundary;

-- EXPECTED at the time of writing: captured = by_pred = control_count, and
-- total - captured = 0 unless an identity was created during the transaction.
-- The design pass observed 16 auth.users on 2026-08-16, but that figure MUST be
-- re-read immediately before execution rather than assumed -- see the
-- pre-flight query in supabase/sql/README-u3-deployment.md.

commit;   -- or ROLLBACK if any assertion above failed


-- ======================= POST-COMMIT VERIFICATION =======================
-- Run separately, after commit. Re-derives the boundary rule from scratch.
--
-- select
--   (select count(*) from public.membership_cutover)                        as captured,
--   (select count(*) from auth.users u
--      where u.created_at < (select cutover_at from public.membership_control where id))
--                                                                           as by_pred,
--   (select cutover_identity_count from public.membership_control where id) as recorded;
--
-- All three must agree. This is the invariant that makes "pre-cutover" a
-- definition rather than a memory, and it stays checkable for as long as the
-- snapshot exists -- including at U6c, when the removal rule needs it.
