# C-3 — post-C-84 measurement protocol (DRAFT, NOT RUN)

Written 2026-09-14 at `3c68d81`. **Measurement only. No C-3 performance fix is
chosen until this has run and been scored.** C-89 (audit A5) is a correctness fix
regardless of the result and is scored separately (§6).

Read with `docs/phase-5-c3-resume-handover.md` (the original baseline and what
C-84 changed) and the C-3, C-84 and C-89 rows of `docs/audit-findings.md`.

## 0. Fixture safety — BEFORE ANYTHING ELSE

**The account holder's personal "Samuel Dixon" account in Études Dev
(`com.samueldixon.motivo.dev`) holds about six months of practice history and is
NOT expendable** (account holder, 2026-09-14).

- **Preferred:** a disposable installation and account. Device B's Études Dev
  must not be assumed disposable.
- **If Device B's Études Dev must be used:** before staging anything, confirm
  with the account holder which account it holds, and confirm the Practice Timer
  has **no in-progress session with staged media**. Ending this protocol uses
  **Reset** (the confirmed whole-session discard), which deletes staged data —
  it must only ever discard fixtures this protocol created.
- **Never** Erase All, account deletion, uninstall/reinstall, or a container
  wipe. Install only as an in-place update. The Release app stays untouched.

## 1. What the source says happens on every `.active` (source-established)

`PracticeTimerView.onChange(of: scenePhase)`, `.active` branch, in order:

1. `commitAllAudioTitleBuffersAndPersist()`, `evaluateAppSetUpGate()`.
2. `hydrateTimerFromStorage()` — **reads every staged audio and image file in
   full** with `Data(contentsOf:)`, synchronously on the main actor. Videos are
   restored by file with no bytes read (C-84); their posters are decoded with
   `UIImage(contentsOfFile:)`. Emits the existing `Practice Timer restore` line.
3. `StagingStore.bootstrap()` and `list()` (JSON decode), again.
4. ID-set comparison; **if in-memory and store IDs differ,
   `mirrorFromStagingStore()` reads every staged audio and image file again.**
5. `recomputeSessionMetaTint()`, and an async relational-count refresh.

On `.inactive`/`.background`: persist the snapshot, `purgeStagedTempFiles()`
(deletes audio/image/video `tmp` surrogates **and clears `videoThumbnails`**),
`closeTuner()`.

`.active` also follows `.inactive` from Control Center, the notification shade
and system prompts, not only a true background.

**The existing `restore` line is emitted inside step 2, before steps 3–4, so it
UNDERSTATES a foreground that takes the mirror pass** (account holder,
2026-09-14). It cannot be the whole instrument.

## 2. Instrument — TEMPORARY, removed at scoring

One `// TEMPORARY — C-3` line at the **end** of the `.active` branch, through
`PracticeTimerDiagnostics.notice` (Release-readable, `privacy: .public`):

```
Practice Timer foreground • cycle=<n since launch> • mirror=<took pass 4?>
  • audioBytes=<Σ staged audio> • imageBytes=<Σ staged images>
  • ms=<whole .active branch> • headroomMB=<after> • peakFootprintMB=<process lifetime max>
```

- `ms` spans steps 1–5 synchronously, so it includes any mirror pass.
- `peakFootprintMB` is `ri_lifetime_max_phys_footprint` from
  `proc_pid_rusage(RUSAGE_INFO_V4)`, sampled at the same point. **It is a
  PROCESS-LIFETIME maximum and must never be reported as the peak caused by a
  particular foreground cycle.** It can only be read as an upper bound for that
  fresh process, and a higher value than the previous reading is described only
  as **"the process maximum increased between readings"** — never attributed to a
  particular foreground cycle, and never as "this cycle peaked at X". To keep even that
  reading narrow, each size runs in a **fresh process** and the value is read
  after every cycle. If a per-cycle peak is ever needed, it needs a different
  instrument (sampling during the branch), not this one.
- `cycle` distinguishes the **first** restoration after launch from later ones.

**Removal condition: delete it the moment C-3 is scored, and verify the removal
as a pure deletion** against its pre-instrumentation commit, as every earlier
probe was.

## 3. Fixtures — record ACTUAL sizes, not estimates

The recorder is AAC, 44.1 kHz, mono, **192 kbps constant**, which *predicts*
≈1.44 MB per minute. **That is a planning estimate; the protocol records the
bytes actually staged.**

| Rung | Content | Record |
|---|---|---|
| A0 | empty timer | baseline `ms`, `headroomMB`, `peakFootprintMB` |
| A1 / A10 / A60 | one audio take of ~1, ~10, ~60 min (Background mode for 60) | exact bytes from `Staging/` |
| I1 / I5 / I10 | 1, 5, 10 camera photos | exact bytes each and total |
| V | one existing large video (control; C-84 says ≈ A0) | bytes |

Sizes are read from the app container's `Staging/` directory and cross-checked
against `staged.json`.

## 4. Procedure per rung

1. Fresh launch, stage the fixture, let staging finish.
2. **Cycles 1–5:** background → foreground, 3 s apart, read the line each time.
3. **Mirror-forced cycle:** one additional cycle while a condition that makes
   IDs differ is present (see §6 for the camera case), to price step 4.
4. **Inactive-only cycle:** open and close Control Center; note whether video
   thumbnails blank while it is open (the original C-3 supporting observation,
   predicted still present from `purgeStagedTempFiles`).
5. Reset (fixtures only — §0), confirm the timer is empty.

## 5. Predictions — to be committed before the run

Stated as directions and structure, because no post-C-84 audio/image number
exists yet:

- **P1** — V restores at A0's cost (C-84's measured result holds).
- **P2** — `ms` rises with staged audio + image bytes; `mirror=false` on ordinary
  cycles.
- **P3** — a `mirror=true` cycle costs roughly twice the staged-byte component
  of an ordinary cycle.
- **P4** — `headroomMB` falls by roughly the staged audio + image bytes
  (they are held as `Data`) and does **not** fall further with later cycles.
- **P5** — cycle 1 and cycles 2–5 differ by no more than noise, because the
  work is identical (a first-cycle difference would be page-cache or decode
  warm-up, and is recorded, not assumed).
- **P6** — Control Center blanks video thumbnails while open.

Any miss is recorded as a miss and diagnosed before continuing.

## 6. C-89 (A5) — own regression case, own acceptance

- **Automated, failing-first:** stage a camera photo; assert the in-memory id
  equals the `staged.json` ref id; delete it through the viewer's path; hydrate;
  assert it does not return.
- **Device acceptance:** take a timer photo, wait for staging, delete it in the
  viewer, background/foreground, then relaunch; check both the visible
  attachments and `staged.json`. Separately confirm a selected thumbnail keeps its
  identity across recovery.

## 7. Constraints on ANY later C-3 performance fix

- **Matching IDs are not proof that attachments are unchanged.**
  `StagingStore.replace` keeps an attachment's id while replacing its file, so a
  skip-when-IDs-match optimisation would serve stale bytes after a trim. Any fix
  must still refresh **trimmed/replaced media, titles, durations and posters**,
  and handle **deletion** and **recovery after a new process**; its verification
  must include each.
- Preserve the first-video startup sequence and the accepted audio behaviour
  (C-92…C-96); neither is touched as incidental cleanup.
- Smallest options remain candidates only until §5 is scored: skip the byte
  rebuild when nothing changed **by a content-aware test, not IDs**; stop
  clearing thumbnails on inactive; file-backed staged audio (C-84's video
  pattern) only if A60 shows a real memory cost.
