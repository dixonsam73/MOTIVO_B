# P5-C / CP-0 — EXECUTED AND VERIFIED. 2026-09-06

**THE PRE-RELEASE RESET IS DONE. 15 dormant beta identities and their
server-side data are permanently deleted. Samuel and Steve survive intact.**

Executed exactly the committed `8b7434a` preflight. **No widening of the 15-user
set. No repair-forward. No guard was relaxed.**

---

## 1. RESULT — EVERY PREDICTED FIGURE MATCHED

**The transaction's own verification row, returned before `commit`:**

| measure | POST | predicted | | measure | POST | predicted |
|---|---|---|---|---|---|---|
| `auth.users` | **2** | 2 ✓ | | `shadow_enforcement_stat` | **75** | 75 ✓ |
| `account_directory` | **2** | 2 ✓ | | `membership_notification` | **74** | 74 ✓ |
| `posts` | **7** | 7 ✓ | | `auth.identities` | **2** | 2 ✓ |
| `post_comments` | **5** | 5 ✓ | | `auth.sessions` | **23** | ~23 ✓ |
| `post_shares` | **0** | 0 ✓ | | `auth.refresh_tokens` | **382** | ~382 ✓ |
| `post_comment_views` | **3** | 3 ✓ | | `auth.mfa_amr_claims` | **23** | ~23 ✓ |
| `follows` | **2** | 2 ✓ | | storage `avatars` | **3** | 3 ✓ *(untouched)* |
| `follows` approved | **2** | 2 ✓ | | storage `attachments` | **10** | 10 ✓ *(untouched)* |
| `connected_attachments` | **25** | 25 ✓ | | **keeper mutual follow** | **2** | **2 ✓** |
| `membership` / `binding` / conflicts | **1 / 1 / 0** | 1 / 1 / 0 ✓ | | | | |

**21 of 21 matched, including all three volatile auth measures, which landed on
their exact predicted values rather than merely near them.**

**The two storage figures correctly report the PRE-deletion values**, because
storage had not been touched at commit time — the preflight's stated tell that a
run reporting 1 and 8 there would have done something nobody asked for.

## 2. INDEPENDENT VERIFICATION — NOT THE RETURNED ROW

Re-queried from a fresh statement after commit:

| | `1fbf664a` **Samuel** | `64ffb132` **Steve** |
|---|---|---|
| directory row / `lookup_enabled` / `follow_requests_enabled` | ✓ / T / T | ✓ / T / T |
| avatar | **✓ retained** | – |
| posts | **6** | **1** |
| comments authored / on own posts | **4 / 2** | **1 / 3** |
| following / followers | **1 / 1** | **1 / 1** |
| `post_comment_views` | **3** | 0 |
| membership / binding | 0 / 0 | **1 / 1** |
| `auth.identities` | **1** | **1** |

**Exactly 2 identities survive.** 6 + 1 = **7 posts**; 4 + 1 = **5 comments**;
the **mutual approved follow survives in both directions**; Steve's Connected
membership and binding are intact; Samuel's avatar — the one C-34's replacement
test needs — is retained.

**Samuel's `following` went 6 → 1 exactly as predicted**, because his five
outgoing `requested` rows pointed at deleted identities. **Predicted in §3 of the
census, not discovered afterwards.**

## 3. STORAGE — 4 OBJECTS DELETED, BUT NOT IN ONE PASS

**Final state verified against `storage.objects`, never an HTTP `GET`:**

| | actual | predicted |
|---|---|---|
| `avatars` | **1** | 1 ✓ |
| `attachments` | **8** | 8 ✓ |
| total objects | **9** | 9 ✓ |
| **objects not owned by a keeper** | **0** | 0 ✓ |
| post attachment references | **8** | 8 ✓ |
| **dangling references** | **0** | **0 ✓** |
| directory rows with `avatar_key` | **1** | 1 ✓ |
| **dangling `avatar_key`** | **0** | **0 ✓** |

**Zero mismatches.** No retained post points at deleted bytes, and the retained
avatar still resolves.

### 3.1 THE FIRST PASS DELETED 3 OF 4, AND EVERY OPERATION REPORTED SUCCESS

**A shell defect of mine, not a storage failure.** The staged target file was
written with `'\n'.join(...)` and therefore had **no trailing newline**, so
`while read` silently dropped the final line. Three `DELETE`s ran, **each
returning HTTP 200 `{"message":"Successfully deleted"}`**.

**Every individual operation succeeded and the set was still incomplete.** That
is the same failure class this project already documents twice — `supabase
storage rm` exiting 0 having issued no request, and *"Success. No rows returned"*
disguising a migration that never ran — **arriving from a third direction: the
loop, not the command.** Per-item success is not set-level success, and a
completion count is the only thing that distinguishes them.

**It was caught by re-measuring rather than by reading the output**, because the
output looked perfect.

### 3.2 Recovery followed the authorised procedure exactly

**The database transaction was not re-run and not altered.** Storage state was
re-measured; `attachments` had already reached its target of 8; **one authorised
path remained** (`avatars`, owner `daed2252`). It was re-verified as
**unreferenced with its owner deleted** immediately before the retry, then
deleted — HTTP 200 — and the full verification above was run afterwards.

**No path outside the four authorised was touched at any point.**

## 4. TWO TOOLING FINDINGS THAT OUTLIVE THIS UNIT

**`supabase db query` IS NOT SINGLE-STATEMENT at CLI 2.113.0.** CLAUDE.md
records it as refusing more than one statement; it **accepts a full
multi-statement submission**, executes every statement, and **returns only the
last statement's rows**. That is what made the committed transaction executable
as written — `begin … commit; select …` — with the verification `select` last so
it is the row that comes back.

**A `raise` aborts the WHOLE submission — established by probe before the
destructive run, not assumed.** A deliberate `raise exception` inside a
transaction returned HTTP 400 and the statement after `commit` **did not
execute**. Had statements been independent, every guard in this transaction
would have been decorative. **The exit code was 0 in that failure**, so the
response body is the only reliable signal.

## 5. WHAT WAS NOT TOUCHED

`connected_attachments` (25, guarded at zero references), `membership_control`
and `enforcement_enabled` (still true), `membership_notification` (74), the eight
keeper-owned attachment objects, and every other table classified as retained.
**`membership_cutover` did not exist to clean.**

## 6. STATUS

**CP-0 complete. CP-1 apply NOT started, as instructed.**

**Samuel remains a standing keeper. Steve remains a temporary Phase 4 fixture
keeper** and carries no retention claim once Phase 4's conditions 2 and 8 and
C-34 are dispositioned.
