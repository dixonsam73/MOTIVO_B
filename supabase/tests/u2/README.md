# U2 — backend verification harness

**Local and disposable only.** Every endpoint here is `127.0.0.1`. Nothing in
this directory can reach production, and nothing in it is applied to production.

Discharged B-4, B-12, B-13 and B-9's two-recipient subcase on 2026-08-16 against
the B-23 reproduction. Predictions were committed at `ca697ec` **before** any
destructive run; results are in `docs/qa-plan.md` under "U2 — RESULTS".

## Why this exists at all

These four obligations had been blocked since 2026-08-11 for want of an
environment where a destructive or fault-injecting experiment is free. Two of
them were unstageable on production by construction:

- **B-9's two-recipient subcase** needs a sender plus two *distinct* recipients.
  Sign in with Apple cannot use sandbox testers, so the rig has two real Apple
  IDs by hard constraint. Here they are three local GoTrue users and cost
  nothing.
- **B-12** needs >1000 objects under one prefix, which on production means bulk
  junk in a live bucket and depending on a deletion path to remove it.

## The fault-injection route, and why it is not one of the three declined

Phase 1 declined three routes and they stay declined: a temporarily-broken
production deploy, QA-only failure injection inside the function, and DDL
against production. This is a fourth — **DDL against a disposable local
database** — which only became possible once B-23 existed.

It cannot alter production behaviour:

- `delete_account_v1`'s source is **not touched**. The function under test is
  the real one.
- `fault-inject.sql` is applied by hand and is deliberately **not** in
  `supabase/migrations/`, so no reproduction of the baseline contains it — the
  B-23 gate fails on an extra trigger if it ever does.

## Files

| | |
|---|---|
| `lib.sh` | Shared helpers. **Credentials are loaded dynamically from `supabase status -o json`** and never written down. No hard-coded JWT and no fallback: if the stack is not running it fails loudly, and it **refuses to run unless `API_URL` is localhost**, so the tooling cannot be pointed at a hosted project even if configuration drifts |
| `fixture.sh` | Fixture 1 — A/B/C for B-4, B-13 and B-9's subcase. Asserts its own inventory, because an empty fixture is not a pass |
| `fixture-b12.sh` | Fixture 2 — 1500 objects under **one** prefix, plus a protected bystander |
| `fault-inject.sql` / `fault-remove.sql` | The named B-4 fault and its removal |
| `inspect.sh` | Reads resulting state directly. A command result is not a pass; the state is |

## Running

```bash
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
supabase start
supabase functions serve --env-file supabase/.env &   # see below
supabase db reset --local
./supabase/verify-baseline.sh                          # B-23 gate must pass first
./supabase/tests/u2/fixture.sh
```

**`supabase/.env` is required and is gitignored.** The local edge runtime
provides `SUPABASE_SERVICE_ROLE_KEY` but the function reads `SERVICE_ROLE_KEY`,
which production supplies as a secret. Generate it rather than pasting a key:

```bash
printf 'SERVICE_ROLE_KEY=%s\n' \
  "$(supabase status -o json | jq -r .SERVICE_ROLE_KEY)" > supabase/.env
```

This is local configuration standing in for a production secret — **not** a
change to the function.

`[edge_runtime.secrets]` in `config.toml` does **not** work at CLI 2.113.0; the
container environment shows the variable absent. `supabase functions serve
--env-file` is the route that does.

## Rules that hold here

- An empty or vacuous fixture is not a pass.
- A command exit status is not a pass. Verify the resulting state.
- Everything verified here is **"verified against a faithful local
  reproduction"**, never "verified in production".
- Any change to `delete_account_v1` invalidates these results.
