# UNIT 1b — PREDICTION, COMMITTED BEFORE MUTATION. PRESENTATION ONLY.

**At `bba6a7b`, 2026-09-10.** Unit 1a's format identity, derivative, preflight
logic and durable `authorisedOmissions` are **not reopened**.

---

## 1. The constraint that shapes this — `save()` DISMISSES

`AddEditSessionView.save()` (`:1935`) publishes and then calls `dismiss()`
(`:2136`–`:2138`). **So an alert raised after `save()` can never appear — the
view is gone.** The decision must therefore happen **before** `save()` runs, at
the Save action (`:1682`). `PostRecordDetailsView` has the same shape:
`saveToCoreData(visibility:)` (`:1755`) publishes at `:1840`.

## 2. A product question the instruction leaves open — MY RESOLUTION, STATED

*"Cancel → no publish payload is queued"* does not say whether the **local
session still saves**.

**Resolution: Cancel returns the member to the editor and saves NOTHING.** The
dialog is raised **by pressing Save**, so the least surprising meaning of Cancel
is "go back" — and it avoids inventing a local/remote mismatch, where a session
would sit locally with Share ON while nothing was ever queued (the C-60/C-61
class of defect). The member keeps every edit and can remove the attachment or
turn Share off. **If you want Cancel to mean "save locally but don't share",
say so and it is a one-line change.**

## 3. PREDICTION

**P1 — no omission needed → nothing changes.** When the preflight clears, Save
behaves exactly as today: no dialog, no extra state, the same publish call.

**P2 — one restrained dialog.** *"Attachment too large to share — This
attachment can stay in your Journal, but it can't be included in this Connected
post."* · **Cancel** / **Share Without It**. Plural wording for several; **no
attachment-management UI**.

**P3 — the presentation is CAUSE-AGNOSTIC.** The copy names no reason, so a
future permanent preflight case needs **no presentation change**. Nothing in
Unit 1b understands "video" specifically.

**P4 — Cancel queues nothing** (and, per §2, saves nothing).

**P5 — Share Without It** passes the preflight's own omission set into the
payload's `authorisedOmissions` and proceeds through the **existing** publish
call. **The persistent private-eye state is never touched.**

**P6 — retry never re-prompts**, because the consent is already in the persisted
payload and the queue replays that payload. Unit 1b adds no runtime prompt path.

**P7 — both entry points behave consistently**, and neither changes outside this
decision.

**P8 — no new modifier on `AddEditSessionView`'s body.** Its body is at the
type-checker limit — a fourth `.alert`, *even extracted into a `ViewModifier`*,
produced *"unable to type-check this expression in reasonable time"* during
Unit 1a. **The existing single attachment alert is generalised** to carry either
a one-action notice or this two-action consent. That is the small dedicated
boundary, and it adds **zero** modifiers.

### Evidence

Non-vacuous focused tests: preflight-clear publishes unchanged; Cancel queues
nothing; Share Without It queues **exactly** the authorised set; the consent
survives payload encode/decode; attachment privacy is unchanged. Debug and
Release clean **on clean derived data**; **warning delta zero**; structured
full-suite census.

## 4. Out of scope

Video optimisation (**C-75**) · C-73's remainder · any change to publishing
architecture · any broader refactor of either view.
