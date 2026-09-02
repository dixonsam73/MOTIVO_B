-- Phase 3 U7c — THE NON-MUTATING PREVIEW PATH.
--
-- RATIFIED DECISION: a dry run must not mutate and must not acquire a claim.
-- The lease exists to protect concurrent DESTRUCTIVE EXECUTION, not observation.
--
-- WHY THIS EXISTS AT ALL, recorded because the defect it prevents is invisible
-- at the moment it bites. U7b's selector claims a lease as a side effect of
-- being called. A dry run implemented as "run the pipeline, skip the deletions"
-- would therefore claim every identity it previewed and hold it for an hour --
-- so an operator who previews, reads the output, and authorises an execute would
-- find the execute RETURNS NOTHING, because their own preview still holds the
-- claims. It looks exactly like "there was nothing to do", which is the most
-- dangerous available misreading, and it lands precisely at U7d's P4->P5
-- authorisation point.
--
-- The rejected alternative was a dry run that claims and then releases. It was
-- rejected for creating mutation and concurrency semantics at the preview stage
-- for no gain: a preview holds nothing worth protecting, because it destroys
-- nothing.
--
-- ONE ELIGIBILITY DEFINITION, TWO BEHAVIOURS. Both paths derive their candidate
-- set from membership_cleanup_eligible_v1 below, so preview and execute cannot
-- silently disagree about who is eligible. What differs is only whether a claim
-- is taken.


-- ============================================================== the lease
--
-- ONE DEFINITION OF THE INTERVAL. It is consulted by the eligibility predicate
-- AND by the claiming UPDATE's re-check, and a constant duplicated across those
-- two is a drift vector of exactly the kind this migration exists to remove.
-- Granted to no role: it is an implementation detail of the two selectors, not
-- a surface.
create function public.membership_cleanup_lease_v1()
returns interval
language sql
immutable
as $$ select interval '1 hour' $$;

comment on function public.membership_cleanup_lease_v1() is
  'The cleanup claim lease. Long enough that a slow Apple read cannot lose its own claim mid-run, short enough that a crashed run recovers the same working day. Internal.';


-- ======================================================= THE eligibility rule
--
-- STABLE, AND THAT IS A STRUCTURAL GUARANTEE RATHER THAN A PROMISE. PostgreSQL
-- refuses a write inside a non-volatile function at runtime, so this path CANNOT
-- acquire a claim -- not merely "does not today". If someone later adds an
-- UPDATE here it fails at execution rather than quietly reintroducing the
-- preview-claims-then-execute-finds-nothing defect. Asserted on provolatile
-- rather than by reading the body, because reading a body is how that guarantee
-- would be lost.
--
-- RETURNS EVERY MEMBERSHIP ROW OF EACH ELIGIBLE IDENTITY, unchanged from U7b and
-- for the same reason: the authority decision is identity-scoped, so a worker
-- that refreshes exactly what it was handed is automatically correct.
create function public.membership_cleanup_eligible_v1(p_limit integer default 25)
returns table (
  user_id                 uuid,
  environment             text,
  original_transaction_id text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_limit is null or p_limit < 1 then
    raise exception 'membership_cleanup_eligible_v1: p_limit must be >= 1'
      using errcode = '22004';
  end if;

  return query
  with eligible as (
    -- GROUP BY, not DISTINCT: the limit counts IDENTITIES, and ordering by the
    -- identity's earliest due row makes "oldest first" mean the same thing for a
    -- one-row and a two-row identity.
    select m.user_id as uid
      from public.membership m
     where m.pending_cleanup_at is not null
       and m.pending_cleanup_at <= now()
       and (m.cleanup_claimed_at is null
            or m.cleanup_claimed_at < now() - public.membership_cleanup_lease_v1())
     group by m.user_id
     order by min(m.pending_cleanup_at) asc
     limit p_limit
  )
  select m.user_id, m.environment, m.original_transaction_id
    from public.membership m
   where m.user_id in (select e.uid from eligible e)
   order by m.user_id, m.environment;
end
$$;

comment on function public.membership_cleanup_eligible_v1(integer) is
  'THE cleanup eligibility definition, and the non-mutating preview path. STABLE, so it structurally cannot claim. Both preview and execute derive their candidate set from this function so the two cannot drift. Selection is not authority.';


-- ================================================ the claiming path, rebuilt
--
-- REPLACED so that it no longer carries its own copy of the eligibility rule.
-- Behaviour is unchanged: same candidates, same claim, same returned shape. What
-- changes is that "eligible" is now defined in exactly one place.
--
-- THE CLAIMING UPDATE KEEPS ITS OWN LEASE PREDICATE, and that is NOT a second
-- definition of eligibility -- it is the EvalPlanQual re-check, and its purpose
-- is concurrency rather than selection. Two selectors can compute the same
-- candidate set because both read before either writes; the loser blocks on this
-- statement's row lock, and on resuming READ COMMITTED re-evaluates this WHERE
-- against the UPDATED row, sees the fresh claim and takes nothing. Without it
-- the loser would re-check only membership of the candidate set, still true, and
-- both runs would claim the same identity.
create or replace function public.membership_due_for_cleanup_v1(p_limit integer default 25)
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
begin
  -- Validation lives in the eligibility definition, so both paths refuse the
  -- same arguments. Calling it here is what makes that true rather than parallel.
  return query
  with candidate as (
    select distinct e.user_id as uid
      from public.membership_cleanup_eligible_v1(p_limit) e
  ),
  claimed as (
    update public.membership m
       set cleanup_claimed_at = now()
      from candidate c
     where m.user_id = c.uid
       and m.pending_cleanup_at is not null
       and m.pending_cleanup_at <= now()
       and (m.cleanup_claimed_at is null
            or m.cleanup_claimed_at < now() - public.membership_cleanup_lease_v1())
    returning m.user_id as uid
  )
  select m.user_id, m.environment, m.original_transaction_id
    from public.membership m
   where m.user_id in (select c.uid from claimed c)
   order by m.user_id, m.environment;
end
$$;

comment on function public.membership_due_for_cleanup_v1(integer) is
  'Cleanup EXECUTE selector. Derives its candidates from membership_cleanup_eligible_v1 -- the single eligibility definition -- then claims the lease. Returns every membership row of each claimed identity. Selection is not authority. Server-internal.';


-- ==================================================================== security
--
-- membership_cleanup_eligible_v1 is granted to service_role because the worker
-- calls it for dry run. membership_cleanup_lease_v1 is granted to NOBODY: it is
-- an implementation detail shared by the two selectors, and a caller has no
-- business asking how long the lease is.
revoke execute on function public.membership_cleanup_eligible_v1(integer) from public, anon, authenticated, service_role;
revoke execute on function public.membership_cleanup_lease_v1()           from public, anon, authenticated, service_role;

grant execute on function public.membership_cleanup_eligible_v1(integer) to service_role;


-- ========================================================== THE AUTHORITY GATE
--
-- ADDED DURING U7c IMPLEMENTATION, FROM A MEASURED FAILURE RATHER THAN A DESIGN
-- REVIEW. The worker's first executable version aborted every identity with
-- "permission denied for function connected_member", and that was CORRECT
-- behaviour by U3/U5b: connected_member(uuid) is ungranted to EVERY role,
-- service_role included, which is B-33's resolution -- the membership oracle is
-- structurally unbuildable, so no role can ask "is this arbitrary user a member".
--
-- A SECOND VIOLATION WAS HIDING BEHIND THE FIRST, and it is the C-54 shape
-- exactly: the worker also re-read public.membership directly to confirm a
-- schedule was still due, and service_role holds ZERO table privilege on all six
-- membership tables. That call never ran, because the first one failed before
-- it. Measured, not reasoned: has_function_privilege(service_role,
-- connected_member) = false AND has_table_privilege(service_role, membership,
-- select) = false.
--
-- THE WRONG FIX WOULD HAVE BEEN TO GRANT connected_member TO service_role. It
-- would have worked, and it would have dismantled B-33 to save one function.
--
-- WHAT THIS DOES INSTEAD IS ALSO BETTER THAN THE CODE IT REPLACES. The worker
-- previously asked two questions over two round trips and composed the AND
-- itself -- so the authority decision lived in the caller, where it could be got
-- half right. Here the DATABASE decides, in one statement, on one snapshot, and
-- hands back a reason. The worker cannot compose a partial authority because it
-- is never given the parts.
--
-- SELECTION IS NOT AUTHORITY, AND THIS IS THE AUTHORITY HALF. It must be called
-- only AFTER a fresh authoritative Apple read has been applied through the
-- canonical writer -- it reads the refreshed row and has no way to know whether
-- the refresh happened. That ordering is the worker's obligation and is asserted
-- there, not here.
create function public.membership_cleanup_authorised_v1(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member boolean;
  v_due    boolean;
begin
  if p_user_id is null then
    raise exception 'membership_cleanup_authorised_v1: no user_id' using errcode = '22004';
  end if;

  -- The SAME predicate the API enforces with. Not a second expression of
  -- membership: if these ever disagreed, the server would be destroying content
  -- belonging to someone it is simultaneously serving.
  v_member := public.connected_member(p_user_id);

  select exists (
    select 1 from public.membership m
     where m.user_id = p_user_id
       and m.pending_cleanup_at is not null
       and m.pending_cleanup_at <= now())
    into v_due;

  return jsonb_build_object(
    'authorised', (not v_member) and v_due,
    'connected_member', v_member,
    'still_due', v_due,
    'reason', case
      when v_member then 'connected_member() is true after refresh'
      when not v_due then 'no schedule remains due after refresh'
      else 'not entitled and a schedule is due'
    end);
end
$$;

comment on function public.membership_cleanup_authorised_v1(uuid) is
  'THE authority gate for irreversible expiry cleanup. Decides in ONE statement whether an identity may be cleaned: not connected_member() AND a schedule still due. Keeps connected_member(uuid) ungranted (B-33) while giving the worker exactly the one decision it needs. Must be called only AFTER a fresh Apple read has been applied.';

revoke execute on function public.membership_cleanup_authorised_v1(uuid) from public, anon, authenticated, service_role;
grant  execute on function public.membership_cleanup_authorised_v1(uuid) to service_role;
