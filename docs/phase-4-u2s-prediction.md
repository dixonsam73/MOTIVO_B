# P4-U2s — PREDICTION AND PREFLIGHT, COMMITTED BEFORE ANY PRODUCTION MUTATION

**Written 2026-09-04 at `85d1884`.** The change is rehearsed on the local stack
and **not yet applied to production**.

---

## 1. PREFLIGHT — RE-MEASURED IMMEDIATELY BEFORE

| measure | production |
|---|---|
| `posts` / public / `false` / `null` | **101 / 101 / 0 / 0** |
| distinct owners | **9** |
| `enforcement_active()` | **true** |
| `membership` rows | **1** (`Sandbox`, `sandbox_only`, `connected_member` **false**) |
| `is_public` column default | **`false`** |
| `authenticated` INSERT column grants on `posts` | 17 |

**`posts_insert_owner` — exact current definition, roles `{authenticated}`,
`qual` NULL:**

```
(( SELECT enforcement_gate('posts.insert'::text) AS enforcement_gate) AND (owner_user_id = auth.uid()))
```

**The local stack's copy is BYTE-IDENTICAL** — both `md5(with_check)` =
`3c690fb054533d593f72656859c4c8eb`. **That is what makes the local rehearsal
faithful rather than merely similar.**

---

## 2. THE CHANGE — ONE CONJUNCT

`supabase/sql/2026-09-04-u2s-posts-insert-privacy.sql`:

```sql
alter policy posts_insert_owner on public.posts
  with check (
    (select public.enforcement_gate('posts.insert'::text))
    and (owner_user_id = auth.uid())
    and (is_public = true)
  );
```

**Predicted rendered `with_check` after apply — already observed locally, so this
is a prediction of an exact string, not a shape:**

```
(( SELECT enforcement_gate('posts.insert'::text) AS enforcement_gate) AND (owner_user_id = auth.uid()) AND (is_public = true))
```

`md5` = **`fb1873d10077148c59180ec7d45edbcb`**

### 2.1 The seven requirements, and where each is met

| # | requirement | how |
|---|---|---|
| 1 | preserve every existing condition | both conjuncts reproduced verbatim; nothing rewritten |
| 2 | applies regardless of `enforcement_gate` state | **top-level conjunct, NOT nested in the gate** — `enforcement_gate` returns TRUE when enforcement is inactive, so a nested clause would evaporate with the kill switch. Proven by test **E** |
| 3 | **no UPDATE restriction** | `posts_update_owner` untouched; test **D** proves demotion still works |
| 4 | no schema-default change | the default stays `false`; the guard rejects the **resulting value**, so an omitted column is refused too — test **B** |
| 5 | legitimate `true` inserts preserved | test **C** |
| 6 | update/delete/read unchanged | only the INSERT policy's `with_check` is altered |
| 7 | U6b enforcement preserved independently | the gate conjunct is untouched; test **E** shows both clauses acting independently |

**`= true` rather than `IS NOT FALSE`:** `is_public` is `NOT NULL`, so `= true`
is strictly two-valued.

---

## 3. A MEASURED BLOCKER — PRODUCTION BEHAVIOURAL TESTS CANNOT BE RUN BY ME

**The brief requires PostgREST negative tests with a genuine authenticated JWT.
I cannot obtain one for production, and this was measured, not assumed:**

```
auth.identities by provider :  apple = 17   (no other provider)
auth.users with a password  :  0 of 17
```

**Every production identity is Sign in with Apple only, and none has a
password.** So there is no password grant; SIWA needs a device I cannot drive;
minting a JWT would need the project JWT secret, which I do not have and will not
go looking for; and `service_role` **bypasses RLS**, which U1 already recorded as
the trap that would fake a pass *while writing the forbidden row*.

**Consequence, stated rather than worked around:**

- **A, B, C, D, E are executed on the LOCAL stack** with genuine
  `authenticated`-role JWTs through PostgREST — the exact path the policy
  governs. Evidence level: **verified against a faithful local reproduction**,
  and §1 shows the reproduction is byte-identical.
- **Production gets STRUCTURAL verification** — the deployed `with_check` byte-
  exact against §2, plus an unchanged census.
- **Production behavioural verification is DEFERRED** and folds naturally into
  U2b's outstanding Device A run: an old client attempting a private insert is
  precisely what this guard defends against, and that run has a real JWT.

**No production fixture is proposed.** Creating a password user to test with
would itself be a production auth fixture, which the brief says to propose rather
than create — and it is unnecessary, because the local reproduction is
byte-identical.

---

## 4. TEST MATRIX — RESULTS ALREADY OBSERVED LOCALLY

| # | case | observed |
|---|---|---|
| **A** | authenticated owner-valid INSERT, explicit `is_public = false` | **HTTP 403**, `42501` RLS violation, **0 rows persisted** (verified by id lookup, not by the HTTP code alone) |
| **B** | same, **omitting** `is_public` → takes `DEFAULT false` | **HTTP 403**, `42501`, **0 rows persisted** |
| **C** | legitimate `is_public = true` | **HTTP 201**, **1 row** — the policy remains satisfiable |
| **D** | UPDATE `true → false` | **HTTP 204**, **allowed**, `is_public` now false — unshare demotion intact |
| **E** | A/B/C with enforcement **ACTIVE** | **A 403, B 403, C 201** |

### 4.1 E HAD TO BE MADE DISCRIMINATING, AND THE FIRST ATTEMPT WAS NOT

Run naively with enforcement on, **C also returned 403** — the local identity has
no membership, so the **gate** denied everything and A/B's refusal proved
nothing. A local `Production` membership row was inserted so
`connected_member()` returned **true**; only then does **C succeed while A and B
fail**, isolating the new clause from the gate. **The fixture was removed
afterwards and local enforcement restored to `false`.**

### 4.2 THE PRE/POST DISCRIMINATOR

With the clause reverted locally, **A and B return HTTP 201 and the private rows
persist**. Re-applied, both return 403 with zero rows. **The guard is what
refuses, and a test that passed either way would have proved nothing.** The two
residue rows were removed by explicit id and local `posts` is back to its
baseline **2**.

---

## 5. THE STORAGE CONSEQUENCE — FROM TOPOLOGY, NO FIXTURE

**No production attachment fixture is created; the established ordering plus the
existing local evidence is sufficient.**

In `BackendShim.uploadPost` the post row is written **first** (`:901`); a
non-409 failure **returns at `:921`**; `loadIncludedAttachments` is at `:940` and
`uploadStorageObject` at `:1009` — both **downstream**. An RLS refusal is **403**,
and only **409** is treated as "already created, continue" (`:917`).

**So a pre-U2b client whose private INSERT is refused returns before the
attachment loop and uploads nothing.** This is the same ordering U2a-2 already
relied on, and U2c pinned the single-entry topology.

---

## 6. PREDICTED POST-APPLY STATE

| measure | predicted |
|---|---|
| `posts` / public / `false` / `null` | **101 / 101 / 0 / 0** — unchanged |
| owners | **9** |
| `with_check` md5 | **`fb1873d10077148c59180ec7d45edbcb`** |
| `enforcement_active()` | **true** — untouched |
| `membership` rows | **1** — untouched |
| policies on `posts` | **4** — unchanged, only one altered |
| `P4U1-15` / `U2c-14` (schema snapshot says no guard) | **flip to 1** once the snapshot is recaptured; until then they read the committed snapshot |

**Standing gates:** Debug + Release build; `MOTIVOTests` 40/40; `u5` 60/60;
`u2a` 16/16; `u2a2` 22/22; `u2b` 16/16; `u2c` 20/20 — **except the two
assertions that exist to say "U2s has not started"**, which this unit
legitimately falsifies and which will be re-pointed per the pinning policy.

## 7. OUT OF SCOPE

**U3 is not started.** No client code changes. No membership state, no U6b
enforcement change, no Device A action. **U2b remains device-verification-pending.**
