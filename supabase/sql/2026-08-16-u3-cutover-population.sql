-- Phase 3 U3 — PRODUCTION CUTOVER POPULATION.
--
-- NOT YET EXECUTED. Prepared for separate review and explicit authorisation.
--
-- Step A of the U3 deployment is the structural DDL
-- (supabase/migrations/20260816120000_u3_membership_schema.sql, applied by hand
-- to production as a reviewed diff; production is not on the migration history
-- and is deliberately not re-based). This file is step B. Run step A first,
-- verify the structural delta, then run this.
--
--
-- ================== WHY THIS IS NOT A SERIALIZABLE TRANSACTION ==============
--
-- An earlier draft used SERIALIZABLE and claimed it closed the concurrent-
-- identity race. IT DOES NOT, and the reason matters more than the correction.
--
-- The schedule of concern: this transaction fixes a boundary T; a GoTrue
-- transaction inserts an auth.users row whose created_at < T; that transaction
-- commits AFTER this one's snapshot; this one therefore never sees it.
--
-- PostgreSQL's SSI aborts on a DANGEROUS STRUCTURE -- two consecutive
-- read-write anti-dependency edges through a pivot. Here there is exactly one
-- edge: we read a predicate on auth.users (SIReadLock), GoTrue inserts a
-- matching row, giving rw-conflict us -> GoTrue. GoTrue never reads
-- membership_cutover or membership_control, so there is NO edge back. One edge
-- is not a cycle, so there is no serialization failure.
--
-- And SSI is RIGHT to allow it: the execution IS serializable, equivalent to
-- the order (this transaction, then GoTrue's). Serializability guarantees
-- equivalence to SOME serial order; it does not guarantee that a transaction
-- saw everything that would later be true. The business predicate is violated
-- by application data -- created_at is a column value with no relationship to
-- commit order -- not by a concurrency anomaly. NO isolation level fixes that.
--
-- So SERIALIZABLE bought nothing here except the possibility of a 40001 retry.
-- READ COMMITTED is used, and completeness is established AFTER commit, by a
-- fresh snapshot that can actually see the raced transaction.
--
--
-- ============== WHY RE-RUNNING THE POPULATION IS NOT AN APPEND ==============
--
-- The set is determined the moment cutover_at is committed:
--     pre-cutover = { u in auth.users : u.created_at < cutover_at }
-- The INSERT is an ATTEMPT TO MATERIALISE that set, not the definition of it.
--
-- The population statement is predicate-limited and idempotent, so it can only
-- ever insert rows satisfying that frozen predicate. A post-cutover identity
-- fails the WHERE clause permanently, because cutover_at never changes.
-- Re-running therefore COMPLETES the materialisation; it cannot expand the set.
--
-- The invariant that matters is "no post-cutover identity ever enters", which
-- the predicate enforces by construction -- not "the statement runs exactly
-- once", which protects nothing.


-- ############################################################################
-- PHASE 0 -- PRE-FLIGHT. Read-only. Run BEFORE declaring any boundary.
-- ############################################################################
--
-- Do not assume the design-pass figure of 16 identities still holds. Read it.
select
  (select count(*) from auth.users)                                  as auth_users,
  (select count(*) from auth.users where created_at is null)         as null_created_at,
  (select count(*) from public.membership_cutover)                   as cutover_rows,
  (select cutover_at          from public.membership_control where id) as cutover_at,
  (select cutover_verified_at from public.membership_control where id) as verified_at;

-- STOP unless ALL of:
--   null_created_at = 0   <-- see below. This is a HARD GATE.
--   cutover_rows    = 0
--   cutover_at      IS NULL
--   verified_at     IS NULL
--   auth_users        recorded, whatever it is
--
-- WHY null_created_at MUST BE ZERO. auth.users.created_at is NULLABLE with no
-- default, and the column belongs to GoTrue rather than to us. A NULL satisfies
-- NEITHER `< cutover_at` NOR `>= cutover_at`, so such an identity would be
-- excluded from the snapshot AND from every completeness check -- the counts
-- would agree while the identity was silently unclassifiable, and it would be
-- treated as post-cutover at U6b and denied. That is a worse failure shape than
-- the race, because it leaves no discrepancy to detect. If this is not zero,
-- STOP and establish why before defining any boundary.


-- ############################################################################
-- PHASE 1 -- BOUNDARY + POPULATION. One transaction, READ COMMITTED.
-- ############################################################################

begin;

-- Re-run guard. If cutover_at is already set this updates nothing and the
-- coherence assertion below fails, so the transaction is rolled back.
update public.membership_control
   set cutover_at = now(),
       updated_at = now(),
       notes      = 'U3 cutover. pre-cutover = auth.users.created_at < cutover_at.'
 where id
   and cutover_at is null;

-- Predicate-limited population. One statement, so partial capture within this
-- transaction is impossible. Reads cutover_at from the COLUMN, not now(), so
-- the boundary is a single durable value rather than several close timestamps.
insert into public.membership_cutover (user_id)
select u.id
  from auth.users u
 where u.created_at < (select cutover_at from public.membership_control where id)
    on conflict (user_id) do nothing;

-- cutover_identity_count is deliberately NOT set here. It is the VERIFIED
-- materialised count and belongs with phase 3; the schema enforces that by
-- tying it to cutover_verified_at rather than to cutover_at.

-- ---------------------------------------------------------------------------
-- IN-TRANSACTION ASSERTIONS -- COHERENCE AND RE-RUN PROTECTION ONLY.
--
-- THESE DO NOT DETECT STRAGGLERS, and must not be described as if they do.
-- They run on this transaction's own snapshot, which is the same snapshot the
-- INSERT read, so `captured` and `by_pred` are derived from an identical
-- visible set and agree BY CONSTRUCTION whether or not a raced identity exists.
-- Completeness is established in phase 2, on a fresh snapshot.
--
-- What these DO establish:
--   boundary_declared  the guard fired and a boundary now exists
--   count_still_unset  the count is correctly absent until verification
--   captured           what this transaction materialised
--   total_now          identities visible to this snapshot, for the record
-- ---------------------------------------------------------------------------
select
  (select cutover_at is not null       from public.membership_control where id) as boundary_declared,
  (select cutover_identity_count is null from public.membership_control where id) as count_still_unset,
  (select count(*) from public.membership_cutover)                               as captured,
  (select count(*) from auth.users)                                              as total_now,
  (select cutover_at from public.membership_control where id)                    as boundary;

-- STOP and ROLLBACK unless: boundary_declared = true AND count_still_unset = true
-- AND captured > 0 (a zero capture on a populated production would itself be
-- unexpected and is worth stopping on).

commit;

-- ^ THE BOUNDARY IS NOW IRREVERSIBLE. cutover_at cannot be re-declared without
--   destroying the definition every later check depends on. Record it.


-- ############################################################################
-- PHASE 2 -- POST-COMMIT CONVERGENCE. MANDATORY. Bounded: at most one repair.
-- ############################################################################
--
-- Fresh transactions from here, so each check takes a NEW snapshot and can see
-- any identity that committed after phase 1's snapshot. This is the only place
-- the race is observable.

-- 2a. COMPLETENESS CHECK.
select
  (select count(*) from auth.users u
     where u.created_at < (select cutover_at from public.membership_control where id)
       and not exists (select 1 from public.membership_cutover c where c.user_id = u.id))
                                                                        as missing,
  (select count(*) from auth.users where created_at is null)            as null_created_at,
  (select count(*) from public.membership_cutover c
     join auth.users u on u.id = c.user_id
    where u.created_at is null
       or u.created_at >= (select cutover_at from public.membership_control where id))
                                                                        as invalid_members;

-- missing = 0 AND null_created_at = 0 AND invalid_members = 0  -> go to PHASE 3.
-- missing > 0                                                 -> run 2b ONCE.
-- invalid_members > 0                                         -> STOP. A
--     post-cutover identity is in the snapshot, which the predicate makes
--     impossible; something outside this procedure wrote to the table.
-- null_created_at > 0                                         -> STOP. An
--     identity is unclassifiable; do not finalise a snapshot around it.

-- 2b. REPAIR -- the SAME predicate-limited statement, run at most ONCE.
--     Not a "top-up": it is byte-identical to phase 1's population, so it can
--     only complete the already-frozen set.
insert into public.membership_cutover (user_id)
select u.id
  from auth.users u
 where u.created_at < (select cutover_at from public.membership_control where id)
    on conflict (user_id) do nothing;

-- 2c. RE-VERIFY -- fresh snapshot, same query as 2a.
select
  (select count(*) from auth.users u
     where u.created_at < (select cutover_at from public.membership_control where id)
       and not exists (select 1 from public.membership_cutover c where c.user_id = u.id))
                                                                        as missing,
  (select count(*) from auth.users where created_at is null)            as null_created_at,
  (select count(*) from public.membership_cutover c
     join auth.users u on u.id = c.user_id
    where u.created_at is null
       or u.created_at >= (select cutover_at from public.membership_control where id))
                                                                        as invalid_members;

-- ALL THREE MUST BE ZERO. If they are not, **STOP AND REPORT**. Do not repair
-- again and do not loop. One straggler is an explicable millisecond race; a
-- second round of divergence is unexplained by that model and is itself the
-- finding -- something is inserting identities with backdated created_at, or
-- the boundary is not being read consistently. Automating past that would hide
-- exactly the evidence needed to understand it.


-- ############################################################################
-- PHASE 3 -- FINALISE. Only after phase 2 converged with all three zero.
-- ############################################################################

begin;

update public.membership_control
   set cutover_identity_count = (select count(*) from public.membership_cutover),
       cutover_verified_at    = now(),
       updated_at             = now()
 where id
   and cutover_at is not null
   and cutover_verified_at is null;

-- Final record. All four must agree before commit.
select
  (select count(*) from public.membership_cutover)                        as materialised,
  (select count(*) from auth.users u
     where u.created_at < (select cutover_at from public.membership_control where id))
                                                                          as by_predicate,
  (select cutover_identity_count from public.membership_control where id) as recorded_count,
  (select cutover_verified_at    from public.membership_control where id) as verified_at;

-- STOP and ROLLBACK unless materialised = by_predicate = recorded_count
-- AND verified_at is not null.

commit;


-- ############################################################################
-- PERMANENT INVARIANT -- re-runnable at any time, forever.
-- ############################################################################
--
-- This is the check that matters for the life of the snapshot, and U6c's
-- removal rule leans on it. Both columns must always be zero.
--
-- select
--   (select count(*) from public.membership_cutover c
--      join auth.users u on u.id = c.user_id
--     where u.created_at is null
--        or u.created_at >= (select cutover_at from public.membership_control where id))
--                                                             as post_cutover_in_snapshot,
--   (select count(*) from auth.users u
--      where u.created_at < (select cutover_at from public.membership_control where id)
--        and not exists (select 1 from public.membership_cutover c where c.user_id = u.id))
--                                                             as qualifying_but_missing;
--
-- post_cutover_in_snapshot > 0 means a post-cutover identity entered the
-- snapshot, which the predicate makes impossible -- so it would mean something
-- wrote to the table outside this procedure.
--
-- qualifying_but_missing > 0 after cutover_verified_at is set means the
-- snapshot has diverged from its own frozen definition since verification.
-- Either is a stop-and-report, never a silent repair.
