# P4-U1 — PHASE 4 MEASUREMENT BASELINE

**Captured 2026-09-04, 09:16–09:40 UTC, at working-clone HEAD `78e2002`
(`feature/solo-connected`), BEFORE any Phase 4 implementation change.**

**U1 IS A MEASUREMENT UNIT. IT MUTATES NOTHING** — no client code, no SQL, no
production row, no storage object. Every production query below is a read-only
`select`. U2a/C-60, U2b, U2c, U2s and U3 have not begun.

Scope and decisions: `docs/phase-4-scope.md`. This file is its evidence.

---

## 1. WHY THIS UNIT EXISTS

The phase's central measurement — that no private post rows exist — is a
statement about a **moving population**, and F-1 establishes it is **not** a
statement about history. Inherited from a document a month from now it is an
assertion; re-measured at the moment of the fix it is evidence. Phase 3 learned
this four times: **a durable document asserting a fact is not evidence of that
fact.**

---

## 2. F-1 — POST CENSUS (PRODUCTION, READ-ONLY)

```sql
select count(*)                                   as total_posts,
       count(*) filter (where is_public is true)  as public_posts,
       count(*) filter (where is_public is false) as private_false,
       count(*) filter (where is_public is null)  as private_null,
       count(distinct owner_user_id)              as owners,
       min(created_at)::date                      as earliest,
       max(created_at)::date                      as latest,
       coalesce(sum(jsonb_array_length(attachments)),0) as total_attach_refs
  from public.posts;
```

| measure | value |
|---|---|
| `total_posts` | **101** |
| `public_posts` (`is_public is true`) | **101** |
| `private_false` (`is_public is false`) | **0** |
| `private_null` | **0** |
| `owners` | **9** |
| `earliest` → `latest` | 2026-03-02 → 2026-09-01 |
| `total_attach_refs` | **10** |

**`false` and `null` are counted separately, deliberately.** The column is
`NOT NULL DEFAULT false`, so `null` must be 0 structurally; splitting them means
a future non-zero tells you *which* mechanism produced it rather than merely that
one did.

**Identical to the scoping run of the same date.** The population is stable, and
that is an observation about these two measurements — **not** evidence about any
earlier state. Per F-1, `public.posts` has no audit column and no history table
exists, so a private row created and later deleted would leave no trace.

**The supported claim, and no stronger one:** *no private post rows exist at this
baseline, and there is no private population to purge at this measurement.*

---

## 3. F-6 — STORAGE / REFERENCE CENSUS (PRODUCTION, READ-ONLY)

### 3.1 THE REFERENCE-SET METHOD FOR B-8 — THE LOAD-BEARING PART

**B-8's warning is that the obvious heuristic destroys exactly what B-1
protects.** An object is live if something references it; liveness is **never**
read from the `users/<uid>/` path prefix, because that prefix carries the
**sender's** uid and a dead sender is the *correct* state for a preserved asset.
B-22 already produced one false positive that way.

The reference set is the **union of two sources**, and it is the definition U4
must reuse verbatim:

```sql
with refs as (
    -- (a) every attachment referenced by any post
    select a.value->>'path' as p
      from public.posts, lateral jsonb_array_elements(attachments) a
     where attachments is not null
    union
    -- (b) every attachment referenced by a LIVE connected_attachments row.
    --     Liveness is deleted_at IS NULL. NEVER the path prefix.
    select storage_path
      from public.connected_attachments
     where deleted_at is null
       and storage_path is not null
)
select ... from storage.objects o
 where o.bucket_id='attachments' and o.name not in (select p from refs);
```

### 3.2 MEASUREMENTS

| measure | value |
|---|---|
| `attachments` bucket objects | **15** |
| — referenced | **11** |
| — **unreferenced** | **4** |
| `avatars` bucket objects | **3** |
| `connected_attachments` rows | **31** |
| — live (`deleted_at is null`) | **6** |
| reference-set size (union, distinct) | **16** |

### 3.3 THE FOUR UNREFERENCED OBJECTS

**Recorded WITHOUT their paths. No production UID appears in this repository,
deliberately** — the same rule U3 followed for `membership_cutover`. Each is
pinned by the first 8 hex of `md5(name)`, which is stable, comparable at U4, and
carries no identity.

| `md5(name)[0:8]` | path segments | ext | created | bytes |
|---|---|---|---|---|
| `c27236f6` | 4 | pdf | 2026-08-11 | 1,938 |
| `76f5d323` | 4 | jpg | 2026-08-14 | 313,192 |
| `8bbe612d` | 4 | pdf | 2026-08-14 | 54,338 |
| `fe3cdd49` | 4 | pdf | 2026-08-15 | 148,684 |

**All four are 4-segment paths**, i.e. the
`users/<uid>/<postID>/<attachmentID>.<ext>` shape that
`BackendShim.storageObjectPath` produces — so all four are **post attachments
that lost their reference**, which is B-8's exact stated mechanism, rather than
direct-send (`connected_attachments`) residue. **This is a shape observation and
not a cause**; establishing why each lost its reference is U4's job, not U1's.

Total orphaned: **518,152 bytes**.

---

## 4. STRUCTURAL BASELINE — `supabase/tests/p4/u1-baseline.sh`

**16 assertions, 16 passed, 0 failed.**

It asserts the state as it is **today**, not the state Phase 4 wants. **Several
of these are SUPPOSED to fail once U2 lands** — §6 says which, and that is the
point: it makes the U2 change measurable rather than described.

**Comments are stripped before counting.** `LocalFactoryReset.perform` is the
worked example: a naive grep returns **3**, because
`AccountDeletionTransaction.swift:7` carries a doc comment naming it. Counting
that as a caller would have silently broken a Phase 3 exit assertion. Same shape
as U5c-34 and C57-*, anticipated rather than repeated.

| id | asserts | value |
|---|---|---|
| P4U1-1/2 | AESV and PRDV each hard-code `shouldPublish: true` | 1, 1 |
| P4U1-3/4 | neither yet gates on `isPublic`/`visibility` | 0, 0 |
| P4U1-5 | unshare-delete gates on `.backendPreview` (**C-60**) | 2 |
| P4U1-6 | `PublishService` never mentions `.backendConnected` | 0 |
| P4U1-7 | `SessionSyncQueue` flush **is** mode-complete | 1 |
| P4U1-8 | `loadIncludedAttachments` — 1 decl + 1 call | 2 |
| P4U1-9 | `payload.isPublic` used only to WRITE the column | 2 |
| P4U1-10 | sole attachment filter is per-attachment privacy | 1 |
| P4U1-11/12/13 | **`LocalFactoryReset.perform`: exactly 2 callers, both in `ProfileView`, 0 elsewhere; the 3rd match is the doc comment** | 2, 0, 1 |
| P4U1-14 | `posts` carries 4 policies | 4 |
| P4U1-15 | **`posts_insert_owner` has NO `is_public` predicate** | 0 |
| P4U1-16 | the SELECT policy **does** gate on `is_public` | 1 |

### 4.1 PHASE 3 CARRY-FORWARD — VERIFIED, AND ONE DOCUMENTATION DRIFT

**`LocalFactoryReset.perform` has exactly two callers.** CLAUDE.md makes this a
Phase 3 **exit assertion**, not a convention, and Phase 4 must not add a third.

**Verified at `ProfileView.swift:1724` (Solo erase) and `:1797` (Connected
delete).** **CLAUDE.md cites `:1680` and `:1753`** — the two line numbers have
drifted by 44. **The assertion is on the COUNT and it holds; only the cited
locations are stale.** Recorded rather than silently corrected, because a
durable document naming a line number is exactly the kind of claim that rots
invisibly — the C-52 shape. P4U1-11/12/13 assert the count, so they cannot rot.

---

## 5. REGRESSION AND BUILD BASELINE

| gate | result |
|---|---|
| `xcodebuild … -configuration Debug … build` | **BUILD SUCCEEDED**, 0 errors |
| `xcodebuild … -configuration Release … build` | **BUILD SUCCEEDED**, 0 errors |
| `MOTIVOTests` (iPhone 17 Pro sim) | **TEST SUCCEEDED — 15 of 15 passed** |
| `supabase/tests/u5/client-structural.sh` | **60 passed, 0 failed** |
| `supabase/tests/p4/u1-baseline.sh` | **16 passed, 0 failed** |

**The U5 suite is included as a REGRESSION baseline, not as U1 evidence.** It
contains C57-1..7, which pin the 401-only auth challenge; U2 touches the publish
path and must not disturb them.

---

## 6. PREDICTIONS

**Committed before the change, so the check is binary rather than a reading of
the aftermath.** Anything that does not match is a stop-and-report.

### 6.1 POST-U2 — STRUCTURAL (these baseline assertions MUST flip)

| id | now | after U2 |
|---|---|---|
| P4U1-1, P4U1-2 | 1, 1 | **0, 0** |
| P4U1-3, P4U1-4 | 0, 0 | **1, 1** |
| P4U1-5 (C-60) | 2 | **0** |
| P4U1-6 | 0 | **≥ 1** |
| P4U1-7, P4U1-8, P4U1-10 | 1, 2, 1 | **unchanged** |
| P4U1-11/12/13 | 2, 0, 1 | **unchanged — a Phase 3 exit assertion** |
| P4U1-14/15/16 | 4, 0, 1 | **unchanged by U2** (U2s changes 15) |

Debug + Release still build clean; `MOTIVOTests` still 15/15; U5 suite still
60/60.

### 6.2 POST-U2 — BEHAVIOURAL (device)

1. Saving a session with **Share OFF** creates **no** `posts` row and uploads
   **no** storage object.
2. Saving a **Thought** while Connected creates **no** `posts` row.
3. Saving with **Share ON** behaves exactly as today — row created, included
   attachments uploaded.
4. **Un-sharing a previously shared session DELETES the row and every storage
   object it referenced** (C-60 fixed). `deletePost` is fail-closed, so if any
   object cannot be removed the row survives — that is correct, and it is the
   branch to watch.
5. `total_posts` after the run = 101 + (public posts deliberately created)
   − (posts deliberately unshared). **`private_false` and `private_null` remain
   0.**

### 6.3 POST-U3 — PURGE

**Predicted: a recorded NO-OP.** If the pre-U3 census still reads
`private_false = 0` and `private_null = 0`, U3 deletes nothing and is recorded as
a no-op **with its evidence**, not omitted and not written up as a completed
purge.

If it reads non-zero, U3 purges **by explicit id** with a prediction committed
beforehand, the way B-22 was done — **never a liveness-predicate sweep**.

**U3 does not touch storage.** `unreferenced` stays **4** through U3; those are
U4's.

### 6.4 POST-U2s — THE SERVER-SIDE INVARIANT TEST

**DESIGN ONLY. NOT PERFORMED AT U1** — it is a mutation.

The guard: `posts_insert_owner WITH CHECK ... AND (is_public = true)`.

| # | attempt | predicted |
|---|---|---|
| **N** | owner-valid insert, `is_public = false` | **REFUSED** — RLS violation, **no row lands** |
| **N2** | owner-valid insert, `is_public` **omitted** (takes `DEFAULT false`) | **REFUSED** — this is why the guard is on the value, not on the client's payload |
| **P** | owner-valid insert, `is_public = true` | **INSERTED** — legitimate flow unaffected |
| **U** | existing public post PATCHed to `is_public = false` | **STILL ALLOWED** — UPDATE is deliberately not covered (§2a); an old-client unshare must not fail leaving content publicly visible |

**`supabase db query --linked` CANNOT RUN THIS TEST, AND ASSUMING IT COULD IS THE
TRAP.** Its role `cli_login_postgres` is a member of `postgres` and therefore
holds **`bypassrls`** — every attempt above would succeed regardless of the
policy, and **N would appear to prove the guard absent while also writing the
forbidden row.** The test must go through **PostgREST carrying a genuine
authenticated JWT**, which is the path the policy actually governs and the path
the client uses.

**Where each case runs:**

- **Local first** (`supabase db reset --local` with the U2s migration applied):
  **all four**, N/N2/P/U. Failures are free there.
- **Production**: **N and N2 only.** Both are predicted to be refused and
  therefore to leave nothing behind, verified by re-running §2's census and
  showing `total_posts` **unchanged at its then-current value**. **P is not run in
  production** — it would deliberately create a real post; the positive control
  is the local run plus the 101 rows that already demonstrate public inserts
  work. **U is not run in production** — it would mutate a real member's post.
- **If N or N2 unexpectedly SUCCEEDS in production**, that is the stop-and-report
  case: the row is removed **by explicit id** and U2s is treated as not
  deployed.

---

## 7. WHAT U1 DID NOT DO

- No client code, SQL, migration or policy changed.
- No production row, storage object or bucket touched.
- No U2s guard deployed; no purge; no orphan cleanup.
- **C-31 untouched** — it remains an open carried release obligation with its
  24-hour App Store Connect propagation window, owned outside Phase 4.
