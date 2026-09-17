# USB audio, video and drone — device QA acceptance

**17 September 2026. QA7 and QA8 ACCEPTED on Samuel's report.** Physical-device QA performed
by Samuel; recorded here from his report, not observed by any agent.

## Hardware

**Teenage Engineering CM-15**, USB-C, class-compliant microphone.

**Deliberately not recorded:** the exact iPhone model, the iOS version, and the Bluetooth
headset model. **None was supplied, and none is inferred.**

## The six checks, and their results

| # | Check | Result |
|---|---|---|
| 1 | Connect the CM-15 **before** opening the recorder; record, save, replay; confirm USB input | **GREEN** |
| 2 | Connect **with the recorder already open**; record without restarting | **GREEN** |
| 3 | **First video after app launch** with USB connected; clap near the beginning and end; saved playback has no missing initial sound and stays in A/V sync | **GREEN** |
| 4 | **Unplug and reconnect during recording** | **GREEN** — see below |
| 5 | **Bluetooth output alongside USB**; verify the intended input and output | **GREEN** |
| 6 | **Drone** note, octave and start/stop with USB; unplug and reconnect; pitch recovery | **GREEN** — see below |

Samuel reported checks 1–4 as *"All green"* and 5–6 as *"Both Green"*.

### Check 4 — route change during a take, both directions

**Disconnecting the CM-15 mid-recording continued the take seamlessly on the phone
microphone. Reconnecting it during the SAME recording switched back to USB, also
seamlessly.** Both directions were observed within one take.

### Check 6 — drone recovery is AUTOMATIC, as observed

**The drone stopped briefly when the CM-15 was unplugged, then restarted at the correct
pitch within a second or so.** Recorded exactly as observed: **recovery was automatic, and no
manual restart was reported or required.**

**One thing this does NOT settle, flagged rather than resolved.** C-96's implementation note
says a route change *"stops the drone for an explicit restart"*. The observed behaviour reads
as automatic recovery instead. **This record does not assert which is right, does not infer a
mechanism, and proposes no change** — it notes that the relationship between the implemented
design and the observed recovery is unestablished, for whoever next touches that code.

## Channel selection — NOT tested, and the earlier mention is withdrawn

Channel selection was raised when the checklist was first described and then **corrected:
Études has no channel selector**, so nothing about channel selection was tested and none is
claimed.

## What this accepts, and what it does not

**Accepted:** **QA7 (USB audio / video) and QA8 (drone)**. **QA1–QA6 were already accepted**
and are unchanged by this record.

**NOT accepted, claimed or closed here:**

- **Phase 5 gates, the legal/DPIA review, and B-40's status** — untouched. Nothing in device
  QA bears on them.
- **Unrelated residual QA** of any kind.
- **C-97 part (2)** — the absent capture runtime-error, interruption and media-services-reset
  observers, and the missing-audio watchdog. Check 3 is **first physical evidence on part (1)
  only**, which is what that row anticipated.
- **C-96's separate defensive correction** — the equality guard on
  `PracticeTimerView`'s `.onReceive(droneEngine.$isRunning)` — which remains **NOT
  implemented**. No loop has been observed, and this record changes nothing about it.
- **The three Lists device scenarios** still outstanding: Ensemble delivery, deletion
  isolation, and re-adoption after local deletion.

## Evidence grade

**User-reported device observation.** No agent operated a device, no capture, log or
measurement artefact accompanies it, and no build or test was run to produce this record.
Pitch reported correct; assessment method not supplied.
