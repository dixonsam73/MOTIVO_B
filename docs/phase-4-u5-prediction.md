# P4-U5 — PREDICTION, COMMITTED BEFORE ANY PRODUCTION OR CLIENT MUTATION

**Written 2026-09-05 at `672341f`.** SQL rehearsed on the local stack; **nothing
in production changed and no client file has been edited.**

---

## 1. B-15 — DISPOSED ON MEASUREMENT, NOT IMPLEMENTED

**No SQL change. The floor stays at 2. The function body is reproduced verbatim
apart from one added output column, and its comment is corrected to say why.**

Recorded, per direction:

- **2 characters is already the smallest PRODUCT-VALID floor.** Production
  carries **one display name of 2 characters** and three of 3; raising the floor
  to 3 makes that member unsearchable by their complete name, and 4 breaks four
  of seventeen. Two-character surnames (Ng, Li, Wu, Xu) are ordinary.
- **Instrument discovery and name search are intentional product behaviour** —
  `PeopleView:499` advertises *"Search by name or instrument"*. Bulk reachability
  by instrument follows from a small closed vocabulary and is a feature.
- **Further resistance to systematic enumeration needs a DIFFERENT mechanism** —
  rate limiting / query budgeting, which a SQL function cannot express, and/or a
  product decision about what the directory publishes.
- **That work is NOT absorbed into U5.** It is **re-filed as B-37** so the
  concern keeps an owner.

**`LIMIT 20` IS NOT DESCRIBED AS A SECURITY CONTROL.** The earlier investigation
called it "the only structural control"; **that is withdrawn.** It is a
**per-query result cap** — repeated queries still enumerate, and calling a cap an
anti-enumeration control is the kind of claim that later gets relied upon.

**Preserved exactly:** `auth.uid() is not null`; self-exclusion
(`ad.user_id <> auth.uid()`) with its "not a security control" warning; and
**G10** — `get_account_directory_by_user_ids` gains a returned column and **no
predicate**.

## 2. C-34 — THE NARROWER TRIGGER IS CONFIRMED BY MEASUREMENT

**`BEFORE UPDATE OF avatar_key` fires when the column is TARGETED BY THE SET
CLAUSE, whether or not the value changes.** Measured locally, three ways, and
then again through **real PostgREST**:

| case | version stamped? |
|---|---|
| `SET avatar_key = <same value>` — **the replacement path** | **YES** |
| `SET <other column> = …` — an unrelated directory edit | **no** |
| `SET avatar_key = <different value>` | **YES** |
| **PostgREST** `PATCH {"display_name": …}` (204) | **no** |
| **PostgREST** `PATCH {"avatar_key": <same value>}` (204) | **YES** |

**So unconditional stamping is not needed** and is dropped from the design: an
unrelated profile edit will not invalidate every member's avatar cache.

### 2.1 Initial semantics — NULL, and NO backfill

`avatar_version` is **nullable with no default and no backfill**. Existing rows
keep NULL, the client folds NULL into the cache identity as a stable empty
component, and **every existing avatar continues to render unchanged**. The first
replacement stamps. Rewriting all 17 directory rows to seed a version would
invalidate every member's cache once, for nothing.

### 2.2 A behavioural note found in rehearsal

**`avatar_version` cannot be cleared in the same statement that touches
`avatar_key`** — the `BEFORE` trigger overwrites the assignment. Clearing needs
its own statement. Harmless, and recorded because it looks like a failed write.

## 3. THE SQL ARTEFACT

`supabase/sql/2026-09-05-u5-avatar-version.sql`, applied locally and **green**.

1. `alter table public.account_directory add column if not exists avatar_version timestamptz;`
2. `tg_stamp_avatar_version()` — sets `new.avatar_version := now()`
3. `create trigger tg_directory_avatar_version before update of avatar_key …`
4. **`search_account_directory`** — DROP + CREATE with `avatar_version` added to
   `RETURNS TABLE`; **body byte-identical otherwise**, floor unchanged
5. **`get_account_directory_by_user_ids`** — same, **returned column only**

### 3.1 The drop/recreate hazard, and why the grants are restated

**Changing `RETURNS TABLE` requires DROP + CREATE**, and B-15's recorded warning
is operative: *Supabase's default privileges on `public` re-grant anon,
authenticated and service_role on any newly created object.* Both functions are
**`authenticated`-ONLY** today (measured: anon/public/service_role all false).

The migration therefore **REVOKEs from `public`, `anon` and `service_role` and
GRANTs to `authenticated`** on both, and **GUARD 6 fails the transaction if any
of those grants came back.**

### 3.2 Seven in-transaction guards, and one already earned its keep

Guards assert the column, the trigger's existence, **that the trigger is
`UPDATE OF avatar_key` and not a blanket UPDATE**, both RPC signatures, that
`authenticated` kept EXECUTE, that **anon/service_role did not gain it**, and
that the by-ids RPC **still has no subject-side filter (G10)**. The file ends in
a **returning SELECT**, so *"Success. No rows returned."* cannot disguise a no-op.

**GUARD 4 FAILED ON THE FIRST LOCAL RUN AND THE TRANSACTION ROLLED BACK.** The
assertion looked for `avatar_version timestamptz`; Postgres renders the signature
as **`avatar_version timestamp with time zone`**, so the guard never matched. **A
guard caught my own assertion string before it reached production** — which is
what the guard-inside-the-transaction rule is for.

### 3.3 Route

**`supabase db query --linked` is SINGLE-STATEMENT and cannot carry this.** The
file is a guarded `begin … commit` and must be submitted whole through the SQL
editor, the U6a route. **Dropping a live directory function outside a
transaction is the failure this avoids.**

## 4. PREDICTED CLIENT CHANGES

| file | change |
|---|---|
| `AccountDirectoryService.swift` | `DirectoryAccount` gains `avatarVersion: String?` + coding key `avatar_version` |
| `NetworkManager.swift` | `fetchAvatarImageIfNeeded(avatarKey:version:expiresInSeconds:)`; cache key becomes `"avatars\|<key>\|<version ?? "">"`. **The signed-URL cache and the storage path keep using `avatarKey` alone** — the version must never reach the storage request |
| 9 render sites | pass the version through |

**The version is a cache-identity component only.** Invariant 3 permits it:
a cache key is entirely reversible.

## 5. PREDICTED VERIFICATION

**Discriminator, to be re-run against PRODUCTION after apply:** a same-value
`avatar_key` PATCH **changes** `avatar_version`; an unrelated directory UPDATE
**does not**.

**Production census predicted unchanged:** 17 directory rows, 101 posts, 9
owners, 25 `connected_attachments` (all soft-deleted), 10 attachment objects,
3 avatars. **`avatar_version` NULL on all 17 rows immediately after apply** — no
backfill.

**Gates:** Debug + Release build; `MOTIVOTests`; `u5/client-structural.sh`;
`p4/u1..u2s` suites unchanged; **`u6b/acceptance.sh` U6b-G2/G3 must still pass**,
because the floor did not move.

## 5a. TWO CLIENT FINDINGS THAT ENLARGE §4 — REPORTED, NOT ABSORBED

**Found while sizing the client work, after this prediction's §4 was written.
§4 is left as committed; these correct it.**

**(i) `.task(id:)` MUST CARRY THE VERSION TOO, and §4 did not say so.** Every
render site is `.task(id: key)`. The key never changes on a replacement, so the
task **never re-runs** and the view holds the stale image in `@State` as well as
in the shared cache — which is exactly what the register says makes the feed row
the worst site. **Invalidating the cache alone therefore cannot fix it.** The
version must reach `.task(id:)`, not merely the fetch.

**(ii) THE CACHE-KEY FORMAT IS DUPLICATED IN EIGHT PLACES OUTSIDE THE PIPELINE** —
`"avatars|\(key)"` appears in `ContentViewSessionRow:488`, `ProfileView:1515`,
`ContentViewRemotePostRowTwin:553`, `ProfilePeekView:504`,
`BackendSessionDetailView:423`, `PracticeTimerView:1200`, `AuthManager:404`,
`ContentView:616`. **Two of them are INVALIDATION sites** (`ProfileView:1515`,
`AuthManager:404`), so changing the format without changing all eight in lockstep
would **silently stop the owner's own invalidation working**.

**Consequence for the design: DO NOT change the cache-key format.** Instead the
pipeline invalidates the existing entry when the supplied version differs from
the one it last saw for that key, and `fetchAvatarImageIfNeeded` takes
`version: String? = nil` so the eight duplicated sites and any call site without
a version are untouched.

**(iii) ONLY THE DIRECTORY-SOURCED SITES NEED IT.** The nine fetch sites split in
two: **other members' avatars** from `DirectoryAccount` (feed row, People,
comments, peek, session detail) — which is what C-34 is about — and **the
viewer's OWN avatar** from `auth.backendAvatarKey` (both toolbars, the owner
branch of the session row, ProfileView), where the owner's device already
invalidates explicitly. **The owner-side sites keep passing nothing and behave
exactly as today.**

## 6. OUT OF SCOPE

**C-34's TTL half remains Phase 5.** **U6 not begun.** No membership state, no
U6b enforcement change, no Device A action. **U2b/U2s device verification remains
Phase 4 exit condition 8.**
