# B-48 + avatar image names per upload — deployment (PREPARED, NOT EXECUTED)

**Prepared** 2026-11-12. **Nothing here has run against production.** It needs
one Codex review round of the SQL and Samuel's approval; Samuel runs it.

## What changes on the server

Migration `20261112120000_b48_avatar_names_and_own_folder_reference.sql`:

| Object | Change |
|---|---|
| `account_directory` | new CHECK `account_directory_avatar_key_own_folder`: `avatar_key` is NULL, `users/<user_id>/avatar.jpg`, or `users/<user_id>/avatar-<32 lowercase hex>.jpg`, for the row's own `user_id`. **This is the fix for B-48.** |
| `avatars_insert_owner_only` | accepts the old fixed name **or** the per-upload form, in the caller's own folder. The membership gate is unchanged. |
| `avatars_delete_owner_only` | the same two forms. |
| `avatars_update_owner_only` | **unchanged** (fixed name only): a per-upload image can never be overwritten. |
| `avatars_select_owner_or_approved_follower` | **unchanged**: it already works on the folder. |

**Unchanged:** both Edge Functions (`delete_account_v1` and
`membership_cleanup_v1` already delete every object in `users/<uid>/`), every
function, grant, trigger and bucket setting, and all data. No reference and no
stored image is altered or deleted by this change.

*Known stale comment, deliberately not touched:* `delete_account_v1/index.ts`
says the insert policy pins every client write to one object. After this change
a folder can hold several; the code already lists and deletes the whole folder.
Correct the comment at that function's next deployment.

## Artifacts

| Step | File |
|---|---|
| Preflight (read only) | `2026-11-12-b48-avatar-names-preflight-production.sql` |
| Apply | `2026-11-12-b48-avatar-names-apply-production.sql` (the migration verbatim between `BEGIN` and `COMMIT`) |
| Rollback, policies only | `2026-11-12-b48-avatar-names-rollback-production.sql` |
| Rehearsal | `supabase/tests/b48/rehearse.sh`, and `supabase/tests/p6-single-delete/e2e.sh` for the two Edge Functions |

**The route.** Production is `supabase db query --linked -f <file>`, the route
used for the last production apply (adult gate, 2026-10-15). It was **not
exercised for these files**, because it only reaches production. The local CLI
route cannot stand in for it: `supabase db query --local -f` refuses a file of
several statements ("cannot insert multiple commands into a prepared
statement", seen again 2026-11-12), so the rehearsal submits the same apply and
rollback files, unedited, through `psql`. The preflight is one statement and
was also run through `supabase db query --local -f`.

## Order

**Server first, then the app.** A build that stores per-upload names cannot
publish a photo against the old INSERT policy. Old builds are unaffected by
the server change: they write only the fixed name, which every policy and the
CHECK still accept.

1. **Storage version** (B-47). The rehearsal ran on storage-api `v1.80.2`
   (`supabase/.temp/storage-version`). If Supabase has upgraded production
   storage since 2026-10-15, re-pin, rebuild the local stack and run the
   rehearsal again before going on.
2. **Preflight.**
   ```
   supabase db query --linked -f supabase/sql/2026-11-12-b48-avatar-names-preflight-production.sql
   ```
   One row. Go on only if `nonconforming` = 0, `nonconforming_user_ids` is
   null, the three `*_policy_as_expected` are true and `constraint_exists` is
   false. **If `nonconforming` is not 0: stop and report the listed
   `user_id`s.** Nothing is to be altered or deleted to make it pass without a
   decision about each one.
3. **Apply.**
   ```
   supabase db query --linked -f supabase/sql/2026-11-12-b48-avatar-names-apply-production.sql
   ```
   Expect the last row `applied | <rows> | <rows with a reference> | 0 | <objects>`.
   `NOT APPLIED`, a non-zero fourth column, or an error body means nothing was
   changed (one transaction; every guard is inside it). **The exit code is 0
   even on failure: read the response.**
4. **Recapture and verify**, then commit the snapshot diff (expected: two
   policies in `policies.json`, one row in `constraints.json`, nothing else):
   ```
   ./supabase/capture-schema.sh
   ./supabase/verify-baseline.sh
   ```
   Until step 3 has run, `verify-baseline.sh` on a rebuilt local stack differs
   from the committed snapshot in exactly those three places.
5. **The app** ships in the next internal build. First real use is at the
   internal TestFlight checkpoint (decision D5): a photo published by the new
   build should leave exactly one object in the member's avatar folder, named
   `avatar-<32 hex>.jpg`, and the row's `avatar_key` naming it.

## Rollback

**The ownership constraint is not rolled back.** It is the B-48 fix, it accepts
the old fixed name, and so it never stands in the way of an old build or of
rolling back anything else. There is no script that drops it.

**The app can be rolled back at any time, on its own.** An old build reads a
per-upload reference like any other key and writes the fixed name.

**The two storage policies** can be put back with the rollback script, under
two conditions that it checks or that must be checked by hand:

- **No per-upload image and no reference to one exists** (checked by the
  script; it refuses otherwise). Their owners can only delete them under the
  widened DELETE policy. Once the new build has published a photo anywhere,
  do not roll the policies back: roll back the app only.
- **No build that stores per-upload names is still installed** (not checkable
  from the server). Restoring the old INSERT policy while such a build is in
  use means it can no longer publish a photo at all. Roll the app back first.

```
supabase db query --linked -f supabase/sql/2026-11-12-b48-avatar-names-rollback-production.sql
```
Expect `rolled back | t` (policies as before, constraint still validated).

## What the rehearsal showed (local stack, 2026-11-12)

`supabase/tests/b48/rehearse.sh`, storage-api v1.80.2, PostgREST v14.1,
Postgres 17.6, membership enforcement ON for the HTTP part:

- **Guards:** the migration applies with an existing old-name reference and
  leaves it untouched; a second run is refused; **eight kinds of reference
  outside the owner's folder** (another member's old or per-upload name, free
  text, the empty string, another file in the own folder, an upper-case id or
  hex, a path that climbs out) each make it refuse, name the row, and change
  nothing; the rollback restores both policies exactly, keeps the constraint,
  and refuses while a per-upload image or reference exists.
- **Storage, with real sessions for separate members:** the owner stores the
  fixed name and per-upload names; the same per-upload name cannot be stored
  twice, upserted or updated, and its content is unchanged afterwards; another
  member's folder, thirteen malformed names, an unentitled member and an
  anonymous caller are refused; an approved follower can read and sign but not
  delete; a non-follower cannot read; the owner's delete removes exactly the
  named image; an unentitled member can still delete their own.
- **The reference, as the owner through PostgREST:** own names accepted; seven
  others refused with `23514`, and by the service role too; the conditional
  write is refused on an older version and made on the current one.
- **Two responses the app relies on, now observed:** a delete of a name that
  is already gone answers HTTP 400 with body `statusCode "404"`, `not_found`,
  which the app reads as gone; a delete of another member's image answers
  `403`, which it does not.
- **Edge Functions** (`p6-single-delete/e2e.sh`, both unchanged): expiry
  cleanup and account deletion each remove a referenced image **and** a second
  image in the folder, whichever of the two forms is the referenced one, and
  leave another member's images and reference alone.

Not shown by a local rehearsal: the hosted storage backend, and production's
own rows (the preflight reads those).
