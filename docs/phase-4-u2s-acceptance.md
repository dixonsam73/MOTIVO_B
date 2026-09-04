# P4-U2s — SERVER-SIDE SHARED-ONLY INSERT INVARIANT. ACCEPTANCE.

**Applied to production 2026-09-04. Prediction and preflight committed
beforehand at `6f6a3c0`; deployed checkpoint `4febb8b`.**

## STATUS — RECORD IT IN EXACTLY THESE FOUR PARTS

1. **Production policy deployment is COMPLETE and INDEPENDENTLY STRUCTURALLY
   VERIFIED** — the deployed `with_check` was re-read after the apply and is
   byte-exact (`md5 fb1873d10077148c59180ec7d45edbcb`).
2. **The full authenticated behavioural matrix (A/B/C/D/E) is PROVEN against the
   FAITHFUL, BYTE-IDENTICAL local policy through PostgREST**, with genuine
   `authenticated`-role JWTs.
3. **Production authenticated behavioural observation is DEFERRED**, because no
   genuine production JWT is currently obtainable without Device A / Sign in with
   Apple — all 17 production identities are Apple-only with zero passwords, and
   `service_role` bypasses RLS.
4. **That observation is carried into the existing Device A Phase 4 exit
   verification** (exit condition 8) **and MUST NOT be claimed now.** U2s is not
   "behaviourally verified in production"; it is deployed, structurally verified,
   and behaviourally verified against a faithful reproduction.

**The invariant now achieved:**

> An authenticated INSERT into `public.posts` is accepted **only** when
> `is_public = true` — including when the client omits the column and receives
> the schema `DEFAULT false` — and this holds **in both positions of the U6b
> kill switch**.

---

## 1. BEFORE → AFTER

**Before** (`md5` `3c690fb054533d593f72656859c4c8eb`):

```
(( SELECT enforcement_gate('posts.insert'::text) AS enforcement_gate) AND (owner_user_id = auth.uid()))
```

**After** (`md5` **`fb1873d10077148c59180ec7d45edbcb`**):

```
(( SELECT enforcement_gate('posts.insert'::text) AS enforcement_gate) AND (owner_user_id = auth.uid()) AND (is_public = true))
```

`cmd` INSERT, roles `{authenticated}`, `qual` NULL — **all unchanged**. Both
prior conjuncts are reproduced **verbatim**; nothing was rewritten for tidiness.

**The deployed md5 matched the prediction exactly.** The apply's own output was
not treated as evidence — the policy was **independently re-read** afterwards,
per the standing rule that a procedure whose success is reported by the thing
being asked to act is unverified.

Artefact: `supabase/sql/2026-09-04-u2s-posts-insert-privacy.sql`.

### 1.1 Why the clause is a peer of the gate, not inside it

`enforcement_gate` returns **TRUE** whenever U6b enforcement is inactive, so a
clause nested within it would **evaporate the moment the membership kill switch
was thrown**. This is a **Domain 3 privacy invariant, not membership
enforcement**, and must hold in both switch positions. Asserted structurally
(`U2s-5`) and proven behaviourally (**test E**).

### 1.2 Why `= true`, and why the default was not touched

`is_public` is `NOT NULL`, so `= true` is strictly two-valued. **The column
defaults to `false`**, so a client that *omits* it is refused as well — which is
the case a payload-shaped check would miss, and why **requirement 4 is satisfied
by rejecting the resulting value rather than by changing the default.** Nothing
measured required touching it. Test **B**.

---

## 2. A MEASURED BLOCKER — PRODUCTION BEHAVIOURAL TESTS COULD NOT BE RUN BY ME

```
auth.identities by provider :  apple = 17  (no other provider)
auth.users with a password  :  0 of 17
```

**Every production identity is Sign in with Apple only and none has a
password.** So: no password grant; SIWA needs a device I cannot drive; minting a
JWT would need the project JWT secret, which I do not have and did not go looking
for; and `service_role` **bypasses RLS** — U1 already recorded that as the trap
that would fake a pass *while writing the forbidden row*.

**What was done instead, and its evidence level:**

- **A/B/C/D/E on the LOCAL stack**, through PostgREST with genuine
  `authenticated`-role JWTs — the exact path the policy governs. **The local
  policy was byte-identical to production beforehand** (both md5
  `3c690fb…`), which is what makes this a faithful reproduction rather than an
  analogy.
- **Production: structural verification** — deployed `with_check` byte-exact,
  census unchanged, sibling policies unchanged.
- **Production behavioural verification is DEFERRED into U2b's outstanding
  Device A run.** An old client attempting a private insert is precisely what
  this guard defends against, and that run has a real JWT. **No production
  fixture was created or proposed.**

---

## 3. TEST MATRIX — LOCAL, ALL PASS

| # | case | HTTP | rows persisted |
|---|---|---|---|
| **A** | owner-valid INSERT, explicit `is_public = false` | **403** `42501` RLS violation | **0** |
| **B** | owner-valid INSERT, **omitting** `is_public` → `DEFAULT false` | **403** `42501` | **0** |
| **C** | legitimate `is_public = true` | **201** | **1** |
| **D** | UPDATE `true → false` | **204 — ALLOWED** | row kept, now private |
| **E** | A/B/C with enforcement **ACTIVE** | **403 / 403 / 201** | 0 / 0 / 1 |

**Every negative was verified by id lookup against the database, never by the
HTTP status alone** — the brief's requirement, and the only way to know nothing
persisted.

### 3.1 E HAD TO BE MADE DISCRIMINATING, AND THE FIRST ATTEMPT WAS NOT

Run naively with enforcement on, **C also returned 403**: the local identity has
no membership, so `connected_member()` was false and **the gate denied
everything** — A and B's refusals would have proved nothing about the new clause.

A local `Production` membership row was inserted so `connected_member()` returned
**true**. Only then does **C succeed (201) while A and B fail (403)**, isolating
the privacy clause from the gate and proving they act independently
(requirement 7). **The fixture was deleted and local enforcement restored to
`false`.**

### 3.2 THE PRE/POST DISCRIMINATOR

With the clause reverted locally, **A and B return 201 and the private rows
persist**. Re-applied, both return 403 with zero rows.

**The guard is what refuses.** A matrix that passed either way would have been
decoration. The two residue rows were removed by explicit id and local `posts` is
back to its baseline **2**.

---

## 4. THE STORAGE CONSEQUENCE — FROM TOPOLOGY, NO FIXTURE

**No production attachment fixture was created.** In `BackendShim.uploadPost` the
post row is written **first** (`:901`); a non-409 failure **returns at `:921`**;
`loadIncludedAttachments` (`:940`) and `uploadStorageObject` (`:1009`) are both
**downstream**. An RLS refusal is **403**, and only **409** is treated as
"already created, continue" (`:917`).

**So a pre-U2b client whose private INSERT is now refused returns before the
attachment loop and uploads nothing.** Same ordering U2a-2 relied on; the
single-entry topology is pinned by U2c-1..8.

---

## 5. REQUIREMENTS

| # | requirement | evidence |
|---|---|---|
| 1 | preserve every existing condition | `U2s-3`, `U2s-4` — both verbatim |
| 2 | applies regardless of gate state | `U2s-5` + **test E** |
| 3 | **no UPDATE restriction** | `U2s-6`, `U2s-7` + **test D** |
| 4 | no schema-default change | default still `false`; **test B** refuses the omitted case |
| 5 | legitimate `true` preserved | **test C** |
| 6 | update/delete/read unchanged | `U2s-6..9`; sibling policy fingerprints unchanged |
| 7 | enforcement preserved independently | **test E** — C succeeds while A/B fail, under enforcement |

---

## 6. GATES

| gate | result |
|---|---|
| Debug / Release build | **BUILD SUCCEEDED** |
| `MOTIVOTests` | **40 / 40**, exit 0 |
| *(one run reported 39 and the next 40, both exit 0 with zero failures — one result line lost in interleaved output across parallel simulator clones, the same artefact recorded at U2c. **40 is the true count**: 15 pure + 8 + 12 + 5.)* | |
| `u5/client-structural.sh` | **60 / 60** |
| **`p4/u2s-acceptance.sh`** | **12 / 12** |
| `p4/u2c-acceptance.sh` | **20 / 20** |
| `p4/u2b-acceptance.sh` | **16 / 16** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **16 / 16** |
| `p4/u1-baseline.sh` | 10 pass / **6 documented flips** (P4U1-15 joins the five) |

**Five assertions across three suites said "U2s has not started"** — `U2a2-20/21`,
`U2b-14/15`, `U2c-14`. U2s legitimately falsifies all five, so each is pinned to
its own unit's commit per the policy adopted in U2b. **The live guard did not
disappear: `u2s-acceptance.sh` replaces it with the stronger claim** — those
asserted an *absence*, this asserts the *presence of the exact clause*.

---

## 7. PRODUCTION CENSUS — BEFORE AND AFTER

| measure | before | after |
|---|---|---|
| `posts` / public / `false` / `null` | 101 / 101 / 0 / 0 | **101 / 101 / 0 / 0** |
| owners | 9 | **9** |
| `enforcement_active()` | true | **true — untouched** |
| `membership` rows | 1 | **1 — untouched** |
| policies on `posts` | 4 | **4** |
| `post_comments` / `follows` / attachment objects | 5 / 9 / 15 | **5 / 9 / 15** |

**Zero delta.** The only production change is one policy's `with_check`, and the
committed schema snapshot's diff is **exactly one line**.

## 8. OUT OF SCOPE

- **U3 has not begun.** The purge is still predicted to be a recorded no-op.
- No client code changed. No membership state, no U6b enforcement change, no
  Device A action.
- **U2b remains device-verification-pending** — Phase 4 exit condition 8, and now
  also the natural home for U2s's production behavioural verification.
