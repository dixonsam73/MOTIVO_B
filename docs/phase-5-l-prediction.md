# P5-L — INVESTIGATION RESULT AND FIRST PREDICTION, COMMITTED BEFORE MUTATION

**At `7091ba3`, 2026-09-10.** All six rows were re-measured against HEAD first.
Account-holder decisions the same day. **C-3, C-80, C-81, P5-I/C-34 and the
carried Production Connected checks are out of scope.**

---

## 1. Dispositions decided

| Row | Decision | Basis |
|---|---|---|
| **C-37** | **CLOSE on evidence, no code** | Avatar key is locked to `users/<uid>/avatar.jpg`, so it moves only between `""` and that value — both transitions pass through the placeholder where the task lives. Same-key replacement is C-34's, not this row's |
| **C-39** | **CLOSE on evidence — intended** | `fetchFeed` "all" targets `[owner] + following` and relies on RLS; own posts in the feed are the recorded product model |
| **C-40** | **CLOSE on evidence, no new test** | No client path treats a 401 as authoritative: expiry preflight (60 s skew), 401 → forced refresh → one retry, four-way refresh-failure disposition whose worst case is reversible and data-preserving. **The original one-off 401 remains UNEXPLAINED** |
| **C-62** | **FIX (a) under an explicit waiver** of P5-L's measure-first rule | The title has no diagnostic value; removing it ends the privacy question at negligible cost |
| **C-42** | **MEASURE — temporary probe on Device B** | Account holder confirmed **both** Device B's App Store country **and** the Sandbox tester's are **United Kingdom**, so the storefront-mismatch explanation is **ruled out** and must not be used to close it. The observation has not recurred since |
| **C-47** | **HOLD — history reported before any change** | Option B preferred in principle |

## 2. PREDICTION — C-62

**L1 — pre-change:** `PrivacyLogHygieneTests.testPublishEnqueueLogCarriesNoSessionTitle`
**FAILS**; `testPublishEnqueueLogKeepsItsNonContentDiagnostics` **PASSES**.

**L2 — after:** both pass. The log line keeps `postID`, duration, activity,
mood, effort, `notes` present/nil and `notesPrivate`; only the title goes.

**L3 — warnings unchanged: Debug 177 / Release 165.** The probe adds no warning.

**L4 — census 221 / 221** (219 + 2).

## 3. C-42 PROBE — TEMPORARY INSTRUMENTATION, WITH ITS REMOVAL CONDITION

`C42StorefrontProbe` logs, through `os.Logger` with `privacy: .public`, the
`Storefront.current` country, id and currency, and for each product its
`displayPrice`, `price` and `priceFormatStyle` currency and locale — **after
every product load** and **when the selection screen appears**. It changes no
behaviour and touches no purchase call.

**STANDING REMOVAL CONDITION, as for `ActivationTrace` and `JWSFreshnessProbe`:
the probe is deleted the moment C-42 is scored, and the removal is verified as a
pure deletion.** Recorded in `CLAUDE.md`'s temporary-instrumentation entry.

**The historical observation and the storefront-change edge case stay
separate.** The probe diagnoses what StoreKit returns; the reload-on-change
hardening is a different change and is **not** made here.
