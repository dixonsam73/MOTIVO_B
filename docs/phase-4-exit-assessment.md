# PHASE 4 — EXIT ASSESSMENT. 2026-09-05

**PHASE 4 IS IMPLEMENTATION-COMPLETE AND EXIT-INCOMPLETE. IT IS NOT CLOSED.**

All eight units are implemented and accepted. **Three exit conditions are
outstanding, plus one carried obligation that post-dates the exit list.**

**The exit conditions below are quoted from `docs/phase-4-scope.md` §6 and are
neither reinterpreted nor relaxed.** Condition 8 forbids closure in its own
words — *"DEFERRED, NOT WAIVED"*, *"must not be called formally closed"* — so
this is the criteria applying themselves, not a judgement added on top.

---

## 1. THE EIGHT CONDITIONS

| # | condition (abbreviated from §6) | status | evidence |
|---|---|---|---|
| 1 | No path uploads a post with `isPublic == false`, asserted structurally | **MET** | `u2b`/`u2c` suites; U2c makes the state unrepresentable |
| 2 | Un-sharing deletes the row and its storage objects in `.backendConnected`, **device-verified** | **NOT MET as scored 2026-09-05. DEVICE HALF RUN 2026-09-16 — NOT re-scored here; see §2.1** | logic proven by `UnshareDurabilityTests` and U2a; ~~**the device half has never run**~~ — *superseded 2026-09-16: it has now run, owner-side and entitled. §2.1 states exactly what it does and does not cover* |
| 3 | Production census shows zero private posts, pre-change number recorded | **MET** | re-measured 2026-09-05: **101 posts, 101 public, 0 private**; U1 baseline recorded the same shape |
| 4 | **Durability** — no client of any build can create a private row, demonstrated **positively** by an observed rejected write | **MET LOCALLY**; production half carried under 8 | U2s A/B/C/D/E against a **byte-identical** local policy; production verified structurally (`with_check` md5) |
| 5 | Zero unreferenced attachment objects, or each survivor dispositioned | **MET** | U4/B-8: unreferenced 4 → 0; CA residue cleared at `4ee7a0b` |
| 6 | Onboarding, settings **and App Store privacy disclosures** describe the shipped upload behaviour | **PARTIALLY MET** — the ASC half's remainder is **PUBLICATION**, not entry | in-app copy done by U8 (`u8-acceptance` 29/0); ~~**the ASC labels have NOT been entered**~~ — *reconciled 2026-09-16 to the state documented in `docs/phase-5-scope.md`: the **nine ASC data types are ENTERED AND SAVED, and NOT PUBLISHED**. Publication is gated — see §2.2* |
| 7 | `LocalFactoryReset.perform` still has exactly two callers | **MET** | re-verified 2026-09-05: `ProfileView:1733`, `:1806` — exactly two |
| 8 | U2b's device verification executed; **and** U2s's production authenticated behavioural observation | **NOT MET** — U2b's half EXECUTED 2026-09-16; U2s's half OUTSTANDING and now the sole remainder | ~~both outstanding~~; see below and §2.1 — *amended 2026-09-16: U2b's device verification executed; U2s's production authenticated **rejected-write** observation remains outstanding* |

---

## 2. WHAT IS OUTSTANDING, AND WHY IT IS ONE BLOCKER RATHER THAN THREE

**Conditions 2 and 8 share a single measured cause**, re-confirmed 2026-09-05:

- `posts` **INSERT and SELECT are both gated** by `enforcement_gate`;
- enforcement is **live** in production;
- ~~**all 17 identities are unentitled** — grandfathering is retired and the only
  `membership` row is Sandbox, so `connected_member` is false for every one.~~
  **SUPERSEDED 2026-09-16, AND THIS IS THE LOAD-BEARING CORRECTION.** It was true
  when written and is now false. **Scope 011 — verified Apple Sandbox membership
  counts as Connected entitlement — deployed to production 2026-09-15 19:47:14
  UTC**, so a Sandbox row now entitles. Measured the next day: the 2026-09-16
  device QA baseline read `connected_member()` **true for both** participating
  identities, with `membership_state()` `sandbox_only`. **That is why the
  legitimate Connected path below became runnable at all.** The paragraph is
  struck rather than deleted because it is the reasoning a later session would
  otherwise plan from — the same failure mode as C-52 and the U4/U5 headings: a
  document accurate on its own date, never re-read after the change that
  falsified it.

**THE TWO PARAGRAPHS THAT FOLLOW ARE THE 2026-09-05 TEXT AND ARE HISTORICAL.
They are preserved as written and are NOT the current position — read §2.1.**

> So nothing can be shared, confirmed, or unshared from any device, and no
> production JWT can exercise the U2s guard behaviourally. **A single legitimate
> Connected path on Device A would discharge conditions 2, 4's production half and
> 8 together.**

**SUPERSEDED IN PART 2026-09-16, and the two halves went different ways.** The
first clause is **false now**: a session was shared, confirmed and unshared from
Device A on 2026-09-16. The second clause is **not endorsed as written** — *can* and *has* are
different: **the authenticated U2s rejected-write observation has not been
obtained; current impossibility is not established.** Condition 8 remains NOT MET. **The prediction that one path would discharge all
three together did NOT hold** — the path ran, and it discharged the device halves
while leaving U2s's authenticated rejected-write untouched. §2.1 maps which is
which.

**The two routes to that are both currently refused, deliberately:** weakening
U6b enforcement, and manufacturing production membership. That constraint has
governed since U2b and is not relaxed here.

**Neither route was taken.** The path below ran because scope 011 changed what
counts as entitlement, not because enforcement was weakened or membership
manufactured. **That constraint still stands.**

---

## 2.1 WHAT THE 2026-09-16 DEVICE RUN ACTUALLY COVERS — mapped to exact evidence

**Phase 4 is NOT declared closed here, and no condition is re-scored here.** This
section maps evidence to conditions so the scoring decision can be made against
what was observed rather than against an inference from it. Source:
`claude-device-qa-2026-09-16.md` §4, Device A (`6fd0a833`), every device action
performed by Samuel through the normal UI on a new disposable session; the
server side read-only. Build provenance `d2f4a15`, **user-reported and
source-verified**, not independently established — every install reports
`1.0 (131)`.

| Stage | UTC | Server state |
|---|---|---|
| Share OFF, saved | 17:50:49 | posts **3**, no matching row, **no object** — a Share-OFF save writes nothing |
| Share ON, saved | 17:52:06 | post `987c91c2…`, `is_public` **true**, one attachment, one new object; posts 3→**4**, storage 8→**9** |
| Share OFF, saved | 17:53:50 | **row gone**, **object gone**, posts back to **3**, storage back to **8** |

**Newly orphaned storage: ZERO**, computed against the 17:40:29 baseline. The two
pre-existing orphan PDFs were observed and deliberately **not** repaired.

**What this covers**

- **Condition 2's device half** — un-sharing deleted the row *and* its storage
  object in `.backendConnected`, on a device, measured server-side.
- **Condition 8's U2b half** — the Share-OFF save at 17:50:49 wrote no row and no
  object, observed on a device.

**What this does NOT cover, and must not be read as covering**

- **C-61's queued-intent path was NOT exercised.** The run scores the **entitled
  owner-side removal path only**; the durable demote-then-delete intent draining
  on a later foreground is unobserved.
- **U2s's production authenticated behavioural observation is NOT obtained.**
  Condition 4 asks for durability *"demonstrated **positively** by an observed
  rejected write"*. This run shows the client **does not attempt** the write; it
  does not show the policy **refusing** one. Those are different observations and
  only the second discharges it. `docs/phase-4-u1-baseline.md` records why it is
  hard to obtain: it cannot go through `supabase db query --linked`, because
  `cli_login_postgres` holds `bypassrls` and the attempt would pass while writing
  the forbidden row, so it must go through PostgREST with a real JWT. **The
  obstacle that route faced is recorded at a DATE, not as a present fact:** at the
  2026-09-05 baseline all 17 identities were Apple-only with zero passwords.
  **That count was NOT re-measured in this pass and must not be read as current** —
  the identity population and its credential shape are simply not established here.
- **Condition 6's ASC remainder is untouched** by any of this — and it is reconciled
  separately in §2.2, which corrects what that remainder actually is.

**The follower-visibility half — two separate records, deliberately not merged**

1. **In the 17:40–17:54 backend-probe window it is NOT scored.** Device B's
   entitlement went true → false between the publish and the unshare, so
   `enforcement_gate` denies B whether or not the post exists and any "B cannot
   see it" observation in that window is **over-determined**. The cause of B's
   lapse is **unknown and was not investigated** — an unchanged membership row is
   consistent with Apple not sending a renewal, with a notification sent but not
   delivered, with failed or refused ingestion, and with a sandbox renewal cap.
2. **Samuel subsequently reconfirmed follower disappearance AND reappearance**
   (QA1–QA5 accepted, 2026-09-16): share off → the post disappears for the
   follower, share on → it reappears. **This is a user-reported device
   observation, not a server-side measurement from the probe window**, and it is
   recorded separately for exactly that reason. It is not evidence about the
   window in (1), and (1) is not evidence against it.

**Device QA status at this date:** QA1–QA6 user-reported green — QA6 covering
staging survival across Control Centre and another app, timer correctness and
save. **QA7 (USB / audio / video) and QA8 (drone) are PENDING.** No device
coverage beyond this is inferred.

~~**Condition 6's remainder is unrelated and cheap:** entering the App Store
privacy labels is an **account-holder action in App Store Connect**, which no
part of this work can perform.~~ Content and behaviour mapping are ready in
`docs/app-store-privacy-disclosures.md`.

---

## 2.2 CONDITION 6's ASC HALF — reconciled 2026-09-16, and it is NOT cheap any more

**Reconciled to the documented state, with no account action taken and nothing
published.** `docs/phase-5-scope.md` records it directly: *"The privacy policy and
the ASC labels remain UNPUBLISHED. The policy is a draft carrying an open
`[AGE]`; the nine ASC data types are entered and saved but not published."*

**So "entering" is done and the struck sentence above is wrong twice over** — the
remainder is **publication**, and publication is **not cheap and not unrelated**,
because it is gated on the children's-privacy work:

- **P5-H must RE-DERIVE the mapping, not merely publish it.** The nine categories
  *"were derived against the PHASE 4 build"*, and CP introduces a server-side age
  band plus changed defaults. `docs/phase-5-scope.md` states the rule in its own
  words: **"Do not treat 'the labels are already entered' as evidence they are
  still"** correct.
- **Order is fixed:** resolve the policy's open `[AGE]` → publish
  `etudes.app/privacy` → **then** publish the ASC labels. Policy first, ASC
  second, and both **after** P5-F and the **P5-G legal/DPIA review**.

**NOTHING HERE CLAIMS LEGAL OR PUBLICATION COMPLETION.** **P5-G's product
decisions completed 2026-09-09; its DPIA and legal confirmations remain
outstanding.** No label was published, no policy was published, and no App Store
Connect action was taken or is proposed by this reconciliation. **Condition 6 stays PARTIALLY MET.**

---

## 3. CARRIED, AND NOT AN ORIGINAL EXIT CONDITION

**C-34's avatar replacement / cache-invalidation device verification.** It
post-dates §6, because C-34's client half was scoped into Phase 4 after the exit
list was written. **It is blocked by the same cause** — `storage.avatars` INSERT
is gated, so no avatar can be replaced.

**C-34 fixes a CACHING defect, so the only observation that settles it is a
replacement under an unchanged storage key propagating to another member.** The
2026-09-05 device pass explicitly did **not** claim it.

**What Phase 4's device pass DID establish** (`docs/phase-4-device-qa-acceptance.md`):
U7/C-58 verified on hardware, and the C-34 **client-plumbing** smoke passed.

---

## 4. THE STANDING SUITES AT EXIT

| suite | result |
|---|---|
| `u8-acceptance` | 29 / 0 |
| `u7-acceptance` | 26 / 0 |
| `u6b/acceptance` | 64 / 0 |
| `u2a / u2a2 / u2b / u2c / u2s` | 16 / 22 / 16 / 20 / 12, all 0 failed |
| `MOTIVOTests` | 49 passed |
| Debug / Release | BUILD SUCCEEDED |
| `u1-baseline` | 10 / 6 — expected inversions; **16 of 16 at its own commit `f12330e`** |
| `u5-client-acceptance` | 28 / 2 — **time-scoping, not regression**; **30 of 30 at its own commit `7744027`** |

**Two suites report failures at HEAD and neither is a regression.** Both are
unit-specific assertions pinned to their own unit's baseline, and both pass
against their own commit. **Neither was weakened to make the number look
better** — that is the suite-pinning policy working, not being worked around.

---

## 5. THOUGHTS — PRODUCT DECISION, SETTLED 2026-09-05

**A Thought is primarily a diary/journal entry, so Share INITIALISES OFF. The
owner may deliberately enable Share to publish one** — a general update, a gig
announcement, an instrument for sale, or any other non-practice post.

**Thoughts are therefore DEFAULT-private and NOT structurally private, and must
never be described as "never shared".**

**Current behaviour matches the decision; no implementation change was
required.** Verified rather than assumed, and now pinned executably:

| | evidence | assertion |
|---|---|---|
| Share initialises OFF for a Thought | `isPublic = isThoughtMode ? false : …` (`:1829`) | `U8-F1` |
| the toggle is still **offered** in Thought mode | brace analysis: `:1123` is guarded by `canShareWithFollowers`, **not** `!isThoughtMode` | `U8-F2` |
| a shared Thought really does publish | `publish(…, shouldPublish: isPublic)` carries no Thought guard | `U8-F3` |

**One comment was corrected** — comment-only, asserted by `U8-D1b`. It had said
`isPublic` is *"unconditionally false in thought mode"*, which describes the
**initialiser** as though it were the state. Read literally it invites a future
"simplification" that removes the toggle and deletes an intended capability.
**The superseded sentence is quoted in place rather than deleted**, per the house
convention — which is also why `U8-F4` asserts the correction's presence instead
of the old phrase's absence.

---

## 6. THE CONDITION FOR CLOSING PHASE 4

Phase 4 closes when **2**, **6**'s ASC half and **8** are discharged. **C-34's
device verification is carried alongside them and should be taken in the same
window**, since it is blocked by the same gate and needs the same fixture.

**Nothing here waives anything.** An obligation that is deferred is open, and
this document exists so that "Phase 4 is done" cannot be read as "nothing is
left".
