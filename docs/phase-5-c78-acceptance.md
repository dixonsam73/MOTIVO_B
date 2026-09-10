# C-78 — COMPLETE AND DEVICE-CONFIRMED. RESOLVED 2026-09-10.

> **DEVICE CHECK GREEN 2026-09-10, reported by the account holder.** Device B,
> Études Dev (Debug), all five steps of `docs/phase-5-c78-prediction.md` §4:
> the imported title shows before Save, in session detail after Save, as the
> persisted filename, and after reopening, through **both** import paths; and a
> rename made before Save wins. **Not observed:** the duplicate-name case (P5),
> which was not one of the five checks.
>
> *Previous banner, preserved:* "C-78 stays open until the Device B check …
> confirms that a freshly imported named audio file displays and persists under
> its expected title." §1–§4 below were written before the device check and
> remain accurate as of that point.

Prediction: `docs/phase-5-c78-prediction.md`, committed at `def1f3b` **before
mutation**, together with the guard test. **C-80** (imported video) was filed
separately and is untouched.

## 1. Result

| | Prediction | Outcome |
|---|---|---|
| **P1** | the guard FAILS on the pre-fix code | **MET** — against `def1f3b`'s tree, the two counting tests **failed** and the regression guard passed. Structured: *3 reported, 2 Failed, 1 Passed* |
| **P2–P5** | titles, persistence, rename, duplicates | **Not device-observed.** Supported by the behavioural tests (seed, trim, audio-only, blank/nil, never overwrite) and by the traced readers in the prediction §1 |
| **P6** | nothing else changes | **MET in source** — `Attachment.displayName` still `.file`/`.pdf` only; the rule returns `nil` for every non-audio kind (tested) |
| **P7** | server effect: publish none; explicit direct send carries the title | **CORRECTED 2026-09-10 — the "publish: none" half was WRONG.** Publish falls back to the saved audio/video title (`BackendShim:1156-1158`), so a `PostRecordDetailsView` import publishes `display_name = "Again"`; an `AddEditSessionView` import saves no title and sends none. The value is the title the member sees, on a post they chose to share. See the prediction's correction |
| **P8** | no migration | **MET** — no migration code |
| **P9** | 208/208; warning delta zero | **MET** — **208 declared, 208 passed**, structured census, nothing missing in any named suite. **Debug 187 / Release 175** on clean derived data — **delta ZERO**, and no warning in any touched file |
| **P10** | non-vacuous | **MET** — with the call removed from `PostRecordDetailsView.stageData`, **exactly the two counting tests failed** (*8 reported, 6 Passed, 2 Failed*); the call was restored and the full suite had already run green on the restored state |

## 2. What changed — three files of production code, one line per view

- **`AttachmentImportPolicy`** — `stagedAudioNamesKey`,
  `importedAudioTitle(kind:displayName:)`, and
  `seedImportedAudioTitle(stagedID:kind:displayName:defaults:)`, which **never
  overwrites** an existing entry.
- **`AddEditSessionView+Attachments.stageData`** and
  **`PostRecordDetailsView+Attachments.stageData`** — one call each, **before**
  the append.

## 3. The guard, and why it counts

`ImportedAudioTitleTests` asserts **exactly one call inside each `stageData`**
and **exactly two call sites in the whole app, one per import path**. The
counted token is the qualified call `AttachmentImportPolicy.seedImportedAudioTitle(`,
which the declaration does not contain — **so it cannot pass on the function's
own presence** (Unit 1b §4's trap). Comments are stripped first (`U5c-34`).

## 4. The register's proposed fix was wrong, and it would have passed review

C-78 as filed proposed widening `stageData`'s `.file || .pdf` condition. That
would have written a map no audio reader consults — **a fix that compiles,
looks right, and changes nothing a member can see.** Caught by tracing every
reader before writing code, not by a device. `testTheSeededKeyIsTheOneAudioReadersUse`
pins the distinction.

## 5. Device check — the remaining obligation

Run `docs/phase-5-c78-prediction.md` §4 on **Device B, Études Dev (Debug)**:
import a named WAV through **both** paths (new session, and post-record after a
timer), confirm the title before Save, in session detail after Save, in the
persisted filename, and after reopening; and confirm a rename made before Save
wins.
