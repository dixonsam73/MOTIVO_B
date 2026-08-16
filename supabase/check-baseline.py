#!/usr/bin/env python3
"""B-23 fidelity gate — the comparison half.

Compares a local structural capture against supabase/schema/ (observed
production truth) across all ten surfaces.

THE CRITERION, stated so it cannot drift into "close enough":

  1. Every surface that CAN be reproduced byte-identically MUST be
     byte-identical.
  2. A catalog-serialization exception is permissible only where it is
     individually demonstrated to be PostgreSQL normalization or catalog
     history rather than a semantic or schema difference, and only where it is
     declared in supabase/baseline-exceptions.json.
  3. Every declared exception is still DETECTED here and verified to be
     exactly the approved difference — the production value, the local value
     and the identified row must all match what was approved.
  4. Anything else fails: a new difference, a changed difference, a difference
     in a file with no exceptions, or a declared exception that no longer
     appears (a stale allowlist is a failure, not a pass).

This is deliberately not a normalizer. It never rewrites either side to make
them compare equal; it compares them exactly and then checks the residue
against a narrow, evidenced allowlist.
"""

import json
import os
import sys

FILES = ["functions", "policies", "rls_enabled", "triggers", "constraints",
         "columns", "function_grants", "table_grants", "column_grants",
         "storage_buckets"]

# How to identify a row within each surface, so a difference can be named
# rather than reported as "line 23". Surfaces absent here are compared as
# whole documents and may not carry exceptions.
KEYS = {
    "constraints": ("table_name", "conname"),
    "functions": ("proname",),
    "policies": ("schemaname", "tablename", "policyname"),
    "triggers": ("on_table", "tgname"),
    "rls_enabled": ("table_name",),
    "columns": ("table_name", "column_name"),
    "function_grants": ("proname", "grantee"),
    "table_grants": ("table_name", "grantee", "privilege_type"),
    "column_grants": ("table_name", "column_name", "grantee", "privilege_type"),
    "storage_buckets": ("id",),
}


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def keyed(rows, fields):
    out = {}
    for r in rows:
        out[tuple(str(r.get(f)) for f in fields)] = r
    return out


def main():
    if len(sys.argv) != 2:
        print("usage: check-baseline.py <local-capture-dir>", file=sys.stderr)
        return 2

    local_dir = sys.argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    prod_dir = os.path.join(root, "supabase", "schema")
    exc_path = os.path.join(root, "supabase", "baseline-exceptions.json")

    approved = []
    if os.path.exists(exc_path):
        approved = load(exc_path).get("exceptions", [])

    # Index approved exceptions by (file, identifying key tuple).
    approved_index = {}
    for e in approved:
        fields = KEYS[e["file"]]
        k = tuple(str(e["key"][f]) for f in fields)
        approved_index[(e["file"], k)] = e

    failures = []
    matched_exceptions = set()
    surface_status = []

    for f in FILES:
        p_path = os.path.join(prod_dir, f + ".json")
        l_path = os.path.join(local_dir, f + ".json")
        if not os.path.exists(l_path):
            failures.append("%s: local capture missing" % f)
            surface_status.append((f, "MISSING"))
            continue

        prod_raw = open(p_path, encoding="utf-8").read()
        local_raw = open(l_path, encoding="utf-8").read()
        if prod_raw == local_raw:
            surface_status.append((f, "IDENTICAL"))
            continue

        prod, local = load(p_path), load(l_path)
        fields = KEYS.get(f)
        if fields is None:
            failures.append("%s: differs and carries no row key" % f)
            surface_status.append((f, "DIFFERS"))
            continue

        pk, lk = keyed(prod, fields), keyed(local, fields)

        for k in sorted(set(pk) | set(lk)):
            if k not in lk:
                failures.append("%s %s: present in production, absent locally" % (f, "/".join(k)))
                continue
            if k not in pk:
                failures.append("%s %s: present locally, absent in production" % (f, "/".join(k)))
                continue
            if pk[k] == lk[k]:
                continue

            e = approved_index.get((f, k))
            if e is None:
                differing = [c for c in pk[k] if pk[k].get(c) != lk[k].get(c)]
                failures.append(
                    "%s %s: UNAPPROVED difference in %s" % (f, "/".join(k), ", ".join(differing)))
                continue

            # Approved — but verify it is EXACTLY the approved difference.
            field = e["field"]
            differing = [c for c in pk[k] if pk[k].get(c) != lk[k].get(c)]
            if differing != [field]:
                failures.append(
                    "%s %s: approved exception covers %r but the difference is in %s"
                    % (f, "/".join(k), field, ", ".join(differing)))
                continue
            if pk[k][field] != e["production"]:
                failures.append(
                    "%s %s: PRODUCTION value changed since the exception was approved"
                    % (f, "/".join(k)))
                continue
            if lk[k][field] != e["local"]:
                failures.append(
                    "%s %s: LOCAL value changed since the exception was approved"
                    % (f, "/".join(k)))
                continue
            matched_exceptions.add((f, k))

        surface_status.append((f, "DIFFERS"))

    # A declared exception that no longer appears means the allowlist is stale.
    for key, e in approved_index.items():
        if key not in matched_exceptions:
            failures.append(
                "%s %s: approved exception NO LONGER APPEARS — the allowlist is stale "
                "and must be re-reviewed, not left in place" % (key[0], "/".join(key[1])))

    print("B-23 fidelity gate — local baseline vs supabase/schema/")
    print()
    for f, st in surface_status:
        note = ""
        if st == "DIFFERS":
            n = len([1 for (ff, _kk) in matched_exceptions if ff == f])
            if n:
                note = "  (%d approved catalog-serialization exception%s, verified)" % (
                    n, "" if n == 1 else "s")
        print("  %-18s %s%s" % (f, st, note))

    print()
    if failures:
        print("GATE NOT MET — %d problem%s:" % (len(failures), "" if len(failures) == 1 else "s"))
        for m in failures:
            print("  - %s" % m)
        return 1

    if matched_exceptions:
        print("GATE MET, with %d approved and mechanically verified exception%s:"
              % (len(matched_exceptions), "" if len(matched_exceptions) == 1 else "s"))
        for f, k in sorted(matched_exceptions):
            e = approved_index[(f, k)]
            print("  - %s %s (%s)" % (f, "/".join(k), e["class"]))
            print("    %s" % e["equivalence"])
    else:
        print("GATE MET. All ten surfaces byte-identical.")

    print()
    print("This is NOT production verification — see supabase/README.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
