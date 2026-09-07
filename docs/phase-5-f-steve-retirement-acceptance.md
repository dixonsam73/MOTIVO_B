# STEVE RETIRED — EXECUTED AND VERIFIED. 2026-09-07

**Deleted through the app's REAL *Delete Account & All Études Data* path on
Device A**, not by hand-written SQL. Prediction: `5db0982`, committed before the
mutation.

---

## 1. BLAST RADIUS — 17 OF 17 MATCHED

| measure | before | after | predicted | |
|---|---|---|---|---|
| `auth.users` | 2 | **1** | 1 | ✅ |
| `auth.identities` | 2 | **1** | 1 | ✅ |
| `account_directory` | 2 | **1** | 1 | ✅ |
| `posts` | 7 | **6** | 6 | ✅ |
| `post_comments` | 5 | **1** | 1 | ✅ |
| `follows` / approved | 2 / 2 | **0 / 0** | 0 / 0 | ✅ |
| `membership` / `binding` | 1 / 1 | **0 / 0** | 0 / 0 | ✅ |
| `shadow_enforcement_stat` | 75 | **34** | 34 | ✅ |
| storage `attachments` | 8 | **7** | 7 | ✅ |
| storage `avatars` | 1 | **1** | 1 | ✅ |
| `post_comment_views` | 3 | **3** | 3 | ✅ |
| `connected_attachments` | 25 | **25** | 25 | ✅ |
| `post_shares` / `account_privacy` | 0 / 0 | **0 / 0** | 0 / 0 | ✅ |
| `membership_notification` | 74 | **74** | 74 | ✅ |

**Nothing was repaired forward and no figure was reinterpreted.**

## 2. SAMUEL SURVIVED INTACT — THE NEGATIVE CONTROLS

**Exactly one identity remains**, and it is Samuel:

| control | result |
|---|---|
| `uid8` / `account_id` | **`1fbf664a`** / **`samueldixon`** ✅ |
| **`avatar_key` present** | **yes** ✅ |
| **avatar STORAGE OBJECT present** | **yes** ✅ |
| posts | **6** ✅ |
| comments authored | **1** ✅ (was 4 — 3 died with Steve's post, as authorised) |
| `post_comment_views` | **3** ✅ |
| `membership` / `account_privacy` | **0 / 0** ✅ |

**The avatar was checked in BOTH places deliberately** — `avatar_key` and the
object it points at. B-20/C-33's lesson is that a pointer and an object can
diverge, and C-34's outstanding verification needs the object, not the pointer.

## 3. NO RESIDUE

Every orphan class **zero**: posts, comments-by-author, directory rows, follows,
comment views, shadow rows, and storage objects under a `users/<uid>/` prefix
whose owner no longer exists.

**That last one matters most.** Storage has **no FK to `auth.users`**, so an
incomplete deletion would leave untracked bytes rather than a broken row —
exactly B-21's residue class. **It did not.**

## 4. DEVICE A

- **Landed on first-run onboarding, not the journal** — **C-49's exact assertion,
  re-exercised and passing** on a second legitimate destructive run.
- **Sign in with Apple appeared at confirmation** and was completed, so the
  credential re-authorisation ran rather than falling back to C-44's manual
  Settings step. **This is the first recorded run where that authorisation
  succeeded in-app** — the 2026-08-15 D15 run recorded
  `outcome=notAttempted(1001)` (cancelled) and showed the manual fallback.
- Local journal, Scores, media and profile erased.
- **No Connected identity**, so `hasConnectedIdentity` is now **false** — which is
  precisely what makes the next CP-3 run take the genuine new-user path.
- **Sandbox Apple Account `sdsongsltd+devicec@gmail.com` and its Age Assurance
  fixture are untouched.** No Apple Account was changed anywhere.

## 5. THE FIXTURE IS DELIBERATELY RETIRED

**The Samuel↔Steve Phase-4 fixture no longer exists.** `follows` is **0**.

**Phase 4 conditions 2, 8 and C-34's avatar verification remain OUTSTANDING**, and
now additionally require a **replacement entitled fixture** — two Connected
identities with an approved follow.

**That cannot be built until a real Production subscription exists**, because
`follows_insert_requester`, `posts` INSERT/SELECT and `storage.avatars` INSERT are
all gated by `enforcement_gate`, and no identity is entitled.

**This is not a downgrade of those conditions.** They were **already unreachable
for exactly the same reason** — the fixture was inert. What changes is that it
must be **rebuilt** when entitlement arrives rather than found waiting, and
**creating that approved follow is itself part of what conditions 2 and 8
exercise.**

**Samuel is now the sole production identity**, holding 6 posts, 1 comment, an
avatar, and no membership.

## 6. STATUS

**Retirement complete and verified. The fresh-identity CP-3 join has NOT been
started. CP-3 remains open** until the new-identity device test establishes the
SIWA / privacy / directory ordering.
