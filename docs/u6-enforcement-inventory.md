# U6 — CANONICAL ENFORCEMENT INVENTORY

**Produced by the U6a gate, 2026-08-30, from the live local B-23 reproduction —
not from prose.** Every row was read out of `pg_policies` and `pg_proc` on a
database carrying all four deployed migrations, and the counts agree with the
committed production snapshot in `supabase/schema/` (33 policies).

**This file is the object U6a's predictions are written against.** It is not a
summary of the design; it is the enumeration of every surface B-11 says is
unenforced, with the intended entitlement direction for each. **If a surface is
not in this file, U6 has not considered it.**

**NOTHING HERE IS IMPLEMENTED.** No policy has been altered, no grant changed,
no function created. `posts_select_public_or_owner` and the other 32 policies are
byte-identical to their deployed definitions.

---

## 0. The six dimensions

A single "is enforcement needed here" column would have hidden the four places
where the answer is *no* for a different reason each time. Every surface below
carries exactly one dimension.

| Dimension | What it governs |
|---|---|
| **R — read visibility** | What Connected content a viewer may SELECT |
| **W — write authority** | INSERT / UPDATE / DELETE of Connected content |
| **D — identity & directory discoverability** | Whether an identity can be *found* |
| **A — retained-content resolution** | Whether an already-authored artefact still resolves its author after that author lapses |
| **S — storage object access** | Bytes in the `attachments` and `avatars` buckets |
| **X — SECURITY DEFINER behaviour** | Surfaces that bypass RLS entirely, so policy work does not reach them |

## 0.1 The four directions

| Direction | Meaning |
|---|---|
| **GATE-VIEWER** | Require the **caller's** own entitlement. Deny when not entitled |
| **GATE-SUBJECT** | Require the **subject's** entitlement — the lapsed member disappears *for others*. **See D-U6-1: this direction has no safe predicate yet** |
| **OPEN** | Must NOT be gated |
| **OPEN-CRITICAL** | Must never be gated, and a named finding says why. Gating it is a regression with a register row attached |

---

## 1. RLS POLICIES — all 33

### 1.1 `public.posts` — 4 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `posts_select_public_or_owner` | SELECT | **R** | **GATE-VIEWER** | The feed. B-11's headline surface: today any authenticated Apple user reads the whole corpus, because all posts are `is_public = true` |
| `posts_insert_owner` | INSERT | **W** | **GATE-VIEWER** | Publishing is a paid action |
| `posts_update_owner` | UPDATE | **W** | **GATE-VIEWER** | |
| `posts_delete_owner` | DELETE | **W** | **OPEN — decision D-U6-2** | Unsharing is how a member *withdraws* content. Gating it means a lapsed member cannot retract their own post. Costs nothing to leave open and removes a trap |

### 1.2 `public.post_shares` — 4 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `post_shares_insert_owner` | INSERT | **W** | **GATE-VIEWER** | |
| `post_shares_select_recipient` | SELECT | **R** | **GATE-VIEWER** | |
| `post_shares_update_recipient` | UPDATE | **W** | **GATE-VIEWER** | |
| `post_shares_delete_owner` | DELETE | **W** | **OPEN — D-U6-2** | Same reasoning as `posts_delete_owner` |

### 1.3 `public.post_comments` — 2 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `post_comments_select_visible` | SELECT | **R** | **GATE-VIEWER** | |
| `post_comments_delete_owner_or_author` | DELETE | **W** | **OPEN — D-U6-2** | |

**There is no INSERT or UPDATE policy on `post_comments`.** Comments are written
exclusively through `add_post_comment`, `reply_to_commenter` and
`respond_to_commenters` — all SECURITY DEFINER, all in §2. **Policy work does not
reach comment creation at all**, and a U6 that only edited policies would leave
comment writing fully unenforced while every policy read as hardened.

### 1.4 `public.follows` — 4 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `follows_select_involved` | SELECT | **R** | **GATE-VIEWER** | |
| `follows_insert_requester` | INSERT | **W** | **GATE-VIEWER** | Its `WITH CHECK` already calls `follow_requests_open()` — a SECURITY DEFINER function, see §2 |
| `follows_update_approve_by_followed` | UPDATE | **W** | **GATE-VIEWER** | |
| `follows_delete_involved` | DELETE | **W** | **OPEN — D-U6-2** | Unfollow / remove-follower. C-43 notes this deletes both directional rows |

### 1.5 `public.connected_attachments` — 3 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `connected_attachments_insert_sender` | INSERT | **W** | **GATE-VIEWER** | |
| `connected_attachments_select_recipient` | SELECT | **R** | **GATE-VIEWER** | |
| `connected_attachments_update_recipient` | UPDATE | **W** | **GATE-VIEWER** | The soft-delete (`deleted_at`) path — reference counting for the expiry matrix depends on it |

### 1.6 `public.post_comment_views` — 3 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `pcv_select_self` | SELECT | **R** | **GATE-VIEWER** | Read-state bookkeeping |
| `pcv_upsert_self` | INSERT | **W** | **GATE-VIEWER** | |
| `pcv_update_self` | UPDATE | **W** | **GATE-VIEWER** | |

### 1.7 `public.account_directory` — 3 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `account_directory_select_owner` | SELECT | **D** | **OPEN-CRITICAL** | **Own row only** (`user_id = auth.uid()`). A lapsed member must still see their own profile and reach account deletion without re-subscribing — **C-35**. Gating this is a C-35 regression |
| `account_directory_insert_owner` | INSERT | **D** | **GATE-VIEWER** | Creating a Connected presence |
| `account_directory_update_owner` | UPDATE | **D** | **OPEN — D-U6-3** | Expiry **retains** `display_name` deliberately, so retained comments keep attribution (G10). Whether a lapsed member may still *edit* it is a separate question from whether it is retained |

**Discoverability is NOT in this table's policies.** All three are owner-scoped;
neither of them is how one member finds another. Discovery is
`search_account_directory`, in §2 — so **the "lapsed member becomes
undiscoverable" rule cannot be implemented in RLS at all.**

### 1.8 `storage.objects` — 10 policies

| Policy | Cmd | Dim | Direction | Note |
|---|---|---|---|---|
| `attachments_user_select_auth` | SELECT | **S** | **GATE-VIEWER** | Own prefix |
| `attachments_select_via_visible_post` | SELECT | **S** | **GATE-VIEWER** | Reads bytes via post visibility. B-6 bound this to the post's owner |
| `connected_attachment_recipient_select` | SELECT | **S** | **GATE-VIEWER** | Recipient inbox; keyed on `deleted_at IS NULL` |
| `attachments_user_insert_auth` | INSERT | **S** | **GATE-VIEWER** | |
| `attachments_user_update_auth` | UPDATE | **S** | **GATE-VIEWER** | |
| `attachments_user_delete_auth` | DELETE | **S** | **OPEN — D-U6-2** | |
| `avatars_select_owner_or_approved_follower` | SELECT | **S** | **GATE-VIEWER** | |
| `avatars_insert_owner_only` | INSERT | **S** | **GATE-VIEWER** | |
| `avatars_update_owner_only` | UPDATE | **S** | **GATE-VIEWER** | |
| `avatars_delete_owner_only` | DELETE | **S** | **OPEN — D-U6-2** | Expiry removes the avatar object; C-33's ordering rule applies |

---

## 2. SECURITY DEFINER SURFACES — dimension X

**RLS does not apply inside a SECURITY DEFINER function body.** Eight of the
twelve `authenticated`-executable functions are SECURITY DEFINER, so **editing
policies does not enforce them.** They need their own in-body check.

| Function | secdef | Writes | Dim | Direction | Note |
|---|---|---|---|---|---|
| `add_post_comment(uuid,text)` | **yes** | **YES** | W·X | **GATE-VIEWER** | The only comment-creation path. No RLS policy covers it |
| `reply_to_commenter(uuid,uuid,text)` | **yes** | **YES** | W·X | **GATE-VIEWER** | |
| `respond_to_commenters(uuid,text)` | **yes** | **YES** | W·X | **GATE-VIEWER** | |
| `mark_post_comments_viewed(uuid)` | **yes** | **YES** | W·X | **GATE-VIEWER** | |
| `has_unread_private_comments()` | **yes** | no | R·X | **GATE-VIEWER** | Badge state |
| `follow_requests_open(uuid)` | **yes** | no | R·X | **GATE-VIEWER** | Also invoked from `follows_insert_requester`'s WITH CHECK |
| `search_account_directory(text)` | **yes** | no | **D**·X | **GATE-VIEWER + GATE-SUBJECT** | **The discoverability rule lives here and only here.** A lapsed member must become undiscoverable — that is a gate on the *subject*, see D-U6-1 |
| `get_account_directory_by_user_ids(uuid[])` | **yes** | no | **A**·X | **GATE-VIEWER, NEVER GATE-SUBJECT** | **The retained-content resolution surface.** It must keep resolving a lapsed author so retained comments keep their display name (G10). Gating it on the subject breaks attribution while appearing to satisfy "undiscoverable" |
| `get_unread_private_comment_groups(int)` | no | no | R | **GATE-VIEWER** | Invoker rights, so its own RLS reads apply — but gate it explicitly rather than relying on that |
| `whoami()` | no | no | — | **OPEN** | Identity echo, no Connected content |
| `enforce_connected_attachment_recipient_update()` | n/a | — | — | **OPEN** | Trigger function, not a client API |
| `ensure_membership_binding()` | yes | YES | — | **OPEN-CRITICAL** | U5's binding RPC. **Gating it on membership is circular** — it is how a member becomes establishable in the first place |

**`search_account_directory` and `get_account_directory_by_user_ids` must
diverge, and that divergence is the whole reason they are two RPCs.** The
architecture states it as contract; this inventory is where it becomes two
different directions on two different rows.

---

## 3. SURFACES THAT ARE STRUCTURALLY OUT OF REACH

**Measured on the local reproduction, 2026-08-30, not assumed.**

| Surface | Why U6 cannot affect it |
|---|---|
| `delete_account_v1` | Runs as `service_role`, and **`service_role` carries `rolbypassrls = true`**. No policy U6 writes can block account deletion. **This is what makes C-35 structurally safe under enforcement**, rather than something U6 must remember |
| `revoke_apple_identity_v1` | Same |
| `membership_attest_v1` | Same, plus it must never consult membership — it is what *creates* it |
| `appstore_notifications_v1` | Apple→server, no client identity |
| The local journal | Not on the server. Invariant 1 |

---

## 3.5 U6a OBJECTS — added 2026-08-30, and they are NOT gated surfaces

| Function | secdef | Grants | Direction |
|---|---|---|---|
| `connected_member_self()` | yes | `authenticated` only | **OPEN-CRITICAL** — the zero-argument viewer predicate B-33 requires. Gating it would be circular |
| `shadow_observe(text)` | yes | `authenticated` only | **OPEN-CRITICAL** — the observer itself. Always returns true, never raises |

Neither takes a user id, so neither can be aimed at another identity.

## 3.6 THE SETTLED DIRECTIONS — decided 2026-08-30, §4's questions are CLOSED

**23 observed, 10 open, 33 total — asserted mechanically by
`supabase/tests/u6a/inventory-complete.sh` direction 6, not counted by hand.**

**OBSERVED (23).** `posts` SELECT *(non-owner branch)* / INSERT / UPDATE ·
`post_shares` SELECT / INSERT / UPDATE · `post_comments` SELECT *(owner and
recipient branches)* · `follows` INSERT / UPDATE · `connected_attachments`
SELECT / INSERT / UPDATE · `post_comment_views` all three ·
`account_directory` INSERT · `storage.objects` seven.

**OPEN (10).** All six DELETEs · `follows` SELECT · `account_directory` SELECT
and UPDATE · `attachments_user_select_auth`.

## 4. THE DECISIONS THIS INVENTORY FORCED — ALL SETTLED 2026-08-30

**Recorded as decided rather than deleted, because the reasoning is the durable
part.** The original text of each follows.

### D-U6-1 — **SETTLED: option 1.** A server-owned visibility state on
### `account_directory`, not directly client-writable. **It is U6b, not U6a**, and
### no uuid-addressable membership oracle is created. Original analysis:

Quarantine requires a lapsed member's presence to become "invisible to other
members immediately", and `search_account_directory` requires them to become
undiscoverable. Both are gates on the **subject**, not the viewer.

**Measured in the U6a gate:** a predicate taking a `uuid` must be granted EXECUTE
to `authenticated` to be usable from a policy (experiment 1), and once granted it
is callable as a PostgREST RPC for **any** uuid — **a membership oracle over the
whole user base** (experiment 1b, S3, which answered for a uuid the caller had no
relationship to). The zero-argument wrapper that solves GATE-VIEWER has no
argument to aim and therefore cannot express GATE-SUBJECT at all.

Three candidate resolutions, none yet chosen:

1. **Do not put subject-gating in the predicate.** Maintain a visibility flag on
   `account_directory`, written by the lifecycle, and let the existing policies
   read a column. No oracle, and it matches "presence becomes invisible" being a
   *state transition* rather than a per-query derivation.
2. **A bounded subject predicate** callable only where the caller already has a
   relationship to the subject (a follow edge, or authorship of a visible post).
   Narrower, but the boundary is a judgement rather than a structure.
3. **Accept the oracle** as low-severity. **Recommended against** — it is a
   shippable exception inside the paid-access boundary, which is what D4 rejected
   once already for the same reason.

### D-U6-2 — **SETTLED: no.** All withdrawal/DELETE paths stay ungated. Lapse
### must never prevent deleting your own data, account or relationships. Original:

Six DELETE policies are marked OPEN above on one argument: **withdrawal is not
consumption.** A lapsed member retracting their own post, unfollowing, or
removing an attachment is reducing their footprint, and gating it strands
content the member has asked to remove. Needs an explicit yes.

### D-U6-3 — **SETTLED: yes.** Self-profile maintenance is separate from
### discoverability. Original:

Expiry retains it so attribution survives (G10). Retention and editability are
different questions and the durable record answers only the first.

### D-U6-4 — **SETTLED: no.** A lapsed member reads their own retained material;
### only branches reaching other members' content are gated. For `post_comments`
### that means the `author_user_id` branch alone stays open (Q1). Original:

`posts_select_public_or_owner` has an owner branch. Quarantine hides presence
*from others*; it does not say whether the lapsed member may still read their own
server-side posts. **Invariant 1 is not in play** — the local journal is
untouched either way — so this is a product decision, not a safety one.
