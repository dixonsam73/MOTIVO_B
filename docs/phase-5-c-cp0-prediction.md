# P5-C / CP-0 — FRESH CENSUS AND PREDICTION. 2026-09-06

**NOTHING HAS BEEN DELETED. NOTHING HAS BEEN MUTATED. THIS IS A READ-ONLY
CENSUS AND A COMMITTED PREDICTION, FOR REVIEW BEFORE EXECUTION.**

Every figure below was read from **production** on 2026-09-06 (server time
19:29–19:4x UTC) via `supabase db query --linked`, `SELECT` only. Identities are
`left(md5(user_id::text), 8)` throughout, per the standing rule that **no raw
production UUID enters the repository**.

**This census is dated authority and expires.** It must be **re-taken
immediately before execution** and compared to this document. The `d5d6d27`
census is superseded by this one, exactly as that one was declared to be.

---

## 1. THE MEASUREMENT THAT CHANGES CP-0's SHAPE

**CP-0 IS NOT A CASCADE OPERATION, AND TREATING IT AS ONE WOULD ORPHAN 94 POSTS
WHILE REPORTING SUCCESS.**

Only **seven** foreign keys reference `auth.users`, all `ON DELETE CASCADE`:
`account_directory`, `follows` (both directions), `membership`,
`membership_binding`, `membership_binding_conflict`, `shadow_enforcement_stat`.

**`posts`, `post_comments`, `post_shares`, `post_comment_views` and
`connected_attachments` are NOT among them.** Measured directly: those five
tables carry **exactly two** foreign keys between them, both
`post_id → posts(id) ON DELETE CASCADE`. **Not one of them references
`auth.users` at all.**

**So `delete from auth.users where id in (…)` would delete the identity, its
directory row, its follows and its membership — and leave every post, comment,
view and attachment row behind, permanently unreachable and unattributable.**

**This is why `delete_account_v1` exists and why it deletes content explicitly,
in order, with `auth.users` strictly last.** It is an **Edge Function**, not a
SQL function, and it authenticates the caller as the account owner — so it
**cannot be used here**: these fifteen identities are dormant and nobody holds
their credentials. **CP-0 must be an explicit SQL transaction that mirrors
`delete_account_v1`'s deletion order**, by explicit id, following B-22's rule
that a destructive production statement names its rows and carries **no liveness
predicate anywhere**.

---

## 2. THE CENSUS — 17 IDENTITIES

`dir` = has an `account_directory` row · `lu` = `lookup_enabled` ·
`fr` = `follow_requests_enabled` · `av` = has `avatar_key`

| # | md5[0:8] | created | dir | lu | fr | av | posts | c.auth | c.own | fol→ | ←fol | pcv | memb | bind | shadow |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `965caeff` | 2026-02-26 | ✓ | T | T | – | 3 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | |
| 2 | `776bf498` | 2026-03-01 | ✓ | F | T | – | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | |
| 3 | `c0464940` | 2026-03-02 | ✓ | T | T | **✓** | 12 | 0 | 0 | 0 | 1 | **6** | 0 | 0 | |
| 4 | `1778a35d` | 2026-03-10 | ✓ | F | T | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 5 | `daed2252` | 2026-03-10 | ✓ | T | T | **✓** | **72** | 0 | 0 | 1 | 1 | 0 | 0 | 0 | |
| 6 | `41aacc65` | 2026-03-11 | ✓ | T | T | – | 4 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | |
| 7 | `fb9b8413` | 2026-03-11 | ✓ | F | T | – | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 8 | `d66695a2` | 2026-04-19 | ✓ | F | T | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 9 | `a7d22d28` | 2026-04-29 | ✓ | F | T | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 10 | `853397a4` | 2026-05-03 | ✓ | F | T | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 11 | `9b8dde86` | 2026-05-09 | ✓ | F | T | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 12 | `3d2b85bf` | 2026-06-06 | ✓ | F | T | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| 13 | `b085b77e` | 2026-07-01 | ✓ | T | T | – | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | |
| **K1** | **`1fbf664a`** | 2026-07-23 | ✓ | T | T | **✓** | **6** | **4** | 2 | 6 | 1 | **3** | 0 | 0 | |
| 14 | `fb543460` | 2026-07-31 | ✓ | T | T | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | |
| **K2** | **`64ffb132`** | 2026-08-15 | ✓ | T | T | – | **1** | **1** | 3 | 1 | 1 | 0 | **1** | **1** | |
| 15 | `03fc4262` | 2026-08-19 | ✓ | T | T | – | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | |

**Global:** `auth.users` **17** · directory rows **17** · **users with no
directory row 0** · directory orphans **0** · posts **101** (all public) ·
comments **5** · follows **9** (4 approved) · post_shares **0** ·
post_comment_views **9** · connected_attachments **25** (**0 live**) ·
membership **1** · binding **1** · conflicts **0** ·
`shadow_enforcement_stat` **79** across 4 identities · storage: **3** avatars,
**10** attachment objects · `entitled_until` non-null **0** · enforcement
**enabled**.

### 2.1 The dated census is CONFIRMED on everything it recorded, and SILENT on three things

**All five measures recorded at `d5d6d27` reproduce exactly** — identities 2/15,
posts 7/94, comments 5/0, follows 2/7, avatars 1/2. **Nothing has drifted.**

**It recorded no figure at all for three measures that CP-0 must handle**, and
they are added here rather than discovered mid-execution:

- **attachment storage objects** — **2** belong to the delete set;
- **`post_comment_views`** — **6** belong to the delete set;
- **`shadow_enforcement_stat`** — **4** rows belong to the delete set.

**Not an error in the earlier census; an incompleteness.** It is exactly what a
fresh census is for.

### 2.2 A stale statement in CLAUDE.md, found in passing

CLAUDE.md's U6a section states **"`shadow_enforcement_stat` holds zero rows"**.
That was true at U6a's deploy. **It now holds 79.** The claim is dated and
correct as of its own date; recorded here because the number is used as a
zero-baseline elsewhere and would mislead. **No action taken** — this unit does
not rewrite the U6a record.

---

## 3. THE FOLLOW GRAPH, AND THE RETAINED-PAIR GUARD

| follower | followed | status | created |
|---|---|---|---|
| `41aacc65` | `daed2252` | approved | 2026-03-14 |
| `daed2252` | `41aacc65` | approved | 2026-03-14 |
| `1fbf664a` | `965caeff` | requested | 2026-07-23 |
| `1fbf664a` | `c0464940` | requested | 2026-07-23 |
| `1fbf664a` | `b085b77e` | requested | 2026-07-23 |
| `1fbf664a` | `776bf498` | requested | 2026-08-11 |
| `1fbf664a` | `03fc4262` | requested | 2026-08-27 |
| **`64ffb132`** | **`1fbf664a`** | **approved** | **2026-09-01** |
| **`1fbf664a`** | **`64ffb132`** | **approved** | **2026-09-01** |

**THE RETAINED-PAIR GUARD IS SATISFIED BY CONSTRUCTION.** The mutual approved
follow is the only pair with **both endpoints in the keep set**, so it is the
only follow that **cannot** be reached by any cascade from a deleted identity.
The other seven all have at least one endpoint in the delete set and go with it.

**`1fbf664a` loses five outgoing `requested` rows**, because their targets are
deleted. **That is a visible product change on the retained fixture**: Samuel's
"pending requests" list goes from 5 to 0. **It destroys nothing Phase 4 needs** —
conditions 2 and 8 and C-34 require the *approved* pair, not the pending
requests — but it is stated so it is not discovered as a surprise.

---

## 4. PREDICTED DELTAS

**Committed before execution. Every number is to be scored exactly.**

| measure | before | **after** | mechanism |
|---|---|---|---|
| `auth.users` | 17 | **2** | explicit delete, **strictly last** |
| `account_directory` | 17 | **2** | FK cascade |
| `posts` | 101 | **7** | **explicit — no FK** |
| `post_comments` | 5 | **5** | untouched; **0 on deleted posts** |
| `post_shares` | 0 | **0** | none exist |
| `post_comment_views` | 9 | **3** | **explicit — no FK at all** |
| `connected_attachments` | 25 | **25** | **no row references any deleted identity** |
| `follows` | 9 | **2** | FK cascade |
| `follows` approved | 4 | **2** | the retained mutual pair |
| `membership` | 1 | **1** | belongs to `64ffb132` |
| `membership_binding` | 1 | **1** | belongs to `64ffb132` |
| `membership_binding_conflict` | 0 | **0** | |
| `shadow_enforcement_stat` | 79 | **75** | FK cascade |
| storage `avatars` | 3 | **1** | **explicit by path** |
| storage `attachments` | 10 | **8** | **explicit by path** |
| `membership_notification` | 74 | **74** | not keyed on user |

**Storage objects to delete — 4, by explicit path, never by predicate:**
one avatar and one attachment under `daed2252`; one avatar under `c0464940`;
one attachment under `41aacc65`.

**Deleting them strands nothing.** Measured: **all 10 attachment objects are
already unreferenced** by any `connected_attachments` row (`referenced 0 /
unreferenced 10`), and `ca_live` is **0**.

**B-8's rule is respected and its inverse is noted.** Liveness is **not** read
from the path prefix; the prefix is used only to establish **ownership**, which
is what the bucket's path CHECK pins. Object deletion is verified against
`storage.objects`, **never** an HTTP `GET`, which P4-U4 measured returning 200
after a successful DELETE.

---

## 5. WHAT CP-0 MUST NOT DO

- **Must not use a predicate sweep.** Fifteen explicit ids, B-22's rule.
- **Must not touch `1fbf664a` or `64ffb132`**, their posts, their comments, their
  mutual approved follow, their storage objects, or `64ffb132`'s membership and
  binding.
- **Must not sweep the 8 surviving unreferenced attachment objects.** They are
  **pre-existing B-8-shaped residue owned by the retained pair**, not created by
  CP-0, and they need their own decision.
- **Must not sweep the 25 soft-deleted `connected_attachments` rows.** None
  references a deleted identity; they are pre-existing residue.
- **Must not "repair forward."** Any figure that does not match this prediction
  stops the run.

---

## 6. EXECUTION SHAPE — PROPOSED, NOT APPROVED

One transaction, with the guard **inside** it and a final `SELECT` that returns
a row, per the standing rule that **a procedure whose success is reported by the
thing being asked to act is unverified** and that *"Success. No rows returned"*
must be the symptom rather than the disguise:

1. **Guard**: assert exactly 17 identities and exactly 2 keepers resolve; assert
   every predicted before-count. **Any mismatch aborts.**
2. `post_comment_views` for the 15 → **explicit**.
3. `posts` for the 15 → **explicit** (cascades their comments/shares — measured
   **0** of each).
4. `auth.users` for the 15 → **last**, cascading directory, follows, membership,
   binding, conflicts and shadow rows.
5. **Final `SELECT`** returning every after-count.
6. **Storage objects deleted separately, by explicit path**, and verified against
   `storage.objects` — Storage is not transactional with Postgres, so it cannot
   be inside step 1's transaction and must not be pretended to be.

**Ordering note:** storage deletion **after** the database transaction commits.
If the transaction aborts, the objects are still there and nothing is
inconsistent; the reverse order could destroy objects for a deletion that then
rolls back. **This is C-33's ordering lesson** — clear the pointer only after the
object is gone — applied in the direction that fails safe here.

---

## 7. NOT EXECUTED

**No deletion has been performed. No SQL other than `SELECT` has been run
against production.** CP-0 executes only after this prediction is reviewed and
explicitly approved, and only after the census is re-taken and compared.
