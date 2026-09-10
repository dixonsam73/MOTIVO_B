# UNIT 1b — CONSENT PRESENTATION. IMPLEMENTATION COMPLETE; DEVICE QA OUTSTANDING.

Prediction: `docs/phase-5-unit1b-prediction.md`, committed before mutation.
**Unit 1a is untouched.**

## 1. Result

| | Prediction | Outcome |
|---|---|---|
| **P1** | preflight-clear publish unchanged | **MET** — `attemptSaveWithConnectedPreflight` calls `save()` directly |
| **P2** | one restrained dialog, plural-aware | **MET** |
| **P3** | cause-agnostic presentation | **MET** — the copy names no reason |
| **P4** | Cancel queues nothing | **MET** — and saves nothing; see §3 |
| **P5** | Share Without It carries the authorised set | **MET** |
| **P6** | retry never re-prompts | **MET** — consent lives in the payload |
| **P7** | both entry points consistent | **PARTIAL — see §4** |
| **P8** | no new modifier on that body | **MET** — the existing alert was generalised |

**Debug and Release clean on CLEAN derived data — 187 / 175, warning delta
ZERO. 187 of 187 tests pass**, structured census.

## 2. Two real defects the process caught

**(a) The custom decoder would have silently dropped the consent.**
`authorisedOmissions` carries a default, so `init(from:)` compiles happily
without touching it — and the member's consent would have been **lost on every
relaunch**, re-prompting them or omitting nothing. Fixed with an explicit
`decodeIfPresent`, and `testAuthorisedOmissionsSurvivesEncodeDecode` **fails when
that line is removed** — proven, not assumed.

**(b) `AttachmentStore.fileSize` is `#if DEBUG` only.** Debug built clean and
**Release failed** — exactly why the project rule says always verify Release.
Replaced with `localFileSizeBytes`, which is already shipping code, rather than
widening a Debug-only helper.

## 3. A product question I resolved, and how to change it

The instruction said *"Cancel → no publish payload is queued"* without saying
whether the local session still saves. **Cancel returns the member to the editor
and saves nothing**: the dialog is raised **by pressing Save**, so "go back" is
the least surprising meaning, and the alternative would leave a session saved
locally with Share ON while nothing was ever queued — the C-60/C-61 class of
mismatch. **Every edit is kept.** If you want "save locally but don't share"
instead, it is a one-line change.

## 4. WHAT IS NOT DONE — `PostRecordDetailsView`

**The second publish call site does NOT yet run the preflight.** Its
`saveToCoreData(visibility:)` (`:1755`) publishes at `:1840` unchanged, so an
oversized explicitly-shared attachment created through that path still reaches
the queue without consent.

**Stated rather than glossed:** P7 is only half met. That view needs the same
decision, and it has its own body and its own alert surface. **It is small but it
is not done**, and Unit 1b should not be recorded as complete until it is.

## 5. Device QA — the smallest that closes both open items

Device B, **Études Dev (Debug)** is sufficient for (1); (2) needs no Connected
entitlement either, because the derivative is built before upload. **No account
state, no purchase, nothing destructive, no production contact.**

**(1) The consent flow**
1. Create a session, attach a **video longer than ~90 seconds** (Études' own
   recorder crosses 50 MB at ~83 s).
2. **Turn the private-eye OFF** for it, and turn Share ON.
3. Press **Save**. → *"Attachment too large to share"* appears with **Cancel**
   and **Share Without It**.
4. **Cancel** → you stay in the editor, nothing saves. Confirm the session is
   not in the Journal.
5. Press Save again → **Share Without It** → the session saves and publishes.
6. **Control that proves it is not firing at random:** attach an **ordinary
   photo**, private-eye OFF, Save → **no dialog at all**.
7. **The private-eye state of the omitted video is UNCHANGED** — reopen the
   session and confirm it is still marked shareable.

**(2) The audio derivative timing**
8. Attach a **5–10 minute WAV or AIFF** (a reference mix or bounce), private-eye
   **OFF**, Share ON, Save.
9. With the Xcode console attached, find the line
   `Connected audio derivative • <seconds>s • <bytes>B • <ms>ms`.
10. **Report those three numbers.** Host measurement for comparison: 5 min →
    2.59 s, 10 min → 6.92 s.

**Step 9 is the one that closes the outstanding device-performance question.**
Until it is read, the derivative is **not** device-accepted.
