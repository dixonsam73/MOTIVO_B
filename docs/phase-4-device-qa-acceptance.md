# PHASE 4 — PHYSICAL-DEVICE QA PASS. 2026-09-05

**Bounded pass, ~15 minutes, Device A (SD beta burner, iPhone 16e), Release,
fresh build from the current tree.** Deliberately not a regression matrix: local
and production evidence already covers most of Phase 4, so only tests where real
hardware adds evidence were run.

**Two things PASS. Two remain DEFERRED and are not claimed.**

---

## 1. WHAT THE DEVICE ACTUALLY WAS

| | |
|---|---|
| Device | **Device A** — SD beta burner, iPhone 16e, `com.sdsongs.etudes` (Release) |
| Build | fresh, current tree (carries the C-34 client half, `7744027`) |
| Signed-in identity | **`64ffb132`** — `account_id` `steveckeabuo`, "Steve Rename" |
| Connected UI | engaged via a **Sandbox** subscription |
| Server entitlement | **still `false`** — a Sandbox row yields `sandbox_only`, so `connected_member` is false and **U6b enforcement was neither weakened nor bypassed** |

**The client was Connected and the server still denied everything it gates.**
That is the whole point: `canViewFeed` resolves from local StoreKit, and the
server gates on membership. No production membership was manufactured.

---

## 2. THE COUNTERPARTY, ESTABLISHED READ-ONLY RATHER THAN INFERRED FROM THE UI

The name on screen is what was under test, so it cannot also be the evidence of
*whose* name it was. Resolved server-side instead:

| | md5[0:8] | account_id | display_name |
|---|---|---|---|
| viewer (device) | **`64ffb132`** | `steveckeabuo` | Steve Rename |
| counterparty | **`1fbf664a`** | `samueldixon` | Samuel Dixon |

Both directions are **approved**, created 2026-09-01 09:59:32 and 09:59:54.

**No ambiguity was possible:** exactly **one** directory row matches
`%samuel%`/`%dixon%` on either `display_name` or `account_id`. There is no second
identity the UI could have been showing.

`1fbf664a` is the same row U5 used for its avatar-version discriminator, and the
same viewer as U7's production `requested`-only probe.

---

## 3. PASS — U7 / C-58 ON PHYSICAL HARDWARE

**People → Following and People → Followers both rendered "Samuel Dixon" by real
name, not `User • <suffix>`.**

That is C-58 closed on device, by an **unentitled viewer** under **live
enforcement**, through the exact path U7 opened: `follows` SELECT is ungated, and
`get_account_directory_by_user_ids` now resolves an approved follow for a viewer
who is not a member.

**Samuel rendered with INITIALS, not a photo — predicted, and correct.** Avatar
*reads* are gated (`avatars_select_owner_or_approved_follower`), so an unentitled
viewer gets the name and not the image. This is the shape the expiry retention
matrix specifies. **Attribution without discoverability, observed on hardware.**

**Feed empty with "Follow people to see their sessions here."** — `posts SELECT`
is gated; the empty *state* rendering is itself the discriminator that separates
a denial from the failed-request shape that contaminated U6b's 2026-09-01 QA
window.

---

## 4. PASS — C-34 CLIENT-PLUMBING SMOKE

The C-34 client half wired **17 caller sites across 8 files** and five directory
render sites, and **had never run on any device**. Exercised here: People
browsing, Followers, Following, profile peek, and Journal scrolling.

**No crash, no blank or broken row, no stuck spinner, no duplication.**

**Incidental and stated narrowly:** `1fbf664a` carries `avatar_key` with
`avatar_version` **NULL** — U5 deliberately performed no backfill — so the
version-carrying render path executed with a NULL version and did not misbehave.
**That is not a verification of acceptance point 6**, whose unit test remains the
evidence; it is only that the NULL case did not break on hardware.

---

## 4b. FIND PEOPLE RETURNS NOTHING — VERIFIED, AND THE INTERPRETATION IS NARROWED

**Observed on device:** Find People returns no results for several known beta
testers by name, while Samuel Dixon continues to resolve by real name in
Followers/Following.

**Reproduced server-side as the EXACT device identity**, not inferred: searching
`'Samuel'` as `64ffb132` returns **0**.

**The offered interpretation — "this confirms the U7 boundary, discovery stays
gated for the unentitled viewer" — is consistent with the observation but is NOT
established by it, because the result is OVER-DETERMINED.** Reading the deployed
`search_account_directory`, **two independent and individually sufficient
predicates** are both false here:

| predicate | why it is false | whose axis |
|---|---|---|
| `(select enforcement_gate('rpc.search_account_directory'))` | the viewer is unentitled | **viewer** |
| `((select not enforcement_active()) or ad.entitled_until > now())` — **D-U6-1** | **all 17 directory rows have `entitled_until` NULL** with enforcement active | **subject** |

**So an ENTITLED viewer would also have seen zero results**, because every
subject is filtered out. There is no entitled identity in production, so the two
causes cannot be separated by any observation available to us.

**And it is not "nothing matched":** evaluating the token predicate alone, the
searched terms match real rows — `Samuel` 1, `Steve` 1, `Nixey` 2, `nix` 2 —
while **0** rows pass the subject filter for any term. The names are there; both
gates independently exclude them.

### What IS confirmed, stated at the strength the evidence supports

1. **The architectural separation is real and was observed on hardware:**
   attribution resolves (`get_account_directory_by_user_ids` has **no**
   subject-side filter, G10) while discovery returns nothing (`search_...`
   carries one, D-U6-1). Two RPCs, two behaviours, same viewer, same moment.
2. **D-U6-1 is what the observation most strongly demonstrates** — *a lapsed
   member becomes undiscoverable*. Every production identity is lapsed, so every
   one is undiscoverable, which is exactly the designed outcome.

### What is NOT confirmed

**That the VIEWER gate is what produced the zero.** It is one of two sufficient
causes and the observation cannot distinguish them. **Recorded as such rather
than folded into the U7 pass**, whose evidence is §3 — the positive resolution —
and which does not depend on this at all.

---

## 5. NOT CLAIMED — AND THE DISTINCTION IS THE POINT

**C-34 avatar replacement and cache invalidation are NOT device-verified.**
No avatar was replaced, because `storage.avatars` INSERT is gated and every
production identity is unentitled. **The defect C-34 fixes is a CACHING defect,
so the only observation that would settle it is a replacement under an unchanged
storage key propagating to another member.** That observation was not made.
Fault-injection and unit evidence stand; the device half remains **open**.

**U2b / U2s Share ON → confirm → Share OFF, and the offline-unshare convergence,
remain DEFERRED**, unchanged. `posts` INSERT *and* SELECT are both gated and all
17 identities are unentitled, so nothing can be shared, confirmed or unshared
from any device. **Enforcement was not weakened and no membership was
manufactured to get around it** — the constraint that has governed this since
U2b.

**C-51 needed no device test**; its fault-injection evidence is sufficient and
was accepted as such.

---

## 6. WHAT THIS PASS IS AND IS NOT

It is evidence that **U7 works on real hardware for the exact population it was
built for**, and that **the C-34 client plumbing does not break the app**.

It is **not** a Phase 4 exit gate, not a regression matrix, and not a
substitute for the two deferred verifications above.
