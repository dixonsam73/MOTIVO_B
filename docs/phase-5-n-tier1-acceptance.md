# P5-N TIER 1 — ACCEPTANCE. COMPLETE AND DEVICE/VOICEOVER-VERIFIED.

**DEVICE PASS GREEN 2026-09-09.** All five checks confirmed on hardware with
VoiceOver: the favourites action, Share session/thought and Open comments are
distinguished; video and audio transport controls and both scrub sliders
announce sensible labels and values; the playback-speed accessibility is
unchanged; no adjacent control tested announces the wrong action. **§4's
limitation is now DISCHARGED rather than standing** — it is preserved below as
the record of what source evidence could and could not establish.

**Prediction:** `docs/phase-5-n-tier1-prediction.md`, committed at `cd3f0a3`
**before** any product change. **Scope held to C-11 + C-67.**
**Tier 2's ~49 candidates were not touched, are not defects, and are not a
quality metric.**

---

## 1. Result against the committed prediction

| | Prediction | Outcome |
|---|---|---|
| **P1** | mislabel gone; favourite label follows `isSavedLocal` | **MET** |
| **P2** | adjacent actionable controls do not share a label | **MET** — `testAdjacentActionableControlsDoNotShareALabel` |
| **P3** | comments label byte-identical; share labelled | **MET** |
| **P4** | C-67 controls labelled; centre play and speed menu unchanged | **MET** — asserted per page, plus two regression checks |
| **P5** | both sliders carry label AND value; neither says "Slider" | **MET** |
| **P6** | value formatter is a pure, directly-tested type | **MET** — `PlaybackAccessibility` |
| **P7** | no unrelated UI change | **MET** — see §3 |
| **P8** | non-vacuous control, clean builds, measured warnings, structured census | **MET** |

**Builds:** Debug and Release both `BUILD SUCCEEDED`.
**Warning delta: ZERO** — 187 Debug / 175 Release, identical to the figure
measured at C-70(a)'s closure (`2a8e361`); everything between that commit and
the start of this unit is documentation-only, verified by `git diff --stat`
excluding `docs/`.
**Suite: 147 of 147 passed**, structured census. Console `passed` counts were
not used for any claim.

## 2. Non-vacuity — BOTH halves were made to fail, and the second attempt found a real weakness in my own test

**C-11.** Restoring `.accessibilityLabel("Open comments")` on the favourite
control failed `testAdjacentActionableControlsDoNotShareALabel` and
`testFavouriteLabelIsStateDerived`.

**C-67 — and this is the part worth keeping.** Deleting the video row's
*"Skip forward 10 seconds"* label **passed** the first version of the transport
test. It searched the whole file, and the audio row carries the identical
string, so one of two duplicates satisfied it. **That is presence-of-the-fix
again — the exact defect P5-M was caught by.** The assertion is now scoped to
the `VideoPage` and `AudioPage` regions separately, and the same deletion now
fails it.

**A second self-inflicted error, recorded because it repeats a pattern.** The
first label extractor matched only bare string literals and therefore **failed
against correct code**: both new labels are state ternaries, so the row yielded
one label and the uniqueness check had nothing to compare. An extractor blind to
state-dependent labels is blind to precisely the controls this unit added.

## 3. Every product line changed — 15 additions, 1 deletion

```
- .accessibilityLabel("Open comments")                                  ← the C-11 mislabel
+ .accessibilityLabel(isSavedLocal ? "Remove from favourites" : "Add to favourites")
+ .accessibilityLabel(session.isThought ? "Share thought" : "Share session")
+ 12 lines in AttachmentViewerView: 2 slider label/value pairs and 8 transport labels
```

**No layout, colour, control, gesture or transport change.** The diff is labels
and values only, plus one new pure file.

**Two deviations from the literal strings proposed, both flagged in the
prediction and both for truthfulness:** `SessionDetailView` renders Thoughts as
well as sessions, so the favourite pair is object-neutral and share is
state-dependent on `session.isThought`.

## 4. WHAT THIS DOES NOT ESTABLISH

**No claim of natural VoiceOver behaviour.** Source and tests prove that a label
exists, is derived from live state, and is distinct from its neighbours. They
cannot prove any of it is *announced* well, in a sensible order, or that a
slider's value is spoken as intended. **P5-N Tier 1 is therefore
implementation-complete with device VoiceOver verification outstanding, and must
not be recorded as passed.**

## 5. The device checklist to close it — smallest sufficient

Device A or B, **Release**, VoiceOver on (Settings → Accessibility → VoiceOver,
or triple-click side button). **No account state, purchase or destructive action
is involved; nothing here mutates production.**

**C-11 — Session Detail, one session and one Thought:**
1. Swipe to the **heart**. It announces **"Add to favourites"** (or "Remove from
   favourites" if already favourited) — **not** "Open comments".
2. Double-tap it. The announcement **flips** to the other string.
3. Swipe right once. The next control announces **"Open comments"**, and it is
   the speech-bubble icon.
4. Swipe right again on a session you own. It announces **"Share session"** — and
   **"Share thought"** on a Thought.
5. **No two controls in that row announce the same thing.**

**C-67 — Attachment viewer, one video and one audio attachment:**
6. Swipe to the scrub slider. It announces **"Playback position"** and a value
   like **"1 minute 23 seconds of 4 minutes 10 seconds"** — never "Slider".
7. Swipe up/down to adjust it; the spoken value **changes** and playback seeks.
8. Transport buttons announce **"Mute"**/**"Unmute"**, **"Skip back 10 seconds"**,
   **"Skip forward 10 seconds"**.
9. Audio: the play button announces **"Play"**, and after double-tapping it
   announces **"Pause"**.
10. Video: while playing, the inline button announces **"Pause"**; when stopped,
    the large centre button announces **"Play video"**.
11. **Regression:** the speed control still announces its label and its rate
    (e.g. "0.75 times"), unchanged from its P5-M device pass.

**Report any step where the announcement is absent, wrong, or duplicated.**
Steps 5, 6 and 11 are the ones that would falsify this unit.
