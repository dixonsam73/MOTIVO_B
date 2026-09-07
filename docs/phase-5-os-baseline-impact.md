# PHASE 5 — iOS 26.2 BASELINE: IMPACT ASSESSMENT. 2026-09-07

**ASSESSMENT ONLY. NOTHING CHANGED.** No project setting, no source file, no
production object. Reported for acceptance before implementation.

**Proposed:** raise `IPHONEOS_DEPLOYMENT_TARGET` from **18.5** to **26.2** for
the whole product. The r3 split — *"Solo on 18.5+, Connected requires iOS 26
continuously"* — is withdrawn.

---

## 1. HEADLINE — THE CHANGE IS SMALL, AND THE STATED RATIONALE NEEDS ONE ADJUSTMENT

**The edit is four literals and one dead branch.** There is no compatibility
layer to dismantle, because **one barely exists**.

**Measured: the entire app source contains exactly ONE availability branch** —
`DebugViewerView.swift:1185`, `if #available(iOS 16.0, *)`, and that file is
`#if DEBUG` end to end. There is **no `@available` anywhere**, and **no `18.5`
reference outside the project file and the documentation**.

**So "a single 26.2 baseline materially simplifies the product surface" is TRUE
of the TESTING and CAPABILITY surface and NOT TRUE of the CODE surface** — there
is essentially no old-OS code to delete. **The change should be justified on what
it guarantees, not on what it removes**, because the removal is one `#if DEBUG`
branch.

**The capability argument is the strong one and it is now measured**, see §5:
both rig devices are on **26.6.1**, so a 26.2 baseline makes `DeclaredAgeRange`
unconditionally available on every supported installation **and** on every device
Études is tested on.

---

## 2. PROJECT AND TARGET SETTINGS — 4 LITERAL EDITS

| block | target | current | after |
|---|---|---|---|
| **Project-level Debug** | — | `18.5` | **`26.2`** |
| **Project-level Release** | — | `18.5` | **`26.2`** |
| App target Debug (`com.samueldixon.motivo.dev`) | app | *(inherits)* | *(inherits)* |
| App target Release (`com.sdsongs.etudes`) | app | *(inherits)* | *(inherits)* |
| **`MOTIVOTests` Debug** | unit tests | `18.5` **explicit** | **`26.2`** |
| **`MOTIVOTests` Release** | unit tests | `18.5` **explicit** | **`26.2`** |
| `MOTIVOUITests` Debug/Release | UI tests | *(inherits)* | *(inherits)* |

**The app target carries no explicit deployment target and inherits the
project-level value** — so the two project-level edits move the shipping product.
`MOTIVOTests` overrides it redundantly and must be moved too, or the test target
would keep a **lower** floor than the host app.

**`TARGETED_DEVICE_FAMILY = 1` is unchanged.** `Info.plist` carries no
`MinimumOSVersion` override, so nothing there needs touching.

## 3. AVAILABILITY BRANCHES THAT BECOME REDUNDANT

**Exactly one, and it needs removing in the same unit rather than left behind:**

`DebugViewerView.swift:1185` — `if #available(iOS 16.0, *)`. Under a 26.2 floor
this is **always true**, and Swift will emit a *"condition is always true"*
warning. **Leaving it would add a new warning to a build this project verifies
warning-by-warning**, so it is part of the change, not follow-up.

**Nothing else qualifies.** No `@available` attributes exist in the app source.

## 4. PACKAGE DEPENDENCIES — NO CONSTRAINT CAN CONFLICT

Ten resolved packages: `audiokit 5.7.2`, `audiokitex 5.7.0`,
`soundpipeaudiokit 5.7.3`, `tonic 2.1.0`, `kissfft 1.0.0`,
`supabase-swift 2.5.1`, `swift-crypto 3.15.1`, `swift-asn1 1.5.1`,
`swift-concurrency-extras 1.3.2`, `keychainaccess 4.2.2`.

**Every pin is a MINIMUM version, and SPM resolves against package requirements,
not our deployment target.** Raising our floor **relaxes** constraints and cannot
produce a resolution conflict. The AudioKit family is the oldest-feeling
dependency and is the one to watch **at build time**, not at resolution time.

**This is a build-verification item, not a risk.**

## 5. DEVICE AND TESTFLIGHT REQUIREMENTS — THE OPEN RIG QUESTION IS NOW CLOSED

**Measured today with `devicectl`.** This was recorded as *"NOT recorded anywhere
in this repository"* in the r2 acceptance cases and is now established:

| rig device | model | iOS |
|---|---|---|
| **Device A** — SD beta burner | iPhone 16e | **26.6.1** (build 23G83) |
| **Device B** — SD iPhone | iPhone 17 Pro | **26.6.1** (build 23G83) |

**Both exceed 26.2.** Two consequences:

- **The 26.2 baseline is installable on the whole rig**, so the change costs no
  test coverage.
- **`docs/phase-5-b-cp1-design-r2.md` §11.5's rig precondition is MET** — sandbox
  age-assurance testing needs 26.2+ and both devices qualify. That open item can
  be closed when the design text is updated.

**TestFlight and App Store:** testers must run **26.2+**, and the App Store
minimum becomes 26.2. **The installable device set narrows to models supporting
iOS 26.2 — confirm the exact model list against Apple's current support page
before any release messaging.** I have not verified that list and am not
asserting it.

**No installed customer base exists** (B-36, account-holder confirmed), so no
existing user loses access. **Build 131 on TestFlight was built against 18.5 and
remains installable on older devices until replaced** — a transient, pre-release
artefact, not a supported configuration.

## 6. PHASE 5 DESIGN TEXT CARRYING THE OBSOLETE SPLIT

| where | what changes |
|---|---|
| `phase-5-b-cp1-design-r2.md` **§2** | the A/B/C options table and the recommendation. **Option C is withdrawn**; the outcome — **no fallback self-declaration** — is unchanged and is now reached more directly |
| **§2.1 INVARIANT CP-OS-1** | **subsumed, not wrong.** "Connected requires 26 at all times" is trivially satisfied when the app requires 26.2. **Its reasoning must be RETAINED**, because it is why the app-wide floor is coherent: below 26 `activeParentalControls` cannot be read and reconciliation cannot run |
| **§2.1 billing edge** | **dissolved.** A member cannot run Études on a sub-26 device at all, so "billed while Connected is unavailable" cannot arise. Remove from the P5-G list (item 8) |
| **§3 flow** | drop *"iOS 26+ only; older iOS shows a requirement notice"* — there is no older-iOS branch to describe |
| **§11.5 S-B9 / S-B9b** | **become unrunnable and must be retired, not left failing.** Both require a pre-26 device; none exists in the supported set. S-B9b was the CP-OS-1 acceptance |
| **§11.5 rig precondition** | **now MET** (§5) |
| **§10.2 client delta** | drop the planned `@available(iOS 26.0, *)` gating — a **real simplification for P5-F** |
| `phase-5-scope.md` P5-B row | restate without the join-gate clause |
| `CLAUDE.md` Environment | *"deployment target iOS 18.5"* → 26.2 |

**§9.1's limitation is unchanged and must not be quietly upgraded.** The band
remains **client-asserted**; a guaranteed-available Apple API does not make the
server able to verify what the client sent.

## 7. CP-1 REASSESSMENT — NO CHANGE REQUIRED, CHECKED NOT ASSUMED

**Not one CP-1 object exists to accommodate pre-26.2 clients.** Verified against
the deployed definitions:

- **`account_privacy`** — bands, preferences and `*_set_under_band` are
  Apple-band semantics, OS-agnostic.
- **The four RPCs** — none references an OS, a version or a client capability.
- **The trigger** — its skip clause exists because **`BEFORE INSERT` fires on
  `ON CONFLICT DO UPDATE`** and because two keeper directory rows predate the
  constraint. **Neither reason is OS-related.**

**One measurement correction on myself:** a crude substring check reported the
trigger function as `mentions_os = true`. **It was matching `26` inside the date
`2026-09-06` in its own comment.** A precise re-check returns
`real_os_coupling = false`. **A search loose enough to be safe was loose enough
to be wrong** — the same shape as the C-14 detector, and the reason it is
recorded rather than silently corrected.

**So: do not redesign the accepted privacy model. There is no evidence for it.**

## 8. WHAT THE CHANGE COSTS, STATED PLAINLY

**One deliberate design property is being given up, and it was chosen one day
ago for a reason:** option C kept Solo — a purely local journal needing no age
data at all — available to the widest possible device base, on the argument that
subjecting Solo users to an OS floor they gain nothing from is a pure loss.

**That argument is not refuted by this decision; it is outweighed by it** — a
single baseline removes a permanent two-capability product. **The cost is real
and worth naming: any future decision to widen Solo's reach again reintroduces an
availability split, and by then there will be shipped members.** The window in
which this is free is now, and only because nothing has shipped.

## 9. PROPOSED UNIT SHAPE — "P5-A2, PRODUCT BASELINE"

Small, self-contained, and **before CP-2**:

1. Four literal edits (§2) and removal of the one dead `#available` (§3).
2. **Verification:** Debug **and** Release compile clean with **no new
   warnings**; `xcodebuild -showBuildSettings` confirms **26.2** resolves for the
   app target in both configurations, and for `MOTIVOTests`.
3. **`MOTIVOTests` must still run its 7 tests** — C-54's lesson is that this
   target has broken silently before because nobody executed it.
4. Documentation updates per §6, including **closing the §11.5 rig precondition**
   and **retiring S-B9/S-B9b**.
5. **Not included, flagged only:** `MARKETING_VERSION 1.0` and
   `CURRENT_PROJECT_VERSION 131` are hard-coded and never incremented, so
   CLAUDE.md records that **no installed build can be traced to its source**.
   Editing project settings is a natural moment to fix that. **It is a separate
   decision and is deliberately not bundled here.**

## 10. STATUS

**NOTHING IMPLEMENTED. CP-2 NOT STARTED.** Awaiting acceptance of this scope.
