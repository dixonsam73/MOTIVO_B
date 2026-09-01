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

**NEVER RUN `supabase db push` AGAINST PRODUCTION. IT WOULD REPLAY EVERY
MIGRATION, INCLUDING THE LOCAL BASELINE REPRODUCTION.**

Discovered 2026-08-23 by a dry run at U5g's pre-flight, before any mutation:

```
$ supabase db push --dry-run
Would push these migrations:
 • 20260816000000_baseline_production_reproduction.sql   <-- LOCAL-ONLY
 • 20260816120000_u3_membership_schema.sql               <-- ALREADY DEPLOYED
 • 20260820120000_u4_ingestion.sql                       <-- ALREADY DEPLOYED
 • 20260823120000_u5b_establishment.sql                  <-- the only new one
```

Production's `supabase_migrations.schema_migrations` records **none** of them,
because U3 and U4 were applied directly by the account holder as atomic
transactions, and the baseline migration exists **only** to rebuild a local
reproduction — it must never touch production at all.

At best `db push` fails partway on objects that already exist, leaving the
migration history half-written. At worst the baseline reproduction executes
against the live database. Neither is recoverable by re-running.

**The mechanism is unchanged and is the one U3 and U4 used:** the account holder
applies the single new migration file verbatim, wrapped in `BEGIN; … COMMIT;`,
in the SQL editor or `psql`. `supabase/sql/README-u5-deployment.md` §3.1 is the
worked example.

**This is recorded here rather than only in the U5 package because `db push` is
the obvious command to reach for**, and the next person to deploy — at U6 or U7 —
will not necessarily have read a unit-specific file first.

### `supabase db query` IS NOT AN ESCAPE HATCH — it is SINGLE-STATEMENT ONLY

**Measured 2026-09-01 at the U6a pre-flight, because the U5 package's flat claim
that there is "no arbitrary-SQL CLI path" is not quite what is true, and the gap
between the two readings is where somebody improvises.**

`supabase db query --linked` **does** work, and it is how `capture-schema.sh`
reads production. Its role, `cli_login_postgres`, is a member of `postgres` and
therefore holds write as well as read. So the honest statement is not "there is
no path" — it is this:

```
$ supabase db query --local "create table public._probe(x int); select 1/0;"
{"error":{"code":"LegacyDbQueryExecError",
  "message":"failed to execute query: error: cannot insert multiple commands
             into a prepared statement"}}
```

**It refuses more than one statement.** Enough for the ten read-only structural
queries, each of which is one `select`; **not** enough for a migration, a
rollback baseline, or anything wrapped in `BEGIN; … COMMIT;`.

**Do not work around this by folding a migration into one `DO $$ … $$` block.**
It would mean editing the file to make the mechanism accept it, which is the one
thing every deployment procedure in this repository forbids, and nesting
`$function$` bodies inside `$$` is a quoting hazard with no upside.

**The conclusion is the same as `db push`'s and the reason is different, which is
why both are written down.** Multi-statement production SQL goes through the
account holder in the SQL editor.

Never edit a function in the dashboard. If one is ever edited there, the repo
is silently stale and the next deploy from Git will overwrite the change
without either version being reviewed. Before editing a function, re-download
it and confirm the diff is empty:

```bash
supabase functions download delete_account_v1 && git diff --stat supabase/functions
```

**THAT CHECK AS WRITTEN CANNOT PASS AT CLI 2.113.0, AND THE CORRECTION MATTERS
MORE THAN THE OBSERVATION — recorded 2026-08-20 during U4h's P1.**
`supabase functions download` returns the **transpiled** function, not the
source: TypeScript annotations are stripped (`readonly step: string` becomes a
plain assignment, `(req) =>` becomes `(req)=>`) and multi-line call chains are
rejoined onto one line. **Comments and string literals ARE preserved.** So
`git diff` is never empty for a TypeScript function, and a naive reading of a
non-empty diff as "production drifted" would be wrong every time.

**The working form of the check, which is what P1 actually ran:**

1. Copy the tree file aside, download, then `git checkout --` to restore it.
   The download **overwrites the tree**, and leaving transpiled JS in place
   would be far worse than the drift it was looking for.
2. Compare **comment text** and **string literals** directly — both survive.
3. Compare executable token counts **with comments stripped and whitespace
   collapsed**. Line-based grep is not sufficient: `admin.storage\n.from(x)\n.list(...)`
   in the tree is one line in the transpiled output, and counting the literal
   `storage.from` made three identical call sites look like one. That produced a
   false "executable difference" during P1 and was resolved by looking at the
   call sites rather than by explaining the count.
4. **Use an unmodified function as the control.** `revoke_apple_identity_v1` has
   never been redeployed since v1, so every difference it shows is transpilation
   by definition. At P1 it showed **zero** token differences and byte-identical
   comments — which is what licenses reading the same shape of difference in
   `delete_account_v1` as transpilation rather than drift.

A difference that survives all four steps means production drifted; resolve that
before making changes.

**KNOWN, DELIBERATE DIVERGENCE AS OF 2026-08-14 — `delete_account_v1`, COMMENTS
ONLY.** The download check above will report a non-empty diff for this function,
and it is **not** drift. A stale comment block was corrected in the tree: it
described the pre-2026-08-13 retention rule and explicitly instructed the reader
not to add a `post_comments` statement, twenty lines above the `author_user_id`
statement the revised rule requires. Deployed **v7 is byte-identical to the tree
apart from that comment**, verified by stripping comments and blank lines from
both and diffing: the executable body is identical. **The correction has NOT been
deployed**, because deploying it would mean shipping a change to the P0 deletion
path for a comment, and the deploy is not scoped to one function (see below).
**Fold it into the next legitimate deploy of this function**, and re-run the
download check afterwards to return the diff to empty. Until then, read the tree
for intent and remember that the running code is the same code.

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

### CLI options that print database credentials — observed 2026-08-16

**Do not run `supabase db dump --dry-run`.** At CLI **2.113.0** it prints the
generated `PGPASSWORD` in cleartext as part of the shell script it would have
executed. Treat `--debug` the same way wherever it would surface generated
connection credentials. There is no flag to suppress it; the only safe answer is
not to run those forms.

**This is recorded as behaviour observed with the currently installed tooling,
not as a claim about every Supabase CLI version.** Re-check before assuming a
later release behaves the same way — in either direction.

**What was actually exposed, established read-only rather than assumed.** During
U1 a dry-run printed a credential for the role **`cli_login_postgres`** — the
role the CLI mints for itself, announced by the *“Initialising login role…”*
line before every `--linked` command.

| | |
|---|---|
| **Privilege while valid** | Powerful. It is a member of `postgres`, so it inherits `bypassrls` and `createrole` — full read and write with row-level security bypassed |
| **Validity** | **Ephemeral, roughly a five-minute rolling window.** `rolvaliduntil` was observed advancing to `now() + ~4m59s` on every CLI invocation, twice, two seconds apart |
| **What it is not** | **Not the persistent project database password.** That belongs to the `postgres` role and was never printed |
| **Status** | **Expired.** The window closed minutes after it was printed |
| **Runtime dependencies** | **None.** No Postgres connection string exists in the app, either Edge Function, `config.toml` or this file. The app uses `SUPABASE_URL` + `SUPABASE_ANON_KEY`; the functions use `SERVICE_ROLE_KEY` and the `APPLE_*` secrets |

**Rotating the project database password would rotate a different credential and
is not required for this incident.** It would address the `postgres` role, which
was not exposed, and would leave the ephemeral role untouched — it is not ours to
rotate, being minted and expired by the CLI.

One limit worth stating rather than glossing: whether the CLI re-sets that role's
*password* on each invocation, or only extends its validity, is **not
observable** at this privilege level — `pg_authid.rolpassword` is not readable.
It does not change the conclusion, since the printed value is past its
`rolvaliduntil` either way, but it is the difference between “rotated many times
since” and “expired once”, and only the weaker claim is supported.

**Verify, do not test by connecting.** Confirming the window is closed is a
read of `rolvaliduntil` against `now()`. Re-using the exposed value to see
whether it still works would itself be use of an exposed credential.

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

**Phase 3 U1 / B-23 introduces migrations and a local instance.** The deferral
recorded here since Phase 1 is discharged as a decision at U0; the operating
instructions land with U1, which is the unit that builds it.

**Two things are now tracked, and confusing them defeats the point:**

| | What it is | Authority for |
|---|---|---|
| `supabase/schema/` | A **structural snapshot** — what production *looks like*, captured after the fact | **Observed truth.** The comparison authority the baseline is measured against |
| `supabase/migrations/` | **Committed migrations** — a definition the backend can be *rebuilt from* | **Reproducible source.** What the local instance is built from |

**Local verification is NOT production verification, and the distinction is
load-bearing rather than pedantic.** A faithful local reproduction runs the same
software; it is not the same deployment. Storage-listing semantics, PostgREST
error shapes and the exact response to a delete of a missing object are all
things this project has already been caught assuming — C-33's cell says so in as
many words. Anything verified locally is recorded as **"verified against a
faithful local reproduction"**, never as "verified in production", and the
residual gap is stated rather than glossed.

**Production is not re-based onto the migration history.** B-23 delivers a
faithful reproduction; production remains exactly as it is. Applying migrations
to production is explicitly out of scope.

The applied-change workflow below is unchanged and still governs production:

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

## Local backend (Phase 3 U1 / B-23)

**Purpose: an environment where a destructive or fault-injecting experiment is
free.** B-4, B-12, B-13 and B-9's two-recipient subcase have been blocked since
2026-08-11 for want of one.

### Prerequisites

A container runtime. This machine had none, so U1 installed Colima:

```bash
brew install colima docker
colima start --cpu 4 --memory 8 --disk 60
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
```

`DOCKER_HOST` matters: the Supabase CLI looks for `/var/run/docker.sock`, and
Colima's socket is elsewhere. Without it every CLI command that needs a
container fails with `LegacyDockerRunError`.

### Start, reset, stop

```bash
supabase start                 # first run pulls ~12 images
supabase db reset --local      # recreate the DB and apply supabase/migrations/
supabase stop --no-backup      # destroy all local state
```

**`supabase db reset` accepts `--linked`, which resets PRODUCTION. Always pass
`--local`.** There is no reason to type `--linked` on a reset in this project,
ever.

### The fidelity gate

```bash
./supabase/verify-baseline.sh
```

Captures the same ten structural surfaces from the local instance and compares
them against `supabase/schema/` via `check-baseline.py`, which enforces the
criterion below. **It exits non-zero on any unapproved difference**, so it is an
executable gate rather than an instruction to inspect and excuse a diff.

```bash
./supabase/capture-schema.sh --local <outdir>    # the capture on its own
```

The script refuses to write a `--local` capture into `supabase/schema/`, which
would destroy the observed-truth record and make the gate compare a file with
itself.

### Two artefacts, and confusing them defeats the point

| | Authority for |
|---|---|
| `supabase/schema/` | **Observed production truth.** Captured after the fact. The thing the baseline is measured *against* |
| `supabase/migrations/` | **Reproducible source.** What the local instance is built *from* |

**Production is not re-based onto the migration history.** The baseline
reproduces production as it existed at U1 entrance; applying migrations to
production is explicitly out of scope, and no Phase 3 membership object appears
in the baseline.

### Local verification is NOT production verification

**Load-bearing, not pedantic.** A faithful local reproduction runs the same
software; it is not the same deployment. Storage-listing semantics, PostgREST
error shapes and the exact response to a delete of a missing object are all
things this project has already been caught assuming — C-33's cell says so in as
many words. Anything verified locally is recorded as **"verified against a
faithful local reproduction"**, never as "verified in production", and the
residual gap is stated rather than glossed.

### The acceptance criterion, stated so it cannot drift into "close enough"

**Faithful database reproduction and byte-identical catalog serialization are
not the same thing**, and B-23 distinguishes them explicitly rather than
informally.

1. **Every surface that CAN be reproduced byte-identically MUST be.**
2. A **catalog-serialization exception** is permissible only where it is
   **individually demonstrated** to be PostgreSQL normalization or catalog
   history rather than a semantic or schema difference.
3. Every such exception is **declared in `baseline-exceptions.json`** with its
   evidence, narrowly keyed to one row and one field.
4. The tooling **still detects the difference** and verifies it is *exactly* the
   approved one — production side, local side, and the identified row.
5. **Anything else fails**: a new difference, a changed difference, a difference
   in a file with no exceptions, or a declared exception that **no longer
   appears**. A stale allowlist is a failure, not a pass.

**There is no whitespace or parenthesis normalizer, deliberately.** A broad
normalization rule would conceal genuine future differences, which is the
opposite of what the gate is for. Nothing is rewritten to compare equal; the
comparison is exact and the residue is checked against a narrow allowlist.

### The one approved exception — `account_directory.account_id_format`

```
production  CHECK (((account_id IS NULL) OR (((char_length(account_id) >= 3) AND (char_length(account_id) <= 24)) AND (account_id ~ '...'))))
local       CHECK (((account_id IS NULL) OR ((char_length(account_id) >= 3) AND (char_length(account_id) <= 24) AND (account_id ~ '...'))))
```

Production stores a **left-nested** two-way `AND`; local reproduces a **flat
three-way** `AND`. Logically identical — `AND` is associative — and no query,
constraint check or error message can distinguish them.

**It was not assumed to be irreproducible. It was tested, and the test is the
reason it is admissible:**

- Both servers are PostgreSQL **17.6** (`select version()` on each), so it is
  not a major-version difference.
- Feeding **production's own emitted expression** straight back into 17.6
  produces the **flat** form — production's representation cannot be
  round-tripped from its own rendering.
- A **right**-nested source *is* preserved verbatim, showing the parser flattens
  left-nesting specifically rather than normalising all nesting.
- Therefore **no migration SQL produces production's representation on 17.6**.
  It is inherited catalog history, almost certainly carried through a
  major-version upgrade.

It is removed from the allowlist the moment production's representation becomes
reproducible — for example after a schema change that rewrites the constraint.
The gate fails at that point, which is the intended prompt to revisit it.

### `function_grants` — widened, because the old capture had a blind spot

The previous definition captured `has_function_privilege(role, oid, 'EXECUTE')`
alone. That answers *"can this role execute?"* — **true whether the privilege is
held directly or inherited from `PUBLIC`.** Postgres grants `EXECUTE` to
`PUBLIC` by default, so that single column **cannot distinguish B-5's hardened
directory RPCs from a function nobody has touched.**

`get_unread_private_comment_groups` is the proof: in production `PUBLIC` is
revoked and all three roles hold direct grants, and the old column rendered that
identically to the default state.

Three columns now:

| Column | Question |
|---|---|
| `can_execute` | **Effective** — direct *or* via `PUBLIC`. The old meaning, kept so "who can call this?" is still answerable in one place |
| `direct_execute` | Is there an **explicit ACL entry** for this role? |
| `public_execute` | Does **`PUBLIC`** hold `EXECUTE` on this function? |

`aclexplode()` reads the real ACL; `proacl` is `NULL` for a function nobody has
granted on, so `acldefault('f', proowner)` supplies the implicit default rather
than the row reading as "no privileges". `grantee = 0` is `PUBLIC`.

**Consequence for the baseline:** it must `REVOKE EXECUTE … FROM PUBLIC` on the
four hardened functions before granting, or B-5's hardening does not reproduce.
Revoking from the three roles alone leaves everything executable.

**The production snapshot and the local capture were established
independently** under the widened definition — production re-captured
read-only, local rebuilt from committed migrations — so the agreement is a
result, not an artefact of changing the question.

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

### B-6 policy hardening — expected snapshot delta, written before applying (2026-08-14)

| Snapshot file | Before | After | Change |
|---|---|---|---|
| `policies` | 33 | **33** | **row count unchanged** — one row MODIFIED: `attachments_select_via_visible_post` on `storage.objects`, `qual` only |
| `functions` | 11 | **11** | none |
| `function_grants` | 33 | **33** | none |
| `triggers` | 5 | **5** | none |
| `rls_enabled` | 7 | **7** | none |
| `constraints` | 24 | **24** | none |
| `columns` | 60 | **60** | none |
| `table_grants` | 102 | **102** | none |
| `column_grants` | 523 | **523** | none |
| `storage_buckets` | 2 | **2** | none |

**This delta differs in kind from B-7/B-10's.** Those were deletions and the
whole diff was removals. This is a **single-row modification**: `policies.json`
must show exactly one changed entry, its `policyname` unchanged, its `cmd`,
`roles` and `permissive` unchanged, and **only `qual` differing**. Any change to
`with_check`, to the roles list, or to a second policy row means something other
than the intended edit landed.

`ALTER POLICY` is used rather than DROP + CREATE precisely so the name, command
and role list cannot move.

**No storage object and no application row is touched.** Backend counts are
re-read afterwards to confirm rather than assumed.

**The regression this must not cause is a read failure, not a write failure**,
and the snapshot cannot detect it. A device read-path check is therefore part of
the acceptance, not an optional extra: owner reading their own post's
attachments, and an approved follower reading another member's — the second
being the one a naive `auth.uid()` binding would have broken.

## U4 — ingestion and reconciliation (Phase 3)

**Implemented and green locally, 2026-08-20. NOT DEPLOYED.** The production
package is `supabase/sql/README-u4-deployment.md`; run it only under explicit
authorisation.

### Two new Edge Functions, and one of them is a different kind of thing

`appstore_notifications_v1` is **the first genuinely unauthenticated endpoint in
this project.** `delete_account_v1` and `revoke_apple_identity_v1` also set
`verify_jwt = false`, but each then performs its own `auth.getUser(token)` and is
stricter than the gateway would have been. **Apple sends no Supabase JWT and
never will**, so the Apple JWS signature — an x5c chain verified against a
pinned, embedded Apple Root CA G3 — is the entire authorisation story. Do not
read the older `config.toml` comments as covering it; that file now says so
explicitly.

`appstore_reconcile_v1` requires the service role key, compared in constant time.
Note what `verify_jwt = true` would **not** have given us: any valid user JWT
satisfies the gateway, and every authenticated Apple user can obtain one.

### The dependency, and why it is pinned this hard

`@peculiar/x509@1.12.3`, exactly pinned in `supabase/functions/deno.json` with a
committed `deno.lock` carrying sha512 integrity for all 19 resolved packages.
**It sits in the verification path of an unauthenticated endpoint**, which is why
it is pinned to an exact version with integrity rather than to a range.

Regenerate the lock — there is no `deno` on this machine — with:

```bash
docker run --rm -v "$PWD/supabase/functions:/w" -w /w --entrypoint deno \
  denoland/deno:2.1.4 cache --node-modules-dir=false \
  _shared/appstore/jws.ts _shared/appstore/derive.ts _shared/appstore/api.ts
```

**Two routes were tried first and both are dead**, which is recorded in B-28 and
re-proved on every run of `supabase/tests/u4a/run.sh`: `node:crypto`'s
`X509Certificate.verify` throws `ERR_NOT_IMPLEMENTED`, and
`@apple/app-store-server-library@1.6.0` rejects payloads it should accept while
reporting its own runtime incapacity with **the same status as a genuine
forgery**.

### The trust anchor is embedded in source, and there is no switch

A user worker's code is relocated to `/var/tmp/sb-compile-edge-runtime/`, so
`Deno.readTextFile` against a path beside the source fails. The anchor is
therefore a constant in `_shared/appstore/apple_root_ca_g3.ts` — which is also
the safe design: **no environment variable can relax the one control that makes
the endpoint safe.** The local E2E suite substitutes the anchor in a *copy*,
never in the source.

### U4 does not establish membership, and the executable surface is four functions

`membership_apply_state_v1` is **UPDATE-only**; there is no `INSERT INTO
public.membership` anywhere in U4. Ownership establishment — and therefore
`binding_method` and `bound_at`, which record *how ownership was proved* — is
U5's alone. A notification that maps to a live binding but finds no authoritative
row is recorded `ignored`/`unestablished` for U5 to pick up.

Four functions carry `service_role` EXECUTE: `membership_ingest_notification_v1`,
`membership_due_for_reconciliation_v1`, `membership_apply_reconciliation_v1` and
`membership_record_reject_v1`. The canonical writer, the B-24 binding resolver
and the audit recorder are granted to **nobody**. **`membership_record_reject_v1`
is kept separate from the ingest entry point deliberately** — folding it in would
put the function that can write `membership` on the path an unauthenticated
caller reaches by sending garbage.

### Runtime secrets

Five, named in the deployment package. **`APPLE_IAP_BUNDLE_ID` is deliberately
separate from `APPLE_CLIENT_ID`** even though they hold the same value: they mean
different things, and coupling them means a future SIWA change silently breaks
IAP authentication. **`APPLE_API_BASE_URL_SANDBOX` / `_PRODUCTION` must remain
unset in production** — they exist for local stubs and for Q5/Q6.

### Local suites

```bash
./supabase/tests/u4a/run.sh                       # the verification route gate
supabase db reset --local && ./supabase/tests/u4/run.sh
```

### Never

Write experiments against production, even with synthetic values and a
`ROLLBACK`. A rolled-back transaction is still a write, and tooling that sends
statements as separate round trips will not roll it back at all. Where a
runtime proof is needed, it goes through the QA plan against real accounts —
see E8/E8b for the B-6 example.

## STANDING RULE — a production mutation's guard must be enforced by Postgres

**Never pair an unconditional `COMMIT` with an instruction to inspect the result
and `ROLLBACK` if it looks wrong.** By the time the count is read the commit has
happened, and the two instructions contradict each other. Caught by review on
2026-08-25, in a procedure this file's own "Never" section already had the
reasoning to reject.

**And do not fix it by splitting `BEGIN` and `COMMIT` across two SQL-editor
submissions.** Studio gives no session continuity between Run clicks — each is
its own request over a pooled connection — so the follow-up `COMMIT` most likely
lands with no transaction in progress. **That fails safe and reads exactly like
success**, which is the worst property a safety procedure can have.

The shape that works is **one submission, with the guard inside it**:

```sql
DO $$
DECLARE n integer;
BEGIN
  DELETE FROM public.some_table WHERE <scoped predicate>;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'ABORT: expected exactly 1 row, deleted %', n;
  END IF;
END $$;
```

`RAISE EXCEPTION` aborts the block's own transaction, so a wrong count rolls
itself back and reports the number it saw. **No human decision sits between the
observation and the outcome** — the same reasoning that rejected D4's allowlist,
one level down: a safety property must not rest on operational discipline when
the database can hold it.

Precede it with a read-only `SELECT` of the same predicate, and **do not select
`user_id`** — a pasted result must not be able to put a production UID into the
repository or a transcript.

## Working rule

The audit register (`docs/audit-findings.md`) is **evidence, not the
implementation**. Every B-finding is verified against the deployed source
before any change is proposed — the same discipline applied to the client,
where it repeatedly changed the conclusion: C-13 was misfiled as benign,
C-19's mechanism dissolved on inspection, and an earlier P0 was retracted once
`pg_trigger` was actually read.
