# C-97 R1 — route observability. Bounded finish, evidence

**21 September 2026. Claude.** Scope: the **NEW BOUNDED FINISH** at the head of
`docs/recorder-reliability-codex-review-2026-09-21.md`.

## STATUS

**CODEX FINAL LOCAL ACCEPTANCE GRANTED, 21 September 2026.** Codex independently read the final
code and tests, matched all three hashes, parsed the retained original `.xcresult`
(1070 passed / 0 failed / 6 standing skips / 1076 total), compared test IDs against F3 —
**16 added, none removed, no existing result changed** — confirmed the Release build and that
the normalised warning sets are identical, and confirmed controls I and J fail exactly what is
claimed. **No code findings.** Recorded at the head of
`docs/recorder-reliability-codex-review-2026-09-21.md`.

**NOT COMMITTED. Holding for Samuel's commit instruction.**

**No commit, push, server, device, purchase or reset action. No new device QA campaign, no
scope expansion.** `HEAD` = `b479487` = `origin/feature/solo-connected`.

---

## 1. The seven corrections, each applied

| # | Required | Done |
|---|---|---|
| 1 | Classify and render from ONE capture | `CapturedRoute` reads `inputs`, `currentInputs` and `preferredInputID` once; classification and rendering both use it |
| 2 | Changing-getter test making the defect observable | `testAChangingRouteCannotProduceAContradictoryRecord`, plus the mismatch direction and a read-count test |
| 3 | Not called an atomic snapshot | The doc comment says the properties are read one after another and the route can move between them — it **bounds** the inconsistency, it does not remove it |
| 4 | Trim development-history comments | Both files reduced to contract comments; the history lives in this document and the checkpoint |
| 5 | Fix the early-return explanation | Corrected: the old `return` would have skipped the **USB branch's** observation, not the no-input path, which fell through to the end. Test renamed accordingly |
| 6 | Correct the OS-log overclaim | Withdrawn. The claim is now bounded to **no app-managed upload or persistence, and port types only**; what the OS does with its own log store is not something this code controls or can promise |
| 7 | Remove the unused controller sink | `routeObservationSink` deleted — zero references. Tests inject into the diagnostic directly |

**Correction 5 is mine to own:** I had the early return backwards in both a comment and a test
name, and Codex caught it.

## 2. Results

| | |
|---|---|
| **Bundle** | `Test-MOTIVO-2026.09.21_15-25-07-+0100.xcresult` — **1076 total / 1070 passed / 0 failed / 6 skipped** |
| Targeted | 16 passed across the two R1 classes |
| Release build | **SUCCEEDED** |
| Skips | the same six standing skips |

## 3. Warnings — zero delta, proven rather than inferred

**71 unique in Release, the same total as the accepted baseline.** 25 fall in
`VideoRecorderView.swift`, which looked like new warnings and is not: they are the **same
warnings displaced** by the lines this unit added (1748→1770, 2212→2234, 2540→2562 — all +22).

**Established, not assumed:** with line numbers stripped, the two warning sets are
**identical**. `RecordingRouteObservation.swift` contributes **zero**.

## 4. Files and hashes

```
393b7f2ff1cee41258ffddc98e438455023acd6e8ed1dad41cde02ec0c173bbf  MOTIVO/RecordingRouteObservation.swift
18bd175b27a912e7066d473a8e8abdc05b8d778aeb829c8b3d97150d0c095d70  MOTIVO/VideoRecorderView.swift
5ac79408aaec8b972cffc3d1d26aac33d9aacf81a38c3a0e9c41e87a9b64c5f4  MOTIVOTests/RecordingRouteObservationTests.swift
```

`MOTIVO/RecordingRouteObservation.swift` (new), `MOTIVO/VideoRecorderView.swift` (modified),
`MOTIVOTests/RecordingRouteObservationTests.swift` (new). **No other source or test file
touched.**

## 5. Controls — two, both with retained logs

| # | Mutation | Log | Observed |
|---|---|---|---|
| **I** | Early `return` restored after the USB branch | `control-I.log` | `testThePreferencePathHasASingleExit…` **FAILED**, alone |
| **J** | Live getters re-read after classification — the defect Codex found | `control-J.log` | **the three capture tests FAILED**, and only those |

Both restored and verified byte-identical by hash; control-text sweep returns zero. **The full
suite and the Release build ran after restoration.**

## 6. What this does and does not establish

- **It is observability, not a fix.** No reproduced defect is repaired. **C-97 R2, R3 and R4
  are carried, untouched, and not addressed by a route measurement**; a full concurrency audit
  remains separately scoped.
- **It does not prove a soundtrack.** A match says the session reported the desired input at
  that instant, not that samples arrive — which is R4.
- **A mismatch is not a diagnosis.** Both readings are deferred to main after their selection
  attempt, so a route can legitimately have moved. Nothing refuses, retries or warns.
- **The tests cannot show real hardware routing.** They drive the production classifier with
  fakes; no `AVAudioSession` is exercised.
- Previously accepted first-use setup, the shipped observers and cancellation, and the waived
  device checks are **unchanged**.

## 7. Device measurement — minimal, and no campaign

**No new QA matrix is proposed.** Whenever a recorder run next happens for its own reasons, the
Release log can be read for `subsystem=com.motivo.recorder category=route`, reporting
stage plus port types. There are two observation sites, not a fixed two lines per session:
the preference helper also runs on meaningful route changes.

**Limits to carry with any such reading:** both stages are deferred, so a line describes a
moment shortly after selection; `1.0 (131)` is fixed for every build, so **a log line cannot be
attributed to a particular source revision** without separate provenance; and a mismatch on its
own is not a fault.

**§7 was corrected by Codex directly in this document**, and that correction stands as written:
two observation SITES, not a fixed two lines per session, because the preference helper also
runs on meaningful route changes (`applyPreferredRecordingInput` is called from
`configureAudioSession` at `:1666` **and** from the route-change handler at `:1860`). My
original "two lines per session" was wrong and is withdrawn.

**Codex's acceptance is LOCAL code and validation only.** It does not extend to device
behaviour, to real hardware routing, to C-97 R2/R3/R4, or to Phase 6 closure. **Samuel has given
no commit instruction yet.**
