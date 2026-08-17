-- Phase 3 U3 — inert server-authoritative membership schema.
--
-- INERT BY CONSTRUCTION. Nothing here is read by any existing policy or
-- function, no client role can reach any of it, no Edge Function is deployed,
-- no Apple request is made and no cleanup is scheduled. U3 exists so that U4,
-- U5, U6 and U7 have somewhere to write; it changes no product behaviour.
--
-- ENTITLEMENT IS DERIVED, NEVER STORED. A stored boolean would drift the moment
-- a grace period elapsed with no notification: the row would still read
-- entitled while Apple's own formula said otherwise, and nothing would correct
-- it. Deriving it means the passage of time alone produces the right answer,
-- which is what makes a missed notification safe rather than dangerous. It also
-- keeps the server's semantics identical to Transaction.currentEntitlements on
-- device, so client and server can disagree about freshness but never meaning.
--
-- SECURITY IS NOT OPTIONAL HERE, AND IT IS DETERMINED BY THE SQL BELOW RATHER
-- THAN BY THE ENVIRONMENT. A new public table inherits whatever pg_default_acl
-- entry applies to the role that creates it, and that entry differs between
-- deployments: the local stack's `postgres` entry grants anon, authenticated
-- and service_role `Dxtm`, while the stock `supabase_admin` entry grants all
-- three `arwdDxtm`. An earlier revision of this file asserted the second shape
-- as production fact without evidence, and predicted a structural delta
-- measured under the first -- two statements that cannot both describe one
-- environment.
--
-- The fix is not to discover which default applies. It is to stop depending on
-- it: every privilege on these five tables is revoked from PUBLIC and from all
-- three client/server roles, so the final state is the same under every
-- default. U4 introduces whatever server mutation surface it needs by explicit
-- grant, deliberately, rather than inheriting one by accident.


-- ========================================================= ownership binding
--
-- Per IDENTITY, not per subscription, for two independent reasons.
--
--   1. The token must exist BEFORE the StoreKit purchase, because it is passed
--      through Product.PurchaseOption.appAccountToken(_:). At that moment there
--      is no original_transaction_id, no Apple subscription and no legitimate
--      membership row. Putting it on `membership` would require inventing a
--      fake row to mint a token.
--
--   2. Cardinality. `membership` is per (user_id, environment), so a user
--      holding both a Sandbox and a Production subscription would have had TWO
--      tokens and no single expected value for the Apple-side comparison.
--
-- Created LAZILY, when an identity actually reconciles or purchases. Eager
-- population for the cutover identities buys no safety property and would mint
-- tokens for accounts that will never launch again.
create table public.membership_binding (
  user_id       uuid        not null,
  binding_token uuid        not null default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint membership_binding_pkey primary key (user_id),
  constraint membership_binding_user_fk
    foreign key (user_id) references auth.users(id) on delete cascade,
  constraint membership_binding_token_unique unique (binding_token)
);

comment on table public.membership_binding is
  'Per-identity Apple appAccountToken binding. Server-private. Survives ordinary expiry cleanup; removed only by auth.users cascade on explicit account deletion.';


-- ================================================================ membership
--
-- Authoritative Apple state, Études scheduling state, and the ordering key,
-- kept visibly separate. Nothing stored here can contradict Apple.
create table public.membership (
  user_id                    uuid        not null,
  environment                text        not null,

  -- ---- authoritative Apple state ----
  original_transaction_id    text        not null,
  product_id                 text        not null,
  apple_status               smallint,
  renewal_date               timestamptz,
  grace_period_expires_date  timestamptz,
  is_in_billing_retry        boolean     not null default false,
  auto_renew_status          smallint,
  expiration_intent          smallint,
  revocation_date            timestamptz,

  -- ---- authority / ordering ----
  -- NOT the notification's own signedDate: a notification signed later can
  -- carry renewal info signed earlier. This is the monotonic key that makes
  -- out-of-order delivery a no-op, so a row that cannot be ordered must not
  -- exist.
  renewal_info_signed_date   timestamptz not null,
  last_notification_uuid     uuid,

  -- ---- ownership binding (B-24) ----
  -- NOT NULL so the database CANNOT hold an ownership-unverified membership
  -- row. This is the central security rule expressed as a constraint rather
  -- than as something U5 must remember.
  binding_method             text        not null,
  bound_at                   timestamptz not null,

  -- ---- Études scheduling state ----
  entitlement_ended_at       timestamptz,
  pending_cleanup_at         timestamptz,

  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),

  constraint membership_pkey primary key (user_id, environment),
  constraint membership_user_fk
    foreign key (user_id) references auth.users(id) on delete cascade,

  -- 'Xcode' IS EXCLUDED DELIBERATELY. AppStore.Environment has three values,
  -- and a local StoreKit-configuration transaction is signed by Xcode's test
  -- certificate rather than Apple's root, so U5 rejects it at signature
  -- verification. This constraint is defence in depth for that. DO NOT add
  -- 'Xcode' to make a synthetic run work: that is the failure it prevents.
  constraint membership_environment_check
    check (environment in ('Sandbox', 'Production')),

  constraint membership_apple_status_check
    check (apple_status is null or apple_status between 1 and 5),
  constraint membership_auto_renew_status_check
    check (auto_renew_status is null or auto_renew_status in (0, 1)),
  constraint membership_binding_method_check
    check (binding_method in ('purchase', 'legacy_claim')),

  -- Defence in depth mirroring Apple's own binding, and a product invariant:
  -- Family Sharing is OFF for both products, so one Apple subscription is
  -- intended to entitle at most one Études identity. It does NOT establish
  -- that the identity is the legitimate owner -- that is the JWS and token
  -- check in U5 -- but it means a defect there surfaces as a constraint
  -- violation rather than two silently entitled identities.
  constraint membership_transaction_unique
    unique (environment, original_transaction_id),

  constraint membership_cleanup_requires_end
    check (pending_cleanup_at is null or entitlement_ended_at is not null)
);

comment on table public.membership is
  'Server-authoritative membership. Entitlement is DERIVED via connected_member(), never stored. Server-private.';

-- The ONLY selector U7's worker may use. Its null-ness is what structurally
-- protects an identity that never had entitlement: no row, nothing to
-- transition, nothing to schedule.
create index membership_pending_cleanup_idx
  on public.membership (pending_cleanup_at)
  where pending_cleanup_at is not null;


-- ============================================== notification audit / dedupe
--
-- NO RAW PAYLOAD IS RETAINED. A payload that fails verification is
-- attacker-controlled input by definition, and persisting it stores an
-- unbounded unauthenticated blob to serve a diagnostic need that bounded
-- metadata meets. The digest even improves on the payload for the commonest
-- question -- one payload replayed, or many different ones -- which becomes a
-- group by rather than a manual comparison. What is genuinely lost is
-- recoverable from Apple: Get Notification History replays 180 days in
-- production and 30 in sandbox.
--
-- SURROGATE PRIMARY KEY, because a notification rejected for a decode failure
-- may have NO extractable notificationUUID -- which is precisely what "failed
-- to decode" means. A NOT NULL uuid key could not record the very rows the
-- diagnostics exist for.
create table public.membership_notification (
  id                       uuid        not null default gen_random_uuid(),

  notification_uuid        uuid,
  environment              text,
  notification_type        text,
  subtype                  text,
  original_transaction_id  text,
  signed_date              timestamptz,
  received_at              timestamptz not null default now(),

  outcome                  text        not null,
  failure_category         text,
  request_id               text,
  payload_bytes            integer,
  payload_sha256           text,

  constraint membership_notification_pkey primary key (id),

  constraint membership_notification_outcome_check
    check (outcome in ('applied', 'stale', 'duplicate', 'rejected')),
  constraint membership_notification_failure_only_when_rejected
    check ((failure_category is null) = (outcome <> 'rejected')),
  constraint membership_notification_failure_category_check
    check (failure_category is null or failure_category in
           ('signature', 'decode', 'schema', 'unsupported', 'environment')),
  constraint membership_notification_environment_check
    check (environment is null or environment in ('Sandbox', 'Production')),

  -- Anything we ACCEPTED must be identifiable and orderable. Only a rejected
  -- row may be incomplete.
  constraint membership_notification_accepted_is_complete
    check (outcome = 'rejected'
           or (notification_uuid is not null
               and environment is not null
               and signed_date is not null)),

  constraint membership_notification_sha256_format
    check (payload_sha256 is null or payload_sha256 ~ '^[0-9a-f]{64}$'),
  constraint membership_notification_bytes_nonnegative
    check (payload_bytes is null or payload_bytes >= 0)
);

comment on table public.membership_notification is
  'App Store Server Notifications V2 audit and dedupe. Bounded diagnostics only; raw payloads are never retained.';

-- Dedupe survives intact for everything that decoded, while leaving room for
-- rejected rows that have no uuid at all.
create unique index membership_notification_uuid_key
  on public.membership_notification (notification_uuid)
  where notification_uuid is not null;

create index membership_notification_txn_idx
  on public.membership_notification (original_transaction_id, signed_date desc)
  where original_transaction_id is not null;


-- ================================================ cutover snapshot + control
--
-- STRUCTURE ONLY IN THIS MIGRATION. The contents are production identity data
-- and are captured by a separate, reviewed, one-time deployment transaction --
-- see supabase/sql/. Applied locally this table stays EMPTY, which is honest:
-- the mechanism is reproducible even though the data deliberately is not, and
-- no production UID is ever written into the repository.
create table public.membership_cutover (
  user_id     uuid        not null,
  captured_at timestamptz not null default now(),

  constraint membership_cutover_pkey primary key (user_id),
  constraint membership_cutover_user_fk
    foreign key (user_id) references auth.users(id) on delete cascade
);

comment on table public.membership_cutover is
  'Frozen pre-enforcement identity snapshot. Populated ONCE at production cutover; never appended to for ordinary new users.';

create table public.membership_control (
  id                     boolean     not null default true,

  -- cutover_at is the DEFINITION of "pre-cutover", not merely a note of when
  -- the capture ran: the population predicate is auth.users.created_at <
  -- cutover_at, so the boundary is re-derivable and auditable afterwards.
  cutover_at             timestamptz,
  cutover_identity_count integer,

  -- Set ONLY after post-commit convergence has genuinely passed. It durably
  -- distinguishes "snapshot completeness verified" from "not yet verified",
  -- which nothing else could: the in-transaction assertions run on the
  -- cutover transaction's own snapshot and therefore cannot observe an
  -- identity that committed after it. Without this column a later reader --
  -- U6c in particular, whose removal rule leans on the snapshot being
  -- complete -- would have to take completeness on trust.
  cutover_verified_at    timestamptz,

  -- Defaults TRUE deliberately. The two failure modes are not symmetric:
  -- forgetting to enable it before U6b binds locks out every pre-cutover
  -- member, silently. Enabling it while nothing reads it does nothing at all.
  grandfather_enabled    boolean     not null default true,
  grandfather_expires_at timestamptz,

  u6b_bound_at           timestamptz,
  notes                  text,
  updated_at             timestamptz not null default now(),

  constraint membership_control_pkey primary key (id),
  constraint membership_control_single_row check (id),
  -- The count belongs with VERIFICATION, not with the boundary. An earlier
  -- version tied it to cutover_at, which encoded an assumption the corrected
  -- two-phase cutover invalidates: the boundary must be declared BEFORE the
  -- final count can be known, because completeness is only observable on a
  -- fresh snapshot after commit. CHECK constraints are evaluated per statement,
  -- so that version made the correct procedure literally impossible to execute.
  -- Tying the count to cutover_verified_at instead means it is simply absent
  -- until the snapshot is verified complete -- which is what it always meant.
  constraint membership_control_count_with_verification
    check ((cutover_verified_at is null) = (cutover_identity_count is null)),
  constraint membership_control_count_nonnegative
    check (cutover_identity_count is null or cutover_identity_count >= 0),
  -- Verification cannot precede the boundary it verifies.
  constraint membership_control_verified_needs_cutover
    check (cutover_verified_at is null or cutover_at is not null)
);

comment on table public.membership_control is
  'Single-row control for the cutover boundary and the bounded grandfather compatibility window.';

insert into public.membership_control (id) values (true)
  on conflict (id) do nothing;


-- =================================================================== helpers

-- Apple's own service formula, evaluated against a single transaction-time
-- instant. isInBillingRetryPeriod alone does NOT entitle: it entitles only
-- combined with an unexpired grace period.
--
-- Clause ordering is the implementation of invariants 7 and 8. bool_or over an
-- EMPTY set is NULL and falls through to grandfathering; bool_or over rows that
-- are all false is FALSE and does NOT fall through -- so an authoritative
-- not-entitled row can never be rescued by the compatibility clause.
--
-- EACH TERM IS coalesce()d, AND THAT IS NOT DEFENSIVE PADDING. Without it the
-- clause ordering silently breaks under three-valued logic, and U3's own
-- acceptance run caught it: a row in billing retry with a NULL
-- grace_period_expires_date evaluates `true AND NULL` -> NULL, then
-- `false OR NULL` -> NULL, so bool_or returns NULL over a row that EXISTS.
-- coalesce() at the top level cannot tell that apart from "no rows at all", so
-- the query fell through to the grandfather clause and returned TRUE for an
-- identity whose real membership state said otherwise -- a direct violation of
-- invariant 8. Coalescing each term makes the row-level expression strictly
-- two-valued, so bool_or is NULL if and only if there are no rows, which is
-- exactly the distinction the design depends on.
create function public.connected_member(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select bool_or(
         coalesce(m.renewal_date > now(), false)
         or coalesce(m.is_in_billing_retry
                     and m.grace_period_expires_date > now(), false)
       )
       from public.membership m
      where m.user_id = target_user_id),

    (select exists (
       select 1
         from public.membership_cutover c
         cross join public.membership_control k
        where c.user_id = target_user_id
          and k.grandfather_enabled
          and (k.grandfather_expires_at is null
               or now() < k.grandfather_expires_at))),

    -- Absence is not entitlement. NULL input reaches here and fails closed.
    false
  );
$$;

comment on function public.connected_member(uuid) is
  'Server-private entitlement predicate. Derived from Apple state; real membership always overrides grandfathering.';


-- Server/internal only. NOT a client membership API. Exists so U6a''s shadow
-- window can report WHICH clause decided a denial, which a boolean cannot.
create function public.membership_state(target_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from public.membership m
                  where m.user_id = target_user_id)
      then case when public.connected_member(target_user_id)
                then 'entitled' else 'expired' end
    when public.connected_member(target_user_id) then 'grandfathered'
    else 'unknown'
  end;
$$;

comment on function public.membership_state(uuid) is
  'Server-internal diagnostic: entitled | expired | grandfathered | unknown. Not client-readable.';


-- Pre-purchase binding token delivery.
--
-- TAKES NO ARGUMENT, AND THAT IS THE SAFETY PROPERTY. There is no user_id to
-- tamper with: the identity comes from auth.uid(), derived from the verified
-- JWT, so a caller cannot request another identity's token however the request
-- is forged. That is stronger than validating a parameter, because there is
-- nothing to validate.
--
-- CREATED HERE, GRANTED IN U5. U3 therefore ends with zero client-reachable
-- membership objects, which is a query rather than a code review.
create function public.ensure_membership_binding()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_token uuid;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = '28000';
  end if;

  -- UPSERT-RETURNING. `do nothing` would be wrong: under concurrency the loser
  -- skips WITHOUT taking a lock, and a following SELECT can miss the winner's
  -- as-yet-uncommitted row. `do update` locks, waits for the winner, and
  -- RETURNS the surviving row -- so concurrent callers get the SAME token.
  -- The assignment is a deliberate no-op; it exists only to make RETURNING fire.
  insert into public.membership_binding (user_id)
       values (v_uid)
  on conflict (user_id) do update
       set user_id = excluded.user_id
    returning membership_binding.binding_token into v_token;

  return v_token;
end
$$;

comment on function public.ensure_membership_binding() is
  'Returns the calling identity''s stable binding token, creating it idempotently. Granted to authenticated in U5, not U3.';


-- ================================================================== security
--
-- RLS with zero policies, AND no client privileges. RLS alone is not the
-- boundary: a future policy added carelessly would be immediately writable if
-- the default grants were left in place.
alter table public.membership              enable row level security;
alter table public.membership_binding      enable row level security;
alter table public.membership_notification enable row level security;
alter table public.membership_cutover      enable row level security;
alter table public.membership_control      enable row level security;

-- REVOKED FROM public, anon, authenticated AND service_role -- all four, on
-- purpose, and each for its own reason.
--
--   public          The structural snapshot filters grantee to the three named
--                   roles, so a PUBLIC table grant would be INVISIBLE to the
--                   B-23 gate. This revoke is the only thing that rules it out.
--                   It is the table-level counterpart of the PUBLIC EXECUTE
--                   revoke below, which exists because of the same blind spot.
--
--   anon,           No client may reach membership state directly. RLS with
--   authenticated   zero policies already denies, but privileges are the outer
--                   boundary: a policy added carelessly at U6 would be
--                   immediately live if the grants were left in place.
--
--   service_role    NOT an oversight, and not merely tidiness. Ambient defaults
--                   would otherwise leave service_role holding whatever the
--                   creating role's pg_default_acl says -- Dxtm here, arwdDxtm
--                   elsewhere -- which makes U3's final state a property of the
--                   deployment rather than of this file. U3 needs no direct
--                   table access at all: every read goes through a SECURITY
--                   DEFINER helper owned by the table owner. So the honest
--                   posture is zero, and U4 grants what U4 needs.
--
-- The resulting invariant is checkable in one query rather than by reading this
-- comment: no grantee other than the table owner appears in relacl for any of
-- the five tables. The acceptance suite asserts exactly that (A3f).
revoke all on public.membership              from public, anon, authenticated, service_role;
revoke all on public.membership_binding      from public, anon, authenticated, service_role;
revoke all on public.membership_notification from public, anon, authenticated, service_role;
revoke all on public.membership_cutover      from public, anon, authenticated, service_role;
revoke all on public.membership_control      from public, anon, authenticated, service_role;

-- REVOKE FROM PUBLIC FIRST. has_function_privilege() is true when EXECUTE is
-- inherited from PUBLIC, so revoking only from the three named roles would
-- leave every helper callable while the snapshot still read as expected for
-- those roles. This is exactly the blind spot B-23's widened capture exists to
-- catch.
--
-- SERVICE_ROLE IS REVOKED HERE TOO, for the same determinism reason as the
-- tables above: the stock `supabase_admin` default grants EXECUTE on new
-- functions to anon, authenticated AND service_role, while the local
-- `postgres` default grants it to none of them. Revoking from all four makes
-- the starting point identical under either, so the only EXECUTE any of these
-- helpers carries afterwards is the one explicitly granted below.
revoke execute on function public.connected_member(uuid)      from public, anon, authenticated, service_role;
revoke execute on function public.membership_state(uuid)      from public, anon, authenticated, service_role;
revoke execute on function public.ensure_membership_binding() from public, anon, authenticated, service_role;

-- membership_state() is the one helper a server identity calls directly.
-- connected_member() needs no grant at all: at U6 it is evaluated inside RLS
-- policy expressions, which run as part of the query rather than as a direct
-- call -- so it decides what clients may see while remaining unreachable BY
-- them.
--
-- THIS IS THE ONLY PRIVILEGE U3 GRANTS TO ANY NON-OWNER ROLE. Everything else
-- above is a revoke, so the complete U3 privilege surface is one line long and
-- can be read in full here rather than assembled from defaults.
grant execute on function public.membership_state(uuid) to service_role;
