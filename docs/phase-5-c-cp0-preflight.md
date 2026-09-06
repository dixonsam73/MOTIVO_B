# P5-C / CP-0 — FINAL PREFLIGHT. 2026-09-06

**NOT EXECUTED. NO MUTATION. `SELECT` ONLY.** Awaiting execution authorization.

Delete set **15**. **Samuel `1fbf664a` — standing keeper.**
**Steve `64ffb132` — temporary Phase 4 fixture keeper.**

---

## 1. FRESH RE-CENSUS — 27 MEASURES, **ZERO DRIFT**

Re-taken from production immediately before this preflight and compared to the
committed prediction line by line.

| measure | fresh | predicted | | measure | fresh | predicted |
|---|---|---|---|---|---|---|
| `auth.users` | 17 | 17 ✓ | | `shadow_enforcement_stat` | 79 | 79 ✓ |
| delete set resolves | 15 | 15 ✓ | | `membership_notification` | 74 | 74 ✓ |
| keep set resolves | 2 | 2 ✓ | | `auth.identities` | 17 | 17 ✓ |
| `account_directory` | 17 | 17 ✓ | | `auth.sessions` | 44 | 44 ✓ |
| `posts` | 101 | 101 ✓ | | `auth.refresh_tokens` | 769 | 769 ✓ |
| `posts` in delete set | 94 | 94 ✓ | | `auth.mfa_amr_claims` | 44 | 44 ✓ |
| `post_comments` | 5 | 5 ✓ | | storage `avatars` | 3 | 3 ✓ |
| `post_shares` | 0 | 0 ✓ | | storage `attachments` | 10 | 10 ✓ |
| `post_comment_views` | 9 | 9 ✓ | | **keeper mutual approved follow** | **2** | **2 ✓** |
| `post_comment_views` to delete | 6 | 6 ✓ | | CA rows referencing delete set | 0 | 0 ✓ |
| `follows` | 9 | 9 ✓ | | comments on deleted posts | 0 | 0 ✓ |
| `follows` approved | 4 | 4 ✓ | | `connected_attachments` | 25 | 25 ✓ |
| `membership` / `binding` / conflicts | 1 / 1 / 0 | 1 / 1 / 0 ✓ | | | | |

**DRIFT COUNT: 0.** The prediction stands unmodified.

**Two measures are VOLATILE and are advisory, not abort conditions:**
`auth.sessions` and `auth.refresh_tokens` move whenever Device A or Device B
refreshes a token, which can happen between this preflight and execution.
**They are deliberately absent from the in-transaction drift guard (1f)** —
including them would abort a correct run over a routine token refresh. Their
POST values below are expected-approximate; every other figure is exact.

---

## 2. THE POST-ATTACHMENT EDGE — CLOSED, AND MY EARLIER REASONING CORRECTED

**`posts.attachments` is a `jsonb` COLUMN, not a table.** Every element carries
`bucket` and `path` — a **direct storage reference**. 8 posts carry a non-empty
array; 93 are `[]`; none is null.

**Measured cross-reference of all 10 references against `storage.objects`:**

| | count |
|---|---|
| total attachment references across all posts | **10** |
| references that resolve to a real object | **10** |
| **dangling references** | **0** |
| references from **kept** posts | **8** — `1fbf664a` ×7, `64ffb132` ×1 |
| references from **deleted** posts | **2** — `daed2252` ×1, `41aacc65` ×1 |
| **kept post → object owned by a deleted identity** | **0** |
| **deleted post → object owned by a keeper** | **0** |

**The relationship is 1:1 and perfectly partitioned.** The `attachments` bucket
holds exactly 10 objects and exactly 10 references point at them, one each. The
2 objects owned by delete-set identities are referenced **only** by posts that
are themselves being deleted, and no retained post references them.

### The three questions, answered

1. **Does any live storage object become orphaned by deleting the 94 posts?**
   **Yes — exactly 2**, and both are already in the post-commit deletion list
   (§6). No others: `deleted post → keeper object` is **0**.
2. **Does any retained metadata become orphaned?**
   **No.** `kept post → deleted-identity object` is **0**, so deleting those 2
   objects cannot leave a retained post pointing at missing bytes.
3. **Which mechanism removes the associated metadata?**
   **The post row's own deletion.** `attachments` is a column, so the metadata
   is removed inline with `delete from public.posts` — **no separate statement,
   no cascade, and no table of attachment rows exists for post attachments.**
   `connected_attachments` is a **different mechanism** (direct member-to-member
   sends) and is unrelated to post attachments; **0 of its rows reference the
   delete set**, so it is untouched.

### CORRECTION TO MY OWN EARLIER JUSTIFICATION

The prediction said deleting the 2 objects *"strands nothing"* because **"all 10
attachment objects are already unreferenced"**. That was measured **only against
`connected_attachments`**, and while it was written with that qualifier, the
unqualified reading is **false**: all 10 are referenced — by `posts.attachments`.

**The conclusion was right and the reasoning was wrong.** The correct reason to
delete those 2 objects is that their **only** references are on posts being
deleted in the same operation. **This is corrected because the reasoning is what
the next person implements from** — the D14/B-9 lesson, where a finding's
conclusion held while its stated reason would have produced a destructive
implementation.

---

## 3. DELETION ORDER — EXPLICIT SQL, IN THE MEASURED DEPENDENCY ORDER

| # | statement | rows | why this position |
|---|---|---|---|
| **1** | `delete from public.post_comment_views` where viewer ∈ delete-set **or** post ∈ deleted-posts | **6** | **No FK in either direction.** It orphans off deleted viewers *and* deleted posts, so it must go before both |
| **2** | `delete from public.posts` where owner ∈ delete-set | **94** | Removes the `attachments` jsonb inline (§2). Cascades `post_comments`/`post_shares` via `post_id` |
| **3** | `delete from auth.users` where id ∈ delete-set | **15** | **Strictly last.** Everything else cascades from here |

**Only three explicit statements.** The delete set is **15 enumerated UUIDs**,
staged outside the repository; the transaction then **proves the enumeration
matches this census by `md5[0:8]`**.

---

## 4. MEASURED CASCADE-ONLY TABLES — no statement issued

| table | cascades from | PRE → **POST** | deleted |
|---|---|---|---|
| `public.post_comments` | `posts.id` | 5 → **5** | 0 |
| `public.post_shares` | `posts.id` | 0 → **0** | 0 |
| `public.account_directory` | `auth.users.id` | 17 → **2** | 15 |
| `public.follows` | `auth.users.id` ×2 | 9 → **2** | 7 |
| `public.membership` | `auth.users.id` | 1 → **1** | 0 |
| `public.membership_binding` | `auth.users.id` | 1 → **1** | 0 |
| `public.membership_binding_conflict` | `auth.users.id` | 0 → **0** | 0 |
| `public.shadow_enforcement_stat` | `auth.users.id` | 79 → **75** | 4 |
| `auth.identities` | `auth.users.id` | 17 → **2** | 15 |
| `auth.sessions` | `auth.users.id` | 44 → **~23** | ~21 *(volatile)* |
| `auth.refresh_tokens` | `auth.sessions.id` *(transitive)* | 769 → **~382** | ~387 *(volatile)* |
| `auth.mfa_amr_claims` | `auth.sessions.id` *(transitive)* | 44 → **~23** | ~21 *(volatile, 1:1 with sessions)* |
| `auth.mfa_factors`, `oauth_consents`, `one_time_tokens`, `webauthn_credentials`, `oauth_authorizations`, `webauthn_challenges` | `auth.users.id` | 0 → **0** | 0 |

---

## 5. RETAINED TABLES AND THEIR ZERO-REFERENCE GUARDS

| table | PRE → **POST** | guard |
|---|---|---|
| `public.connected_attachments` | 25 → **25** | **1g** — aborts if any row's sender **or** recipient is in the delete set. Measured **0** |
| `public.post_comments` | 5 → **5** | **1h** — aborts if any comment sits on a post being deleted. Measured **0** |
| `public.membership_notification` | 74 → **74** | not user-keyed |
| `public.membership_control` | unchanged | singleton; `enforcement_enabled` stays **true** |
| `public.membership_notification_reject_stat` | unchanged | aggregate |
| `auth.audit_log_entries`, `auth.flow_state` | 0 → **0** | empty, no FK |
| **the 8 keeper-owned attachment objects** | retained | §2 proves no deleted post references them |
| `storage.buckets` and all other storage tables | unchanged | no per-user rows |

**Guards 1g and 1h are guards, not no-op DELETEs, deliberately:** if drift
introduced such a row, CP-0 must **stop** rather than silently widen its own
blast radius.

**`membership_cutover` does not exist** and `connected_member()` carries no
grandfather arm — B-36's retirement is already applied. **Nothing to clean.**

---

## 6. FINAL TRANSACTION VERIFICATION ROW — EXPECTED VALUES

Returned by the `select` at the end of the transaction, before `commit`:

```
auth_users             2      comments               5      shadow                75
directory              2      shares                 0      notifications         74
posts                  7      comment_views          3      identities             2
follows                2      conn_attachments      25      sessions             ~23
follows_approved       2      membership             1      refresh_tokens      ~382
keeper_mutual_follow   2      binding                1      amr_claims           ~23
conflicts              0
obj_avatars            3   ← PRE-deletion, UNCHANGED
obj_attachments       10   ← PRE-deletion, UNCHANGED
```

**The two storage figures are deliberately the PRE-deletion values.** Storage is
not transactional with Postgres and has not been touched at commit time.
**A run reporting 1 and 8 here has done something nobody asked for.**

---

## 7. POST-COMMIT STORAGE DELETION AND ITS VERIFICATION

**Only after the transaction commits and §6 is checked.** Four objects, **by
explicit path**, staged outside the repository.

| bucket | owner `md5[0:8]` | objects | PRE → **POST** |
|---|---|---|---|
| `avatars` | `daed2252`, `c0464940` | 2 | 3 → **1** |
| `attachments` | `daed2252`, `41aacc65` | 2 | 10 → **8** |

**Verification is against `storage.objects`, never an HTTP `GET`** — P4-U4
measured a `GET` returning **200 after a successful DELETE** and stopped itself
over exactly that. **`supabase storage rm` silently no-ops** at CLI 2.113.0
(exit 0, empty `deleted` list, no DELETE issued); use the route in
`supabase/README.md`.

**Post-deletion assertions:** `avatars` = **1** (the retained `1fbf664a`
avatar C-34 needs); `attachments` = **8**; and **re-run §2's cross-reference —
`refs_dangling` must still be 0**, proving no retained post was left pointing at
deleted bytes.

**Ordering:** database first, storage second. An abort leaves the objects
present and nothing inconsistent; the reverse order could destroy objects for a
deletion that then rolls back, and **there is no backup of Domain 3 content.**

---

## 8. ABORT CONDITIONS

Any guard failure; any drift in a non-volatile measure; any verification-row
figure not matching §6. **The transaction rolls back whole, storage is untouched
because it is never reached, and the run is reported — not repaired forward, not
re-run with a widened predicate.**

## 9. STATUS

**NOT EXECUTED.** Awaiting explicit execution authorization.
