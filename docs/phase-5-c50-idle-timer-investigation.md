# C-50 — MIXED AUTO-LOCK EVIDENCE: SOURCE INVESTIGATION

**2026-09-09. NO CODE CHANGED.** C-50 stays *implementation complete; device
verification mixed/incomplete*. P5-M playback QA is held.

## 1. COMPLETE IDLE-TIMER OWNERSHIP MAP

**There are THREE mechanisms that can keep an iPhone awake here, and only the
first is ours.**

### Mechanism 1 — `UIApplication.shared.isIdleTimerDisabled`

**Exactly ONE writer exists in the entire app**, verified by sweep:
`RecordingIdleTimerGuard.apply()`. **No pre-existing code anywhere touches this
property** — C-50 introduced the only use.

Four call sites, all as designed:

| site | call |
|---|---|
| `AudioRecorderView:201` | `setHolding(newState == .recording, owner: "audio-recorder")` |
| `AudioRecorderView:191` | `release("audio-recorder")` — `onDisappear` |
| `VideoRecorderView:238` | `setHolding(newState == .recording, owner: "video-recorder")` |
| `VideoRecorderView:243` | `release("video-recorder")` — `onDisappear` |

**Scope: app-foreground only.** iOS ignores it when the app is not active — which
is exactly why *"outside Études the device locked normally"* is **consistent with
the flag being stuck true**, not evidence against it.

### Mechanism 2 — `AVPlayer.preventsDisplaySleepDuringVideoPlayback`

**Read from the installed SDK header: "Default is YES on iOS."** The app **never
sets this property anywhere** — verified absent — so **every** `AVPlayer` playing
**video** prevents display sleep, entirely independently of Mechanism 1.

The header adds the warning that matters here:

> *"Other apps or frameworks within your app may still be preventing display
> sleep for various reasons."*

`AVPlayer` instances outside the attachment viewer:

| site | purpose |
|---|---|
| `VideoRecorderView:1253`, `:1403` | **the recorder's review player** |
| `MediaTrimView:854` | trim preview |
| `PostRecordDetailsView+Attachments:1309`, `AddEditSessionView+Attachments:1447` | `AVPlayerViewController` |

### Mechanism 3 — a running `AVCaptureSession`

**NOT ESTABLISHED.** I found **no** statement in the AVFoundation headers that a
running capture session disables the idle timer. **It is listed only so it is not
silently assumed, and it must not be asserted without evidence.**

## 2. DOES THE PRACTICE TIMER EXPLAIN IT? **NO DIRECT MECHANISM.**

`PracticeTimerView` **never touches the idle timer**, and its only two `AVPlayer`
references — `:406`, `:407` — are **commented out**. So a running or paused timer
has **no code-level route** to suppressing Auto-Lock.

**But the correlation is not meaningless, because timer state changes what is
MOUNTED**, and the two recorders are presented completely differently:

| recorder | presentation |
|---|---|
| **video** | `.fullScreenCover(isPresented: $showVideoRecorder)` — modal |
| **audio** | **rendered INLINE** in the timer's `VStack`: `if showAudioRecorder { audioRecorderPanel }` |

**So "timer running/paused" and "timer never started" are different view trees**,
with different lifetimes for anything that holds a lock. **That is a plausible
INDIRECT link and it is not a mechanism.** It should not be written down as a
cause.

## 3. CAN THE NEW GUARD STRAND A HOLDER? **YES — IN EXACTLY ONE WAY.**

Ruled out by construction:
- **double release** — `release` is idempotent, guarded by `holders.remove(owner) != nil`; it cannot drive a count negative;
- **repeated hold** — holders are a **set**, so one release clears it;
- **cross-clearing** — separate owner tokens;
- **off-main mutation** — both `state = .recording` sites are inside `DispatchQueue.main.async` (`:1802`, `:1920`), and the `.idle` sites are on main, so `.onChange` delivery is sound.

**The one surviving path: a recorder view leaves the hierarchy while
`state == .recording` AND its `onDisappear` does not run.** Then `.onChange`
never sees the transition (the view is gone) and the release never happens. The
holder then persists until that view mounts and transitions again — **which is
exactly the shape of "it started working later after more recorder use."**

**This is a hypothesis. It is not demonstrated, and no code should change on it.**

## 4. DOES PRE-EXISTING BEHAVIOUR EXPLAIN THE INITIAL FAILURES? **YES — A STRONG CANDIDATE.**

**`VideoRecorderController.onDisappear()` never pauses or releases the review
player.** Verified — it does only:

```
stopTimer(); removeNotifications()
sessionQueue.async { stopCaptureSession(); cleanupRecordingFile() }
```

The `player?.pause()` / `player = nil` calls live elsewhere (`:1358`, `:1412`,
`:1425-26`) and are **not** on the disappear path.

**So a review player left PLAYING when the recorder is dismissed keeps preventing
display sleep by documented default — app-scoped, foreground-only, and
indistinguishable from a stuck flag without a discriminator. This predates C-50
entirely.**

## 5. WHY BOTH CANDIDATES FIT — AND THE ONE THING THAT SEPARATES THEM

Both produce the same fingerprint: no Auto-Lock anywhere inside Études, normal
Auto-Lock outside it, and clearing later after further recorder use.

**They differ in ONE observable property:**

- **`isIdleTimerDisabled` SURVIVES backgrounding** — it is an application
  property and is simply ignored while inactive, then applies again on return.
- **A playing `AVPlayer` does NOT survive backgrounding** — video playback stops
  when the app leaves the foreground, so the suppression ends.

## 6. THE MINIMUM NEXT DEVICE CHECKS — THREE, NO NEW BUILD

**Do NOT repeat the C-50 suite.** Auto-Lock 30 s throughout.

**D1 — is recording involved at all? (baseline)**
Fresh launch. **Record nothing.** Start the timer, leave it running, sit idle 60 s.
- **Locks** → recording is implicated; continue.
- **Does not lock** → **neither C-50 nor the recorders are the cause**, and this is a pre-existing timer-screen issue. Stop and report.

**D2 — reproduce, minimally**
Record video ~10 s (90 s is not needed to strand a holder), save, dismiss, sit on
the timer screen idle 60 s.
- **Does not lock** → reproduced; go to D3.
- **Locks** → not reproducible on a short take; report, and note the first failure may need the longer recording.

**D3 — THE DISCRIMINATOR. Immediately after a D2 failure, do NOT open the recorder.**
Background Études (Home / app switcher), wait 5 s, foreground it, sit idle 60 s.
- **Now locks** → **Mechanism 2**: a leftover *playing* review `AVPlayer`, paused by backgrounding. **Pre-existing, not C-50.**
- **Still does not lock** → **Mechanism 1**: the flag is stuck, i.e. **the C-50 guard stranded a holder.**

**D3 is the whole investigation in one action, and it needs no build, no code
change and no new fixture.**

**If it helps, one optional extra:** while auto-lock is failing, note whether the
status-bar **camera privacy indicator** is showing. Its presence would say the
capture session is still running — relevant to Mechanism 3, which is otherwise
unestablished.

## 7. What is NOT concluded

- **The newly recorded video attachment is not treated as causal.** It was present, and that is all that is known.
- **Mechanism 3 is not asserted.**
- **No fix is proposed**, and none should be until D3 names the mechanism.

---

# 8. DEVICE RESULTS — 2026-09-09. NOT REPRODUCED.

| check | result |
|---|---|
| **D1** baseline, no recording, timer running, idle | **GREEN** — locked after 30 s |
| **D2** record, save, dismiss, idle — timer not started | **GREEN** — locked after 30 s |
| **D2** repeated in the same session with the **timer running** | **GREEN** — locked after 30 s |
| **D3** the discriminator | **NOT REACHED** — no failure to discriminate |

## 8.1 What this does and does not establish

**ESTABLISHED, and it is the half that matters most:** recording holds the screen
awake (video 90 s, audio 90 s), backgrounding during an active recording restores
normal Auto-Lock, and **Auto-Lock now returns correctly after recording — three
times, including in the timer-running state that originally failed.**

**NOT ESTABLISHED:** what caused the original suppression. **A non-reproduction is
not a refutation.** The first session's observations were specific and internally
consistent — suppressed inside Études across three screens, normal outside it,
clearing later with no new build — and that is a real fingerprint, not noise.

## 8.2 THE UNCONTROLLED VARIABLE, NAMED

**The original failure followed a 90-SECOND video take. D2 used roughly ten
seconds**, because I said duration should not matter for stranding a holder.

**That judgement is unproven.** Both candidate mechanisms could plausibly be
duration-sensitive: a longer take means a longer writer-finish, more straggler
sample buffers, and — for the review-player hypothesis — **a clip long enough to
still be playing across several 30-second observation windows**.

**So the re-test differed from the original in exactly the dimension most likely
to matter, and that is my error in specifying it, not the tester's.**

## 8.3 RECOMMENDATION — one bounded re-test, then a stopping rule

**ONE further check, and then stop chasing it.**

**D4 — replicate the original conditions exactly.** Fresh launch (force-quit
first). **Record video for a full 90 seconds**, save, dismiss, then sit on the
timer screen **with the timer running** and wait 60 s.

- **Locks** → the original observation does not reproduce under its own
  conditions. **Close C-50.2 as *Unverified — unreproduced*** under the stopping
  rule below.
- **Does not lock** → run **D3** immediately: background 5 s, foreground, idle 60 s.
  That names the mechanism, and only then does any fix get designed.

**THE STOPPING RULE, agreed BEFORE the attempt as this project requires:** if D4
does not reproduce, **no further hypotheses are manufactured and no speculative
fix is written.** C-50.2 is recorded as unreproduced, with a **named reopening
condition**: any future observation of Auto-Lock failing inside Études while
succeeding outside it.

**This is deliberately C-38's pattern** — a single unreproduced observation, held
open as *Unverified* rather than either forced to a conclusion or quietly
forgotten.

---

# 9. D4 — GREEN. C-50 CLOSED UNDER THE STOPPING RULE. 2026-09-09

**D4 replicated the original conditions exactly** — force-quit, fresh launch,
**full 90-second video take**, saved, dismissed, timer **running**, idle.

**RESULT: GREEN. The device locked.**

So the original observation **did not reproduce under its own conditions**, and
the uncontrolled variable I had named — 90 s versus 10 s — **is eliminated as the
explanation.**

## 9.1 The stopping rule is applied, not revisited

It was agreed **before** the attempt: no further hypotheses are manufactured and
no speculative fix is written. **C-50.2 is closed as unreproduced.**

**The two candidate mechanisms stay recorded** — a stranded guard holder, and the
review-`AVPlayer` teardown gap (**C-68**) — **as documented hypotheses, not as
conclusions**, and neither is being fixed on the strength of an observation that
will not reproduce.

**REOPENING CONDITION, NAMED:** any future observation of Auto-Lock failing inside
Études while succeeding outside it. That fingerprint is specific enough to
recognise, which is what makes the stopping rule safe rather than a shrug.

## 9.2 C-50 final status

**RESOLVED — implementation complete and device-verified**, on four checks plus
three re-tests of the restoration half.

**The unexplained early observation is carried, not erased.** It was real, it was
internally consistent, and it is written down. **Recording it honestly is the
difference between a closed finding and a forgotten one.**

## 9.3 A free observation worth keeping

D4 also showed that **after lock and unlock the timer screen returned with the
correct elapsed time and the timer still running.** Not a scored check and not
part of C-50 — but it is positive evidence about practice-timer continuity across
a lock cycle, obtained at no cost, and this project's habit is to write those down
rather than let them evaporate.

## 9.4 What is now unblocked

**P5-M's playback-speed device QA** — §4 and §5 of
`docs/phase-5-device-verification-plan.md` — was held pending this disposition and
is now clear to run.
