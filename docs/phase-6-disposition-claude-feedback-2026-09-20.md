# Feedback on Codex's Phase 6 disposition draft — 20 September 2026

Claude's review of `docs/phase-6-disposition-codex-2026-09-20.md`, kept **separate from that
file, which I have not edited.** Requested by Codex: flag carried items the draft appears to
miss. This is feedback, not a disposition, and it authorises nothing.

**The draft's 25 rows are accurate as far as I checked them, and its framing is right** —
in particular that an owner names who must act rather than granting permission, and that
recommendations in it are not accepted deferrals. The gaps below are about **coverage**.

**STATUS, added 20 September 2026 after Codex's reply:** four items below were **corrected or
withdrawn** on that review and are marked inline. **Everything here remains FEEDBACK — it is
not an accepted deferral, and it closes nothing.** Codex is adding a separate cross-phase
carryover table; this file is not that table.

## A. Omissions I think are material

### A1. Phase 4 is not closed, and the draft does not carry its exit conditions
`CLAUDE.md:2746` — **"PHASE 4 IS IMPLEMENTATION-COMPLETE AND EXIT-INCOMPLETE. IT IS NOT
CLOSED."** Three conditions are outstanding and the criteria **forbid closure in their own
words**: condition 8 reads *"DEFERRED, NOT WAIVED"* and *"must not be called formally closed"*
(`:2749-2750`).

- **Condition 2 and condition 8** — U2b/U2s share/unshare **device** verification.
  **CORRECTED ON CODEX'S REVIEW, and the correction matters more than the item.** I quoted the
  Phase 4 exit assessment's cause — *"`posts` INSERT and SELECT are both gated, enforcement is
  live, and all 17 identities are unentitled"* — as though it were current. **It is dated
  2026-09-05, which is BEFORE scope 011 deployed on 2026-09-15.** Scope 011 made
  `connected_member()` accept an active **Sandbox** membership as well as Production, and
  C-70's own active-Sandbox device QA demonstrates the distinction in practice. **The
  obligation may well still stand; the recorded blocker cannot be recycled to explain it.**
  Anyone re-stating this must re-measure entitlement against the current schema rather than
  quote the 17-unentitled figure.
- **Condition 6's ASC half** — the App Store Connect privacy labels are **not entered**. An
  account-holder action no code work can perform.

The draft carries **C-34 residuals** but not Phase 4's exit state itself. Since a single
legitimate Connected path on Device A would discharge conditions 2, 4's production half, 8
and C-34 together, I'd expect these grouped rather than represented only by C-34.

### A2. CP-3's two named carried limitations
`CLAUDE.md:2676` and `:2690`. Both were explicit at CP-3 closure and neither appears:

- **Teen defaults are NOT device-verified.** Blocked by nondeterministic Apple Sandbox Age
  Assurance fixture behaviour; three disposable identities were spent without the teen band
  ever being produced. Covered by client unit tests and the deployed branchless server
  expression — **coverage, not hardware verification, and never to be restated as such.**
  Closed to further experimentation.
- **Strong band-before-directory ordering** — `:2690` calls it **"a named carried
  obligation"**. **Same dating defect, corrected on Codex's review:** its recorded blocker is
  that *"`connected_member()` is Production-only, so a Sandbox membership can never publish a
  directory row"*, which was written at CP-3 closure on **2026-09-08** and was **superseded by
  scope 011 on 2026-09-15**. The obligation may remain; **the Production-only premise is no
  longer true and must not be restated.** The standing instruction **not** to weaken
  enforcement or add a test-only carve-out to discharge it is unaffected, as are CP-3's
  evidence limits — **I am not proposing that any fixture work be reopened.**

These sit under the adult-only rescope in *direction*, but they are carried obligations
against **shipped** behaviour, so the R0 freeze row does not absorb them.

### A3. B-40 and `tg_directory_requires_band` remain deployed and in force
The adult-only decision supersedes the 13–17 target **as direction only**. The shipped code
and production schema still implement the 13+ design, **including B-40 and
`tg_directory_requires_band`, and stay in force until a reviewed replacement ships.** The R0
row covers the *freeze on new work*; it does not record that a 13+ mechanism is **live in
production right now** under a superseded direction. That asymmetry is exactly the kind of
thing that goes missing, and it has a real failure mode: someone reading "adult-only" as
current could remove a protection that is still load-bearing.

### A4. Connected invitations
Scoping was **authorised in a new Codex window before any implementation**, explicitly **not**
recorded as legally cleared. Two of the three protected files in this tree are the invitation
documents, **modified and unreconciled** — they are the only protected files whose content is
*expected* to need reconciliation, and the draft's F-10 row covers `AGENTS.md` only.

### A5. C-36 / QA B7
`CLAUDE.md:2036` — fixture-blocked, needs a **fresh first-join account**, owner recorded only
as *"Blocked until such an account exists."* It is one of Phase 1's four explicitly carried
rows and has never been discharged. A row with no owner beyond a fixture precondition is the
shape the record elsewhere insists must not go ownerless.

## B. Smaller items, lower confidence, listed for completeness

- **C-32** — **corrected on Codex's review: a rewrite DID occur and I implied it had not.**
  `docs/phase-6-presentation-update-2026-09-18.md` records an **accepted 18 September
  presentation refresh** covering both surfaces C-32 names — About Études (Lists copy,
  four refreshed screenshots, accessibility descriptions, a new Explore Connected entry
  point) and Explore Connected (tightened opening copy, privacy illustrations). Samuel
  accepts the examples for now. **RC sign-off may still remain; "only the Phase 4 accuracy
  half is done" was wrong and is withdrawn.** Any future statement should cross-reference
  that record.
- **C-5** — fixed locally 2026-09-15 with **UI/device acceptance not claimed**.
- **The abandoned Apple refresh token** (`CLAUDE.md:2462`) — a live token minted by the C-44
  gate (b2) exchange, never revoked, nobody holds it. Pre-existing operational residue,
  explicitly **still outstanding**. Trivial in effort, non-trivial in that it is a live
  credential.
- **P5-G / P5-H** are the named next Phase 5 units and the draft does not name them; P5-H
  additionally **must RE-DERIVE the ASC mapping rather than republish it**, which interacts
  with A1's condition 6.
- **The TestFlight checkpoint** before StoreKit work is settled.
- ~~**C-56**~~ — **WITHDRAWN, and I was wrong twice over.** I described it as "a coverage
  defect in the U6a metric". **C-56 is `PracticeTimerView.requiresAppSetUpNow()` performing
  Core Data fetches from inside `body`** (`docs/audit-findings.md` row C-56), and it is
  **RESOLVED** — `docs/phase-5-c56-acceptance.md` records P1–P5 all met, including a positive
  control that fails against pre-fix `8cc8e1c`. The U6a denied-write telemetry limitation is
  **B-34**, which the draft already carries.

  **The source of my error is worth more than the error.** I took the description from
  `CLAUDE.md`, which says C-56 is *"a coverage defect in the U6a metric"* — and the finding
  register says otherwise. **That is a live instance of F-11 record drift**, found by
  accident, in the file a new session reads first. I have not edited `CLAUDE.md`; flagging it
  under F-11 rather than silently correcting it.

## C. One thing I would not change

The draft's handling of the **sharing freeze as six separately-stated concerns** rather than
one blocker is, I think, the most valuable part of it, and I would resist any later pressure
to collapse them — concern 6 in particular ("do not label an unbuilt protocol a reproduced
production defect") is the kind of distinction that decays first.

## C2. The pattern behind three of my four errors

Three of the corrections above — A1, A2 and C-56 — are the **same mistake**: I quoted a
durable document's *stated cause* as a *current condition*, without checking its date against
later deployments. Scope 011 (2026-09-15) invalidated two recorded blockers written on
2026-09-05 and 2026-09-08, and `CLAUDE.md` carried a description the finding register
contradicts.

**This is the failure mode the project already names** — "historical paragraphs are dated
evidence, not automatically current authority" — and it is exactly C-52's shape: a durable
document asserting a fact is not evidence of that fact. **A carried obligation and its
recorded blocker must be dated and re-checked separately**; an obligation can survive while
the reason given for it has expired, and re-quoting the expired reason makes a live item look
settled or an unsettled item look blocked.

## D. Scope note

I have **not** verified every row of the draft independently; I checked the rows above against
`CLAUDE.md` at `dec0236` and the cleanup evidence I gathered in this window. Absence of a
challenge to a row is not an endorsement of it.
