# UNIT 1b — CONSENT PRESENTATION. COMPLETE AND DEVICE-ACCEPTED.

> **DEVICE PASS GREEN 2026-09-10, BOTH HALVES.**
> **Consent UX:** dialog exactly as predicted; **Cancel** kept the member in the
> editor and saved nothing; **Share Without It** saved and published with the
> attachment omitted; the omitted attachment's **private-eye state was
> unchanged**; and the **control** — an ordinary photo — produced **no dialog**,
> so the dialog is not firing indiscriminately.
> **Audio derivative:** a 204-second Float32 WAV converts to **6,644,508 B in
> 1,884 ms** — ~113× realtime, essentially matching the Mac, so **no progress UI
> is needed and that is now measured rather than assumed**.
> **The pass also found three defects** — C-77, C-79 and, by inspection, C-76 —
> all recorded.

> **COMPLETED 2026-09-10.** §4's outstanding call site is now done:
> `PostRecordDetailsView` runs the same preflight through the same boundary.
> **P7 is fully met.** Re-verified clean: Debug 187 / Release 175 on clean
> derived data — **warning delta ZERO** — and **191 of 191** tests pass by
> structured census.

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
| **P7** | both entry points consistent | **MET** — see §4 |
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

## 4. `PostRecordDetailsView` — NOW DONE, and it reuses the boundary

Its Save button runs `attemptSaveWithConnectedPreflight()`, asks the **same**
`ConnectedSharePreflight`, presents through the **same**
`ConnectedShareConsentState`, and carries the authorised set into its own
payload. **No second consent model and no second copy of the rule.** The
original save behaviour is preserved verbatim in `commitSaveAndDismiss()`, now
reached from one place. Cancel behaves identically: back to the editor, nothing
saved, nothing queued.

**Shared rather than duplicated:** `ConnectedSharePreflight.candidate(forStaged:…)`
builds the candidate for both sites, so the two views ask the same question of
the same data.

### A third defect the process caught — MY OWN TEST WAS VACUOUS

`ConsentAtBothPublishSitesTests` first asserted the file merely CONTAINED
`attemptSaveWithConnectedPreflight()` — which matches the **function's own
declaration**. Reverting the Save button's gate still passed. **Presence of the
fix again**, the exact trap P5-M recorded. It now pins the **button's action**,
and reverting the gate fails it — verified by doing so.

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
