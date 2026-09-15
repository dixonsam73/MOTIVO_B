-- B-39 (independent audit A1) — A REVOKED SUBSCRIPTION IS NOT ENTITLED.
--
-- LOCAL ONLY UNTIL A SEPARATE, AUTHORISED PRODUCTION DEPLOYMENT. Prediction:
-- docs/phase-5-b39-prediction.md. Failing-first guards:
-- supabase/tests/b39/acceptance-refund.sh and supabase/tests/b39/modules.ts.
--
-- THE RULE. apple_status = 5 ends entitlement, whatever the dates say. A
-- transaction's revocation_date ALONE never does. When apple_status is absent
-- the existing date formula applies unchanged.
--
-- WHY THE STATUS AND NOT THE DATE. Apple's `status` is SUBSCRIPTION-level:
-- 5 = "The auto-renewable subscription is revoked. The App Store refunded the
-- transaction or revoked it from Family Sharing", current as of the signed
-- date, present for every auto-renewable notification and every
-- lastTransactions entry. revocation_date is TRANSACTION-level, and the
-- notification path stores the notification's own transaction -- a REFUND
-- notification can carry an EARLIER period while the subscription is active.
-- An upgrade sets neither (Apple sets isUpgraded and issues a new transaction).
--
-- THREE FUNCTIONS, AND ONLY THREE, DECIDE THE FORMULA. Everything else calls
-- them: membership_state, connected_member_self and every policy through
-- connected_member; membership_cleanup_authorised_v1 through connected_member;
-- the four cached visibility columns through membership_entitled_until.
-- CREATE OR REPLACE preserves every grant, so the privilege surface is
-- unchanged. No table, trigger, comment or grant is touched.

-- ============================================================ 1. the predicate
create or replace function public.connected_member(target_user_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $function$
  select coalesce(
    (select bool_or(
         m.environment = 'Production'
         -- B-39: a revoked subscription is never entitled. coalesce keeps the
         -- row expression strictly two-valued, so bool_or is NULL only when
         -- there are no rows at all.
         and coalesce(m.apple_status, 0) <> 5
         and (coalesce(m.renewal_date > now(), false)
              or coalesce(m.is_in_billing_retry
                          and m.grace_period_expires_date > now(), false))
       )
       from public.membership m
      where m.user_id = target_user_id),      -- NO environment filter here

    false
  );
$function$;

-- ===================================================== 2. the cached deadline
--
-- A revoked row contributes the instant access ENDED -- the revocation date,
-- or Apple's signed status instant when no revocation date was carried --
-- instead of its future renewal. Both are in the past, so every cached
-- visibility column stops conferring access the moment this is written, with
-- no worker and no clock.
create or replace function public.membership_entitled_until(target_user_id uuid)
  returns timestamptz
  language sql stable security definer set search_path = ''
as $$
  select max(case
           when m.apple_status = 5
             then coalesce(m.revocation_date, m.renewal_info_signed_date)
           else greatest(
                  m.renewal_date,
                  case when m.is_in_billing_retry then m.grace_period_expires_date end
                )
         end)
    from public.membership m
   where m.user_id = target_user_id
     and m.environment = 'Production';
$$;

-- ==================================================== 3. the canonical writer
--
-- Verbatim from 20260902130000_u7b_cleanup_primitive.sql except for the two
-- statements marked B-39: v_entitled gains the revoked conjunct, and a revoked
-- lapse ends at coalesce(v_revoked, v_signed) rather than at a future renewal.
-- Anti-sliding, the born-lapsed floor, F11, ordering and UPDATE-ONLY are
-- untouched.
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
  -- B-39: Apple's subscription-level status. 5 = revoked.
  v_status       smallint    := (p_state->>'apple_status')::smallint;
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
  --
  -- B-39: and a REVOKED subscription (status 5) is never entitled, whatever its
  -- dates say. A refund does not rewrite the expiry.
  v_entitled := coalesce(v_status, 0) <> 5
            and (coalesce(v_renewal > now(), false)
                 or coalesce(v_retry and v_grace > now(), false));

  if v_entitled then
    -- Resubscription, refund reversal or grace recovery CANCELS pending cleanup.
    -- QA C5 / G6c.
    v_ended   := null;
    v_cleanup := null;
  else
    -- The instant entitlement actually ended, preferring Apple's own dates over
    -- our clock so the 60 days is measured from the truth rather than from when
    -- we happened to hear about it. GREATEST ignores NULLs unless all are NULL.
    --
    -- B-39: a revoked subscription ended at its revocation, or at the instant
    -- Apple signed the revoked status -- NEVER at a future renewal date, which
    -- would push quarantine beyond the refund.
    if v_status = 5 then
      v_ended := coalesce(v_revoked, v_signed);
    else
      v_ended := coalesce(v_revoked, greatest(v_renewal, v_grace), now());
    end if;
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
