# HANDOVER — RESUME IMMEDIATELY BEFORE P5-G / CP-4 (DPIA AND LEGAL)

Written 2026-09-08. **CP-3 is closed. P5-G has not begun.** This is sufficient to
start P5-G without reconstructing CP-3; the debugging chronology is deliberately
left behind in the commit history and the acceptance documents.

---

## 1. REPOSITORY / PRODUCTION CHECKPOINT

**Branch `feature/solo-connected` · HEAD `d21a7c4` · origin `d21a7c4` ·
0 ahead / 0 behind · tree clean.** Remote parity confirmed at 2026-09-08 17:24.
*(This file cannot record its own commit sha — verify with
`git log --oneline origin/feature/solo-connected..HEAD` rather than trusting this
line. A handover asserting a repository fact is not evidence of it — C-52.)*

**Production `rlwtqxumfobakvdueugm`** — the same ref the app's `Info.plist`
points at, verified, not assumed. Measured 17:25:

| | |
|---|---|
| `auth.users` | **2** |
| `account_privacy` | **1** |
| `account_directory` | **1** |
| `membership` | **1** (Sandbox) |
| posts / comments / follows | **6 / 1 / 0** |
| `storage.objects` | **8** |

**The two identities:**

- **`dfaf8d18-ca27-4e5a-b46f-3c75801492f0`** — "Samuel Dixon" / `samueldixon` /
  London. The **control**: the only `account_directory` row, all 6 posts, the 1
  comment. **Untouched throughout CP-3 and must stay so.**
- **`6fd0a833-9e12-4dbb-a8e4-b4b01f706ea2`** — created 2026-09-08, the surviving
  CP-3 test identity. `band_18_plus`; **`lookup_enabled = false`**, deliberately.

> **DO NOT restore `lookup_enabled` to true.** It is the surviving evidence of an
> explicit user preference persisting through hydration.

**Devices — only what still matters.** **Device A** (SD beta burner, iPhone 16e)
holds the current Release build and is signed in as `6fd0a833`; its Sandbox
account is `sdsongsltd+devicec@gmail.com`, which carries the subscription history
and `originalTransactionId` — **a different tester would yield a second
`membership` row**. Its Sandbox entitlement will have lapsed and **nothing
depends on it**. **Device B is untouched and out of scope.** **P5-G needs no
device at all.**

---

## 2. PHASE-5 COMPLETION STATE

| unit | | state |
|---|---|---|
| **P5-A** | C-14 | **COMPLETE** |
| **P5-B** | CP-1 design | applied and relied upon — **see §8** |
| **P5-C** | CP-0 reset | **COMPLETE** |
| **P5-D** | CP-1 apply | **COMPLETE** — verified against the deployed database |
| **P5-E** | CP-2 server | **COMPLETE** — verified against the deployed database |
| **P5-F** | CP-3 client | **COMPLETE 2026-09-08**, closed with two limitations |
| **P5-G** | **CP-4 — DPIA and legal** | **NEXT. NOT STARTED.** |
| P5-H | CP-5 | blocked on P5-G |
| P5-I…P5-N | quality | do not gate release |

**PHASE 4 IS EXPLICITLY EXIT-INCOMPLETE AND IS NOT CLOSED BY CP-3.** See §7.

---

## 3. THE SETTLED CHILDREN'S-PRIVACY ARCHITECTURE

Current invariants only.

- **Age comes from Apple's `DeclaredAgeRange`, never from Études.** Études never
  asks anyone their age. `requestAgeRange(ageGates: 13, 18)`. **Nothing in the
  product or the record may imply Études asked.**
- **iOS 26.2+ for the whole app, including Solo** (P5-A2). Chosen while
  pre-release with no installed base, so `DeclaredAgeRange` exists on every
  supported install. The earlier "Solo 18.5 / Connected 26" split is withdrawn.
- **Derivation is BOUNDS ARITHMETIC, never gate-shape matching.** `lower >= 18`
  → `band_18_plus`; `lower >= 13` → `band_13_17`; otherwise **ineligible**. Apple
  may override the requested gates for the person's location, and its own sandbox
  returns 13-15 and 16-17 as separate ranges — a client matching on the literals
  13 and 18 would misclassify two of six official fixtures, permissively.
- **A nil `lowerBound` is INELIGIBLE, not "probably a teenager".** Fails closed.
- **Under-13 and unavailable both refuse Connected, and refuse BEFORE any server
  contact** — no identity is minted that would then need deleting.
- **No DOB, no provenance.** `ageRangeDeclaration` (`selfDeclared` / `confirmed`
  / `guardianDeclared`) is **never inspected and never stored** — it changes no
  decision Études makes.
- **Two bands only**, `band_13_17` / `band_18_plus`, in `account_privacy`,
  `NOT NULL`, one row per identity, FK to `auth.users` **ON DELETE CASCADE**.
- **Three distinct concepts, and conflating them is the main hazard:**
  1. **the persisted preference** — `lookup_enabled` / `follow_requests_enabled`;
  2. **the initial default at establishment** — written by
     `account_privacy_upsert_v1` as `(p_age_band = 'band_18_plus')`, i.e.
     **teen ⇒ both FALSE**, adult ⇒ both true. **There is no teen branch**: one
     expression, both rows, only the input differs;
  3. **the effective read-time child override** — a preference set **under an
     adult band** does not apply once the band is `band_13_17`:
     `enabled AND NOT (age_band='band_13_17' AND set_under_band='band_18_plus')`.
     **It destroys no preference history**; it withholds effect. `*_set_under_band`
     exists precisely to make that computable.
- **Teen Share default is OFF.** `shareDefaultOn` returns true **only** for a
  confirmed adult band — teen *and every unknown* default OFF. Governs the
  **default only**; a 13-17 member may still deliberately share a session.
- **Discovery opt-in:** `account_privacy_set_lookup_v1` is the **only** client
  writer, one call site (`ProfileView:742`), and it stamps `lookup_changed_at`
  and copies `lookup_set_under_band` from the row's current band.
- **Follow requests, current disposition — READ THIS BEFORE §5's question.**
  `follow_requests_open` = `enforcement_gate AND account_privacy_requests_open`,
  and the **privacy conjunct is unconditional: the kill switch may relax
  entitlement, never child safety.** CP-2-R1 changed a missing/unresolved row
  from resolving **open** to resolving **CLOSED**. The same child override
  applies. **`account_privacy_set_follow_requests_v1` exists and has NEVER been
  called; there is no client caller of `setFollowRequestsEnabled` anywhere.**
- **Attribution and discovery are separate surfaces, deliberately.**
  `search_account_directory` consults `account_privacy` (discovery);
  `get_account_directory_by_user_ids` does **not** (attribution). That separation
  is what lets a member be undiscoverable while people they already share with
  still see their name.
- **`account_directory.lookup_enabled` and `follow_requests_enabled` are DEAD
  columns** since CP-2. `account_privacy` is authoritative, and the client
  deliberately **does not send** those columns when publishing a profile — which
  is what makes "publishing a profile cannot mutate a privacy preference"
  structural rather than remembered.
- **CP-1's trigger:** `tg_directory_requires_band` refuses a directory row INSERT
  when no `account_privacy` row exists (23514). Band before directory.

---

## 4. CP-3 ACCEPTANCE DISPOSITION

### 4.1 Hardware-verified

Band establishment **3×** by both routes (recovery coordinator and the
Continue/join path) · the adult default row **3×**, identical
(`true / true / band_18_plus / band_18_plus / NULL / NULL`) · the **existing-band
short-circuit** (band present ⇒ read, no Apple call, no write) · the **under-13
refusal**, twice, proven to occur **before any server contact** · a genuinely
band-less identity **created rather than reconstructed**, twice · the
**deletion blast radius** predicted and matched **3×** (including a count that
moved once and correctly did not the next time) · **purchase integrity**
(`binding_method` `purchase`; binding reused, never re-bound) · **the discovery
writer end to end** (§4.4).

### 4.2 Covered structurally / unit / server-side — NOT on hardware

Derivation: **16 unit tests** over Apple's six documented sandbox fixtures,
boundaries and the regulatory over-block · Share default: pure, teen and every
unknown → OFF · **server defaults: one deployed branchless expression**, teen
half evaluated live (`false / false`), adult half hardware-verified 3× ·
the read-time child override: deployed and readable · age-range wiring: **35
structural assertions**, non-vacuity measured · session-refresh policy:
**87 unit tests**, 34 structural.

### 4.3 THE TWO LIMITATIONS — LOAD-BEARING, DO NOT SOFTEN

> **(1) TEEN DEFAULTS ARE NOT DEVICE-VERIFIED.** No end-to-end device
> observation exists of a real Apple 13-17 range establishing `band_13_17`, and
> therefore none of the teen default row or the teen discovery opt-in chain.
>
> **End-to-end teen hardware acceptance is blocked by nondeterministic Apple
> Sandbox Age Assurance fixture behaviour.** The fixture was once set, **verified
> by leaving and re-entering the Settings screen**, measured server-side, and
> found **unset ~2 minutes later with no deletion, install, sign-in or app
> interaction at all**. Apple documents **no** reset, re-arm or
> force-re-evaluation procedure and **no** way to prove the returned value;
> independent developer reports describe the same nondeterminism **including for
> `child 13-15`**, with an Apple engineer unable to reproduce and no resolution.
> **Three disposable identities were spent and the teen band was never produced
> once.**
>
> Teen derivation and defaults remain covered by the **client unit suite** and
> the **deployed branchless server expression**. **That is coverage, not hardware
> verification, and must never be restated as hardware verification.**
>
> **Closed to further experimentation. Do not resume fixture work and do not
> delete further identities chasing it.**

> **(2) STRONG BAND-BEFORE-DIRECTORY PUBLICATION ORDERING remains blocked by
> U6b / D4 Sandbox enforcement** and is a **named carried obligation**.
> `connected_member()` means Production entitlement only, so a Sandbox membership
> can never publish a directory row — and a refusal could not be attributed
> anyway, since the CP-1 trigger and `enforcement_gate` would both be refusing
> indistinguishably.
>
> **DO NOT weaken enforcement and DO NOT add a test-only carve-out merely to
> discharge it.**

### 4.4 General fixes CP-3 surfaced, and their acceptance status

| fix | what it was | status |
|---|---|---|
| **Session-refresh expiry gate + four-way reconciliation** | the refresh rotated unconditionally; its failure branch was a boolean | **device-verified** |
| **Non-user auth withdrawal no longer uses destructive `signOut()`** | `signOut()` also deletes per-user attachment **title** mappings — user-typed content. Five non-user-initiated paths now use `clearConnectedIdentity` | **device-verified for the behaviours exercised**; `self.signOut()` calls in `AuthManager` went **5 → 0** |
| **Refresh↔hydration re-entrancy cut** | hydration preflights a refresh, and a refresh scheduled hydration | **device-verified (Gate C)** — 10 preflights, 4 hydrations, **0 rotations**, against **34 rotations in 20.5 s** pre-fix |
| **Resubscription/hydration scheduling** | a usable session that did not *rotate* scheduled no hydration, so a member who signed in unentitled and subscribed later stayed absent up to a token lifetime | **device-verified** — directory reads rose while tokens did not |
| **Finding-A View-context recovery** | `requestAgeRange` was read from `struct MOTIVOApp: App`, which has no presentation context; recovery read and never wrote | **device-verified** — writer flat before, **+1 after**, on the same identity and server state that had failed |
| **Discovery writer** | `account_privacy_set_lookup_v1` had never been called | **device-verified** — never-called → **exactly 1**; `lookup_enabled` true→false; `lookup_changed_at` stamped; `lookup_set_under_band` copied `band_18_plus`; **the follow-requests trio byte-identical**; and explicit OFF **persisting through hydration with no second write** |

**The last of those is the one to remember:** no second write means the client
reads the preference back rather than re-asserting it — the failure shape CP-3
removed when it stopped sending a hard-coded `lookupEnabled: true`.

---

## 5. P5-G DECISION SURFACE — the genuinely unresolved questions

**None of these is answered by the implementation. Do not read current behaviour
as settled policy.**

1. **Adult → 13-17 reclassification.** Apple owns ageing and may report a new
   range at any time. **What happens to already-published posts and to existing
   approved follows** when an identity reclassifies downward? The read-time
   override withholds *effect* from adult-set preferences and destroys no
   history — but it says nothing about **content already published** or
   **relationships already approved**. Decide explicitly.
2. **Should a 13-17 member ever be able to opt INTO inbound follow requests?**
   Today there is **no client path at all** — the writer exists and has never
   been called. **That is an implementation state, not a decision.** Do not let
   it become permanent policy by silence; and if the answer is "no", record it as
   a decision with a reason.
3. **`activeParentalControls.communicationLimits`** — whether and how Études
   consults it, and what it changes. Added to P5-G's scope by CP-1 r3 and not yet
   worked.
4. **Declined / unavailable age-sharing.** Currently an **eligibility fact only**:
   refuse, say so neutrally, write nothing. Outstanding: **retry policy, wording,
   and jurisdictional variation.**
5. **Age assurance is tied to the DEVICE'S Apple Account, not intrinsically to
   the Études/SIWA identity.** A different Apple Account on the same device — or
   the same Apple Account on another device — is a different age source. **The
   DPIA must state this honestly**; it bears on how much assurance the band
   actually carries.
6. **Lawful basis and DPIA conclusions**, plus any remaining external/legal
   confirmations.

**The DPIA must reflect §4.3(1) as written.** A DPIA implying that teen
protections are device-verified would misstate the evidence.

---

## 6. P5-H DEPENDENCY — RE-DERIVE, DO NOT REPUBLISH

**The nine App Store Connect privacy categories entered during Phase 4 were
derived against the PHASE 4 build.** CP has since added a server-side age band,
changed defaults, and altered which columns are authoritative. **"Already
entered" is not evidence of "still correct".**

**P5-H must re-derive the ASC mapping from the post-CP implementation**, after
P5-G's legal review, and **then** publish — policy first, labels second.

---

## 7. CARRIED NON-CP OBLIGATIONS

- **PHASE 4 IS EXIT-INCOMPLETE AND MUST NOT BE CALLED CLOSED.** Outstanding:
  **condition 2** (U2b/U2s share/unshare device verification), **condition 6's
  ASC half** (an account-holder action in App Store Connect that no code can
  perform), **condition 8** (recorded in its own criteria as *"DEFERRED, NOT
  WAIVED"*), and **C-34's avatar-replacement device verification**. **Conditions
  2 and 8 share one measured cause** — `posts` INSERT and SELECT are both gated
  and there is no Production entitlement.
- **H-1 — ProfileView UI housekeeping, logged-only, NOT part of CP-3 closure.**
  Move `Default to Private Posts` and `Let other members find you` out of the
  ordinary Settings list into their own **"Connected"** section placed **above
  Account**. **Presentation only** — no change to behaviour, privacy semantics,
  hydration, writers, visibility rules or copy. Section name **"Connected", not
  "Privacy"**; **"Account" keeps its name**. A pure move leaves
  `u8-acceptance` at its current score. Full note in
  `docs/phase-5-ui-housekeeping.md`.
- **C-31** (Production App Store Connect Billing Grace) and **B-34** (shadow
  telemetry blind to denied writes — an observability limitation, never a
  correctness defect) remain open Phase-3 obligations.
- **G7** — the first naturally matured production cleanup, earliest 2026-11-01.

---

## 8. P5-B STATUS INCONSISTENCY — administrative, NOT a doubt about CP-1

**`docs/phase-5-scope.md` §2 still labels P5-B "DESIGNED, HELD FOR REVIEW".**

**That label is stale as a description of current state.** The CP-1 design was
**subsequently applied in production by P5-D** — recorded as live and verified
against ten snapshot surfaces — and is **relied upon by completed P5-E and
P5-F**. `account_privacy`, its constraints, the three RPCs and
`tg_directory_requires_band` are all deployed and exercised.

**The only genuine uncertainty is whether a separately named, formal P5-B review
ceremony ever took place.** This session could not establish that, and **no
historical review event is invented here.**

> **Reconcile the label administratively at the start of the next window. It must
> NOT be read as casting doubt on the deployed CP-1 authority.**

---

## 9. FIRST CONCRETE TASK FOR THE NEW WINDOW

**Do not begin implementation. P5-G is a decision-and-documentation unit.**

> **Produce the P5-G decision register: one row per question in §5, each with the
> options, the recommendation, the evidence it rests on, and who must decide
> (account holder, or external legal).** Separate what the *implementation
> currently does* from what has actually been *decided* — §5.2 is the worked
> example of that distinction, and §5.1 is the one most likely to be assumed
> rather than decided.

Confirm remote parity and re-measure the production population first — §1's
figures are dated the moment anything else happens — and reconcile §8's label
before relying on the phase table.
