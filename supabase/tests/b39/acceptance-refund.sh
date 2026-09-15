#!/usr/bin/env bash
#
# B-39 (independent audit A1) — A REFUND OR REVOCATION BEFORE EXPIRY MUST END
# ENTITLEMENT. LOCAL ONLY. FAILING-FIRST.
#
#   supabase db reset --local && B39_PHASE=pre  ./supabase/tests/b39/acceptance-refund.sh
#   supabase db reset --local && B39_PHASE=post ./supabase/tests/b39/acceptance-refund.sh
#
# THE RULE (CLAUDE.md, "Quarantine" and "Subscription semantics"): refund and
# revocation end Connected access and start the same 60-day quarantine; a refund
# reversal restores access and cancels pending cleanup.
#
# THE DEFECT, measured at 3c68d81: connected_member(), membership_entitled_until()
# and membership_apply_state_v1's v_entitled evaluate Apple's DATE formula only.
# Apple does not rewrite expiresDate on a refund, and derive.ts prefers
# renewalInfo's renewalDate, so a refunded subscription keeps a FUTURE
# renewal_date and stays entitled until the original expiry.
#
# WHICH SIGNAL ENDS ACCESS — settled from Apple's reference, 2026-09-14, and
# CORRECTED FROM THIS FILE'S FIRST REVISION. That revision claimed an upgrade
# "revokes the superseded transaction (revocationDate set, isUpgraded)". FALSE:
# Apple sets `isUpgraded` and sends a NEW transaction, and does not set the
# cancellation/revocation date because of an upgrade (StoreKit Test `cancelDate`,
# "equivalent to revocationDate": "If the user upgrades … The system doesn't set
# cancelDate in this case"). revocationDate means refunded, or revoked from
# Family Sharing.
#
# The real hazard is TRANSACTION SELECTION, verified in source:
#   - reconciliation and the cleanup worker take the lastTransactions entry for
#     the originalTransactionId -- the lineage's latest transaction;
#   - the notification path stores the NOTIFICATION's transaction, and a REFUND
#     notification carries the refunded transaction, which may be an EARLIER
#     period while the subscription itself is still active.
# So a row's revocation_date can describe a transaction that is not the current
# one. Reconciliation is operator-invoked, not scheduled, so the notification
# path cannot simply defer to it.
#
# THE SIGNAL CHOSEN IS APPLE'S SUBSCRIPTION-LEVEL `status`, stored as
# apple_status. Apple: status 5 = "The auto-renewable subscription is revoked.
# The App Store refunded the transaction or revoked it from Family Sharing",
# current as of the notification's signedDate, present for every auto-renewable
# subscription notification and in every lastTransactions entry. So:
#   - apple_status = 5 ENDS entitlement, whatever the dates say;
#   - revocation_date ALONE never does (B39-P1: an older refunded period);
#   - an upgrade sets neither (B39-U1);
#   - status absent -> the existing date formula, unchanged (B39-N1).
#
# B39_PHASE selects the predicted failure set: `pre` against 3c68d81, `post`
# once the fix is applied (predicted: no failures). The tally scores observed
# failures against that set, so any deviation is visible.
#
# Identities are disjoint (…0000000b39xx), removed by explicit id on exit, and
# the enforcement flag is restored to whatever it was before the run.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e

PASS=0; FAIL=0; FAILED_IDS=""
ok()  { printf "  \033[32mPASS\033[0m  %-8s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-8s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); FAILED_IDS="$FAILED_IDS $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

case "${B39_PHASE:-pre}" in
  pre)  PRED_FAIL="B39-R2 B39-R3 B39-R4 B39-R5 B39-R6 B39-R7 B39-R8 B39-R9 B39-E1 B39-E2 B39-V1 B39-M1 B39-M2 B39-M3 B39-S1 B39-S2 B39-S3" ;;
  post) PRED_FAIL="" ;;
  *) echo "B39_PHASE must be pre or post"; exit 2 ;;
esac

echo; echo "B-39 / A1 — refund and revocation before expiry (phase ${B39_PHASE:-pre})"; echo

V_ENT=00000000-0000-0000-0000-0000000b3901   # entitled viewer
R_REF=00000000-0000-0000-0000-0000000b3902   # refunded, status 5, future expiry
R_REV=00000000-0000-0000-0000-0000000b3903   # refunded, then refund REVERSED
R_MIX=00000000-0000-0000-0000-0000000b3904   # Production refunded + Sandbox live
R_MX2=00000000-0000-0000-0000-0000000b3905   # Production live + Sandbox refunded
R_ORD=00000000-0000-0000-0000-0000000b3906   # ordinary lapse (control)
R_OLD=00000000-0000-0000-0000-0000000b3907   # an EARLIER period refunded; subscription active
R_UPG=00000000-0000-0000-0000-0000000b3908   # upgrade: isUpgraded, new transaction, no revocation
R_NUL=00000000-0000-0000-0000-0000000b3909   # status absent, revocation date present
R_S5=00000000-0000-0000-0000-0000000b390a    # status 5 with NO revocation date
ALL="'$V_ENT','$R_REF','$R_REV','$R_MIX','$R_MX2','$R_ORD','$R_OLD','$R_UPG','$R_NUL','$R_S5'"

ORIG_FLAG=$(psq "select enforcement_enabled::text from public.membership_control;")
cleanup() {
  psq "update public.membership_control set enforcement_enabled=$ORIG_FLAG where id;" >/dev/null
  psqf <<SQL >/dev/null
delete from public.follows where follower_user_id in ($ALL) or followed_user_id in ($ALL);
delete from public.posts where owner_user_id in ($ALL);
delete from public.membership where user_id in ($ALL);
delete from public.membership_binding where user_id in ($ALL);
delete from auth.users where id in ($ALL);
SQL
}
trap cleanup EXIT
cleanup   # a previous interrupted run must not leave rows that change these counts

mkid() { psq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at) values ('$1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$2@local.invalid',now(),now()) on conflict do nothing;" >/dev/null
         psq "insert into public.membership_binding (user_id) values ('$1') on conflict do nothing;" >/dev/null; }
for p in "$V_ENT vent" "$R_REF ref" "$R_REV rev" "$R_MIX mix" "$R_MX2 mx2" "$R_ORD ord" "$R_OLD old" "$R_UPG upg" "$R_NUL nul" "$R_S5 s5"; do set -- $p; mkid "$1" "b39-$2"; done

# Every row starts ENTITLED with an older signed date, exactly as a live member's would.
seedrow() { psq "insert into public.membership (user_id,environment,original_transaction_id,product_id,apple_status,renewal_date,is_in_billing_retry,renewal_info_signed_date,binding_method,bound_at) values ('$1','$2','b39-$1-$2','p',1, now()+interval '20 days', false, now()-interval '1 day','purchase',now());" >/dev/null; }
seedrow "$V_ENT" Production; seedrow "$R_REF" Production; seedrow "$R_REV" Production
seedrow "$R_MIX" Production; seedrow "$R_MIX" Sandbox
seedrow "$R_MX2" Production; seedrow "$R_MX2" Sandbox
seedrow "$R_ORD" Production; seedrow "$R_OLD" Production; seedrow "$R_UPG" Production
seedrow "$R_NUL" Production; seedrow "$R_S5" Production

psqf <<SQL >/dev/null
insert into public.posts (id,owner_user_id,is_public,created_at,attachments)
select gen_random_uuid(),'$R_REF',true,now(),'[]'::jsonb from generate_series(1,2);
insert into public.follows (follower_user_id,followed_user_id,status,created_at,updated_at)
values ('$V_ENT','$R_REF','approved',now(),now());
SQL

# \$1 uid  \$2 env  \$3 apple_status|null  \$4 renewal sql  \$5 revocation sql|null  \$6 signed sql  [\$7 product]
apply() { psq "select public.membership_apply_state_v1('$1','$2','b39-$1-$2', jsonb_build_object('product_id','${7:-p}','apple_status',$3,'renewal_date',($4)::text,'is_in_billing_retry',false,'revocation_date',$5,'renewal_info_signed_date',($6)::text));" | tail -1; }
REVOKED="(now() - interval '2 hours')::text"
cm()    { psq "select public.connected_member('$1')::text;"; }
ms()    { psq "select public.membership_state('$1');"; }
eu()    { psq "select coalesce(public.membership_entitled_until('$1') > now(), false)::text;"; }
row()   { psq "select $3 from public.membership where user_id='$1' and environment='$2';"; }
seen()  { psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); select count(*) from $2;" | tail -1; }
gate()  { psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); select public.enforcement_gate('probe')::text;" | tail -1; }

echo "— controls: the harness must see an ordinary lapse and a live member correctly"
OUT=$(apply "$R_ORD" Production 2 "now() - interval '1 hour'" null "now()")
is B39-C0a "$(printf '%s' "$OUT" | jq -r .entitled)" "false" "ordinary lapse is not entitled"
is B39-C0b "$(row "$R_ORD" Production "coalesce(pending_cleanup_at = renewal_date + interval '60 days', false)::text")" "true" "ordinary lapse schedules renewal + 60 days"
is B39-C1a "$(cm "$R_REF")" "true" "before the refund the author is a member"
is B39-C1b "$(psq "select count(*) from public.posts where owner_user_id='$R_REF' and owner_entitled_until > now();")" "2" "before the refund the author's posts carry a future deadline"

echo "— refund before expiry: status 5, revocation 2h ago, expiry still 20 days away"
OUT=$(apply "$R_REF" Production 5 "now() + interval '20 days'" "$REVOKED" "now()")
is B39-R1  "$(printf '%s' "$OUT" | jq -r .outcome)"  "applied" "the writer applies the refund"
is B39-R2  "$(printf '%s' "$OUT" | jq -r .entitled)" "false"   "a revoked subscription is NOT entitled"
is B39-R3  "$(cm "$R_REF")" "false"   "connected_member() ends at the refund"
is B39-R4  "$(ms "$R_REF")" "expired" "membership_state() reports the refund as expired"
is B39-R5  "$(eu "$R_REF")" "false"   "membership_entitled_until() is not in the future"
is B39-R6  "$(psq "select count(*) from public.posts where owner_user_id='$R_REF' and owner_entitled_until > now();")" "0" "cached post deadlines stop conferring visibility"
is B39-R7  "$(psq "select count(*) from public.follows where followed_user_id='$R_REF' and followed_entitled_until > now();")" "0" "cached follow deadlines stop conferring visibility"
is B39-R8  "$(row "$R_REF" Production "coalesce(entitlement_ended_at = revocation_date, false)::text")" "true" "entitlement_ended_at is the revocation instant"
is B39-R9  "$(row "$R_REF" Production "coalesce(pending_cleanup_at = revocation_date + interval '60 days', false)::text")" "true" "quarantine is revocation + 60 days, never shortened"
is B39-R10 "$(row "$R_REF" Production "(revocation_date is not null)::text")" "true" "the revocation date itself is stored"

echo "— under enforcement"
psq "update public.membership_control set enforcement_enabled=true where id;" >/dev/null
is B39-E0 "$(gate "$V_ENT")" "true"  "control: the entitled viewer is granted"
is B39-E1 "$(gate "$R_REF")" "false" "the refunded member is denied"
is B39-E2 "$(seen "$V_ENT" "public.posts where owner_user_id='$R_REF'")" "0" "an entitled follower no longer sees the refunded author's posts"
psq "update public.membership_control set enforcement_enabled=$ORIG_FLAG where id;" >/dev/null

echo "— refund, then REFUND_REVERSED"
apply "$R_REV" Production 5 "now() + interval '20 days'" "$REVOKED" "now()" >/dev/null
is B39-V1 "$(row "$R_REV" Production "(pending_cleanup_at is not null)::text")" "true" "the refund scheduled quarantine (so the reversal below is not vacuous)"
OUT=$(apply "$R_REV" Production 1 "now() + interval '20 days'" null "now() + interval '1 hour'")
is B39-V2 "$(printf '%s' "$OUT" | jq -r .entitled)" "true" "the reversal restores entitlement"
is B39-V3 "$(row "$R_REV" Production "(pending_cleanup_at is null and entitlement_ended_at is null)::text")" "true" "the reversal cancels pending cleanup"
is B39-V4 "$(cm "$R_REV")" "true" "connected_member() is restored"
is B39-V5 "$(eu "$R_REV")" "true" "the cached deadline is in the future again"

echo "— multiple membership rows"
apply "$R_MIX" Production 5 "now() + interval '20 days'" "$REVOKED" "now()" >/dev/null
is B39-M1 "$(cm "$R_MIX")" "false"   "a live SANDBOX row cannot rescue a refunded Production row"
is B39-M2 "$(ms "$R_MIX")" "expired" "state is expired, not sandbox_only"
is B39-M3 "$(eu "$R_MIX")" "false"   "the cached deadline ignores the Sandbox row"
is B39-M4 "$(row "$R_MIX" Sandbox "(pending_cleanup_at is null and revocation_date is null)::text")" "true" "the Sandbox row is untouched"
apply "$R_MX2" Sandbox 5 "now() + interval '20 days'" "$REVOKED" "now()" >/dev/null
is B39-M5 "$(cm "$R_MX2")" "true" "control: a refunded SANDBOX row does not deny a live Production member"
is B39-M6 "$(row "$R_MX2" Production "(pending_cleanup_at is null)::text")" "true" "control: the Production row schedules nothing"

echo "— which signal ends access (the rule-choice discriminators)"
OUT=$(apply "$R_OLD" Production 1 "now() + interval '20 days'" "(now() - interval '30 days')::text" "now()")
is B39-P1 "$(printf '%s' "$OUT" | jq -r .entitled)" "true" "an EARLIER period's refund (status 1) does not end the active subscription"
is B39-P2 "$(row "$R_OLD" Production "(pending_cleanup_at is null)::text")" "true" "...and schedules nothing"
OUT=$(apply "$R_UPG" Production 1 "now() + interval '300 days'" null "now()" "p-annual")
is B39-U1 "$(printf '%s' "$OUT" | jq -r .entitled)" "true" "an upgrade (new transaction, no revocation) stays entitled"
OUT=$(apply "$R_NUL" Production null "now() + interval '20 days'" "$REVOKED" "now()")
is B39-N1 "$(printf '%s' "$OUT" | jq -r .entitled)" "true" "status absent: the date formula applies; revocation_date alone never ends access"
OUT=$(apply "$R_S5" Production 5 "now() + interval '20 days'" null "now()")
is B39-S1 "$(printf '%s' "$OUT" | jq -r .entitled)" "false" "status 5 ends access even with no revocation date"
is B39-S2 "$(row "$R_S5" Production "coalesce(entitlement_ended_at = renewal_info_signed_date, false)::text")" "true" "...ending at Apple's signed status instant"
is B39-S3 "$(row "$R_S5" Production "coalesce(pending_cleanup_at = renewal_info_signed_date + interval '60 days', false)::text")" "true" "...with quarantine from that instant"

echo
echo "B-39 tally: $PASS passed, $FAIL failed"
OBS=$(printf '%s\n' $FAILED_IDS | sort | tr '\n' ' ')
PRD=$(printf '%s\n' $PRED_FAIL  | sort | tr '\n' ' ')
if [ "$OBS" = "$PRD" ]; then
  echo "PREDICTION MATCHED (phase ${B39_PHASE:-pre}): failures are exactly the predicted set"
  exit 0
else
  echo "PREDICTION DEVIATION (phase ${B39_PHASE:-pre})"
  echo "  predicted: $PRD"
  echo "  observed:  $OBS"
  exit 1
fi
