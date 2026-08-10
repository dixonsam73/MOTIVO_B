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

## Working rule

The audit register (`docs/audit-findings.md`) is **evidence, not the
implementation**. Every B-finding is verified against the deployed source
before any change is proposed — the same discipline applied to the client,
where it repeatedly changed the conclusion: C-13 was misfiled as benign,
C-19's mechanism dissolved on inspection, and an earlier P0 was retracted once
`pg_trigger` was actually read.
