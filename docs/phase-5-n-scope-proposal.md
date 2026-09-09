# P5-N — PROPOSED SCOPE AND ACCEPTANCE. NOT IMPLEMENTED.

**Reported before implementation because the bounded inventory materially
exceeds C-11 + C-67.** Inspected at `2a8e361`, 2026-09-09. Nothing in this file
has been built.

---

## 1. What P5-N currently owns

`docs/phase-5-scope.md:65` names exactly: **C-11** (VoiceOver mislabel) ·
**C-67** (attachment viewer transport controls unlabelled) · *"remaining
polish"*, gating **none**. No other acceptance criterion for P5-N exists
anywhere in the Phase-5 record — *"remaining polish"* is undefined, and this
proposal does not treat it as authority to expand.

## 2. Both filed defects VERIFIED AT HEAD by reading, not trusted from the register

**C-11 — confirmed, and the register's line number has drifted.** The row says
`SessionDetailView:1704`; at HEAD the site is **`:1667`**. The **heart /
favourite** button carries `.accessibilityLabel("Open comments")` — identical to
the genuine comments button 23 lines below at `:1690`. **VoiceOver therefore
announces two adjacent buttons with the same name, and activating the first one
favourites rather than opens comments.**

**One more control sits in that same row and is unlabelled:** the **share**
button (`square.and.arrow.up`, ~`:1702`) has `.buttonStyle(.plain)` and no
label. So the action row is: heart **mislabelled**, comment **correct**, share
**absent**.

**C-67 — confirmed.** The refined sweep independently flags 5 unlabelled
icon-only controls in `AttachmentViewerView`, consistent with the row's own
account of the transport buttons; both scrub `Slider`s also carry no label.

## 3. The bounded inventory — C-11 AND C-67 ARE NOT ISOLATED

A heuristic sweep for `Button`s whose label content is an `Image(systemName:)`
with no `Text(`/`Label(` and no `accessibilityLabel` within the label window:

| | |
|---|---|
| First pass | **76** candidates across 24 files |
| **Calibrated** by reading a sample | one systematic false-positive class found — an icon rendered *beside* a `Text(title)`, e.g. `ConnectedAttachmentShareUI:239`, which VoiceOver reads correctly |
| **Refined** | **49 candidates across 20 files** |
| Sample true-positive rate | ~3 of 4 read (`TasksManagerView:329` trash, `PeopleView:140` back chevron — real; the share-UI row — false) |

**THIS IS A CANDIDATE LIST, NOT A CENSUS, AND MUST NOT BE QUOTED AS A DEFECT
COUNT.** Every entry needs reading before it is called a defect — the C-64
lesson. Largest concentrations: `PracticeTimerView` 6, `TasksManagerView` 6,
`AttachmentViewerView` 5, `AttachmentsCard` 3, `ContentView` 3,
`SessionDetailView` 3, `PracticeTimerView+Sheets` 3.

**A SECOND DIMENSION IS ENTIRELY UNMEASURED.** This finder detects *absent*
labels. **It cannot detect a MISLABEL — which is exactly what C-11 is** — because
a wrong label is still a label. The size of the mislabel population is
**unknown**, and no claim is made about it. C-11 was found by a human reading the
screen, and nothing here would have found it.

## 4. PROPOSED SCOPE — the smallest unit that discharges what P5-N actually owns

**TIER 1 — proposed, and nothing beyond it.**

1. **C-11** — correct the heart button's label; and label the **share** button in
   the same row, because it is the same control row, in the same edit, and
   leaving one unlabelled control in a row being fixed for labels is the kind of
   half-fix the register keeps recording.
2. **C-67** — label `AttachmentViewerView`'s transport controls (`gobackward.10`,
   play/pause, `goforward.10`, mute) and give both scrub `Slider`s a label and a
   value. **The playback-speed control is already device/VoiceOver verified and
   is NOT touched.**

That is **two files**, both named in the existing scope.

**TIER 2 — REPORTED, NOT PROPOSED.** The ~49 candidates across the other 18
files. They are real work and probably real defects, but fixing them is a
different unit with a different size, and the account holder has ruled out
turning this into whole-app certification.

**EXPLICITLY OUT:** Dynamic Type, colour contrast, focus order, rotor support,
custom actions, reduce-motion, and any claim of VoiceOver conformance.

## 5. PROPOSED ACCEPTANCE

- Prediction committed **before** mutation, as with C-56 and C-70(a).
- A **structural control scoped to the two touched files** — every icon-only
  `Button` in them carries a label — **proven non-vacuous by failing against
  pre-fix HEAD**, comment-stripped (`U5c-34`).
- **C-11 needs an assertion the structural finder cannot make:** that no two
  controls in that action row share a label. Absence-of-defect, not
  presence-of-fix.
- Debug and Release clean; **warning delta zero**, measured against the pre-fix
  commit in an isolated worktree.
- Full suite from the **structured** result via `scripts/test-census.py`.
- **No device claim.** Labels are verifiable in source; whether VoiceOver reads
  them naturally is a device observation this unit will not have. If a VoiceOver
  pass on Device A is wanted, it is a separate authorised step.
- Zero backend, production, ASC, enforcement, device or age-state mutation.

## 6. The decision being asked for

Tier 1 alone is a small bounded unit and can proceed under the standing
prediction-first discipline. **Tier 2 is where the scope question actually
lives**, and it is not proposed here.
