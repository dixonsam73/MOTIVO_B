# C-82 — OMISSION IDENTITY. RESOLVED 2026-09-11.

> **CLOSED ON ITS STATED CONDITIONS, 2026-09-11:**
> - the Device B retest passed (§5);
> - the account holder restored Run → Release, and the scheme is byte-identical
>   to the committed blob `013cc35`;
> - the final census reads **256 declared, 256 passed**, with
>   `testRunActionBuildsRelease` and `testRunActionPinsNoStoreKitConfiguration`
>   both passing.
>
> *Heading at the retest, preserved:* "DEVICE B RETEST PASSED 2026-09-11 (§5).
> NOT CLOSED — RELEASE RESTORE AND SCHEME GUARD OUTSTANDING."

> *Previous heading, preserved:* "IMPLEMENTED. DEVICE RETEST OUTSTANDING — NOT
> CLOSED." §4 below is the procedure as written before the run; §5 is the result.

**Status: implemented, not closed.**
- Nothing below is device evidence.
- **C-82 stays open** until:
  - the Device B retest (§4) passes;
  - the account holder restores Run → Release;
  - `SchemeConfigurationGuardTests` passes;
  - the census reads 256 / 256.
- The Run → Debug scheme change in the working tree is **not committed**.
- Unit 1b's corrected acceptance history and the falsified K5 in
  `phase-5-c82-c73-acceptance.md` are kept as they are.

**The prediction came first.** `docs/phase-5-c82-omission-identity-prediction.md`
and the pre-change guards were committed at **`6fe6833`**, before any fix.

**Out of scope, not touched:** C-3, C-69, C-75, C-76, C-80, C-81 and B-38.

**Not done:**
- no production, ASC, enforcement or age-state mutation;
- no old queued publish touched.

## 1. Result

| | Prediction | Outcome |
|---|---|---|
| **L1** | 256 declared; exactly the 7 new non-control tests fail, plus `testRunActionBuildsRelease`; the control passes; 8 failed / 248 passed | **MET exactly.** 8 failed / 248 passed. The failure messages show the defect: the translation gave A where B was expected (`[F82AEB56…, P]` ≠ `[CF64DD88…, P]`). The flush test stayed queued with no post row. **The control `testUntranslatedStagedIDIsNotMatchedAtFlush` passed**, so the fixture really is selected for preparation when it is not skipped |
| **L2** | 256 declared, 255 passed, 1 failed (the scheme guard only) | **MISSED on the first post-change run: 254 / 2.** See §2. After the stale pin was re-pointed: **256 declared, 255 passed, 1 failed** — `testRunActionBuildsRelease` only. **No test skipped**, so both local-stack flush tests executed |
| **L3** | Debug 177 / Release 165, warning set identical | **MET.** Both clean builds succeeded. See the note below |

**L3 note.** The raw diff first flagged one line: the
`appintentsmetadataprocessor` notice, whose timestamp and pid prefix changes on
every run. With that prefix normalised as well as line and column numbers, both
warning sets are identical: 177 = 177 and 165 = 165.

## 2. The prediction miss — the same one-of-N shape again

**The miss.** `ConsentAtBothPublishSitesTests.testBothSitesCarryConsentIntoThePayload`
(Unit 1b) pinned the literal text
`authorisedOmissions: authorisedOmissions.isEmpty ? nil : authorisedOmissions`
at both editor sites. **I did not inventory it before predicting.** It failed on
the first post-change run.

**The correction.** The test is **re-pointed, not weakened**. It now requires
`ConnectedSharePreflight.persistedOmissions(authorisedOmissions, stagedToFinal: stagedToFinal)`,
and its doc comment records the change.

**The re-pointed test is non-vacuous:**
- at `6fe6833` (pre-fix) the new text is **absent** at both sites and the old
  text is present;
- the working tree is the reverse.

**Inventory afterwards.** Every test mentioning the field was checked:
- `QueuePayloadCompatibilityProbe` and `PublishConsentCarriageTests` check
  **carriage and encoding with arbitrary ids**. They remain true, and they are
  exactly the tests that could not see this defect.
- **No other test pins the old text.**

## 3. What changed

**Six Swift files.** No other change; the scheme file is not committed.

- **`ConnectedSharePreflight.persistedOmissions(_:stagedToFinal:)`** — the one
  translation boundary:
  - an id in the map becomes its saved id;
  - an id not in the map passes unchanged (an attachment saved before editing);
  - an empty list gives `nil`, as before.
- **Both `commitStagedAttachments` return `[UUID: UUID]`:**
  - AESV writes the map **only inside its new-attachments loop**;
  - PRDV returns the map it already kept for the thumbnail.
- **Both saves** keep `let stagedToFinal = …` and pass the translated list into
  the payload.
- **Permanent outcome logs**, ids only, all prefixed `Consent omission`:
  - `Consent omission • staged=<A> → saved=<B>` at the translation;
  - `Consent omission • saved=<P> unchanged` at the translation;
  - `Consent omission skipped at upload • postID=<X> • attachment=<B>` at the
    flush.
- **Guards** (`OmissionIdentityTests`, 8):
  - identity on the real save path;
  - the queue **file** re-decoded;
  - a real local-stack flush, with unconvertible WAVs so that "skipped" is
    observable;
  - both editors' wiring;
  - **a bypass guard over every `PostPublishPayload(` construction**;
  - the raw consent state limited to two uses per editor.

**Residuals, stated rather than absorbed:**
- **A commit that fails mid-loop** rolls back its created attachments, but the
  map keeps their ids. An omission then names an attachment that no longer
  exists, which is inert. This path was not changed.
- **The editors themselves cannot be driven from XCTest**, because their staged
  state is SwiftUI `@State`. Their wiring is pinned structurally. **The retest
  in §4 is the end-to-end evidence for both editors.**

## 4. Device B retest

**Setup:**
- Device B ("SD iPhone"), **Études Dev**, Force Connected.
- Run from Xcode; the working tree's Run action is Debug.
- Xcode console filter: **`Consent omission`**.
- Then separately filter **`Connected audio derivative`** and
  **`Queue enqueue`** / **`Queue update`**.

**Path 1 — `PostRecordDetailsView`, the path that failed:**
1. Record a session. In post-record details attach the **32-minute WAV**.
2. Private-eye off, Share on, title **`C82-R2 PRDV`**. Save and choose **Share
   Without It**.
3. **Expected:**
   - `Consent omission • staged=<A1> → saved=<B1>`;
   - `Queue enqueue • postID=<X1>`;
   - on each flush, `Consent omission skipped at upload • postID=<X1> • attachment=<B1>`;
   - **no `Connected audio derivative` line for X1**;
   - the item stays queued. `posts` INSERT is gated, which is expected and not
     the thing under test.

**Path 2 — `AddEditSessionView`, new session:**
1. Start a new session in the editor and attach the same WAV.
2. Private-eye off, Share on, title **`C82-R2 AESV`**. Save and choose **Share
   Without It**.
3. **Expected:** the same four observations, with A2, B2 and X2.

**Path 3 — AESV, the attachment saved before editing (not remapped):**
1. Reopen `C82-R2 AESV`, change only the notes, and Save.
2. **Predicted:** the dialog appears again. Choose **Share Without It**.
3. **Expected:**
   - `Consent omission • saved=<B2> unchanged`, naming **Path 2's B2**;
   - `Queue update • postID=<X2>`;
   - the skip line still names B2.
4. **If the dialog does not appear, report it.** Do not work around it.

**Queue file:** after the paths, a read-only `devicectl copy from` of
`Library/Application Support/MOTIVO/SessionSyncQueue_v1.json` from the Études Dev
container. Items X1 and X2 must carry `authorisedOmissions` = [B1] and [B2],
**never A1 or A2**.

**Old queued test publishes are left alone.** They will keep flushing and
failing as before (C-76, C-83). They are distinguishable by postID from X1
and X2.

## 5. Device B retest — RESULT, 2026-09-11

Device B, Études Dev, Force Connected. The account holder ran the device; the
queue file was copied read-only with `devicectl copy from`. It held 17 items.

| Path | Evidence | Verdict |
|---|---|---|
| **1 · PRDV** (X1 `3CC35AB5`) | `staged=2A08B0A1… → saved=4A201A19…`; `skipped at upload • postID=3CC35AB5… • attachment=4A201A19…` on every flush; its flush fails only with **403 RLS at the INSERT**, so preparation completed and it **never** hit the size limit; queue file `[4A201A19…]` | **PASS** |
| **2 · AESV, new session** (X2 `C3FEE085`) | `staged=5EFAAF75… → saved=503D288A…`; skip lines naming `503D288A`; fails only with 403; queue file `[503D288A…]` | **PASS** |
| **3 · AESV, attachment saved before editing** | dialog appeared, as predicted; `saved=503D288A… unchanged`; queue file holds `[503D288A…]` after the re-save | **PASS** — not remapped |
| **Queue file, whole** | neither staged id (`2A08B0A1`, `5EFAAF75`) appears anywhere | **PASS** |

**The 1904s conversions are `AAC7D156`, established by post id and not by
duration.**
- Its flush fails with `Connected representation of attachment 8E19903F… is
  61081909 bytes, over the 52428800 byte limit`.
- Its queued consent names `3BA63A87`. That is a staged id queued by the pre-fix
  build, and it can never match.
- **This is C-82's original mechanism, preserved on an item the fix cannot
  reach.**

**§4's own check was badly designed, and that is recorded.** The conversion log
line carries no post id, and an old 32-minute item was still queued, so "no
1904s line" could not discriminate between old and new items. The attribution
comes from the failure lines instead.

**Not exercised:** a flush observed after Path 3's re-save. No flush ran in the
window that was watched. The queue file holds `[B2]` after the re-save.

**`35F7C0BD` `['7CCD6A3B']`, 10:40 UTC — not attributed and not scored.**
- It is the tester's **first Path-1 attempt**, interrupted when the app lost its
  Xcode connection and stopped. The app was restarted and Path 1 repeated,
  which is X1.
- Its flush reaches the server INSERT (403) and never converts, so it shows **no
  violation** of the invariant.
- **Whether `7CCD6A3B` names a saved attachment was not established:** no skip
  line was captured for it.

**Residue, deliberately left in place:**
- **`AAC7D156`** converts for ~15 s and fails on every flush. It is a pre-fix
  item the fix cannot repair.
- **`D8A2D2AA`** is a 204 s WAV re-converted on every flush (C-76).
- **12 older items** fail with 403 (C-83's shape).

Removing any of them is fixture cleanup, for a separate decision.

**Date correction.** The falsification banner in `phase-5-c82-c73-acceptance.md`
and the C-82 row both date the falsifying run **2026-09-12**. The evidence says
**2026-09-11**:
- the queue file dates that run's session (`AAC7D156`) at **2026-09-11 07:50
  UTC**;
- `ec62de5` was committed at 2026-09-11 07:57 UTC.

The original text is kept, and corrected here.

**Remaining before C-82 closes:**
1. The account holder restores Run → Release.
2. The full census reads **256 / 256**, with `SchemeConfigurationGuardTests`
   passing.
