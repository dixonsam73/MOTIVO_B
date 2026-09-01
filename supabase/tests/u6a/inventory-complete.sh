#!/usr/bin/env bash
#
# U6a GATE, EXPERIMENT 2 (checker) — is docs/u6-enforcement-inventory.md ACTUALLY
# complete, or does it merely read as though it is?
#
# The inventory claims "if a surface is not in this file, U6 has not considered
# it". That claim is worthless unless it is checked against the catalog, so this
# script cross-references it BOTH WAYS: every live policy and client-reachable
# function must appear, and every name in the file must exist in the database.
# The second direction matters as much as the first -- a policy renamed out from
# under the inventory leaves a row describing something that is not there.
#
# LOCAL DISPOSABLE STACK ONLY. Read-only: this script creates and alters nothing.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u4/lib.sh

DOC=docs/u6-enforcement-inventory.md
FAIL=0

echo "=============================================================="
echo " U6a GATE 2 — enforcement inventory completeness"
echo "=============================================================="

echo
echo "-- direction 1: every LIVE policy appears in the inventory --"
MISSING=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if ! grep -q -- "\`$p\`" "$DOC"; then echo "  MISSING FROM DOC: policy $p"; MISSING=$((MISSING+1)); fi
done < <(psq "select policyname from pg_policies where schemaname in ('public','storage') order by 1")
echo "  live policies: $(psq "select count(*) from pg_policies where schemaname in ('public','storage')")   missing from doc: $MISSING"
[ "$MISSING" != "0" ] && FAIL=1

echo
echo "-- direction 2: every policy NAMED in the inventory still exists --"
STALE=0
for p in $(grep -o '^| `[a-z_0-9]*` |' "$DOC" | tr -d '|` '); do
  n=$(psq "select count(*) from pg_policies where policyname='$p'")
  if [ "$n" = "0" ]; then
    # Not a policy. Three other legitimate categories exist, and the first
    # revision of this checker knew only one of them -- it reported the four
    # EDGE FUNCTIONS in section 3 as stale, which was a defect in the CHECKER,
    # not in the inventory. A completeness check that does not model every
    # category it will meet manufactures failures.
    f=$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='$p'")
    if [ "$f" = "0" ]; then
      if [ -d "supabase/functions/$p" ]; then
        :   # an Edge Function, enumerated in section 3
      else
        echo "  STALE IN DOC (not a policy, SQL function or Edge Function): $p"; STALE=$((STALE+1))
      fi
    fi
  fi
done
echo "  stale names in doc: $STALE"
[ "$STALE" != "0" ] && FAIL=1

echo
echo "-- direction 3: every authenticated-EXECUTABLE function appears --"
FMISS=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if ! grep -q -- "\`$f" "$DOC"; then echo "  MISSING FROM DOC: function $f"; FMISS=$((FMISS+1)); fi
done < <(psq "select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
              where n.nspname='public'
                and has_function_privilege('authenticated', p.oid, 'EXECUTE')
              order by 1")
echo "  authenticated-executable fns: $(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('authenticated',p.oid,'EXECUTE')")   missing: $FMISS"
[ "$FMISS" != "0" ] && FAIL=1

echo
echo "-- direction 4: SECURITY DEFINER claims in the doc match the catalog --"
XBAD=0
for f in add_post_comment reply_to_commenter respond_to_commenters mark_post_comments_viewed \
         has_unread_private_comments follow_requests_open search_account_directory \
         get_account_directory_by_user_ids; do
  sd=$(psq "select p.prosecdef::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='$f' limit 1")
  [ "$sd" = "true" ] || { echo "  DOC SAYS SECURITY DEFINER, CATALOG SAYS '$sd': $f"; XBAD=$((XBAD+1)); }
done
echo "  secdef mismatches: $XBAD"
[ "$XBAD" != "0" ] && FAIL=1

echo
echo "-- direction 5: the doc's structural claims --"
BR=$(psq "select rolbypassrls::text from pg_roles where rolname='service_role'")
[ "$BR" = "true" ] && echo "  PASS  service_role bypassrls=true (no U6 policy can block deletion)" || { echo "  FAIL  service_role bypassrls=$BR"; FAIL=1; }
PC=$(psq "select count(*) from pg_policies where tablename='post_comments' and cmd in ('INSERT','UPDATE')")
[ "$PC" = "0" ] && echo "  PASS  post_comments has no INSERT/UPDATE policy (writes are SECURITY DEFINER only)" || { echo "  FAIL  post_comments INSERT/UPDATE policies = $PC"; FAIL=1; }
AD=$(psq "select count(*) from pg_policies where tablename='account_directory' and qual not like '%auth.uid()%'")
[ "$AD" = "0" ] && echo "  PASS  every account_directory policy is owner-scoped (discovery is not in RLS)" || { echo "  FAIL  non-owner-scoped account_directory policies = $AD"; FAIL=1; }
# UPDATED AT U6a: this read "zero policies consult connected_member (U6 has not
# begun)". U6a HAS begun, and the honest claim is narrower: no policy calls an
# ENTITLEMENT PREDICATE directly. The observer is reached instead, and it is
# inert. Leaving the old wording would have been a claim that quietly went stale.
EN=$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) ~ 'connected_member\(|membership_state\(|connected_member_self\('")
[ "$EN" = "0" ] && echo "  PASS  zero policies call an entitlement predicate directly (enforcement not bound)" || { echo "  FAIL  policies calling an entitlement predicate = $EN"; FAIL=1; }

echo
echo "-- direction 6: the OBSERVED set matches the inventory exactly --"
OBS=$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_gate%'")
TOT=$(psq "select count(*) from pg_policies where schemaname in ('public','storage')")
OPEN=$((TOT-OBS))
[ "$OBS" = "23" ] && echo "  PASS  23 policies observed" || { echo "  FAIL  observed policies = $OBS, inventory says 23"; FAIL=1; }
[ "$OPEN" = "10" ] && echo "  PASS  10 policies open" || { echo "  FAIL  open policies = $OPEN, inventory says 10"; FAIL=1; }
# The SECURITY DEFINER half -- policy work does not reach these, so a policy-only
# count would report two thirds of the surface as the whole.
FOBS=$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and p.proname<>'enforcement_gate' and pg_get_functiondef(p.oid) like '%enforcement_gate%'")
[ "$FOBS" = "9" ] && echo "  PASS  9 client-reachable functions observed" || { echo "  FAIL  observed functions = $FOBS, inventory says 9"; FAIL=1; }
# Storage policies specifically, since they are a separate schema and easy to miss.
SOBS=$(psq "select count(*) from pg_policies where schemaname='storage' and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_gate%'")
[ "$SOBS" = "7" ] && echo "  PASS  7 storage policies observed" || { echo "  FAIL  observed storage policies = $SOBS, inventory says 7"; FAIL=1; }
# Client-reachable Edge Functions: enumerated in section 3 as OUT of reach.
EF=$(ls -1 supabase/functions | grep -v '^_shared$' | grep -v '^deno' | wc -l | tr -d ' ')
[ "$EF" = "5" ] && echo "  PASS  5 Edge Functions enumerated and structurally out of policy reach" || { echo "  FAIL  Edge Function count = $EF, inventory enumerates 5"; FAIL=1; }

echo
echo "=============================================================="
[ "$FAIL" = "0" ] && echo " INVENTORY COMPLETE — both directions, all claims verified" \
                  || echo " INVENTORY INCOMPLETE — see above"
echo "=============================================================="
exit "$FAIL"
