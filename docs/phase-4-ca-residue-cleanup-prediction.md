# HISTORICAL `connected_attachments` RESIDUE CLEANUP — PREDICTION

**Written 2026-09-04 at `0440e2f`, BEFORE any mutation.** Authorised by the
account holder after the read-only characterisation.

---

## 1. WHAT THIS IS, RECORDED IN FOUR PARTS SO IT CANNOT LATER BE MISREAD

1. **These six rows are confirmed HISTORICAL BETA/TEST RESIDUE by human
   identification.** The account holder, asked directly, answered: *"all six are
   test debris — none worth preserving."* **This is evidence the database cannot
   supply** — no column records that an attachment was a test, both counterpart
   accounts are deleted, and the filenames are suggestive at best.
2. **They predate the current, fixed lifecycle path.** Created 2026-07-14 →
   2026-08-10; already present when B-22 measured them on **2026-08-13**, the
   day the `ca00189` rewrite was deployed.
3. **The current deployed deletion mechanism removes `connected_attachments`
   rows on BOTH sides** — received on `recipient_user_id`
   (`delete_account_v1:138-140`), sent on `sender_user_id` (`:227-229`), with the
   function's own header stating *"every `connected_attachments` row naming them
   on either side is gone (B-9 subsumed)"* (`:21`). **This cleanup is therefore
   NOT remediation of a currently reachable defect.**
4. **B-22 deliberately preserved this population at the time.** This is an
   **explicit later disposition made on evidence that was not then available** —
   specifically the account holder's identification of the content as test debris
   — **and NOT a retroactive claim that B-22 was incorrect.** B-22's decision was
   right on what it knew: it declined to destroy content it could not identify.

---

## 2. THE EXACT CANDIDATE SET — SIX ROWS, ONE OBJECT

Hashes are `md5[0:8]`. Raw ids and the raw path are staged **outside the
repository**; only hashes enter git.

| # | row hash | path hash | object exists |
|---|---|---|---|
| 1 | `c733af34` | `3d9148ae` | no |
| 2 | `ab2d4b54` | `8f3b3a04` | no |
| 3 | `0b10d4cb` | `9a6419f7` | no |
| 4 | `78646d9c` | `ab50a0f4` | no |
| 5 | `1f9cb972` | `8740915d` | no |
| 6 | **`29c994f5`** | **`a70d8d26`** | **YES — the paired operation** |

**No predicate sweep.** Every delete names one id, or one path.

---

## 3. ORDERING — CHOSEN SO REFERENTIAL STATE NEVER DEGRADES

**The object is deleted BEFORE its row.**

Deleting the row first would briefly turn `a70d8d26` into an **unreferenced
object** — the B-8 category U4 has just emptied, and the more confusing of the
two intermediate states. Deleting the object first briefly makes row `29c994f5`
a **sixth dangling row** — a category that already exists, is already understood,
and is resolved one step later. It is also the same objects-before-row ordering
`deletePost` uses for its fail-closed guarantee.

### 3.1 Predicted state at every step

| after | `ca` rows | live `ca` | objects | referenced | unreferenced | **dangling** |
|---|---|---|---|---|---|---|
| **start** | 31 | 6 | 11 | 11 | 0 | 5 |
| step 1 — delete object `a70d8d26` | 31 | 6 | **10** | **10** | 0 | **6** |
| step 2 — delete row `29c994f5` | **30** | **5** | 10 | 10 | 0 | **5** |
| step 3 — delete rows 1–5 | **25** | **0** | 10 | 10 | 0 | **0** |

**Step 1 is the only moment `dangling` rises, and it is immediately paid back by
step 2.** The two are a deliberately paired operation.

---

## 4. VERIFICATION RULES

- **Every check is against authoritative database/storage state** — `storage.objects`
  and `public.connected_attachments` — **never an HTTP `GET`.** U4 recorded a
  `GET` returning **200 after a successful DELETE**, which stopped that run on a
  false negative.
- Each deletion is confirmed before the next is issued.
- **Any mismatch from the committed candidate set or the predicted counts → stop
  immediately, do not repair forward.**

## 5. EXPECTED SETTLED STATE

| measure | before | after |
|---|---|---|
| `connected_attachments` | 31 | **25** |
| live `connected_attachments` | 6 | **0** |
| dangling live references | 5 | **0** |
| attachment Storage objects | 11 | **10** |
| referenced objects | 11 | **10** |
| unreferenced objects | 0 | **0** |
| all remaining `ca` rows soft-deleted | — | **25 of 25** |
| posts / avatars / comments / follows / shares | 101 / 3 / 5 / 9 / 0 | **unchanged** |

## 6. INTEGRITY, TO BE RE-RUN FROM BOTH DIRECTIONS

1. **no unreferenced Storage object**;
2. **no live `connected_attachments` row referencing a missing object**;
3. **no live post attachment reference pointing to a missing object.**

**On success, U4's one unmet acceptance criterion — "no surviving live reference
points to a missing object" — becomes satisfied by this explicit follow-on**, and
is to be recorded as satisfied *here*, not backdated into U4.

## 7. OUT OF SCOPE

**U5 not started.** No client code, no policy, no schema change. No membership
state, no U6b enforcement change, no Device A action.
