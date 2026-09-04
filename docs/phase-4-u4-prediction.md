# P4-U4 / B-8 — PREDICTION, COMMITTED BEFORE ANY MUTATION

**Written 2026-09-04 at `4ae14ec`. Nothing deleted; every query so far is a
`select`.**

---

## 1. A CORRECTION TO MY OWN U1 RECORD, MADE BEFORE ACTING ON IT

**U1 said the four orphans were post attachments. THAT WAS WRONG.**

`docs/phase-4-u1-baseline.md` §3.3 reads: *"All four are 4-segment paths, i.e.
the `users/<uid>/<postID>/<attachmentID>.<ext>` shape … so all four are post
attachments that lost their reference, which is B-8's exact stated mechanism."*

**Segment 3 of all four is the literal string `connected`.** Both shapes have
four segments, which is why a segment *count* could not tell them apart:

| kind | shape | source |
|---|---|---|
| post attachment | `users/<uid>/<postID>/<attachmentID>.<ext>` | `BackendShim:1191` |
| **direct send** | **`users/<uid>/connected/<assetID>.<ext>`** | `ConnectedAttachmentSharing:213` |

**All four candidates are DIRECT-SEND objects**, not post attachments. U1 counted
segments and inferred a shape — the same class of error B-8 warns about, one
level up. **The count was right; the characterisation was not.**

This matters: it makes `connected_attachments` the table that governs them, so
the B-8 guard is the operative test rather than an adjacent caution.

---

## 2. THE REFERENCE SET, RECOMPUTED FROM FIRST PRINCIPLES

```sql
post_refs : posts.attachments ->> 'path'            -- 10 rows, 10 distinct
live_ca   : connected_attachments.storage_path
            WHERE deleted_at IS NULL                --  6 rows,  6 distinct
refs      : post_refs UNION live_ca                 -- 16 distinct
```

| measure | value |
|---|---|
| `attachments` objects | **15** |
| referenced | **11** |
| **unreferenced (candidates)** | **4** |
| **dangling references** (a ref with no object) | **5** — see §5 |

**Liveness is read from `connected_attachments.deleted_at`, never from the
`users/<uid>/` prefix**, and **a dead sender uid in a path is not treated as
evidence of anything** — B-22's recorded false positive.

---

## 3. THE B-8 GUARD, APPLIED EXPLICITLY TO EACH CANDIDATE

**The guard:** *an object is deletable only if NOTHING references it — and
"nothing" is established from rows, on more than one key, never from the path.*

| hash8 | ext | created | bytes | post JSON ref | live `ca` ref | soft-deleted `ca` ref | **any `ca` row by `storage_path`** | **any `ca` row by `asset_id`** | other-bucket row | post JSON mentions assetID |
|---|---|---|---|---|---|---|---|---|---|---|
| **`c27236f6`** | pdf | 2026-08-11 | 1,938 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |
| **`76f5d323`** | jpg | 2026-08-14 | 313,192 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |
| **`8bbe612d`** | pdf | 2026-08-14 | 54,338 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |
| **`fe3cdd49`** | pdf | 2026-08-15 | 148,684 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |

**Two independent keys agree, plus a full-text scan.** `storage_path` equality
could miss a row whose path was written differently, so each candidate's embedded
`assetID` was also matched against `connected_attachments.asset_id` **with no
`deleted_at` filter at all** — catching soft-deleted and live rows alike — and
`posts.attachments::text` was scanned for the assetID as a substring.

**Every candidate has ZERO `connected_attachments` rows of any kind.** There is
no recipient reference to preserve, live or withdrawn, so **B-22's "preserved
asset of a departed sender" case does not arise** — that case requires a
surviving row, and there is none.

**`post_id_survives = 0` for all four is NOT evidence and is not used as such**:
segment 3 is `connected`, not a post id, so the test was vacuous. Recorded so it
is not mistaken for a signal.

**Total to be freed: 518,152 bytes.**

---

## 4. MUTATION PLAN

- **Delete exactly 4 objects, by explicit full path**, from a candidate list
  staged **outside the repository** (no raw UID enters git; the durable record
  carries `md5[0:8]` only, per U3's rule).
- **The paths are re-derived at mutation time and each one's hash is checked
  against the four above before its DELETE is issued.** If the fresh candidate
  set differs in any way — count, hashes, order-independent membership — **stop
  and report.**
- **No prefix sweep. No predicate-driven bulk delete. No row deletion of any
  kind** — B-8 does not require one here, since there are no rows.
- **After each delete, that exact object is confirmed absent before the next.**
- **Any failure, or any candidate becoming referenced between now and then →
  stop, do not repair forward.**

## 5. THE DANGLING REFERENCES — PRE-EXISTING, AND U4 DOES NOT ADDRESS THEM

**Five references point at objects that do not exist**, and **all five are live
`connected_attachments` rows** — none from posts, so no feed attachment is
broken. Of the 6 live `ca` rows, **5 reference missing objects and 1 references a
surviving object.**

**This is the inverse of B-8 — an unreferenced ROW, not an unreferenced
OBJECT — and it exists before U4 touches anything.** Consistent with the
2026-08-11 sweep recorded in `CLAUDE.md` ("30 dead `connected_attachments` rows
with no surviving storage").

**Therefore the acceptance criterion "no surviving live reference points to a
missing object" CANNOT BE MET BY U4, and U4 will not be recorded as meeting
it.** Satisfying it means deleting `connected_attachments` rows — a separate
mutation, separately predicted, on a table whose retention rules are governed by
the expiry matrix. **It is flagged here for a decision, not silently absorbed.**

## 6. PREDICTED FINAL STATE

| measure | before | **predicted after** |
|---|---|---|
| `attachments` objects | 15 | **11** |
| referenced | 11 | **11** |
| **unreferenced** | 4 | **0** |
| `posts` / public / false / null | 101 / 101 / 0 / 0 | **unchanged** |
| distinct owners | 9 | **9** |
| post attachment refs | 10 | **10** |
| `connected_attachments` rows / live | 31 / 6 | **31 / 6 — unchanged** |
| **dangling references** | 5 | **5 — unchanged, see §5** |
| `avatars` objects | 3 | **3** |
| `post_comments` / `follows` / `post_shares` | 5 / 9 / 0 | **unchanged** |

## 7. OUT OF SCOPE

**U5 not started.** No client code, no policy, no schema change. No membership
state, no U6b enforcement change, no Device A action. **U2b/U2s device
verification remains outstanding** (Phase 4 exit condition 8).
