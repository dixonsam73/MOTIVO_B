# C-56 — ACCEPTANCE. BODY-TIME CORE DATA READS ARE GONE.

**Unit:** P5 / C-56. **Prediction:** `docs/phase-5-c56-measurement-and-prediction.md`,
committed at `3b1e8d0` **before** any product change.
**Scope:** `MOTIVO/PracticeTimerView.swift` only. Zero backend change, zero
migration, zero production mutation, no App Store Connect change.

---

## 1. Result against the committed prediction

| | Prediction | Outcome |
|---|---|---|
| **P1** | zero body-time `viewContext.fetch` across the three census sites | **MET** — `testNoBodyTimeDeclarationReadsCoreData` passes |
| **P2** | gate decisions unchanged | **MET by diff** — see §3 |
| **P3** | gate still opens/closes at the same moments; invalidated by the same Core Data writes | **MET by construction** — `@FetchRequest` *is* the Core Data change signal |
| **P4** | initials unchanged for the same `Profile.name` | **MET by diff** — only the source of `profile` changed |
| **P5** | the control **fails** against pre-fix `8cc8e1c` | **MET — and this is the load-bearing one.** See §2 |
| **P6** | no backend/migration/production change; C-3 untouched | **MET** — the diff is 27 insertions / 13 deletions in one file |

**Builds:** Debug **and** Release both `BUILD SUCCEEDED`.
**Suite:** **121 of 121 pass**, twice, measured with `scripts/test-census.py`
across two result bundles — `missing=none` on every named suite. Baseline was
118; the +3 are this unit's control.

---

## 2. THE CONTROL FAILED AGAINST PRE-FIX CODE, AND NAMED THE THREE SITES

`MOTIVOTests/AppSetUpGateBodyFetchTests.swift` run at `8cc8e1c`:

```
body-time Core Data reads must be zero; found:
private func requiresAppSetUpNow() -> Bool { → viewContext.fetch
private func requiresAppSetUpNow() -> Bool { → fetchInstruments(
private func requiresAppSetUpNow() -> Bool { → NSFetchRequest
private var appSetUpCompletenessKey: String { → viewContext.fetch
private var appSetUpCompletenessKey: String { → fetchInstruments(
private var appSetUpCompletenessKey: String { → NSFetchRequest
private var homeTopBar: some View { → viewContext.fetch
private var homeTopBar: some View { → NSFetchRequest
```

**A control that cannot fail is not evidence.** This one fails on the pre-fix
tree, names exactly the three sites the census predicted, and passes after — so
the assertion is about the **absence of the defect**, not the presence of a fix.
It is comment-stripped before scanning, for the reason recorded at `U5c-34` and
twice since.

**Its stated limitation, so it is never over-read:** it scopes itself to six
named declarations. It does not prove `body` is fetch-free in general, and a
body-time fetch introduced through some new helper would not be caught.
`testEveryScopedDeclarationStillExists` keeps it from silently scanning nothing.

---

## 3. The change, and why P2 needs no separate test

The decision expressions are **byte-identical** before and after. Only the
source of the data moved:

```
- guard let profile = try? viewContext.fetch(req).first else {      → guard let profile = profiles.first else {
- let hasInstrument = fetchInstruments().contains(where: { … })     → let hasInstrument = allInstruments.contains(where: { … })
```

`hasName`, `hasInstrument`, every `return`, and the ordering between them are
unchanged, in all three sites. **The error direction is preserved too:** the old
code fell into the "needs set-up" branch when the fetch threw; an empty
`FetchedResults` takes the same branch. It still fails toward showing set-up.

**The gate stays DERIVED and is deliberately not mirrored into `@State`.** That
was the committed anti-prediction: state something has to remember to invalidate
is the class of defect C-55 turned out to be.

**One ordering nuance, stated rather than glossed.** `profiles` is declared
`sortDescriptors: []`, matching the old unsorted `fetchLimit 1` fetch. With more
than one `Profile` row, `.first` was already undefined; this preserves that
rather than silently imposing an order that would look like a decision nobody made.

---

## 4. What this ADDS, named because it is a real behaviour change

`@FetchRequest` subscribes the view to Core Data change notifications for
`Profile` and `Instrument`. The pre-fix code fetched at body time and subscribed
to nothing — so **the view now has two invalidation sources it did not have.**

**It cannot close a re-render loop, and that was checked rather than assumed.**
A loop needs body evaluation to write the entity it observes. The only writers of
`Profile` and `Instrument` in this file are
`createAndSelectInstrumentFromPicker`, `createActivityChoiceFromPicker` and
`fetchOrCreateProfileForSessionMetaPicker` — all picker-driven, none reachable
from a body evaluation. Nothing on the body path writes either entity.

**The residual is a device observation, not a defect:** a save that touches an
`Instrument`'s inverse relationship will now invalidate this view where it
previously would not. That is one extra body evaluation on a user-driven save,
against ~125 µs of main-actor I/O removed from *every* evaluation. **Not
device-verified** — this unit is source and simulator evidence only, and must
not be described otherwise.

---

## 5. Method note — I bypassed my own instrument and it bit me

Two full console runs reported "120 passed" with **different membership** — each
dropped a different test line. That looked exactly like C-64's original claim.
The structured result showed **121 of 121 passed** in both: the console had lost
a line to parallel-clone interleaving.

`scripts/test-census.py` exists precisely to prevent this and its own header says
*"NEVER infer a test's absence from console output again."* I grepped the console
anyway. **The instrument was wrong before the conclusion was — for the second
time on this same question.**
