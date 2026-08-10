# Supabase — backend source of truth

Filed as **B-17**: until this directory existed, the Edge Functions and schema
lived only in the hosted Supabase project. There was no diff, no review and no
rollback for the most irreversible paths in the system, and no way to check an
audit finding against the code it describes.

## The rule

**Structural only. Never data.**

Tracked here: Edge Function source, migrations, RLS policies, triggers, RPCs,
grants, and the schema definitions they depend on.

Never tracked: table contents, user rows, storage objects, JWTs, service-role
keys, `.env` files. A schema dump must be structure-only — `--data-only` and
any full dump that includes table contents would put real user content into git
permanently, where deleting it later does not remove it from history.

If you are unsure whether something is data, it is data. Leave it out.

## Why it sits beside the app

`supabase/` is a sibling of `MOTIVO/` so that a backend change and any client
change depending on it land in the same commit. It cannot affect the Xcode
build: the file-system synchronized groups are scoped to `MOTIVO`,
`MOTIVOTests` and `MOTIVOUITests`, so this directory is invisible to every
target.

## Deployment workflow

**This repository is authoritative for backend code.** The dashboard is for
reading and for emergencies, not for authoring.

### Edge Functions

Edit here, deploy from here:

```bash
supabase functions deploy delete_account_v1
```

Never edit a function in the dashboard. If one is ever edited there, the repo
is silently stale and the next deploy from Git will overwrite the change
without either version being reviewed. Before editing a function, re-download
it and confirm the diff is empty:

```bash
supabase functions download delete_account_v1 && git diff --stat supabase/functions
```

A non-empty diff means production drifted; resolve that before making changes.

### SQL

No migrations until Phase 3, which is a deliberate deferral — migration tooling
needs a local instance, and introducing that mid-Phase-1 would have been an
interruption rather than progress. Until then:

1. Write the change and get it reviewed **as a diff**, in a commit, before it
   is applied.
2. Apply it deliberately, one reviewed change at a time.
3. **Immediately** refresh the snapshot and commit the result:

```bash
./supabase/capture-schema.sh && git diff --stat supabase/schema
```

The snapshot diff is the only record of what changed in production before
Phase 3. If step 3 is skipped, the repository stops reflecting production and
the value of all of this evaporates.

### Never

Write experiments against production, even with synthetic values and a
`ROLLBACK`. A rolled-back transaction is still a write, and tooling that sends
statements as separate round trips will not roll it back at all. Where a
runtime proof is needed, it goes through the QA plan against real accounts —
see E8/E8b for the B-6 example.

## Working rule

The audit register (`docs/audit-findings.md`) is **evidence, not the
implementation**. Every B-finding is verified against the deployed source
before any change is proposed — the same discipline applied to the client,
where it repeatedly changed the conclusion: C-13 was misfiled as benign,
C-19's mechanism dissolved on inspection, and an earlier P0 was retracted once
`pg_trigger` was actually read.
