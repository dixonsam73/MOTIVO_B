-- Phase 3 U5b — ownership establishment foundation, and environment separation.
--
-- LOCAL ONLY AT THIS POINT. Nothing here is deployed by this unit. U5b adds the
-- SQL that U5c's verifier and U5d's attest endpoint will write through; it
-- creates no Edge Function, makes no Apple request, schedules nothing, deletes
-- nothing, and changes no policy. The one client-reachable object it creates is
-- the pre-purchase binding token, which U3 built and deliberately left ungranted.
--
-- U5b IS NOT THE WHOLE OF U5, AND THE BOUNDARY IS DELIBERATE. It cannot perform
-- a legacy claim or an orphan rebind, because both require calling Apple's
-- Set App Account Token and re-reading Apple afterwards -- an HTTPS round trip
-- that must never happen inside a transaction (B-30). Those paths return
-- 'requires_claim' here and are completed in U5c/U5d. **A30 IS THEREFORE NOT
-- DISCHARGED BY THIS UNIT.** What is asserted here is only the SQL-side
-- precondition: that establishment REFUSES to proceed on a token Apple has not
-- yet confirmed as ours.


-- ================================================ D4: environment separation
--
-- PRODUCTION connected_member() MEANS PRODUCTION ENTITLEMENT ONLY. A Sandbox
-- membership row must never make the production membership predicate return
-- true, and there is no exception mechanism inside this function.
--
-- A per-identity allowlist that widened the predicate was proposed and REJECTED,
-- and the rejection is the point: even bounded and self-expiring, it would have
-- put a shippable exception inside the one function that defines paid access,
-- and B-24's whole lesson is that an authority predicate must not contain a
-- branch whose safety rests on operational discipline. Sandbox QA needs no
-- entitlement mechanism at all -- U5's claims are about ROWS, and nothing in U5
-- reads this function. The enforcement-path mechanism is deferred to U6b and
-- owned on B-11.
--
-- THE ENVIRONMENT TEST MOVES INTO bool_or, NOT INTO THE WHERE CLAUSE, AND THE
-- DIFFERENCE IS THE WHOLE CORRECTNESS ARGUMENT. Filtering in WHERE would empty
-- the row set for a Sandbox-only identity; bool_or over an empty set is NULL;
-- and NULL falls through to the grandfather clause -- so a pre-cutover tester
-- holding a live Sandbox subscription would have been granted PRODUCTION
-- entitlement by the compatibility clause. That is the exact inversion of
-- invariant 8, arrived at by the obvious fix.
--
-- So the row set that decides EXISTENCE stays wider than the row set that can
-- decide TRUE:
--
--   Sandbox-only     -> set non-empty, per-row FALSE -> bool_or FALSE -> no
--                       fall-through -> false. Authoritative state wins.
--   Production live  -> true.
--   Production lapsed-> false, no fall-through (unchanged).
--   No rows at all   -> NULL -> grandfather clause (unchanged).
--
-- U3'S coalesce LESSON SURVIVES AND IS STRENGTHENED. environment is NOT NULL and
-- `false AND anything` is FALSE in SQL, so the row-level expression is strictly
-- two-valued in every case -- bool_or is NULL if and only if there are no rows,
-- which is precisely the distinction the clause ordering depends on.
--
-- CREATE OR REPLACE PRESERVES THE EXISTING ACL. U3 revoked EXECUTE from all four
-- roles and granted nothing back on this function; that state is unchanged here
-- and is asserted rather than assumed.
create or replace function public.connected_member(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select bool_or(
         m.environment = 'Production'
         and (coalesce(m.renewal_date > now(), false)
              or coalesce(m.is_in_billing_retry
                          and m.grace_period_expires_date > now(), false))
       )
       from public.membership m
      where m.user_id = target_user_id),      -- NO environment filter here

    (select exists (
       select 1
         from public.membership_cutover c
         cross join public.membership_control k
        where c.user_id = target_user_id
          and k.grandfather_enabled
          and (k.grandfather_expires_at is null
               or now() < k.grandfather_expires_at))),

    false
  );
$$;

comment on function public.connected_member(uuid) is
  'Server-private entitlement predicate. PRODUCTION ENTITLEMENT ONLY -- a Sandbox row can never make this true, and never falls through to grandfathering.';


-- A FIFTH STATE, AND IT IS LOAD-BEARING RATHER THAN COSMETIC.
--
-- Under the semantics above a Sandbox-only identity would report 'expired',
-- which is false: it has not expired, it has no Production membership at all.
-- U6a's shadow window reads this function to report WHICH CLAUSE would have
-- decided a denial, so conflating "Sandbox-only tester" with "Production
-- subscription lapsed" would corrupt exactly the metric B-11's stage-2 gate
-- depends on -- and it is what keeps a tester's would-be denials out of the
-- evidence about real users.
--
-- 'grandfathered' becomes unreachable for any identity holding any row, which is
-- correct: clause 1 of connected_member() is non-NULL for those.
create or replace function public.membership_state(target_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from public.membership m
                  where m.user_id = target_user_id
                    and m.environment = 'Production')
      then case when public.connected_member(target_user_id)
                then 'entitled' else 'expired' end
    when exists (select 1 from public.membership m
                  where m.user_id = target_user_id)
      then 'sandbox_only'
    when public.connected_member(target_user_id) then 'grandfathered'
    else 'unknown'
  end;
$$;

comment on function public.membership_state(uuid) is
  'Server-internal diagnostic: entitled | expired | sandbox_only | grandfathered | unknown. Not client-readable.';


-- ======================================================= binding conflicts
--
-- B-24 requires that a mismatch against a LIVE binding be recorded for explicit
-- operator disposition -- grant nothing, change nothing, but do not discard the
-- observation. membership_notification is the wrong home for it: that table is
-- App Store Server Notification audit, and B-27 exists precisely because its
-- vocabulary was overloaded once already.
--
-- BOUNDED BY CONSTRUCTION, in the same shape as B-29's reject aggregate: the
-- primary key is (claimant, environment, subscription), so repeated attempts
-- increment a counter rather than growing the table. Unlike B-29's, this path is
-- AUTHENTICATED and additionally requires a signature-verified JWS upstream, so
-- the reachable key space is bounded by the transactions a caller can actually
-- prove possession of.
--
-- THE OWNING IDENTITY IS DELIBERATELY NOT STORED. It is derivable at disposition
-- time from membership by (environment, original_transaction_id), and deriving
-- beats storing: recording it here would duplicate the link and put the victim's
-- identifier in a row keyed by the claimant's.
create table public.membership_binding_conflict (
  user_id                 uuid        not null,
  environment             text        not null,
  original_transaction_id text        not null,
  conflict_kind           text        not null,
  observed_count          bigint      not null default 1,
  first_seen_at           timestamptz not null default now(),
  last_seen_at            timestamptz not null default now(),

  constraint membership_binding_conflict_pkey
    primary key (user_id, environment, original_transaction_id),
  constraint membership_binding_conflict_user_fk
    foreign key (user_id) references auth.users(id) on delete cascade,
  constraint membership_binding_conflict_environment_check
    check (environment in ('Sandbox', 'Production')),
  constraint membership_binding_conflict_kind_check
    check (conflict_kind in ('live_binding_mismatch',
                             'transaction_owned_by_other_identity')),
  constraint membership_binding_conflict_count_positive
    check (observed_count >= 1)
);

comment on table public.membership_binding_conflict is
  'B-24 security/account-recovery events: a claim refused because the subscription belongs to another live binding. Server-private, bounded, operator-dispositioned.';


-- ==================================================== establishment writer
--
-- THE ONLY FUNCTION IN THE SYSTEM THAT MAY INSERT INTO public.membership.
-- U4's canonical writer is UPDATE-only and says so structurally; this is its
-- counterpart, and the split is what makes "ownership is established once"
-- checkable rather than remembered.
--
-- PROVENANCE IS DERIVED FROM EVIDENCE, NEVER SUPPLIED BY THE CALLER. There is no
-- p_binding_method parameter, deliberately -- that was the exact defect corrected
-- in U4, one level down. The discriminator is which artefact carried our token:
--
--   the JWS itself carried it  -> the token was attached by StoreKit AT PURCHASE,
--                                 before we could have set it -> 'purchase'
--   Apple reports it but the
--   JWS did not carry it       -> we attached it via Set App Account Token
--                                 -> 'legacy_claim'
--
-- It runs at most once per (identity, environment), because binding_method and
-- bound_at are never rewritten afterwards by any path.
--
-- ESTABLISHMENT NEVER SCHEDULES CLEANUP, UNCONDITIONALLY (F11). Both
-- entitlement_ended_at and pending_cleanup_at are NULL on every insert path.
-- Scheduling is a TRANSITION from entitled to not-entitled, and an establishment
-- has no previous state to transition from -- the same reasoning as "absence of a
-- membership record can never schedule cleanup", one level down. Without this
-- rule U5, the unit explicitly free of enforcement and cleanup, becomes the unit
-- that can schedule destruction of a returning member's Connected content on
-- first contact, with a deadline that may already be in the past.
--
-- THE BORN-LAPSED CASE IS LEFT EXPLICITLY OPEN FOR U7 AND IS NOT SILENTLY
-- RESOLVED HERE. A row established while Apple reports not-entitled carries no
-- schedule; the first subsequent transition observed by the canonical writer will
-- compute one from Apple's own dates, which for a long-lapsed subscription can be
-- immediately due. That is U7's worker to reason about, and it is recorded rather
-- than patched here.
create function public.membership_establish_v1(
  p_user_id                 uuid,
  p_environment             text,
  p_original_transaction_id text,
  p_apple_token             uuid,
  p_jws_token               uuid,
  p_state                   jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_binding   uuid;
  v_owner     uuid;
  v_method    text;
  v_signed    timestamptz := (p_state->>'renewal_info_signed_date')::timestamptz;
  v_product   text        := nullif(p_state->>'product_id', '');
  v_renewal   timestamptz := nullif(p_state->>'renewal_date', '')::timestamptz;
  v_grace     timestamptz := nullif(p_state->>'grace_period_expires_date', '')::timestamptz;
  v_retry     boolean     := coalesce((p_state->>'is_in_billing_retry')::boolean, false);
  v_entitled  boolean;
  v_existing  text;
begin
  -- HARD PRECONDITIONS. Every one is unreachable from a correct caller; if one
  -- fires the defect is upstream, and stopping is better than writing.
  if p_user_id is null then
    raise exception 'membership_establish_v1: no user_id' using errcode = '22004';
  end if;
  if p_environment is null or p_environment not in ('Sandbox', 'Production') then
    raise exception 'membership_establish_v1: bad environment' using errcode = '22023';
  end if;
  if p_original_transaction_id is null then
    raise exception 'membership_establish_v1: no original_transaction_id' using errcode = '22004';
  end if;
  if v_signed is null then
    raise exception 'membership_establish_v1: no renewal_info_signed_date' using errcode = '22004';
  end if;
  if v_product is null then
    raise exception 'membership_establish_v1: no product_id' using errcode = '22004';
  end if;

  -- The caller must already hold a binding token. ensure_membership_binding()
  -- is idempotent and client-reachable, so this is the caller's own doing.
  select b.binding_token into v_binding
    from public.membership_binding b
   where b.user_id = p_user_id;
  if v_binding is null then
    raise exception 'membership_establish_v1: no binding for %', p_user_id
      using errcode = '23514';
  end if;

  -- ---------------------------------------------------------------- decide
  --
  -- RESOLUTION HAPPENS INSIDE THIS TRANSACTION, against the live binding table,
  -- and not in the caller. A decision taken before the network round trip and
  -- trusted afterwards is a TOCTOU race: a concurrent binding change between the
  -- Apple read and the write would otherwise be invisible.
  if p_apple_token is null then
    -- Apple reports no token. Binding it is a LEGACY CLAIM, which requires
    -- Set App Account Token plus an independent Apple re-read -- an HTTPS round
    -- trip that must never happen inside a transaction. U5c/U5d own it.
    return jsonb_build_object(
      'outcome', 'requires_claim',
      'reason', 'apple reports no appAccountToken; legacy claim belongs to U5c/U5d',
      'established', false);
  end if;

  v_owner := public.membership_resolve_binding_v1(p_apple_token);

  if v_owner is null then
    -- An ORPHAN token -- typically left by an explicit account deletion. A
    -- JWS-verified claimant may rebind, but rebinding also means calling
    -- Set App Account Token and re-reading. Same boundary as above.
    return jsonb_build_object(
      'outcome', 'requires_claim',
      'reason', 'apple token matches no live binding (orphan); rebind belongs to U5c/U5d',
      'established', false);
  end if;

  if v_owner <> p_user_id then
    -- A LIVE BINDING BELONGING TO SOMEBODY ELSE. Grant nothing, change nothing,
    -- and never call Set App Account Token -- Apple would let us overwrite it,
    -- which is precisely why our rule has to be the protection (B-24).
    insert into public.membership_binding_conflict as c (
        user_id, environment, original_transaction_id, conflict_kind)
    values (p_user_id, p_environment, p_original_transaction_id,
            'live_binding_mismatch')
    on conflict (user_id, environment, original_transaction_id) do update
       set observed_count = c.observed_count + 1,
           last_seen_at   = now();

    return jsonb_build_object(
      'outcome', 'conflict',
      'reason', 'appAccountToken belongs to another live binding',
      'established', false);
  end if;

  -- Apple reports OUR token. Provenance is decided by which artefact carried it.
  v_method := case when p_jws_token is not distinct from v_binding
                   then 'purchase' else 'legacy_claim' end;

  v_entitled := coalesce(v_renewal > now(), false)
             or coalesce(v_retry and v_grace > now(), false);

  -- ---------------------------------------------------------------- write
  begin
    insert into public.membership (
        user_id, environment, original_transaction_id, product_id,
        apple_status, renewal_date, grace_period_expires_date,
        is_in_billing_retry, auto_renew_status, expiration_intent,
        revocation_date, renewal_info_signed_date,
        binding_method, bound_at,
        entitlement_ended_at, pending_cleanup_at)
    values (
        p_user_id, p_environment, p_original_transaction_id, v_product,
        (p_state->>'apple_status')::smallint, v_renewal, v_grace,
        v_retry, (p_state->>'auto_renew_status')::smallint,
        (p_state->>'expiration_intent')::smallint,
        nullif(p_state->>'revocation_date', '')::timestamptz, v_signed,
        v_method, now(),
        -- F11. Both NULL, unconditionally, on every insert path.
        null, null)
    on conflict on constraint membership_pkey do nothing;
  exception
    when unique_violation then
      -- membership_transaction_unique: this subscription is already established
      -- to a DIFFERENT identity. Not a race to retry -- a conflict to record.
      insert into public.membership_binding_conflict as c (
          user_id, environment, original_transaction_id, conflict_kind)
      values (p_user_id, p_environment, p_original_transaction_id,
              'transaction_owned_by_other_identity')
      on conflict (user_id, environment, original_transaction_id) do update
         set observed_count = c.observed_count + 1,
             last_seen_at   = now();

      return jsonb_build_object(
        'outcome', 'conflict',
        'reason', 'subscription already established to another identity',
        'established', false);
  end;

  if found then
    return jsonb_build_object(
      'outcome', 'established',
      'established', true,
      'binding_method', v_method,
      'entitled', v_entitled);
  end if;

  -- A row already existed for this (identity, environment). OWNERSHIP IS
  -- ESTABLISHED ONCE: binding_method and bound_at are not re-provenanced. The
  -- refresh goes through the CANONICAL writer, so ordering, entitlement
  -- derivation and cleanup scheduling remain defined in exactly one place.
  select m.binding_method into v_existing
    from public.membership m
   where m.user_id = p_user_id and m.environment = p_environment;

  return jsonb_build_object(
    'outcome', 'already_established',
    'established', false,
    'binding_method', v_existing,
    'refresh', public.membership_apply_state_v1(
                 p_user_id, p_environment, p_original_transaction_id,
                 p_state, null));
end
$$;

comment on function public.membership_establish_v1(uuid, text, text, uuid, uuid, jsonb) is
  'THE ONLY INSERT into public.membership. Provenance derived from evidence; never schedules cleanup; refuses on an unconfirmed or foreign token.';


-- ================================================================== security
--
-- Same posture as U3 and U4: revoke from all four, then grant back exactly what
-- is needed, so the end state is a property of this file rather than of whichever
-- pg_default_acl entry applies to the creating role.
alter table public.membership_binding_conflict enable row level security;

revoke all on public.membership_binding_conflict
  from public, anon, authenticated, service_role;

revoke execute on function
  public.membership_establish_v1(uuid, text, text, uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;

-- THE ENTIRE U5b PRIVILEGE DELTA IS THESE TWO LINES.
--
--   ensure_membership_binding()  -> authenticated
--       The ONE client-reachable membership object U5 creates, and the narrowest
--       shape the design admits. IT TAKES NO ARGUMENT, and that is the safety
--       property rather than a convenience: identity comes from auth.uid(), so
--       there is no parameter to tamper with however the request is forged. It is
--       idempotent and can create at most one row per auth.users row, so the
--       reachable growth is bounded by the identity table itself. Created in U3
--       and deliberately left ungranted there; this is the grant U3 named.
--
--   membership_establish_v1      -> service_role
--       Called by U5d's attest endpoint AFTER JWS verification and AFTER the live
--       Apple read. It cannot be internal: it is an entry point, and the Apple
--       round trip necessarily sits outside the transaction.
--
-- NOT GRANTED, AND EACH ABSENCE IS DELIBERATE: no table or column privilege to
-- any role on any of the seven membership tables; nothing at all to anon;
-- nothing to PUBLIC; and connected_member() still carries no EXECUTE for anyone,
-- because at U6 it is evaluated inside policy expressions rather than called.
grant execute on function public.ensure_membership_binding() to authenticated;
grant execute on function
  public.membership_establish_v1(uuid, text, text, uuid, uuid, jsonb) to service_role;
