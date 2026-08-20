-- Phase 3 U4 — notification ingestion and authoritative reconciliation.
--
-- OBSERVE-ONLY, AND STRUCTURALLY SO RATHER THAN BY PROMISE. U4 creates no
-- policy, changes no policy, grants nothing to anon or authenticated, deploys no
-- worker, schedules nothing and deletes nothing. It adds one table, six
-- functions and four EXECUTE grants.
--
-- AND IT CANNOT ESTABLISH MEMBERSHIP AT ALL. Corrected 2026-08-20: an earlier
-- revision let ingestion INSERT a membership row when a notification resolved to
-- a live binding, inferring binding_method = 'purchase' from the fact that
-- Set App Account Token had not shipped yet. That inference was sound for the U4
-- window and is still the wrong thing to build. binding_method and bound_at are
-- statements about HOW OWNERSHIP WAS PROVED, and only the path that proved it may
-- make them; U5's protocol -- JWS possession, a live Apple read, and a token
-- match -- is what earns the right to write them. A rule that happens to hold
-- during one unit's window is not the same as a rule the code enforces.
--
-- SO THE WRITER BELOW IS UPDATE-ONLY. There is no INSERT into membership
-- anywhere in U4, which is a property of this file rather than of the calendar.
-- A notification that maps to a live binding but finds no authoritative row is
-- recorded 'ignored'/'unestablished' and left for U5.
--
-- Two independent things still hold and are worth keeping separate: the only
-- permitted notification -> identity mapping is
-- transactionInfo.appAccountToken -> membership_binding.binding_token (B-24);
-- and no Apple subscription carries an appAccountToken until U5 sets one, so in
-- production nothing will map either. That second statement is a
-- U4-before-U5 ACCEPTANCE-WINDOW PREDICTION, NOT a permanent invariant.
--
-- THE WRITE SURFACE IS EXECUTE-ONLY. service_role still holds ZERO privilege on
-- every membership table, so U3's A3f invariant -- no grantee other than the
-- owner in relacl -- survives U4 unchanged. Everything below reaches the tables
-- through SECURITY DEFINER functions owned by the table owner.
--
-- ONE ENTRY POINT PER PATH, ONE TRANSACTION PER ENTRY POINT (B-30). PROVEN, not
-- assumed: through PostgREST, two successive RPC calls returned
-- pg_current_xact_id() 20888 and 20889, a single RPC that inserted then raised
-- left no row, and two RPCs where the first inserted and the second raised left
-- the first row committed. So the originally proposed pair of separately granted
-- record/apply functions could have committed an audit row describing a state
-- change that rolled back. The canonical writer is therefore INTERNAL, granted
-- to no role at all, and reachable only from inside the two entry points.
--
-- EXPECTED OUTCOMES ARE RETURN VALUES, NEVER raise. stale, duplicate, unmapped
-- and needs_reconciliation are all ordinary answers. Only a genuine defect or
-- infrastructure fault raises, and that correctly rolls back the audit row too:
-- losing a diagnostic row is the right trade against committing half-applied
-- state, and Apple's production retries recover the notification anyway.


-- ============================================ B-26 / B-27: membership_notification
--
-- Applied to a table holding ZERO rows, which is the cheapest this will ever be.
--
-- B-26. outcome = 'duplicate' was structurally unwritable. The partial unique
-- index on notification_uuid means a replay cannot insert a second row, and
-- overwriting the survivor's outcome would destroy the record of what the first
-- delivery did. So a replay left NO evidence, and QA G2 asserted a value no
-- correct implementation could produce. delivery_count makes the replay
-- observable as a counter going 1 -> 2, which is a far stronger assertion than
-- "no second row appeared" -- an endpoint that silently drops everything also
-- produces that. 'duplicate' is now a value the entry point RETURNS, never one
-- it stores.
alter table public.membership_notification
  add column delivery_count   integer     not null default 1,
  add column last_received_at timestamptz;

alter table public.membership_notification
  add constraint membership_notification_delivery_count_positive
  check (delivery_count >= 1);

-- B-27. 'rejected' was the only home for Apple's own TEST notification, renewal
-- extension summaries, EXTERNAL_PURCHASE_TOKEN, RESCIND_CONSENT -- and for every
-- notification whose subscription maps to no Etudes identity, which between U4
-- and U5 is ALL of them. A rejected count is a security signal; filling it with
-- the commonest routine category destroys it, and B-11's shadow window is later
-- read against this record.
alter table public.membership_notification
  drop constraint membership_notification_outcome_check,
  add  constraint membership_notification_outcome_check
       check (outcome in ('applied', 'stale', 'duplicate', 'ignored', 'rejected'));

alter table public.membership_notification
  drop constraint membership_notification_failure_only_when_rejected,
  add  constraint membership_notification_failure_only_when_categorised
       check ((failure_category is null) = (outcome not in ('rejected', 'ignored')));

-- 'signature' and 'decode' are RETAINED even though B-29 moves outer-envelope
-- failures out of this table entirely. An inner JWS that fails verification
-- AFTER the envelope verified is a serious anomaly -- Apple signed the envelope
-- and its contents disagree -- and must keep a durable per-row home.
-- 'incomplete' is B-25's slot: Apple-signed, ownership-mapped, but carrying
-- neither an orderable signedDate nor a usable paid-through date, so it awaits a
-- live read rather than writing a null that would derive to "expired".
-- 'unestablished' is the slot for a notification that is Apple-signed, complete
-- AND resolves to a live binding, but for which no authoritative membership row
-- exists yet. U4 will not manufacture one -- see the writer below.
alter table public.membership_notification
  drop constraint membership_notification_failure_category_check,
  add  constraint membership_notification_failure_category_check
       check (failure_category is null or failure_category in
              ('signature', 'decode', 'schema', 'unsupported', 'environment',
               'unmapped', 'not_applicable', 'incomplete', 'unestablished'));

-- Anything we accepted OR ignored must still be identifiable and orderable.
-- environment is relaxed for 'ignored' alone, because a genuinely Apple-signed
-- EXTERNAL_PURCHASE_TOKEN payload carries none and is not a reject.
alter table public.membership_notification
  drop constraint membership_notification_accepted_is_complete,
  add  constraint membership_notification_accepted_is_complete
       check (outcome = 'rejected'
              or (notification_uuid is not null
                  and signed_date is not null
                  and (environment is not null or outcome = 'ignored')));


-- ================================================= B-29: bounded reject diagnostics
--
-- THE INGESTION ENDPOINT IS THIS PROJECT'S FIRST GENUINELY UNAUTHENTICATED
-- SURFACE. delete_account_v1 and revoke_apple_identity_v1 both set
-- verify_jwt = false and then perform their own auth.getUser(token); Apple sends
-- no Supabase JWT, so the JWS signature is the entire authorisation story and
-- anyone who learns the URL can POST arbitrary bytes.
--
-- PERSISTING A ROW PER REJECT WOULD HAND THAT CALLER AN UNBOUNDED DURABLE INSERT
-- PRIMITIVE. Bounding the payload bounds row SIZE and leaves row COUNT under
-- their control, which both costs storage without limit and drowns the very
-- signal the diagnostics exist to carry.
--
-- U3 IS NOT CONTRADICTED. Its surrogate primary key requires that a decode
-- failure with no extractable notificationUUID be REPRESENTABLE. It does not
-- require that every such payload be PERSISTED.
--
-- THE PRINCIPLE: durable per-row persistence is a privilege earned by passing
-- signature verification.
--
--   Tier 1  structural rejects write NOTHING -- not a row, not a counter.
--   Tier 2  outer-envelope signature failures increment THIS table, whose
--           cardinality is bounded by hours x categories however large the
--           flood.
--   Tier 3  signature-verified notifications persist per-row in
--           membership_notification, bounded by Apple's own sending rate.
--
-- The dividend is that 'rejected' becomes meaningful again: in
-- membership_notification it can now only mean Apple-signed but refused
-- downstream, which is low-volume and always worth reading.
--
-- RESIDUAL, STATED RATHER THAN HIDDEN: a caller can still cause one bounded
-- upsert per Tier-2 request. That is a load concern and not a growth concern.
-- This table is diagnostics an operator may purge freely -- unlike anything in
-- membership.
create table public.membership_notification_reject_stat (
  hour_bucket      timestamptz not null,
  failure_category text        not null,
  reject_count     bigint      not null default 0,
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),

  -- A CAPPED SAMPLE, not a corpus. It answers U3's stated question -- one
  -- payload replayed, or many different ones -- without letting the caller
  -- decide how much we store.
  sample_sha256    text[]      not null default '{}',

  constraint membership_notification_reject_stat_pkey
    primary key (hour_bucket, failure_category),
  constraint membership_notification_reject_stat_bucket_aligned
    check (hour_bucket = date_trunc('hour', hour_bucket)),
  constraint membership_notification_reject_stat_count_positive
    check (reject_count >= 0),
  constraint membership_notification_reject_stat_sample_bounded
    check (cardinality(sample_sha256) <= 8),
  constraint membership_notification_reject_stat_category_check
    check (failure_category in ('signature', 'decode', 'schema', 'unsupported',
                                'environment', 'oversize'))
);

comment on table public.membership_notification_reject_stat is
  'Bounded aggregate for unauthenticated invalid-signature traffic (B-29). Fixed cardinality: hours x categories. Diagnostics only; freely purgeable.';


-- ========================================================== internal writers
--
-- NONE of the three below is granted to ANY role. They are reachable only from
-- inside the SECURITY DEFINER entry points further down, which is what lets
-- "one canonical writer" and "one transaction per path" both hold at once.

-- The B-24 boundary, expressed as the only mapping function that exists.
--
-- THERE IS DELIBERATELY NO FUNCTION ANYWHERE IN U4 THAT RESOLVES A user_id FROM
-- AN original_transaction_id. Apple's answer confirms that somebody's
-- subscription is active and never says whose; original transaction identifiers
-- appear in receipts, support mail and our own logs and carry no secrecy
-- property. The token is the only artefact that binds a subscription to an
-- Etudes identity.
create function public.membership_resolve_binding_v1(p_app_account_token uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b.user_id
    from public.membership_binding b
   where p_app_account_token is not null
     and b.binding_token = p_app_account_token;
$$;

comment on function public.membership_resolve_binding_v1(uuid) is
  'B-24 boundary: appAccountToken -> user_id. The ONLY permitted notification-to-identity mapping. Internal; granted to no role.';


-- THE CANONICAL MEMBERSHIP WRITER. Notifications and reconciliation both land
-- here and nowhere else, so ordering, entitlement derivation and cleanup
-- scheduling are defined exactly once.
--
-- UPDATE-ONLY. IT CANNOT CREATE A MEMBERSHIP ROW, AND THAT IS THE POINT.
-- Corrected 2026-08-20. An earlier revision inserted when a notification resolved
-- to a live binding, supplying binding_method = 'purchase' on the reasoning that
-- Set App Account Token has not shipped, so any token Apple reports must have
-- been attached at purchase. THE REASONING WAS SOUND AND THE DESIGN WAS STILL
-- WRONG: binding_method and bound_at record HOW OWNERSHIP WAS PROVED, and a
-- value inferred from what has not been built yet is provenance we invented
-- rather than established. U5's protocol -- Apple-signed JWS for possession, a
-- live Apple read for currency, and a token match for the binding -- is what
-- earns the right to write them.
--
-- The practical consequence is small and the structural one is not: U4 refreshes
-- authoritative rows and never originates them, so there is no INSERT into
-- membership anywhere in this migration for a future reader to find and reuse.
create function public.membership_apply_state_v1(
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
  'THE canonical membership writer. UPDATE-ONLY: refreshes an authoritative row, never originates one. Internal; granted to no role.';


-- Audit + dedupe, in one statement so a replay cannot race.
create function public.membership_record_notification_v1(p_event jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id     uuid;
  v_count  integer;
begin
  -- The outcome inserted here is PROVISIONAL and is corrected by the caller in
  -- the same transaction, so no intermediate value is ever visible to anyone.
  -- It cannot be left NULL: the CHECK forbids it, and a nullable outcome would
  -- be a worse design than a provisional one.
  insert into public.membership_notification as n (
      notification_uuid, environment, notification_type, subtype,
      original_transaction_id, signed_date, outcome, failure_category,
      request_id, payload_bytes, payload_sha256, last_received_at)
  values (
      nullif(p_event->>'notification_uuid', '')::uuid,
      nullif(p_event->>'environment', ''),
      nullif(p_event->>'notification_type', ''),
      nullif(p_event->>'subtype', ''),
      nullif(p_event->>'original_transaction_id', ''),
      nullif(p_event->>'signed_date', '')::timestamptz,
      'ignored', 'not_applicable',
      nullif(p_event->>'request_id', ''),
      (p_event->>'payload_bytes')::integer,
      nullif(p_event->>'payload_sha256', ''),
      now())
  on conflict (notification_uuid) where notification_uuid is not null
  do update set delivery_count   = n.delivery_count + 1,
                last_received_at = now()
  returning n.id, n.delivery_count into v_id, v_count;

  -- delivery_count > 1 is exactly "the conflict path ran", which is what makes
  -- a replay observable at all (B-26).
  return jsonb_build_object(
    'id', v_id,
    'delivery_count', v_count,
    'duplicate', v_count > 1);
end
$$;

comment on function public.membership_record_notification_v1(jsonb) is
  'Audit row + atomic dedupe for App Store Server Notifications V2. Internal; granted to no role.';


-- ================================================================ entry points
--
-- EXACTLY FOUR, each doing everything its path needs inside ONE transaction.

-- Tier 2 of B-29. The only thing an unauthenticated caller can ever reach, and
-- it cannot grow the database: the primary key is (hour, category), so the row
-- count is bounded by hours x categories no matter how many requests arrive.
create function public.membership_record_reject_v1(
  p_failure_category text,
  p_sha256           text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  -- VALIDATED HERE RATHER THAN TRUSTED FROM THE CALLER. This is the only
  -- function an unauthenticated request can reach, indirectly, so its inputs are
  -- narrowed at the door: a digest that is not 64 lowercase hex characters is
  -- dropped rather than stored, and an unrecognised category is normalised to
  -- 'decode' instead of aborting the request on a CHECK violation. Neither can
  -- happen from the shipping endpoint; both would be an upstream defect, and the
  -- right response to one is a bounded row, not a 5xx that hides it.
  v_sha text := case when p_sha256 ~ '^[0-9a-f]{64}$' then p_sha256 else null end;
  v_cat text := case when p_failure_category in
                       ('signature','decode','schema','unsupported','environment','oversize')
                     then p_failure_category else 'decode' end;
begin
  insert into public.membership_notification_reject_stat as s (
      hour_bucket, failure_category, reject_count,
      first_seen_at, last_seen_at, sample_sha256)
  values (
      date_trunc('hour', now()), v_cat, 1, now(), now(),
      case when v_sha is null then '{}'::text[] else array[v_sha] end)
  on conflict (hour_bucket, failure_category) do update
     set reject_count  = s.reject_count + 1,
         last_seen_at  = now(),
         -- Bounded three ways: no null, no repeat, never more than eight.
         sample_sha256 = case
           when v_sha is null
             or v_sha = any (s.sample_sha256)
             or cardinality(s.sample_sha256) >= 8
           then s.sample_sha256
           else s.sample_sha256 || v_sha
         end;
end
$$;

comment on function public.membership_record_reject_v1(text, text) is
  'B-29 Tier 2: bounded aggregate counter for unauthenticated invalid-signature traffic. Fixed cardinality by construction.';


-- INGESTION. Record, resolve, apply -- one transaction, one call.
create function public.membership_ingest_notification_v1(p_event jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rec         jsonb;
  v_id          uuid;
  v_token       uuid    := nullif(p_event->>'app_account_token', '')::uuid;
  v_disposition text    := coalesce(p_event->>'disposition', 'unsupported');
  v_user        uuid;
  v_applied     jsonb;
  v_outcome     text;
  v_category    text;
begin
  v_rec := public.membership_record_notification_v1(p_event);
  v_id  := (v_rec->>'id')::uuid;

  -- A replay short-circuits before ANY state work. The counter has already been
  -- incremented, the stored outcome of the first delivery is untouched, and
  -- 'duplicate' is returned rather than stored (B-26).
  if (v_rec->>'duplicate')::boolean then
    return jsonb_build_object(
      'outcome', 'duplicate',
      'notification_id', v_id,
      'delivery_count', (v_rec->>'delivery_count')::integer);
  end if;

  if v_disposition = 'state' then
    v_user := public.membership_resolve_binding_v1(v_token);
    if v_user is null then
      -- THE PRODUCTION CASE UNTIL U5 SHIPS, and it is ordinary traffic rather
      -- than a reject. No appAccountToken exists on any Apple subscription yet,
      -- so every real notification lands here.
      v_outcome := 'ignored'; v_category := 'unmapped';
    else
      v_applied := public.membership_apply_state_v1(
        v_user,
        p_event->>'environment',
        p_event->>'original_transaction_id',
        p_event->'state',
        nullif(p_event->>'notification_uuid', '')::uuid);
      v_outcome := v_applied->>'outcome';        -- 'applied', 'stale' or 'ignored'
      -- MAPPED, COMPLETE, AND STILL NOT WRITABLE. The token resolves to a live
      -- binding and Apple's state is usable, but no authoritative membership row
      -- exists -- so there is nothing to update and U4 will not originate one.
      -- Recorded rather than discarded, because U5 needs to know this arrived.
      if v_outcome = 'ignored' then
        v_category := 'unestablished';
      else
        v_category := null;
      end if;
    end if;
  elsif v_disposition = 'incomplete' then
    -- B-25. Apple-signed and possibly ownership-mapped, but carrying neither an
    -- orderable signedDate nor a usable paid-through date. WRITE NOTHING and ask
    -- for a live read. Crucially this leaves entitlement_ended_at and
    -- pending_cleanup_at untouched: ambiguous state must never schedule cleanup.
    v_outcome := 'ignored'; v_category := 'incomplete';
  elsif v_disposition = 'not_applicable' then
    v_outcome := 'ignored'; v_category := 'not_applicable';
  else
    v_outcome := 'rejected'; v_category := 'unsupported';
  end if;

  update public.membership_notification
     set outcome = v_outcome, failure_category = v_category
   where id = v_id;

  return jsonb_build_object(
    'outcome', v_outcome,
    'failure_category', v_category,
    'notification_id', v_id,
    'mapped', v_user is not null,
    'needs_reconciliation', v_disposition = 'incomplete',
    'needs_establishment', coalesce((v_applied->>'needs_establishment')::boolean, false),
    'applied', v_applied);
end
$$;

comment on function public.membership_ingest_notification_v1(jsonb) is
  'U4 ingestion entry point. Records, resolves the B-24 binding and applies state in ONE transaction.';


-- RECONCILIATION. A live authoritative Apple read, applied through the same
-- canonical writer.
--
-- UPDATE-ONLY BY DESIGN. Reconciliation may refresh a row whose ownership was
-- already established; it may NEVER create one, because binding_method and
-- bound_at are statements about how ownership was proved and only the path that
-- proved it may make them. Creation from a bare transaction identifier is
-- precisely the B-24 bypass, and there is no code here that could perform it.
create function public.membership_apply_reconciliation_v1(
  p_user_id     uuid,
  p_environment text,
  p_state       jsonb,
  p_original_transaction_id text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_txn text;
begin
  select m.original_transaction_id into v_txn
    from public.membership m
   where m.user_id = p_user_id and m.environment = p_environment;

  -- Checked here as well as in the writer, because this entry point needs the
  -- stored original_transaction_id and cannot fall through without one.
  if not found then
    return jsonb_build_object(
      'outcome', 'ignored',
      'needs_establishment', true,
      'reason', 'no authoritative membership row; ownership establishment belongs to U5');
  end if;

  return public.membership_apply_state_v1(
    p_user_id, p_environment,
    coalesce(p_original_transaction_id, v_txn),
    p_state, null);
end
$$;

comment on function public.membership_apply_reconciliation_v1(uuid, text, jsonb, text) is
  'U4 reconciliation entry point. UPDATE-ONLY: refreshes an already-bound row, never creates one.';


-- The server needs to know WHICH rows to reconcile, and holds no table SELECT.
-- RETURNS ONLY THE THREE COLUMNS THE CALLER USES. Narrowed 2026-08-20 during the
-- grant audit: it previously also returned renewal_info_signed_date and
-- pending_cleanup_at, neither of which appstore_reconcile_v1 reads. Staleness
-- ordering is applied HERE, so the caller never needed the timestamp to sort by
-- it -- and a scheduling column has no business leaving the database on a path
-- that has no use for it.
create function public.membership_due_for_reconciliation_v1(
  p_user_id     uuid default null,
  p_environment text default null
)
returns table (
  user_id                 uuid,
  environment             text,
  original_transaction_id text
)
language sql
stable
security definer
set search_path = ''
as $$
  select m.user_id, m.environment, m.original_transaction_id
    from public.membership m
   where (p_user_id is null or m.user_id = p_user_id)
     and (p_environment is null or m.environment = p_environment)
   order by m.renewal_info_signed_date asc;
$$;

comment on function public.membership_due_for_reconciliation_v1(uuid, text) is
  'Server-internal selector for reconciliation targets. Returns no Apple state, no scheduling state and grants no authority.';


-- ================================================================== security
--
-- Same posture as U3, for the same reasons and by the same construction: revoke
-- from all four, then grant back exactly what is needed. The end state is a
-- property of this file rather than of whichever pg_default_acl entry applies to
-- the creating role.
alter table public.membership_notification_reject_stat enable row level security;

revoke all on public.membership_notification_reject_stat
  from public, anon, authenticated, service_role;

revoke execute on function public.membership_resolve_binding_v1(uuid)                        from public, anon, authenticated, service_role;
revoke execute on function public.membership_apply_state_v1(uuid, text, text, jsonb, uuid)       from public, anon, authenticated, service_role;
revoke execute on function public.membership_record_notification_v1(jsonb)                   from public, anon, authenticated, service_role;
revoke execute on function public.membership_record_reject_v1(text, text)                    from public, anon, authenticated, service_role;
revoke execute on function public.membership_ingest_notification_v1(jsonb)                   from public, anon, authenticated, service_role;
revoke execute on function public.membership_apply_reconciliation_v1(uuid, text, jsonb, text) from public, anon, authenticated, service_role;
revoke execute on function public.membership_due_for_reconciliation_v1(uuid, text)           from public, anon, authenticated, service_role;

-- THE ENTIRE U4 PRIVILEGE SURFACE IS THESE FOUR LINES, AUDITED 2026-08-20 AND
-- FOUND MINIMAL. Each is named, justified, and checked against the question
-- "could this stay internal?".
--
--   membership_ingest_notification_v1
--       Called by appstore_notifications_v1 for every verified payload. Cannot
--       be internal: it is the entry point.
--
--   membership_due_for_reconciliation_v1
--       Called by appstore_reconcile_v1 BEFORE the Apple read. Cannot be merged
--       into the applier, because the HTTPS call to Apple sits between selection
--       and application and must never happen inside a transaction. NARROWED in
--       this audit to the three columns the caller actually uses.
--
--   membership_apply_reconciliation_v1
--       Called AFTER the Apple read, with verified state. Same reason, other
--       side of the network call.
--
--   membership_record_reject_v1
--       Called at B-29 Tier 2, when verification failed and there is therefore
--       NO event to ingest. It could technically be folded into the ingest entry
--       point as another disposition, AND IT DELIBERATELY IS NOT: folding it
--       would put the function that can write membership and
--       membership_notification on the code path an unauthenticated caller
--       reaches by sending garbage. Kept separate, the Tier-2 path can touch
--       nothing but the bounded aggregate, whatever goes wrong upstream. That
--       separation is a security property, not tidiness.
--
-- THE THREE INTERNAL FUNCTIONS ARE GRANTED TO NOBODY -- the canonical writer,
-- the B-24 binding resolver and the audit recorder. No role can invoke them
-- directly, so the atomicity of the entry points cannot be bypassed and neither
-- can the ownership precondition.
--
-- NOT GRANTED, AND EACH ABSENCE IS DELIBERATE: no table or column privilege to
-- any role on any of the six membership tables; nothing at all to anon or
-- authenticated; nothing to PUBLIC; and ensure_membership_binding stays
-- ungranted because it is U5's to expose.
grant execute on function public.membership_record_reject_v1(text, text)                     to service_role;
grant execute on function public.membership_ingest_notification_v1(jsonb)                    to service_role;
grant execute on function public.membership_apply_reconciliation_v1(uuid, text, jsonb, text) to service_role;
grant execute on function public.membership_due_for_reconciliation_v1(uuid, text)            to service_role;
