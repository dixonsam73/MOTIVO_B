# P5-N TIER 1 — PREDICTION, COMMITTED BEFORE PRODUCT MUTATION

**Unit:** P5-N Tier 1 — C-11 and C-67 only. Approved scope; **Tier 2's ~49
candidates are NOT touched** and remain an unverified candidate inventory, never
a defect count and never an accessibility-quality metric.
**Inspected at:** `49ca610`, 2026-09-09.
**Out of scope, explicitly:** Dynamic Type, colour contrast, focus order, rotor,
whole-app VoiceOver certification, any conformance claim.
No backend, production, ASC, enforcement, device or age-state mutation.

---

## 1. Labels are DERIVED from the controls, not invented

### C-11 — `SessionDetailView` action row

Read at HEAD (`:1644`–`:1710`). Three controls in one `HStack`:

| Control | Site | State today |
|---|---|---|
| heart / favourite — `FeedInteractionStore.toggleSaved`, `isSavedLocal` | `:1646` | `.accessibilityLabel("Open comments")` — **the mislabel** |
| comment — `isCommentsPresented` | `:1672` | `.accessibilityLabel("Open comments")` — **correct, preserved verbatim** |
| share — `isShareSheetPresented`, owner-only | `:1698` | **no label at all** |

**TWO DEVIATIONS FROM THE LITERAL STRINGS PROPOSED, BOTH FOR TRUTHFULNESS, BOTH
FLAGGED RATHER THAN SLIPPED IN.**

1. **`SessionDetailView` renders Thoughts as well as sessions** — `session.isThought`
   is consulted at `:745`, `:757`, `:864` and elsewhere. So *"Favourite session"*
   would be false for a Thought. The favourite control uses the object-neutral
   pair **`"Add to favourites"` / `"Remove from favourites"`**, which carries the
   state semantics asked for and is true of both content types. It also matches
   the product's own words — the hint says *"Added to Favourites"* (`:1606`).
2. **Share becomes state-dependent for the same reason:**
   `session.isThought ? "Share thought" : "Share session"`.

**A consistency question is REPORTED, NOT ACTED ON.** `AttachmentViewerView:916`
already uses a different pattern for a different object — *"Favourite
attachment" / "Unfavourite attachment"*. That control is already labelled, so it
is outside C-67 (absent labels) and is not relabelled here.

### C-67 — `AttachmentViewerView` transport

Read at HEAD. **`VideoPage`** (`:1784`) and **`AudioPage`** (`:2694`) each carry
their own `mediaControlButton` helper (`:2360`, `:2915`).

| Control | Video | Audio | Derived label |
|---|---|---|---|
| mute toggle | `:1997` | `:2801` | `isMuted ? "Unmute" : "Mute"` |
| back 10s | `:2015` | `:2813` | `"Skip back 10 seconds"` |
| play / pause | `:2025` | `:2819` | video: `"Pause"`; audio: `isPlaybackPlaying ? "Pause" : "Play"` |
| forward 10s | `:2038` | `:2859` | `"Skip forward 10 seconds"` |
| scrub `Slider` | `:1956` | `:2768` | label `"Playback position"`, value = elapsed of duration |

**Two findings from reading that change what gets labelled:**

- **The video row's inline play/pause is PAUSE-ONLY.** It renders only when
  `isPlayingState`; otherwise the slot is `Color.clear` (`:2033`) and play is the
  big centre overlay button — **which already carries
  `.accessibilityLabel("Play video")` at `:2108`**. That one is **not touched**,
  and P4 below asserts it survives.
- **Neither viewer displays elapsed/duration as text and the file has no time
  formatter**, so the slider's value string must be built. Both sliders bind a
  `TimeInterval` against a duration, which is exactly the data needed.

**`routePickerControl()` is an `AVRoutePickerView`** and carries the system's own
accessibility. Untouched.

**`PlaybackSpeedMenu` is untouched.** It is device/VoiceOver verified already.

---

## 2. PREDICTION

**P1 — the mislabel is gone.** No control in `SessionDetailView`'s action row
announces an action it does not perform. The favourite control's label changes
with `isSavedLocal`.

**P2 — adjacent actionable controls in that row do NOT share a label.** Asserted
directly, as an absence-of-defect check over the row's labels, not as a spot
check on one string. This is the assertion the structural finder could never
make, and it is the one that would have caught C-11 originally.

**P3 — the comments button keeps `"Open comments"` byte-for-byte**, and the
share button gains a label.

**P4 — every C-67 control named above carries a label; the already-labelled
centre play button and the speed menu are unchanged.** A regression check pins
`"Play video"` and the `PlaybackRate` accessibility strings.

**P5 — both scrub sliders carry a label AND a value.** The value is derived from
the live position and duration, e.g. *"1 minute 23 seconds of 4 minutes 10
seconds"*. **Neither is labelled "Slider".** When duration is unknown or zero the
value degrades to the elapsed time alone rather than asserting a false total.

**P6 — the value formatter is a PURE type in its own file**, tested directly —
the `PlaybackRate.swift` / `DirectorySyncFailure.swift` precedent. The app has no
localisation catalogue (no `.lproj`, no `.xcstrings`), so plain English strings
are consistent with every other string in the product.

**P7 — no unrelated UI change.** No layout, no colour, no control added or
removed, no transport redesign. The diff is labels, values, and one new pure
file.

**P8 — evidence.** Structural control scoped to the two files, **proven
non-vacuous by failing against pre-fix `49ca610`**, comment-stripped (`U5c-34`).
Debug and Release clean. **Warning delta measured** against `49ca610` in an
isolated worktree. Full suite from the **structured** census, never console
`passed` counts.

### What this unit CANNOT establish

**No claim of natural VoiceOver behaviour.** Source and tests prove a label
*exists* and *changes with state*. They cannot prove it is announced sensibly,
in a sensible order, or that the row reads well aloud. On a clean
implementation this unit reports **implementation complete; device VoiceOver
verification outstanding**, with a minimal physical checklist — never "P5-N
passed".
