# U6b — SUBJECT-SIDE VISIBILITY. BOUNDED SCOPE, 2026-09-01. NOT IMPLEMENTED

**Nothing built, nothing deployed.** This is the enumeration and the mechanism
decision that must precede implementation.

**Requirement (accepted, in scope for U6b, not deferred):** once a member is no
longer entitled, their Connected presence and content become **invisible to other
members immediately**. U6b must not ship with viewer entitlement enforced while
lapsed authors remain visible.

---

## A. THE DERIVATION PRINCIPLE — the retention matrix already answers this

**"Invisible at lapse" and "removed at cleanup" are the same rule at two
different times, so the settled expiry retention matrix decides every surface
without a new judgement call:**

> **If ordinary expiry cleanup would REMOVE it, gate it at lapse.**
> **If cleanup would RETAIN it, do NOT gate it** — gating at lapse would hide
> something that is required to remain resolvable forever afterwards.

That is the whole design, and it means subject-side gating adds **no new product
rule**. It makes the quarantine window look like the post-cleanup world, which is
the state the product already commits to.

## B. SURFACES REQUIRING SUBJECT-SIDE GATING

| # | Surface | Subject | Cleanup says |
|---|---|---|---|
| 1 | `posts_select_public_or_owner` *(non-owner branch)* | `posts.owner_user_id` | **Removed** |
| 2 | `post_shares_select_recipient` | `post_shares.owner_user_id` | **Removed** |
| 3 | `storage.attachments_select_via_visible_post` | post owner | **Removed** |
| 4 | `storage.avatars_select_owner_or_approved_follower` *(non-owner branch)* | avatar owner | **Removed** |
| 5 | `search_account_directory` | each candidate row | **Undiscoverable** |

**Five surfaces. That is the entire subject-side delta.**

**All WRITE policies stay viewer-gated only.** `posts` insert/update,
`post_shares` insert, `connected_attachments` insert/update, `follows`
insert/update, `post_comment_views`, `account_directory` insert and the storage
write policies all concern **the caller's own** material. The visibility rule is
about reads.

## C. SURFACES THAT MUST **NOT** BE SUBJECT-GATED

These are the retention rules, and gating any of them would break something the
product has already committed to.

| Surface | Why it must stay open |
|---|---|
| **`get_account_directory_by_user_ids`** | **Retained attribution.** The directory row survives cleanup precisely so retained comments still render a name. Gating on the subject breaks every retained comment — **G10** |
| **`post_comments_select_visible`** | **Comments authored on other members' surviving posts are RETAINED.** A lapsed member's comments stay, attributed. This is a deliberate, settled exception to "invisible presence" |
| **`connected_attachments_select_recipient`** | **Sent attachments with a live recipient reference are RETAINED, row and object.** The recipient's inbox copy survives cleanup, so it must not vanish at lapse |
| **`storage.connected_attachment_recipient_select`** | Same rule, object side |
| **`follows_select_involved`** | Untouched by U6a for D-U6-2's reason — **you cannot delete what you cannot see.** It reveals a relationship, not content, and item 1 already hides the content |
| **All six DELETE policies** | **D-U6-2 — withdrawal is never gated** |
| **`account_directory` SELECT / UPDATE (own row)** | **D-U6-3 — self-profile maintenance while lapsed** |
| **`attachments_user_select_auth`** | **D-U6-4 — own retained material stays readable** |

## D. CONFLICTS CHECKED — one real tension, and it is already settled

**A lapsed member's NAME still appears**, on their retained comments on other
people's surviving posts. So "invisible presence" is not literal invisibility, and
**it never was**: the retention matrix retains those comments and retains the
directory row that renders them, and B-19 protects content merely *addressed to* a
departing member.

**The precise settled meaning is therefore:** their **own posts, shares,
post-attachment bytes and avatar** become invisible, and their **directory row
becomes undiscoverable** — while their **authored comments elsewhere, and the
attribution needed to render them, remain**.

**A pleasing consequence that argues the design is right:** gating the avatar at
lapse makes a retained comment render as **initials** — which is exactly what
CLAUDE.md already predicts for the *post-cleanup* render. **Quarantine and
post-cleanup produce an identical UI, so no new visual state is introduced.**

## E. A LAPSED AUTHOR, SURFACE BY SURFACE

| Their… | Entitled viewer sees |
|---|---|
| **Posts** | **gone from the feed**, and not fetchable directly |
| **Post attachments (bytes)** | **refused** |
| **Post shares they sent** | **gone** |
| **Avatar** | **refused** → renders as initials |
| **Directory row via search** | **not found** |
| **Directory row via `get_..._by_user_ids`** | **STILL RESOLVES** — name and account id |
| **Comments they authored on others' posts** | **STILL VISIBLE, still attributed** |
| **Connected attachments they sent, live recipient reference** | **STILL IN THE INBOX** |
| **Follow rows involving them** | **still visible** — relationship, not content |
| Their own view of their own material | **unchanged** — D-U6-4 |
| Their own profile editing | **unchanged** — D-U6-3 |
| Their ability to delete their account | **unchanged** — D-U6-2, C-35 |

## F. THE MECHANISM PROBLEM — and it is genuinely hard

**A policy cannot simply call `connected_member(subject_uuid)`.** Two settled
findings close the obvious routes:

- **B-33:** EXECUTE **is** checked against the invoking role for a function in a
  policy qual. So the policy needs a grant — and granting the uuid-taking form
  makes the entitlement predicate **a membership oracle over the entire user
  base**, which **D4 rejected outright** and B-33 re-rejected on measurement.
- **B-33 again:** a qual's *table* access is invoker-checked too, so inlining
  `exists (select 1 from public.membership …)` raises
  `permission denied for table membership` against U3's deliberate revokes.

**And a join to `account_directory` does not work either**, which is easy to miss:
`account_directory_select_owner` is `user_id = auth.uid()`, **owner-only**, so a
policy joining to another member's directory row sees nothing.

### The three candidate mechanisms

| | **M1 — denormalised `entitled_until`** | **M2 — granted subject predicate** | **M3 — readable visibility table** |
|---|---|---|---|
| **Shape** | `timestamptz` column on `posts`, `post_shares`, `account_directory`; policy compares `> now()` | `connected_member_subject(uuid)` granted to `authenticated` | tiny `member_visibility` table, SELECT open to `authenticated` |
| **Creates an oracle?** | **NO** — no function, no grant, no cross-row read | **YES** — the exact D4/B-33 rejection | **YES, table-shaped** |
| **Time-correct without a worker?** | **YES** — it stores a *timestamp*, so lapse happens by time passing, with no write and no worker (and none exists until U7) | yes | needs a worker or the same denormalisation |
| **Maintenance** | on membership writes only — U4's canonical writer and `membership_establish_v1`, both already `SECURITY DEFINER`. Scope is one author's rows, not the corpus | none | worker |
| **Drift risk** | real, and mitigable: an assertion recomputes from `membership` and compares | none | real |
| **Reopens a settled invariant?** | no | **yes** | **yes**, and also widens B-5's deliberately hardened directory |

**M1 is the only option that does not create a uuid-addressable entitlement
oracle**, and the timestamp choice is what removes the need for a worker: **storing
`entitled_until` rather than a boolean means time does the expiring.**

**Its honest cost:** four columns of denormalisation, two write paths to maintain,
and a drift class that did not previously exist. **M2 and M3 are cheaper and both
buy that cheapness by re-opening D4** — which is the one thing this project has
refused twice on measurement rather than taste.

## G. IMPACT ON THE U6b PLAN

- **Migration grows** by the `entitled_until` columns, their maintenance in the
  two writers, and **5 further policy edits** — so **28 of 33 policies change**,
  not 23.
- **New acceptance:** a lapsed author's posts/shares/attachment bytes/avatar are
  invisible to an entitled viewer, **and** their comments, their
  `get_..._by_user_ids` attribution and their live-referenced sent attachments
  remain — **the retention half asserted as hard as the hiding half.**
- **New drift assertion:** `entitled_until` recomputed from `membership` equals
  the stored value for every row.
- **Device QA gains a second entitled fixture requirement.** *Today we have no
  entitled viewer in production*, so **the subject-side half is LOCAL-ONLY
  pre-release** — it needs an entitled viewer *and* a lapsed author, and Gate 6
  already established the entitled half is unobtainable before release.
- **The release gate widens:** the first real subscriber verifies both the grant
  path **and** that a lapsed author is invisible to them.

## H. DECISIONS I NEED

1. **Mechanism: M1, M2 or M3?** I recommend **M1** — it is the only one that does
   not re-open D4, and the timestamp form avoids needing U7's worker. It costs
   denormalisation and a drift class.
2. **Is the "lapsed member's name still appears on retained comments" outcome
   accepted?** It follows from the settled retention matrix, but it is the one
   place where "invisible presence" is not literal, and it should be an explicit
   product acceptance rather than a derivation nobody signed.
3. **`follows_select_involved` — leave open?** I recommend yes: it exposes a
   relationship rather than content, item 1 already hides the content, and gating
   it would break D-U6-2's "you cannot delete what you cannot see".
