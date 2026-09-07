# CP-3 — RETIRING STEVE VIA THE REAL DELETION PATH: ANALYSIS. 2026-09-07

**NOTHING MUTATED.** Read-only measurement and source reading.

**The proposed lifecycle is technically sound.** It has one hard constraint that
decides the sequencing, and it is not the one I expected.

---

## Q1 — WOULD A SUBSEQUENT SIWA CREATE A GENUINELY NEW IDENTITY? **YES.**

`delete_account_v1` calls **`admin.auth.admin.deleteUser(uid)`** — it deletes the
`auth.users` row, **strictly last**, and reports success only after.

**With no row to map to, GoTrue creates one on the next sign-in — and this
project has MEASURED exactly that.** After D15 deleted Device A's identity on
2026-08-15, a subsequent Sign in with Apple **"minted a new backend identity
`5ae3faab…`"** and `auth.users` grew.

**This does not contradict the 2026-08-25 "same `sub`" observation, and the
distinction is the whole answer.** That observation was about SIWA
**re-authenticating an existing row** after the *credential* was revoked —
revocation withdraws authentication, not the account (C-45, invariant 5). **Apple
returns the same `sub` either way; what changes is whether a row exists for it.**
Delete the row and the same `sub` produces a **new** Études identity.

**So `signOut()` is insufficient and deletion is sufficient**, for one reason.

## Q2 — WHAT DELETION REMOVES FOR STEVE, MEASURED

| | count |
|---|---|
| Steve's posts | **1** |
| comments **Steve authored** | **1** |
| comments on Steve's post — **all 3 authored by SAMUEL**, removed by the `post_id` cascade | **3** |
| **`follows` rows — the ENTIRE mutual approved follow, both directions** | **2** |
| `membership` / `membership_binding` | **1 / 1** |
| storage objects under `users/<uid>/` | **1** |
| `shadow_enforcement_stat` | **41** |
| `account_directory` row, `auth.identities`, `auth.sessions` | cascade |
| `connected_attachments`, `post_comment_views` | **0 / 0** |

**Samuel is not untouched.** He authored 4 comments; **3 are on Steve's post and
die with it**, leaving him 1. Production `post_comments` would go **5 → 1**.
Samuel's **6 posts and his avatar are unaffected**.

**And it is not only server-side.** The app's *Erase all Études data and account*
routes through `LocalFactoryReset`, so **Device A's local journal, Scores and
media are erased too** — which incidentally leaves Device A in the first-run
state CP-3's new-user path needs.

## Q3 — WHICH PHASE-4 ITEMS STILL NEED THE FIXTURE?

**All three of the fixture-dependent ones: conditions 2, 8, and C-34's avatar
replacement verification.**

## Q4 — CAN WE COMPLETE THEM NOW, THEN RETIRE STEVE? **NO — AND THIS IS THE DECISIVE FINDING.**

**All three are blocked by ONE cause, re-confirmed 2026-09-05:** `posts` INSERT
and SELECT and `storage.avatars` INSERT are gated by `enforcement_gate`,
enforcement is **live**, and **no identity is entitled** — `connected_member()` is
false for both, because the only `membership` row is **Sandbox** and
grandfathering is retired.

**The two routes to entitlement are deliberately refused** — weakening U6b
enforcement, and manufacturing production membership. **The only legitimate route
is a real Production subscription**, which CP-3 cannot supply.

**So the Samuel↔Steve fixture is CURRENTLY INERT. It cannot be exercised at all
until a Production subscription exists.**

### The trade, stated plainly

**The fixture's value was never "Samuel↔Steve" — it is "two Connected identities
with an approved follow".** Deleting Steve destroys that follow, and **it cannot
be rebuilt until entitlement exists**, because `follows_insert_requester` is
itself gated by `enforcement_gate`.

**But the event that would let us rebuild it is the same event that unblocks
conditions 2, 8 and C-34** — and creating an approved follow between two
identities is *itself* part of what those conditions exercise.

> **So preserving Steve protects an asset that cannot be used until the very
> event that would also let us rebuild it.**

That is the argument for treating him as disposable, and it is measured rather
than asserted.

### The honest caveat

**Retiring Steve is irreversible in practice until a Production subscription
exists.** If Phase 4's device work is ever attempted *before* that subscription,
it will find no fixture — but it would have found an unusable one anyway.

## RECOMMENDATION

**Proceed with the lifecycle, in this order:**

1. **Confirm acceptance of the measured cost** — 3 of Samuel's 4 authored
   comments, `post_comments` 5 → 1, and Device A's local data.
2. **Retire Steve through the app's real *Erase all Études data and account*
   path** — the genuine product path, which also exercises `delete_account_v1`
   and leaves Device A at first run.
3. **Verify the blast radius against a committed prediction**, as CP-0 was.
4. **Then run CP-3's ordering discriminators on the fresh identity** created by
   SIWA on Device A's existing primary Apple Account.

**No change to Device A's primary Apple Account is needed.** That route is
withdrawn — it was heavier and, as noted, an Apple device holds only one.

**The Sandbox Apple Account `sdsongsltd+devicec@gmail.com` is unaffected
throughout.** It drives Apple's Declared Age Range fixtures and StoreKit sandbox;
it is **not** the account SIWA uses to mint the Études identity. Retiring Steve
touches the Études identity only.

## STATUS

**NOTHING MUTATED. Awaiting authorisation.** CP-3 remains open.
