# C-82 (REOPENED) — OMISSION IDENTITY. PREDICTION, COMMITTED BEFORE MUTATION. 2026-09-11

**At `ec62de5`.** The account holder chose **option (a)**: translate
`authorisedOmissions` from staged ids to saved ids at save.
- **The attachment identity lifecycle is unchanged.** Saved attachments do NOT
  keep their staged ids.
- **C-82 stays open**, and Unit 1b's corrected history stays, until the repeated
  Device B test passes.
- **The working tree carries an uncommitted Run → Debug scheme change** for the
  retest (Études Dev / Force Connected). It is **not** part of any commit. The
  account holder restores Release after the retest, and the scheme guard must
  pass before the unit closes.
- **Old queued test publishes are not touched.**
- Out of scope: C-3, C-69, C-75, C-76, C-80, C-81 and B-38.

The falsified prediction (K5) is recorded in `phase-5-c82-c73-acceptance.md` and
is not rewritten.

---

## 1. The mechanism, measured at `ec62de5`

- **Consent names the staged id.**
  - Both editors build the preflight candidate for a new attachment from its
    staged id (`candidate(forStaged: att.id …)`).
  - AESV builds it for an already-saved attachment from the saved id
    (`candidate(forPersisted: id …)`).
  - `pendingOmissions` → `authorisedOmissions` keeps whichever id was used.
- **Saving mints a new id.** `AttachmentStore.addAttachment` sets `UUID()` on
  the new object (`:297`). It has no way to receive the staged id.
- **The payload carries the raw state.** See `AddEditSessionView:2113` and
  `PostRecordDetailsView:1898`.
- **The flush matches saved ids.** `BackendShim:994` compares against the ids
  from `loadIncludedAttachments` (`:1276`), which reads Core Data.
- **Every other piece of attachment state is already moved to the new id at
  commit:**
  - privacy (`migratePrivacy`), selected PDF pages (`migratePages`), titles
    (`writeLocalTitle`) and the thumbnail;
  - PRDV keeps a `stagedToFinalID` map (`:732`), but only for the thumbnail;
  - AESV keeps no map.
- **`authorisedOmissions` is the one piece of state left in the staged id
  space.**

## 2. The fix

**One shared boundary:**
`ConnectedSharePreflight.persistedOmissions(_:stagedToFinal:) -> [UUID]?`
- An id found in the map becomes its saved id.
- An id not in the map is returned unchanged. This is what keeps an attachment
  saved before editing on its own id: it never enters the map.
- An empty list gives `nil`, as today.

**Each editor:**
- `commitStagedAttachments` returns its `[UUID: UUID]` map.
- **AESV builds the map inside its new-attachments-only loop**
  (`where existingAttachmentIDs.contains(att.id) == false`).
- PRDV returns the map it already builds.
- Each save keeps `let stagedToFinal = commitStagedAttachments(…)`.
- Each payload passes
  `ConnectedSharePreflight.persistedOmissions(authorisedOmissions, stagedToFinal: stagedToFinal)`.

**Permanent outcome logs.** Ids only, through `BackendLogger`'s public funnel,
all prefixed `Consent omission` so a single console filter finds them:
- `Consent omission • staged=<A> → saved=<B>`, and
  `Consent omission • saved=<P> unchanged`, at the translation;
- `Consent omission skipped at upload • postID=<X> • attachment=<B>`, at the
  flush.

**A pre-change stand-in is committed with the tests.**
- `persistedOmissions` returns the list unchanged, which is today's behaviour
  written as a function.
- **It has no caller**, so this commit changes no behaviour.
- It exists so the behavioural tests compile and fail for the right reason: they
  get A where they expect B.

## 3. The test boundary — `OmissionIdentityTests`

**The editors cannot be driven from XCTest**, because their staged attachments
are SwiftUI `@State`. So the evidence is split:
- **Each editor's wiring is pinned structurally**, on code only, with comments
  stripped.
- **The chain after the wiring runs on real components:**
  - the save path mints B (`AttachmentStore.addAttachment`);
  - the real queue writes its file, which is then read back and decoded;
  - a real flush runs against the local stack.

**The flush fixture is two included WAVs that cannot be converted.** If the flush
ever selects one for preparation, the publish fails. That makes "skipped"
observable, instead of inferring it from a missing log line.

| Test | Proves | Pre-change |
|---|---|---|
| `testStagedOmissionBecomesTheSavedIDAndAPersistedOneKeepsItsID` | A → B; P unchanged; empty → nil | **FAIL** (gets A) |
| `testQueueFileCarriesTheSavedIDAfterRedecode` | the queue file, decoded, carries B and not A | **FAIL** |
| `testUntranslatedStagedIDIsNotMatchedAtFlush` | **the device failure reproduced, and the control**: raw staged ids leave B selected, so conversion fails and no post row is written | **PASS** (before and after) |
| `testFlushSkipsTheSavedIDAndNeverPreparesIt` | the decoded file goes through a real `flushNow`: dequeued as success, post row exists, **0 objects, 0 refs** | **FAIL** (B converts and fails) |
| `testBothEditorsTranslateConsentThroughTheSharedHelper` | each save keeps its commit's map and calls the helper | **FAIL** (both editors) |
| `testNoPayloadConstructionBypassesTheHelper` | **the bypass guard**: across all app code, a payload's consent is `nil`, the helper, or an existing payload's | **FAIL** (exactly the two editor sites) |
| `testCommitsReturnTheStagedToSavedMap` | both commits return the map; AESV writes it only inside the new-attachments loop | **FAIL** (both) |
| `testEditorConsentStateHasNoOtherUse` | the raw state has exactly two uses per editor: the dialog's assignment and the helper's argument | **FAIL** (3 uses each) |

## 4. PREDICTION

**L1 — pre-change census:**
- **256 declared** (248 + 8).
- **Exactly 7 new tests fail** — every row above except the control.
- **Plus `SchemeConfigurationGuardTests.testRunActionBuildsRelease`**, because
  of the uncommitted Debug Run action. Its sibling
  `testRunActionPinsNoStoreKitConfiguration` passes.
- **8 failed, 248 passed.**

**L2 — after:**
- All 8 new tests pass.
- **256 declared, 255 passed, 1 failed** — only `testRunActionBuildsRelease`,
  until Release is restored.
- After the restore: **256 / 256**.

**L3 — warnings unchanged: Debug 177 / Release 165**, with an identical warning
set.

**L4 — device (Device B, Études Dev, Force Connected; no purchase).**
Console filter: `Consent omission`, then separately `Connected audio derivative`.

- **Path 1 — PRDV, the path that failed:**
  - Record, then in post-record details attach the **32-minute WAV**.
  - Private-eye off, Share on, title **`C82-R2 PRDV`**, Save, choose **Share
    Without It**.
  - **Predicted:**
    - one `staged=<A> → saved=<B>` line;
    - `Queue enqueue • postID=<X>`;
    - on each retry, `skipped at upload • postID=<X> • attachment=<B>`;
    - **no** `Connected audio derivative` line for this item.
- **Path 2 — AESV, new session:**
  - The same WAV in a new session, title **`C82-R2 AESV`**, Save, choose **Share
    Without It**.
  - **Predicted:** the same four observations, with its own A, B and X.
- **Path 3 — AESV, the attachment saved before editing:**
  - Reopen `C82-R2 AESV`, change nothing but the notes, Save.
  - **The dialog is predicted to appear again** for the now-saved WAV.
    Choose **Share Without It**.
  - **Predicted:**
    - a `saved=<B> unchanged` line naming **Path 2's B**;
    - `Queue update • postID=<X>` for Path 2's X;
    - the skip line still names B.
  - If the dialog does not appear, that is an observation to report, not a
    failure to explain away.
- **Queue file:** read back from the Études Dev container with read-only
  `devicectl copy from`. Both items' `authorisedOmissions` name B, never A.
- **Not required and not claimed:** a successful server post. `posts` INSERT is
  gated, so these items stay queued, which is expected.

**L5 — closure:**
- L4 is green;
- the account holder restores Release;
- the scheme guard passes;
- the census reads 256 / 256.

**Until then C-82 is open.**
