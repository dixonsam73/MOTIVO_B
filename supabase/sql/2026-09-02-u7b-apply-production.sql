-- U7d P1 — APPLY U7b TO PRODUCTION. ONE TRANSACTION.
--
-- HOW TO RUN: paste this ENTIRE file into the Supabase SQL editor and run it
-- once. Do NOT run `supabase db push` (it would replay the local baseline
-- reproduction) and do NOT split it across Run clicks (Studio gives no session
-- continuity between them, so a split BEGIN/COMMIT reads exactly like success).
--
-- A SUCCESS MESSAGE IS NOT EVIDENCE THAT THE INTENDED TEXT RAN. The U6a apply
-- answered "Success. No rows returned." and changed nothing at all. That is why
-- this file GUARDS ITS OWN RESULT INSIDE THE TRANSACTION and ends in a SELECT
-- that returns a row: "no rows returned" is now the symptom rather than the
-- disguise. If the guard raises, the whole transaction rolls back and NOTHING
-- is applied.
--
-- THIS FILE DELETES NOTHING and touches no user data. It adds two columns, two
-- functions and two grants, and replaces one function body.

begin;

-- Phase 3 U7b — CLEANUP PRIMITIVE AND THE BORN-LAPSED CORRECTION.
--
-- DELETES NOTHING, AND THAT IS STRUCTURAL RATHER THAN A SETTING. There is no
-- `delete` statement anywhere in this migration, no storage call is reachable
-- from SQL, and the worker that will perform deletions does not exist. Nothing
-- here needs a kill switch because nothing here can destroy anything: the gap
-- between deploying this file and any irreversible act is an Edge Function that
-- has not been written, invoked by a credential nobody has presented.
--
-- TWO HALVES, DELIBERATELY SCORED APART. They share a migration because both
-- are SQL-only, mutually independent, and a production SQL submission is the
-- most dangerous routine act in this project -- the U6a apply reported
-- "Success. No rows returned." and changed nothing at all. Halving the number of
-- submissions is a real safety gain. What is NOT shared is the evidence: two
-- acceptance suites, two tallies, two exit codes, disjoint fixtures, and a
-- structural prediction itemised per half, so neither can hide a failure in the
-- other.
--
--   HALF A  the cleanup primitive  -- two columns, two functions, two grants
--   HALF B  the born-lapsed floor  -- one modified function, nothing else
--
-- SELECTION IS NOT AUTHORITY, AND THIS FILE ONLY BUILDS SELECTION. The selector
-- below answers "which identities are worth asking Apple about". It does NOT
-- answer "may this identity's content be destroyed" -- that is a live
-- authoritative Apple read followed by connected_member(), performed by U7c
-- immediately before any irreversible act. A future reader must not mistake a
-- returned row for permission.


-- =========================================================== HALF A, columns
--
-- cleanup_completed_at: WHY A SECOND COLUMN RATHER THAN CLEARING THE FIRST.
-- Clearing pending_cleanup_at alone is necessary -- otherwise a cleaned-up
-- identity is selected forever and cleanup re-runs on every pass -- but it is
-- not sufficient, because NULL would then mean two different things: "the member
-- resubscribed in time" and "cleanup ran". Those are QA C5 and QA C7, the two
-- cases the phase is required to tell apart, and one nullable column cannot.
--
-- membership_cleanup_requires_end permits pending_cleanup_at NULL alongside a
-- non-null entitlement_ended_at, so the clear is legal and no constraint moves.
alter table public.membership add column cleanup_completed_at timestamptz;

-- cleanup_claimed_at: THE LEASE.
--
-- CORRECTED BEFORE IMPLEMENTATION. The U7a scope first proposed
-- `for update skip locked` in the selector and called it concurrency control.
-- THAT IS WRONG ABOUT THE MECHANISM: a row lock lives for the duration of the
-- transaction that took it, and the selector's transaction commits before the
-- worker's Apple reads, deletions and completion happen. It would have protected
-- the milliseconds in which nothing dangerous occurs and nothing at all during
-- the minutes in which everything does -- a plausible-looking clause a reviewer
-- reads as protection that provides none.
--
-- The lease is DURABLE STATE instead, which is why it survives the transaction
-- that takes it. It is live from U7c, the worker's first executable version:
-- the moment a worker can be invoked at all, two invocations are possible.
-- U7e's scheduler raises the LIKELIHOOD of concurrency; it does not create the
-- requirement.
--
-- MINIMAL AND CRASH-RECOVERABLE, AND EXPLICITLY NOT A JOB SYSTEM. One timestamp,
-- one predicate, one interval. No queue, no registry, no heartbeat, no retry
-- counter, no state machine. A crashed run leaves a claim that expires on its
-- own and the identity becomes a candidate again -- that is the whole of the
-- recovery design, and anything more would be a system to maintain rather than a
-- guard to check.
alter table public.membership add column cleanup_claimed_at timestamptz;

comment on column public.membership.cleanup_completed_at is
  'Set by membership_cleanup_complete_v1 when expiry cleanup finished. Distinguishes "cleanup ran" (QA C7) from "resubscribed in time" (QA C5), which a null pending_cleanup_at alone cannot.';

comment on column public.membership.cleanup_claimed_at is
  'Expiring lease held by an in-flight cleanup run. Durable because a row lock would not survive the selector transaction. Expires after one hour so a crashed run recovers without intervention.';


-- ========================================================= HALF A, the selector
--
-- RETURNS EVERY MEMBERSHIP ROW OF EACH CANDIDATE IDENTITY, NOT ONLY THE DUE
-- ONES. This is the load-bearing shape of the whole unit and it is easy to get
-- wrong by writing the obvious thing.
--
-- membership is keyed (user_id, environment), so one identity may hold two rows.
-- connected_member() -- the predicate that AUTHORISES destruction -- reads all
-- of them. And expiry cleanup destroys IDENTITY-scoped material: posts, the
-- social graph, the avatar, the directory presence. There is one Connected
-- presence per identity, not one per environment.
--
-- So a worker that selects a candidate ROW, refreshes that ROW, and then
-- evaluates an identity-level predicate has computed its authority partly from
-- STALE STATE -- on exactly the half of the data it did not look at. The
-- concrete failure is a lapsed Sandbox row causing the destruction of a live
-- PRODUCTION member's content.
--
-- Returning the whole identity makes the rule STRUCTURAL rather than a
-- convention the worker is trusted to follow: a worker that refreshes precisely
-- what it was handed is automatically correct, and one that refreshes less has
-- to actively discard rows it was given.
--
-- RETURNS NO APPLE STATE AND NO SCHEDULING STATE -- three columns, exactly what
-- the caller needs to perform the reads. This is the narrowing U4's own grant
-- audit applied to membership_due_for_reconciliation_v1, for the same reason: a
-- scheduling column has no business leaving the database on a path with no use
-- for it, and a caller that cannot see the schedule cannot be tempted to treat
-- it as permission.
--
-- p_limit BOUNDS IDENTITIES, NOT ROWS. A limit that counted rows would hand out
-- partial identities, and a partial identity is precisely the stale-authority
-- defect above arriving by a different route.
create function public.membership_due_for_cleanup_v1(p_limit integer default 25)
returns table (
  user_id                 uuid,
  environment             text,
  original_transaction_id text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  -- One hour. Long enough that a slow Apple read cannot lose its own claim
  -- mid-run, short enough that a crashed run recovers the same working day.
  c_lease constant interval := interval '1 hour';
begin
  if p_limit is null or p_limit < 1 then
    raise exception 'membership_due_for_cleanup_v1: p_limit must be >= 1'
      using errcode = '22004';
  end if;

  return query
  with candidate as (
    -- GROUP BY, not DISTINCT: the limit must count identities, and ordering by
    -- the identity's EARLIEST due row is what makes "oldest first" mean the same
    -- thing for a one-row and a two-row identity.
    select m.user_id as uid
      from public.membership m
     where m.pending_cleanup_at is not null
       and m.pending_cleanup_at <= now()
       and (m.cleanup_claimed_at is null or m.cleanup_claimed_at < now() - c_lease)
     group by m.user_id
     order by min(m.pending_cleanup_at) asc
     limit p_limit
  ),
  claimed as (
    -- THE LEASE PREDICATE IS REPEATED HERE AND THAT REPETITION IS THE RACE FIX,
    -- not redundancy. Two selectors running concurrently can both compute the
    -- same candidate set, because both read before either writes. The loser
    -- blocks on the row lock this UPDATE takes; when it resumes, READ COMMITTED
    -- re-evaluates this WHERE against the UPDATED row, finds cleanup_claimed_at
    -- freshly set, and claims nothing. Without the repeated predicate the loser
    -- would re-check only `uid in (...)`, which is still true, and both runs
    -- would claim the same identity.
    --
    -- Claimed on DUE rows only. A live Production row sitting alongside a due
    -- Sandbox row is returned to the caller but never claimed -- it is context
    -- for the authority decision, not work.
    update public.membership m
       set cleanup_claimed_at = now()
      from candidate c
     where m.user_id = c.uid
       and m.pending_cleanup_at is not null
       and m.pending_cleanup_at <= now()
       and (m.cleanup_claimed_at is null or m.cleanup_claimed_at < now() - c_lease)
    returning m.user_id as uid
  )
  select m.user_id, m.environment, m.original_transaction_id
    from public.membership m
   where m.user_id in (select c.uid from claimed c)
   order by m.user_id, m.environment;
end
$$;

comment on function public.membership_due_for_cleanup_v1(integer) is
  'Cleanup CANDIDATE selector. Claims an expiring lease and returns EVERY membership row of each candidate identity. Selection is not authority: the live Apple read and connected_member() decide. Server-internal.';


-- ======================================================= HALF A, the completion
--
-- Written LAST by the worker, and only after every destructive step succeeded.
-- Until it lands the identity stays a candidate, so an interrupted run resumes
-- rather than being silently forgotten.
--
-- IDEMPOTENT BY PREDICATE, NOT BY A FLAG. The `pending_cleanup_at is not null`
-- clause means a second call matches nothing and reports 'noop' -- which is QA
-- C8 (a replayed expiry notification is a no-op) expressed one level down, and
-- it keeps cleanup_completed_at from being overwritten by a repeat.
--
-- CLEARS EVERY SCHEDULED ROW OF THE IDENTITY, because cleanup destroyed
-- identity-scoped content. Leaving a second environment's schedule standing
-- would re-select the identity and run a second cleanup over content that is
-- already gone.
--
-- IT TOUCHES NO APPLE STATE. renewal_date, entitlement_ended_at, apple_status,
-- binding_method, bound_at and original_transaction_id are all absent from this
-- statement. Cleanup records what ETUDES did; it never edits what Apple said.
create function public.membership_cleanup_complete_v1(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if p_user_id is null then
    raise exception 'membership_cleanup_complete_v1: no user_id' using errcode = '22004';
  end if;

  update public.membership m
     set pending_cleanup_at   = null,
         cleanup_claimed_at   = null,
         cleanup_completed_at = now(),
         updated_at           = now()
   where m.user_id = p_user_id
     and m.pending_cleanup_at is not null;

  get diagnostics v_rows = row_count;

  return jsonb_build_object(
    'outcome', case when v_rows > 0 then 'completed' else 'noop' end,
    'rows', v_rows);
end
$$;

comment on function public.membership_cleanup_complete_v1(uuid) is
  'Records that expiry cleanup finished for an identity: clears the schedule and the lease, sets cleanup_completed_at. Idempotent -- a second call is a no-op. Never edits Apple state. Server-internal.';


-- ================================================== HALF B, the born-lapsed floor
--
-- ONE BLOCK IS ADDED AND NOTHING ELSE CHANGES. The body below is byte-identical
-- to the deployed U4 function except for the block marked "U7b", which is
-- asserted rather than promised (B-13).
--
-- It lives in the CANONICAL WRITER rather than in the worker, deliberately. The
-- worker cannot distinguish this case: its only durable evidence is
-- entitlement_ended_at, which for a born-lapsed row is genuinely long past and
-- passes every test the worker could apply. There is no smaller correct place.

create or replace function public.membership_apply_state_v1(
  p_user_id                 uuid,
  p_environment             text,
  p_original_transaction_id text,
  p_state                   jsonb,
  p_notification_uuid       uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  -- 60 DAYS IS A HARD CONSTANT AND PRODUCTION CANNOT SHORTEN IT. It is used
  -- ONCE, here, at scheduling; U7's worker afterwards reads only the stored
  -- timestamp. That separation is what lets the deadline behaviour be exercised
  -- with fixture rows instead of a config override or a clock.
  c_quarantine   constant interval := interval '60 days';

  v_signed       timestamptz := (p_state->>'renewal_info_signed_date')::timestamptz;
  v_renewal      timestamptz := nullif(p_state->>'renewal_date', '')::timestamptz;
  v_grace        timestamptz := nullif(p_state->>'grace_period_expires_date', '')::timestamptz;
  v_retry        boolean     := coalesce((p_state->>'is_in_billing_retry')::boolean, false);
  v_revoked      timestamptz := nullif(p_state->>'revocation_date', '')::timestamptz;
  v_product      text        := nullif(p_state->>'product_id', '');
  v_entitled     boolean;
  v_prev         public.membership%rowtype;
  v_ended        timestamptz;
  v_cleanup      timestamptz;
begin
  -- HARD PRECONDITIONS, restated here even though most are also constraints.
  -- This is the only function that may schedule cleanup, so a caller that
  -- reached it with incomplete or unmapped state is a DEFECT and must stop
  -- rather than write. Every one of these is unreachable from the entry points
  -- below, which is the point: if one ever fires, the bug is upstream.
  if p_user_id is null then
    raise exception 'membership_apply_state_v1: no user_id' using errcode = '22004';
  end if;
  if v_signed is null then
    raise exception 'membership_apply_state_v1: no renewal_info_signed_date' using errcode = '22004';
  end if;
  if v_product is null then
    raise exception 'membership_apply_state_v1: no product_id' using errcode = '22004';
  end if;
  if p_original_transaction_id is null then
    raise exception 'membership_apply_state_v1: no original_transaction_id' using errcode = '22004';
  end if;
  -- OWNERSHIP IS A PRECONDITION OF WRITING, not a property checked afterwards.
  if not exists (select 1 from public.membership_binding b where b.user_id = p_user_id) then
    raise exception 'membership_apply_state_v1: no live binding for %', p_user_id
      using errcode = '23514';
  end if;

  select * into v_prev
    from public.membership m
   where m.user_id = p_user_id and m.environment = p_environment;

  -- NO ROW MEANS NO AUTHORITY TO CREATE ONE. Returned as data, not raised: a
  -- mapped notification arriving before establishment is an ordinary thing to
  -- happen, not a fault, and it must be recorded rather than lost.
  if not found then
    return jsonb_build_object(
      'outcome', 'ignored',
      'needs_establishment', true,
      'reason', 'no authoritative membership row; ownership establishment belongs to U5');
  end if;

  -- Apple's own service formula, identical in meaning to connected_member()'s
  -- per-row expression and to Transaction.currentEntitlements on device.
  -- isInBillingRetryPeriod alone does NOT entitle.
  v_entitled := coalesce(v_renewal > now(), false)
             or coalesce(v_retry and v_grace > now(), false);

  if v_entitled then
    -- Resubscription, refund reversal or grace recovery CANCELS pending cleanup.
    -- QA C5 / G6c.
    v_ended   := null;
    v_cleanup := null;
  else
    -- The instant entitlement actually ended, preferring Apple's own dates over
    -- our clock so the 60 days is measured from the truth rather than from when
    -- we happened to hear about it. GREATEST ignores NULLs unless all are NULL.
    v_ended := coalesce(v_revoked, greatest(v_renewal, v_grace), now());
    -- Never slide an already-recorded end forward: that would silently extend
    -- quarantine every time a later notification arrived.
    if v_prev.entitlement_ended_at is not null then
      v_ended := least(v_prev.entitlement_ended_at, v_ended);
    end if;
    v_cleanup := v_ended + c_quarantine;

    -- U7b. THE QUARANTINE IS NEVER RETROACTIVELY SPENT.
    --
    -- THE BORN-LAPSED CASE, left explicitly open by U5b and closed here. A row
    -- established while Apple already reported not-entitled carries no schedule
    -- (F11: membership_establish_v1 writes NULL to both columns on every insert
    -- path, unconditionally). The FIRST transition observed afterwards computes
    -- v_ended from Apple's own dates -- and for a subscription that lapsed eight
    -- months ago that is eight months in the past, so v_ended + 60 days lands
    -- SIX MONTHS AGO and the schedule is due the instant it is written.
    --
    -- The consequence is not theoretical and the timing is the worst available:
    -- the identity in this state is the dormant pre-cutover subscriber U5 exists
    -- to rescue, who is holding the app open right now, being denied by
    -- enforcement, and is therefore the person most likely to resubscribe within
    -- minutes. Quarantine exists so that resubscribing restores their presence
    -- whole. A deadline already past gives them none of it.
    --
    -- entitlement_ended_at IS NOT TOUCHED and remains Apple's own truth. Only
    -- the SCHEDULE is floored, so no fact is falsified -- the row still records
    -- exactly when entitlement ended.
    --
    -- THE GUARD IS `v_prev.pending_cleanup_at is null`, WHICH IS WHAT KEEPS THIS
    -- FROM BECOMING A SLIDING DEADLINE. It fires only where no schedule existed;
    -- an already-recorded schedule is never pushed out, so the anti-sliding rule
    -- immediately above survives intact. On an ordinary lapse v_ended is
    -- approximately now(), v_cleanup is sixty days in the future, and the second
    -- condition CANNOT be true -- which is asserted in both directions rather
    -- than assumed, because a guard that never fires and a guard that always
    -- fires are both defects and only one of them is visible.
    if v_prev.pending_cleanup_at is null and v_cleanup <= now() then
      v_cleanup := now() + c_quarantine;
    end if;
  end if;

  -- ORDERING IS ENFORCED IN THE STATEMENT, NOT IN THE CALLER. The predicate makes
  -- an out-of-order delivery a no-op by construction, so two concurrent
  -- notifications cannot interleave into a lost update. No updated row is
  -- 'stale', not an error.
  --
  -- The key is renewalInfo's OWN signedDate, never the notification's: a
  -- notification signed later can carry renewal info signed earlier.
  --
  -- binding_method and bound_at are ABSENT from this statement, and their absence
  -- is the correction. Ownership is established once, by U5; rebinding is a
  -- security and account-recovery event for explicit operator disposition, never
  -- ordinary application logic (B-24).
  update public.membership m
     set original_transaction_id   = p_original_transaction_id,
         product_id                = v_product,
         apple_status              = (p_state->>'apple_status')::smallint,
         renewal_date              = v_renewal,
         grace_period_expires_date = v_grace,
         is_in_billing_retry       = v_retry,
         auto_renew_status         = (p_state->>'auto_renew_status')::smallint,
         expiration_intent         = (p_state->>'expiration_intent')::smallint,
         revocation_date           = v_revoked,
         renewal_info_signed_date  = v_signed,
         last_notification_uuid    = coalesce(p_notification_uuid, m.last_notification_uuid),
         entitlement_ended_at      = v_ended,
         pending_cleanup_at        = v_cleanup,
         updated_at                = now()
   where m.user_id = p_user_id
     and m.environment = p_environment
     and v_signed > m.renewal_info_signed_date;

  if not found then
    return jsonb_build_object(
      'outcome', 'stale',
      'entitled', v_entitled,
      'reason', 'renewal_info_signed_date not newer than the stored row');
  end if;

  return jsonb_build_object(
    'outcome', 'applied',
    'entitled', v_entitled,
    'entitlement_ended_at', v_ended,
    'pending_cleanup_at', v_cleanup);
end
$$;
comment on function public.membership_apply_state_v1(uuid, text, text, jsonb, uuid) is
  'THE canonical membership writer. UPDATE-ONLY: refreshes an authoritative row, never originates one. U7b added the born-lapsed quarantine floor: a FIRST schedule is never written already-past. Internal; granted to no role.';


-- ==================================================================== security
--
-- Same posture as U3, U4 and U5b, by the same construction: revoke from all
-- four, then grant back exactly what is needed, so the end state is a property
-- of this file rather than of whichever pg_default_acl entry applies.
--
-- THE ENTIRE U7b PRIVILEGE DELTA IS THESE TWO EXECUTE GRANTS. anon,
-- authenticated and PUBLIC gain nothing; no role gains any table or column
-- privilege on any membership table; service_role still holds ZERO table
-- privilege on all six. Both grants go to service_role because both are called
-- by an Edge Function, on either side of the HTTPS round trip to Apple -- which
-- must never sit inside a transaction (B-30), and which is exactly why selection
-- and completion are two functions rather than one.
--
-- membership_apply_state_v1 IS NOT GRANTED AND MUST NOT BE. It is reached only
-- through the ingestion and reconciliation entry points, so its ownership
-- precondition and its atomicity cannot be bypassed. U7b does not change that.
revoke execute on function public.membership_due_for_cleanup_v1(integer) from public, anon, authenticated, service_role;
revoke execute on function public.membership_cleanup_complete_v1(uuid)   from public, anon, authenticated, service_role;

grant execute on function public.membership_due_for_cleanup_v1(integer) to service_role;
grant execute on function public.membership_cleanup_complete_v1(uuid)   to service_role;


-- ===================== GUARD: assert the state this transaction just produced
do $$
declare n int;
begin
  select count(*) into n from information_schema.columns
   where table_schema='public' and table_name='membership'
     and column_name in ('cleanup_completed_at','cleanup_claimed_at');
  if n <> 2 then raise exception 'U7b guard: expected 2 new columns, found %', n; end if;

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public'
     and p.proname in ('membership_due_for_cleanup_v1','membership_cleanup_complete_v1');
  if n <> 2 then raise exception 'U7b guard: expected 2 new functions, found %', n; end if;

  if not has_function_privilege('service_role','public.membership_due_for_cleanup_v1(integer)','execute')
  or not has_function_privilege('service_role','public.membership_cleanup_complete_v1(uuid)','execute')
  then raise exception 'U7b guard: service_role cannot execute the new functions'; end if;

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   cross join (values ('anon'),('authenticated')) r(role)
   where ns.nspname='public'
     and p.proname in ('membership_due_for_cleanup_v1','membership_cleanup_complete_v1')
     and has_function_privilege(r.role, p.oid, 'execute');
  if n <> 0 then raise exception 'U7b guard: a client role can execute a cleanup function'; end if;

  -- The born-lapsed floor is present in the DEPLOYED definition, not merely in
  -- the file that claims to have installed it.
  if (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.proname='membership_apply_state_v1'
         and pg_get_functiondef(p.oid) ~ 'QUARANTINE IS NEVER RETROACTIVELY SPENT') <> 1
  then raise exception 'U7b guard: the born-lapsed floor is not in the deployed writer'; end if;

  -- NOTHING IN THIS FILE MAY TOUCH USER DATA. Asserted, not assumed.
  if (select count(*) from public.membership) <> 1 then
    raise exception 'U7b guard: membership row count changed'; end if;
  if (select pending_cleanup_at from public.membership)
     <> timestamptz '2026-11-01 15:16:44+00' then
    raise exception 'U7b guard: pending_cleanup_at was altered by the deploy'; end if;
  if (select count(*) from public.posts) <> 101 then
    raise exception 'U7b guard: posts count changed'; end if;
end $$;

-- ============ FINAL SELECT — this MUST return exactly one row, or nothing ran
select 'U7b APPLIED' as result,
       (select count(*) from information_schema.columns
         where table_schema='public' and table_name='membership'
           and column_name in ('cleanup_completed_at','cleanup_claimed_at')) as new_columns,
       (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
         where ns.nspname='public'
           and p.proname in ('membership_due_for_cleanup_v1','membership_cleanup_complete_v1')) as new_functions,
       (select pending_cleanup_at from public.membership) as schedule_untouched,
       now() as applied_at;

commit;
