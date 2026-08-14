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

**`supabase functions deploy <name>` is NOT scoped to that one function's
deployment record.** Observed 2026-08-13, CLI 2.113.0: deploying only
`c44_exchange_probe` — a brand-new function, named explicitly on the command
line — also bumped `delete_account_v1` from version 6 to version 7. Its source
was verified byte-identical to the tree immediately afterwards by the download
check above, and `verify_jwt` was still `false`, so nothing about its behaviour
changed.

**The originally stated cause was wrong, and the correction matters more than
the observation.** This note first said the trigger was "almost certainly the new
`[functions.…]` block added to `config.toml`". **Deploying
`revoke_apple_identity_v1` on 2026-08-13 did the same thing — brand-new function,
new config block, named explicitly — and `delete_account_v1` stayed at version 7.**
So the config-block hypothesis is not supported.

The better hypothesis, still **unverified**: the 6→7 bump came from
`supabase secrets set`, which ran shortly before that deploy and not before this
one. Changing function environment plausibly requires re-versioning every
function that consumes it. Recorded as a hypothesis, not a finding.

The operational rule is unchanged and does not depend on knowing the cause:

Two consequences worth having in writing, because this is exactly the drift
class `config.toml` and B-17 exist to prevent:

1. **A version number is not evidence that code changed, and an unchanged
   version number is not evidence that it did not.** Only the download diff
   settles it. Run it after *every* deploy, not only before editing.
2. **Never assume a named deploy leaves its neighbours alone.** If a P0 function
   must not move, verify it explicitly after the deploy rather than reasoning
   from the command line you typed.

### Storage objects — two traps, both hit on 2026-08-13

**`supabase storage rm` SILENTLY DID NOTHING.** Observed clearing B-22 on CLI
2.113.0: the command exited **0** and printed `{"deleted":[],"buckets_deleted":[],"message":""}`
for an object that demonstrably existed — `supabase storage ls` listed it
immediately before and after, and `storage.objects` was unmoved. Re-running with
`--linked` changed nothing; `--debug` showed the CLI fetching
`/v1/projects/<ref>/api-keys` and then **issuing no DELETE request at all**.

So the failure is upstream of permissions, and its shape is the dangerous part:
an empty `deleted` array reads exactly like "nothing matched", and exit 0 reads
like success. **Never accept a storage deletion on the command's exit status.
Verify against `storage.objects` afterwards.** The working route is the Storage
REST API with the service-role key:

```bash
curl -s -w ' [HTTP %{http_code}]\n' -X DELETE \
  -H "Authorization: Bearer $KEY" \
  "https://<ref>.supabase.co/storage/v1/object/<bucket>/<path>"
```

Fetch `$KEY` into a shell variable in the same command
(`supabase projects api-keys --project-ref <ref> -o json`) and never echo it.

**And never delete a `storage.objects` row with SQL.** That row is an index over
S3, not the file. Deleting it removes the only pointer and leaves the bytes
behind — untracked residue in place of tracked residue, unreachable by every
policy path and invisible to the orphan sweep that would otherwise find it. Go
through the Storage API, which removes both.

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

### B-7 / B-10 drops — expected snapshot delta, written before applying (2026-08-14)

Committed ahead of the change so the diff is a binary check rather than a
reading of the aftermath. D14's rule, applied to DDL.

| Snapshot file | Before | After | Change |
|---|---|---|---|
| `functions` | 14 | **11** | −3: `sign_attachment_rpc`, `cleanup_post_attachments_on_delete`, `cleanup_post_attachments_on_update` |
| `function_grants` | 42 | **33** | −9: the same three × `anon` / `authenticated` / `service_role` |
| `policies` | 33 | **33** | none |
| `triggers` | 5 | **5** | none |
| `rls_enabled` | 7 | **7** | none |
| `constraints` | 24 | **24** | none |
| `columns` | 60 | **60** | none |
| `table_grants` | 102 | **102** | none |
| `column_grants` | 523 | **523** | none |
| `storage_buckets` | 2 | **2** | none |

**Nothing else may move.** No policy, trigger, column, constraint, RLS setting,
table or column privilege, or bucket configuration. **No storage object and no
application row is touched** — these are `DROP FUNCTION` statements and nothing
else; backend counts are re-read afterwards to confirm rather than assumed.

Both statements are `RESTRICT` by default. **If either fails on an unexpected
dependency, stop and report — do not reach for `CASCADE`.** A dependency we did
not predict means the analysis was wrong, and cascading would destroy whatever
it was rather than surfacing it.

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
