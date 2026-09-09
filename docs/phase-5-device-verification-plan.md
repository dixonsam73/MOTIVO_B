# COMBINED PHYSICAL-DEVICE VERIFICATION PLAN — C-50 + P5-M

**Written 2026-09-09. NOT RUN.** Covers the two outstanding device obligations in
one pass.

## 0. WHO RUNS THIS, AND WHY IT IS NOT ME

**I cannot execute any part of this.** The simulator tooling available to me
**cannot drive a physical iPhone**, and three of the checks are inherently
perceptual — hearing whether pitch shifts, hearing VoiceOver, and watching a
screen stay awake. **This must be run by the account holder**, and no part of it
should be recorded as verified on my say-so.

## 1. Device, build and configuration

| | |
|---|---|
| **Device** | **Device A — "SD beta burner", iPhone 16e, iOS 26.6.1**. Above the 26.4 floor |
| **Alternative** | Device B — "SD iPhone", iPhone 17 Pro, iOS 26.6.1 |
| **Configuration** | **Release** (`com.sdsongs.etudes`). Device A carries only Release |
| **Why Release** | it is the shipping artefact. **Neither C-50 nor P5-M involves StoreKit**, so Debug would also be valid — but the project's standing rule keeps the Run action on Release, and there is no reason to deviate |
| **Backend** | **irrelevant to every check below except remote audio (§4.3)**. No sign-in required for recording or local playback |

**A build from the current tree is required** — both changes are unreleased.
**Build numbers cannot identify a build** (everything reports `1.0 (131)`), so
install immediately before testing rather than trusting what is already there.

## 2. Fixtures — use what the device already has

**No manufactured test data, and no production mutation.**

**The C-50 checks PRODUCE the media the P5-M checks need**: §3 records a video and
an audio clip, and those become the local attachments played in §4. **Run C-50
first and the fixture problem disappears.**

If Device A already holds a session with playable audio and video attachments,
use those instead and skip nothing.

**Remote audio (§4.3) may not be reachable — see the note there.**

## 3. C-50 — recording versus Auto-Lock

**Setup: Settings → Display & Brightness → Auto-Lock → 30 seconds.** **Note the
previous value.**

| # | action | pass |
|---|---|---|
| 1 | Start a **video** recording. Do not touch the screen for **90 s** | screen stays awake; recording continues; clip saves normally |
| 2 | Close the recorder. Leave the app idle on an ordinary screen for **60 s** | **device auto-locks as normal** |
| 3 | Start a recording, **dismiss the recorder mid-recording** without stopping. Wait **60 s** | **device auto-locks as normal** |
| 4 | Repeat check 1 for **audio** | screen stays awake; recording continues |

**Then restore Auto-Lock to its previous value.**

**Checks 2 and 3 are the important half.** A stranded idle-timer flag flattens the
battery silently and would be worse than the defect being fixed.

## 4. P5-M — playback speed

### 4.1 Local audio (`AVAudioPlayer`)

Open the audio attachment from §3.4 in the attachment viewer.

| # | check |
|---|---|
| 1 | the speed control shows **1×** |
| 2 | all **five** rates appear and are selectable; the current one carries a checkmark |
| 3 | at **0.5×** and **2×** the tempo changes and **the pitch does not** — familiar pitched material, so a shift would be obvious |
| 4 | change rate **while playing** — takes effect without stopping playback |
| 5 | change rate **while paused**, then resume — resumes at the new rate, and **does not start playing when the rate is changed** |
| 6 | pause and resume at 0.75× — **rate is retained** |
| 7 | no glitch, dropout or distortion at 0.5× or 2× |

### 4.2 Video (`AVPlayer`)

| # | check |
|---|---|
| 8 | repeat 1-7 on the video attachment |
| 9 | video and audio stay in sync at 0.5× and 2× |

### 4.3 Remote audio (`AVPlayer`) — **LIKELY NOT REACHABLE, AND THAT IS EXPECTED**

**Attempt only if a Connected audio attachment is already visible.** It probably
is not: `posts` SELECT is gated by enforcement, and production holds **one
membership row, Sandbox only**, so `connected_member()` is false for every
identity. **That is the same blockage as Phase 4 conditions 2 and 8, and it is not
a P5-M defect.**

**If unreachable, record it as such.** Do **not** weaken enforcement, manufacture
membership, or use production content to get around it. The remote-audio path
then stays covered by structural tests only, and **must be reported that way**.

### 4.4 Session semantics

| # | check |
|---|---|
| 10 | set **0.75×**, page to another playable attachment — **rate is still 0.75×** |
| 11 | page back — still 0.75×; playback position follows the existing reset behaviour, which is unchanged |
| 12 | close the viewer and reopen it — **rate is back to 1×** |
| 13 | let a clip play to the end, then replay — **rate is still the chosen one** |

## 5. VoiceOver — the new control only

**Settings → Accessibility → VoiceOver on.**

| # | check |
|---|---|
| 14 | focusing the control announces **"Playback speed"** and the current value, e.g. **"0.75 times"** |
| 15 | the hint **"Choose a playback speed"** is offered |
| 16 | opening the menu, **each of the five rates is individually selectable** — no gesture precision, no counting taps |

**DO NOT extend this into a general transport-accessibility audit.** The
surrounding transport buttons are unlabelled — that is **C-67**, filed into
**P5-N**, and deliberately out of scope here.

## 6. Reporting

Promote **C-50** and **P5-M** to device-verified **only if their own checks pass**
— they are independent, so one may pass while the other does not.

**Report any failure separately, with the check number**, rather than as an
overall verdict. **A partial pass is a partial pass.**

**§4.3 being unreachable is NOT a failure** — it is a recorded coverage limit with
a known, separately-owned cause.
