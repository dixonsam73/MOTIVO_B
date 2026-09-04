# THE SIX LIVE `connected_attachments` ROWS — CHARACTERISED AND DISPOSITIONED

**2026-09-04, at `7bd1543`. READ-ONLY. No row deleted, no Storage touched.**

Surfaced by U4 as the inverse of B-8: **unreferenced ROWS, not unreferenced
objects.** U4 discharged B-8 for objects and explicitly declined to absorb this.

---

## 1. THEY ARE B-22's KNOWN RESIDUE — MATCHED NUMERICALLY, NOT BY IMPRESSION

`CLAUDE.md` records what B-22 **deliberately left behind** on 2026-08-13. Today:

| B-22's recorded leftovers | measured 2026-09-04 |
|---|---|
| "29 `connected_attachments` rows with both parties deleted" | **29** |
| "one live row from a *live* sender to a deleted recipient" | **1** |

The 6 live rows are **5 (both parties deleted) + that 1**. **No archaeology was
required**; the register already answered it.

## 2. NOBODY CAN SEE ANY OF THEM

`fetchReceived` filters on `recipient_user_id` and `deleted_at is null` and
**never tests object existence** (`ConnectedAttachmentSharing:279-288`) — so
these rows *would* be returned to their recipient. But
**`rows_with_a_surviving_recipient` = 0**: every recipient account has been
deleted from `auth.users`, so no client can authenticate as one.

**Not user-visible, and not capable of becoming so.**

## 3. THE SIX ROWS

Hashes are `md5[0:8]`; no raw production UUID appears here.

| # | row / path | object | created | filename | shown as | type | size | sender | recipient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `c733af34` / `3d9148ae` | **gone** | 2026-07-14 17:28 | `All the Better Stuff.pdf` | — | PDF 3pp | 425 KB | `6acb62` deleted | `b41994` deleted |
| 2 | `ab2d4b54` / `8f3b3a04` | **gone** | 2026-07-20 17:58 | `ATGS 2.pdf` | `ATGS 2.pdf` | PDF 159pp | 13.8 MB | `b41994` deleted | `6acb62` deleted |
| 3 | `0b10d4cb` / `9a6419f7` | **gone** | 2026-07-20 17:58 | `18802413-….jpg` | `Photo` | JPEG | 3.5 MB | `b41994` deleted | `6acb62` deleted |
| 4 | `78646d9c` / `ab50a0f4` | **gone** | 2026-07-20 18:12 | `Teste.mov` | `Teste` | QuickTime | 2.5 MB | `b41994` deleted | `6acb62` deleted |
| 5 | `1f9cb972` / `8740915d` | **gone** | 2026-07-20 20:03 | `p3.I.m4a` | `p3.I` | M4A | 293 KB | `6acb62` deleted | `b41994` deleted |
| 6 | `29c994f5` / `a70d8d26` | **EXISTS** | 2026-08-10 10:57 | `All the Better Stuff.pdf` | `All the Better Stuff — Page 12.pdf` | PDF 1p | 124 KB | **Samuel Dixon** (`samueldixon`) | `a9219c` deleted |

Rows 1–5 are **two accounts sending to each other in both directions**, all July,
before Phase 3 began (2026-08-16). Row 6 is the account holder's own send.

## 4. PROVENANCE — SUPPLIED BY THE ACCOUNT HOLDER, WHICH THE DATABASE CANNOT

**2026-09-04, in answer to a direct question: "all six are test debris — none
worth preserving."**

**Recorded because it is unrecoverable from the data.** No table records that an
attachment was a test; the accounts are deleted; the filenames (`Teste.mov`,
`ATGS 2.pdf`, `p3.I.m4a`) are suggestive and nothing more. **This identification
is evidence of a kind the database cannot supply, and re-deriving it later would
be impossible.**

## 5. THE PRODUCING MECHANISM IS ALREADY FIXED — SO THIS IS NOT A LIVE DEFECT

That was the half of the question worth answering, and it is answered from the
**deployed** function's own text:

> *"Consequently every `connected_attachments` row naming them on either side is
> gone (B-9 subsumed)."* — `delete_account_v1/index.ts:21`

The current path deletes **both** sides: received rows keyed on
`recipient_user_id` (`:138-140`) and sent rows on `sender_user_id`
(`:227-229`).

**These six predate that.** They were created 2026-07-14 → 2026-08-10 and were
already present when B-22 measured them on **2026-08-13** — the same day the
rewrite (`ca00189`, B-1/B-3 revised) was deployed. **They are residue of the OLD
deletion path, not evidence that the current one strands rows.**

**Conclusion: historical test debris from a mechanism that no longer exists.
There is no current lifecycle defect here.**

## 6. STATUS

**Not cleared. No register row owns them** — B-22 is Resolved, B-10 is the
dormant SQL trigger functions, B-16 is `post_comment_views`. They are
deliberately-retained residue whose provenance is now settled.

**A cleanup is proposed separately, with its own prediction, and has not been
performed.**
