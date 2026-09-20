#!/usr/bin/env python3
"""Builds the B-38 local proof: the EXACT apply and rollback bodies (the text between
their markers in the sibling SQL files, verbatim, with no transaction control) inside
ONE outer transaction that ends in ROLLBACK. Prints the sha256 of each extracted body.

  python3 supabase/sql/evidence/b38-local-proof-harness.py [output.sql]

The SQL files are resolved from this file's own location, so the script works from any
working directory; the output path may be a temporary file."""
import hashlib, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SQL = HERE.parent                      # supabase/sql
APPLY = SQL / "2026-09-20-b38-avatar-version-guard.sql"
ROLLBACK = SQL / "2026-09-20-b38-avatar-version-guard-rollback.sql"
# Output: argv[1] if given (e.g. a temp path), else beside this script.
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "b38-local-proof-run.sql"

def body(path, name):
    s = Path(path).read_text()
    m = re.search(r"-- >>> %s\n(.*?)-- <<< %s\n" % (name, name), s, re.S)
    assert m, name
    b = m.group(1)
    assert not re.search(r"^\s*(begin|commit|rollback)\s*;", b, re.I | re.M), "transaction control in body"
    return b
apply_b = body(APPLY, "B38 APPLY BODY")
roll_b = body(ROLLBACK, "B38 ROLLBACK BODY")
for n, b in (("apply body", apply_b), ("rollback body", roll_b)):
    print(n, hashlib.sha256(b.encode()).hexdigest())

U = {i: "'b3800000-0000-0000-0000-00000000000%d'" % i for i in range(1, 5)}
def claims(i):
    return ("select set_config('request.jwt.claim.sub', 'b3800000-0000-0000-0000-00000000000%d', true);\n"
            "select set_config('request.jwt.claims', '{\"sub\":\"b3800000-0000-0000-0000-00000000000%d\",\"role\":\"authenticated\"}', true);\n") % (i, i)
def as_client(i, sql):
    return "set local role authenticated;\n" + claims(i) + sql + "\nreset role;\n"
def fixture(i):
    # Transaction-local: bypass ONLY the guard to make the old value observably 2000.
    return ("alter table public.account_directory disable trigger tg_directory_avatar_guard;\n"
            "update public.account_directory set avatar_version = '2000-01-01T00:00:00Z' where user_id = %s;\n"
            "alter table public.account_directory enable trigger tg_directory_avatar_guard;\n"
            "select avatar_version::text as pre from public.account_directory where user_id = %s \\gset\n") % (U[i], U[i])
def result(step, cond, detail, i):
    return ("insert into b38_result select %s, %s, :'pre' || ' -> ' || %s from public.account_directory where user_id = %s;\n"
            % ("'" + step + "'", cond, detail, U[i]))
PRE2000 = ":'pre' = '2000-01-01 00:00:00+00'"
out = []
w = out.append
w("\\set ON_ERROR_STOP on\n")
w("select 'before' as phase, (select count(*) from auth.users) users, (select count(*) from public.account_directory) dir,\n"
  "  (select count(*) from pg_trigger where tgrelid='public.account_directory'::regclass and tgname='tg_directory_avatar_guard') guard_triggers,\n"
  "  (select count(*) from pg_proc where proname='tg_guard_avatar_version') guard_functions;\n")
w("begin;\n")
w("create temp table b38_pre as select\n"
  "  (select array_agg(privilege_type::text order by privilege_type) from information_schema.role_table_grants\n"
  "    where table_schema='public' and table_name='account_directory' and grantee='authenticated') as grants,\n"
  "  (select pg_get_triggerdef(oid) from pg_trigger where tgrelid='public.account_directory'::regclass and tgname='tg_directory_avatar_version') as stamp_def;\n")
w("create temp table b38_result(step text, pass boolean, detail text);\n")
w("insert into auth.users (id, aud, role, email) values\n" + ",\n".join(
  "  (%s,'authenticated','authenticated','b38-%d@example.invalid')" % (U[i], i) for i in range(1, 5)) + ";\n")
w("insert into public.account_privacy (user_id, age_band, lookup_enabled, lookup_set_under_band, follow_requests_enabled, follow_requests_set_under_band)\n"
  "  select id, 'band_18_plus', true, 'band_18_plus', true, 'band_18_plus' from auth.users where id in (%s);\n" % ",".join(U.values()))
w("insert into public.account_directory (user_id, display_name, avatar_key, avatar_version) values\n"
  "  (%s,'b38 one','users/u1/a.jpg','2000-01-01T00:00:00Z'), (%s,'b38 two','users/u2/a.jpg','2000-01-01T00:00:00Z');\n" % (U[1], U[2]))
# BASELINE (no guard)
w("select avatar_version::text as pre from public.account_directory where user_id = %s \\gset\n" % U[1])
w(as_client(1, "update public.account_directory set avatar_version = '2099-01-01T00:00:00Z' where user_id = %s;" % U[1]))
w(result("B0 BASELINE (no guard): direct write accepted, defect reproduced", "avatar_version = '2099-01-01T00:00:00Z'", "avatar_version::text", 1))
w("update public.account_directory set avatar_version = '2000-01-01T00:00:00Z' where user_id = %s;\n" % U[1])
# APPLY (verbatim body)
w("-- ===== EXACT APPLY BODY (extracted verbatim) =====\n" + apply_b + "-- ===== END APPLY BODY =====\n")
w(fixture(1)); w(as_client(1, "update public.account_directory set avatar_version = '2099-01-01T00:00:00Z' where user_id = %s;" % U[1]))
w(result("T1 owner direct write ignored", PRE2000 + " and avatar_version = '2000-01-01T00:00:00Z'", "avatar_version::text", 1))
w(fixture(1)); w(as_client(1, "update public.account_directory set display_name = 'b38 renamed' where user_id = %s;" % U[1]))
w(result("T2 neighbouring field updates; version unchanged", PRE2000 + " and display_name = 'b38 renamed' and avatar_version = '2000-01-01T00:00:00Z'", "display_name || ' ' || avatar_version", 1))
w(fixture(1)); w(as_client(1, "insert into public.account_directory (user_id, display_name, avatar_version) values (%s, 'b38 upsert', '2099-01-01T00:00:00Z') on conflict (user_id) do update set display_name = excluded.display_name, avatar_version = excluded.avatar_version;" % U[1]))
w(result("T3 client upsert carrying version: name applied, version kept", PRE2000 + " and display_name = 'b38 upsert' and avatar_version = '2000-01-01T00:00:00Z'", "display_name || ' ' || avatar_version", 1))
w(fixture(1)); w(as_client(1, "update public.account_directory set avatar_key = 'users/u1/b.jpg' where user_id = %s;" % U[1]))
w(result("T4 real avatar_key change re-stamps", PRE2000 + " and avatar_version = now()", "avatar_version::text", 1))
w(fixture(2)); w(as_client(2, "update public.account_directory set avatar_key = 'users/u2/a.jpg' where user_id = %s;" % U[2]))
w(result("T5 same-value avatar_key PATCH re-stamps", PRE2000 + " and avatar_version = now()", "avatar_version::text", 2))
w(fixture(2)); w("update public.account_directory set avatar_version = '2099-01-01T00:00:00Z' where user_id = %s;\n" % U[2])
w(result("T6 privileged (postgres) direct write also discarded", PRE2000 + " and avatar_version = '2000-01-01T00:00:00Z'", "avatar_version::text", 2))
w(fixture(2)); w(as_client(2, "update public.account_directory set avatar_key = 'users/u2/c.jpg', avatar_version = '2099-01-01T00:00:00Z' where user_id = %s;" % U[2]))
w(result("T7 key + version together: stamp wins", PRE2000 + " and avatar_version = now()", "avatar_version::text", 2))
w(fixture(2)); w("update public.account_directory set avatar_key = null where user_id = %s;\n" % U[2])
w(result("T8 cleanup writer clears avatar_key: re-stamps", PRE2000 + " and avatar_key is null and avatar_version = now()", "avatar_version::text", 2))
w(fixture(1)); w("update public.account_directory set entitled_until = '2001-01-01T00:00:00Z' where user_id = %s;\n" % U[1])
w(result("T9 entitled_until write: still derived; version unchanged", PRE2000 + " and entitled_until is distinct from '2001-01-01T00:00:00Z'::timestamptz and avatar_version = '2000-01-01T00:00:00Z'", "coalesce(entitled_until::text,'null') || ' ' || avatar_version", 1))
w("insert into public.account_directory (user_id, display_name, avatar_key, avatar_version) values (%s,'b38 three','users/u3/a.jpg','2099-01-01T00:00:00Z');\n" % U[3])
w("select 'n/a' as pre \\gset\n")
w(result("T10 INSERT (postgres) supplying version stores NULL", "avatar_version is null", "coalesce(avatar_version::text,'null')", 3))
w("savepoint client_insert;\n")
w(as_client(4, "insert into public.account_directory (user_id, display_name, avatar_version) values (%s,'b38 four','2099-01-01T00:00:00Z');" % U[4]))
w("select count(*) as t11_rows, coalesce(max(avatar_version)::text,'null') as t11_value from public.account_directory where user_id = %s \\gset\n" % U[4])
w("rollback to savepoint client_insert;\n")
w("insert into b38_result select 'T11 INSERT (client role, local gate open) stores NULL; rolled back to savepoint', :t11_rows = 1 and :'t11_value' = 'null', :'t11_value';\n")
# ROLLBACK (verbatim body)
w("-- ===== EXACT ROLLBACK BODY (extracted verbatim) =====\n" + roll_b + "-- ===== END ROLLBACK BODY =====\n")
w("insert into b38_result select 'R1 rollback restores grants and stamping trigger',\n"
  "  (select grants from b38_pre) is not distinct from (select array_agg(privilege_type::text order by privilege_type) from information_schema.role_table_grants where table_schema='public' and table_name='account_directory' and grantee='authenticated')\n"
  "  and (select stamp_def from b38_pre) is not distinct from (select pg_get_triggerdef(oid) from pg_trigger where tgrelid='public.account_directory'::regclass and tgname='tg_directory_avatar_version'), 'grants + stamp def';\n")
w("select avatar_version::text as pre from public.account_directory where user_id = %s \\gset\n" % U[1])
w(as_client(1, "update public.account_directory set avatar_version = '2099-01-01T00:00:00Z' where user_id = %s;" % U[1]))
w(result("R2 after rollback: original behaviour back (direct write accepted)", "avatar_version = '2099-01-01T00:00:00Z'", "avatar_version::text", 1))
w("select step, pass, detail from b38_result order by step;\n")
w("select case when bool_and(pass) and count(*) = 14 then 'ALL PASS (14)' else 'FAILURES' end as verdict from b38_result;\n")
w("rollback;\n")
w("select 'after' as phase, (select count(*) from auth.users) users, (select count(*) from public.account_directory) dir,\n"
  "  (select count(*) from pg_trigger where tgrelid='public.account_directory'::regclass and tgname='tg_directory_avatar_guard') guard_triggers,\n"
  "  (select count(*) from pg_proc where proname='tg_guard_avatar_version') guard_functions,\n"
  "  (select count(*) from auth.users where id::text like 'b3800000-%') synthetic_left;\n")
OUT.write_text("".join(out))
print("wrote", OUT)
