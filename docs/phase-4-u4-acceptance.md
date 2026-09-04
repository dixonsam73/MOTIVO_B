# P4-U4 / B-8 — STORAGE ORPHAN CLEANUP. ACCEPTANCE.

**Executed 2026-09-04. Prediction committed beforehand at `bb1286d`.**
**Every predicted value matched. 4 objects deleted, 518,152 bytes freed, no row
deleted, nothing repaired forward.**

---

## 1. A CORRECTION TO MY OWN U1 RECORD, MADE BEFORE ACTING ON IT

**U1 said the four orphans were post attachments. That was wrong**, and it was
caught by looking rather than by re-reading.

`phase-4-u1-baseline.md` §3.3 claimed the four were
`users/<uid>/<postID>/<attachmentID>.<ext>` — *"post attachments that lost their
reference, which is B-8's exact stated mechanism."*

**Segment 3 of all four is the literal string `connected`.** Both shapes carry
four segments, which is exactly why a segment *count* cannot distinguish them:

| kind | shape | source |
|---|---|---|
| post attachment | `users/<uid>/<postID>/<attachmentID>.<ext>` | `BackendShim:1191` |
| **direct send** | **`users/<uid>/connected/<assetID>.<ext>`** | `ConnectedAttachmentSharing:213` |

**U1 counted segments and inferred a shape — the same class of error B-8 warns
about, one level up.** The count was right; the characterisation was not. It
mattered: it moves the governing table from `posts` to `connected_attachments`,
which makes the B-8 guard the operative test rather than an adjacent caution.

---

## 2. THE B-8 GUARD, AND HOW IT WAS APPLIED

**The guard:** *delete only if NOTHING references the object — established from
ROWS, on more than one key, never from the path.*

**Liveness came from `connected_attachments.deleted_at`. The `users/<uid>/`
prefix was used for nothing**, and a dead sender uid in a path was treated as
evidence of nothing — B-22's recorded false positive, where such a heuristic
flagged D5's survivor precisely because the prefix carries the *sender's* uid and
a dead sender is the **correct** state for a preserved asset.

| hash8 | ext | created | bytes | post JSON | live `ca` | soft-del `ca` | **`ca` by `storage_path`** | **`ca` by `asset_id`, no `deleted_at` filter** | other bucket | post JSON mentions assetID |
|---|---|---|---|---|---|---|---|---|---|---|
| `c27236f6` | pdf | 2026-08-11 | 1,938 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |
| `76f5d323` | jpg | 2026-08-14 | 313,192 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |
| `8bbe612d` | pdf | 2026-08-14 | 54,338 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |
| `fe3cdd49` | pdf | 2026-08-15 | 148,684 | 0 | 0 | 0 | **0** | **0** | 0 | 0 |

**Two independent keys, plus a full-text scan.** Path equality alone could miss a
row whose `storage_path` was written differently, so each candidate's embedded
`assetID` was matched against `connected_attachments.asset_id` **with no
`deleted_at` filter at all** — catching live and withdrawn rows alike — and
`posts.attachments::text` was scanned for the assetID as a substring.

**Every candidate had ZERO `connected_attachments` rows of any kind.** B-22's
"preserved asset of a departed sender" case requires a *surviving row*, and there
was none — so it did not arise, rather than being argued away.

**`post_id_survives = 0` is recorded as VACUOUS, not as evidence**: segment 3 is
`connected`, not a post id, so the test could only ever return 0.

---

## 3. THE DELETION — AND A VERIFICATION METHOD THAT WAS ITSELF WRONG

The candidate set was **re-derived immediately before mutation** and its hashes
compared to the committed four: **exact match, 4 of 4**. Paths were staged
**outside the repository**; only `md5[0:8]` appears in git.

| hash8 | DELETE | rows left in `storage.objects` |
|---|---|---|
| `c27236f6` | **200** | **0** |
| `76f5d323` | **200** | **0** |
| `8bbe612d` | **200** | **0** |
| `fe3cdd49` | **200** | **0** |

### 3.1 THE FIRST RUN STOPPED ITSELF, AND THE VERIFIER WAS AT FAULT

The first attempt verified absence with an **HTTP `GET`** on the deleted object.
`GET` returned **200 after a successful DELETE**, so the script declared *"OBJECT
STILL PRESENT"* and **stopped before touching the other three** — exactly as its
stop rule required.

**The delete had in fact succeeded.** The authoritative check —
`storage.objects` in the database — showed **15 → 14** and `c27236f6` gone.

**This is B-22's lesson inverted.** B-22 recorded an action that *silently
succeeded-looking while doing nothing*; here the action worked and **the
verification method lied in the other direction**. A verifier that reports the
wrong answer is as dangerous as an action that silently fails, and the fix was
the same in both cases: **ask the database, not the thing being asked to act.**
The remaining three were verified against `storage.objects` per object.

**A second, unrelated stop:** the retry loop's `for H in $REMAIN` did not
word-split, because **this shell is zsh**, where unquoted parameter expansion
does not split by default. It printed the whole list as one token and stopped
rather than deleting anything. **A bug in my script, not in the data** — recorded
because a silent mis-split could just as easily have expanded a path.

**No deletion proceeded past a failed check, and nothing was repaired forward.**

---

## 4. INDEPENDENT POST-CLEANUP VERIFICATION

The reference set was **recomputed from first principles** after cleanup, not
carried forward:

| measure | before | **after** | predicted |
|---|---|---|---|
| `attachments` objects | 15 | **11** | 11 ✓ |
| **referenced** | 11 | **11** | 11 ✓ |
| **unreferenced** | 4 | **0** | 0 ✓ |
| dangling references | 5 | **5** | 5 ✓ (§5) |

**Survivors were enumerated, not counted:** the unreferenced-object query
returned **no rows at all**.

| relational measure | before | after |
|---|---|---|
| `posts` / public / private | 101 / 101 / 0 | **101 / 101 / 0** |
| distinct owners | 9 | **9** |
| post attachment refs | 10 | **10** |
| `connected_attachments` rows / live | 31 / 6 | **31 / 6** |
| `avatars` objects | 3 | **3** |
| `post_comments` / `follows` / `post_shares` | 5 / 9 / 0 | **5 / 9 / 0** |

**No row of any kind was deleted.**

---

## 5. THE ONE ACCEPTANCE CRITERION U4 DOES **NOT** MEET

> *"no surviving live reference points to a missing object"*

**Not met, and not claimed. It was already false before U4 began.**

**5 dangling references exist, and all five are live `connected_attachments`
rows** — none from `posts`, so **no feed attachment is broken**. Of the 6 live
`ca` rows, **5 point at objects that do not exist** and 1 points at a survivor.

**This is the inverse of B-8** — an unreferenced **row**, not an unreferenced
**object** — and U4 neither created it nor addressed it. It is consistent with
the 2026-08-11 sweep recorded in `CLAUDE.md` (*"30 dead `connected_attachments`
rows with no surviving storage"*).

**Satisfying it means deleting `connected_attachments` rows**, a separate
mutation on a table whose retention is governed by the expiry matrix, and it must
be separately predicted. **Flagged for a decision, not absorbed.**

---

## 6. GATES

**No source, schema, policy or client change** — `git diff bb1286d -- 'MOTIVO/*.swift' supabase/schema supabase/migrations supabase/functions` is empty, so builds and `MOTIVOTests` are not re-run (green at `4febb8b`, nothing changed since).

| gate | result |
|---|---|
| `p4/u2s-acceptance.sh` | **12 / 12** |
| `p4/u2c-acceptance.sh` | **20 / 20** |
| `p4/u2b-acceptance.sh` | **16 / 16** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **16 / 16** |
| `u5/client-structural.sh` | **60 / 60** |
| `p4/u1-baseline.sh` | 10 pass / its 6 documented flips |

## 7. REMAINING PHASE 4

**U5** (B-15 anti-browse + C-34's version signal) · **U6** (C-51) · **U7**
(C-58) · **U8** (copy and App Store privacy disclosures) · **exit condition 8**
— the Device A run, owning both U2b's and U2s's production behavioural
observations · **and now the dangling-`ca`-rows decision from §5.**

**B-8 itself is discharged for OBJECTS.** Carried from Phase 3 and untouched:
C-31, B-34, G7, B-11's production GRANT.
