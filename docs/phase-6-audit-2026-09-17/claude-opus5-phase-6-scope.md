# Études — Phase 6 independent audit: BASELINE AND SCOPE

**Auditor:** Claude (Opus 5) in Claude Code, working from
`phase-6-claude-prompt.md` and the common brief `phase-6-common-audit-brief.md`.

**Date:** 17 September 2026. **Read-only pass. No code was changed, nothing was
committed, pushed or deployed, no device was operated, and no production
mutation was made. No paused automation was resumed.**

---

## 0. FILENAME COLLISION — READ THIS FIRST

The brief asked me to save `claude-phase-6-scope.md`,
`claude-phase-6-audit.md` and `claude-phase-6-comparison.md` in
`/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/`.

**All three of those filenames were already occupied when I came to write**
(timestamps 15:32 and 15:44 today, while this audit was in progress). The first
five lines of `claude-phase-6-scope.md` identify it as *"executed by the current
Codex agent as an independent pass"* against the Claude-named deliverables.

**I did not overwrite them and I did not read them.** I saw only the opening
lines of the scope file, incidentally, while checking whether the path existed;
I read nothing of the audit or comparison files. My deliverables are therefore:

- `claude-opus5-phase-6-scope.md` (this file)
- `claude-opus5-phase-6-audit.md`
- `claude-opus5-phase-6-comparison.md`

Two independent reports now exist under confusingly similar names. Before the
comparison, please confirm which file belongs to which auditor.

---

## 1. Baseline, recorded at start

| | |
|---|---|
| Repository | `/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO` |
| Branch | `feature/solo-connected` |
| HEAD | `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584` ("Accept QA7 and QA8 on device") |
| Default branch | `main` at `3454f61` |

**Dirty paths at start, with SHA-256 of working-tree content. Preserved
unchanged; re-verified at the end of the pass.**

| Path | Status | SHA-256 |
|---|---|---|
| `docs/connected-invitations-direction.md` | modified | `90f60494f42ec2500254b6a7aa6384ee670ffa49fd5b678fb26191eeb27885c0` |
| `docs/private-connection-invitations-scope-2026-09-17.md` | modified | `c470d4a18c79cff102b01b472f7d06ddb4079fdbcffc998f11e260882236223d` |
| `AGENTS.md` | untracked | `f948387812c8e6b8a002e4baf84cce472430c954677bed8577e5d9b2f1cbaaaa` |

Read as current work. **No inference of implementation approval is drawn from
them.** Nothing about invitations is treated as a shipped feature, and B-40 is
treated as deployed and untouchable.

**Commits supplying the evidence context:** `2fd0f63` USB/drone acceptance ·
`8df457c` teen-contact proposal and invitation direction · `7fe56bf` Lists
client review and device acceptance · `e656752` Lists client implementation ·
`f87a51a` verified Lists production schema · `1f36ef1` reviewed Lists backend.

### What I deliberately did not read

`phase-6-codex-handover.md`, and the three occupied `claude-phase-6-*.md` files.
The handover is a task brief rather than a report, but it could steer scope, and
the brief requires two genuinely independent passes.

---

## 2. Reconciling the phase position before scoping

Phase 6's charter in `CLAUDE.md` is narrow — *"obsolete backend code,
AVFoundation deprecation sweep, architectural leftovers"*. The brief asks that
this not be silently replaced with an unlimited rewrite, while still covering
release-critical risk. Three facts shaped the scope:

1. **Phase 4 is implementation-complete and exit-incomplete**; Phase 5 is
   mid-flight (next unit P5-G / CP-4). Phase 6 therefore inherits a large body
   of *carried* rather than *closed* work, and part of the audit's job is to say
   what is genuinely Phase 6's and what already has an owner elsewhere.
2. **The newest code is the least audited.** Connected Lists (`1f36ef1`,
   `e656752`) shipped two days before this pass behind a focused 13-test suite
   and one device session. A focused suite is evidence about what it asserts,
   not about what it did not touch.
3. **Three device acceptances landed on 17 September** (QA7 USB audio/video, QA8
   drone, Lists delivery/adoption). The brief forbids re-demanding them. My
   treatment: accept them as user-reported device evidence, use them as
   *constraints on hypotheses*, and spend the effort on what they did not
   exercise and on whether the source explains what was observed.

---

## 3. Scope

### In scope — six workstreams

| # | Workstream | What was actually examined |
|---|---|---|
| 1 | **Data integrity and ownership** | Saved-list persistence, migration and adoption (`SavedList.swift`, `TasksManagerView`, `PracticeTimerView`), the legacy per-context saved-set keys, `LocalFactoryReset` blast radius, staged-attachment write paths, `SessionSyncQueue` durability and generation guards |
| 2 | **Connected security / privacy** | Full policy and privilege sweep from the committed catalog snapshot: all 33 policies, table and column grants, CHECK constraints and triggers on `connected_attachments`, `posts`, `follows` and `storage.objects`; the recipient-UPDATE → `storage_path` → object-read chain traced end to end; `enforcement_gate` call-wrapping verified across every policy |
| 3 | **Membership / lifecycle** | `enforcement_gate` / `enforcement_active` definitions; the gated vs ungated policy split (post-delete and storage-delete carve-outs); the unshare demote-then-delete protocol against PostgREST zero-match semantics; the cleanup workflow's branch reachability and version claims |
| 4 | **Audio / video and concurrency** | `DroneEngine`, `AudioServices`, `AudioNotificationObservers`, `RecordingInputPolicy`, `BufferedRecordingAudio`, both recorders' observer sets, the writer finish/watchdog path, every `MainActor.assumeIsolated` site; reconciliation of the QA8 drone observation against the source |
| 5 | **Client sharing and UX reliability** | Lists send/adopt flow, sheet dismissal during an in-flight send, orphan behaviour on partial send, synchronous media work inside SwiftUI view bodies |
| 6 | **Phase 6 cleanup and release engineering** | Clean Release build warning census with isolated derived data; unreferenced-type sweep across all 176 source files; unguarded-`print` census screened for user content and credentials; obsolete backend objects; documentation drift |

### Explicitly out of scope

- **Implementation of any kind** — no fixes, refactors, migrations, package
  changes, commits, pushes, deploys or branch creation.
- **Device operation**, uninstall/reset/erase/sign-out, identity changes,
  personal-data cleanup. Samuel's Études Dev history, staging and old sessions
  were neither touched nor inspected.
- **Production mutation.** No write reached the hosted backend and no database
  connection was opened. All backend analysis comes from the committed
  `supabase/schema/` catalog snapshot, the migrations, and the Edge Function
  sources in the repository.
- **Legal / DPIA / publication gates** and the invitation proposals — recorded
  as separate decisions, never as engineering findings.
- **Re-running accepted device QA** for completeness.
- **Broad modernisation for its own sake.** A deprecated API is reported only
  where a consequence is demonstrated, or where the call site is named to bound
  a sweep.

### Coverage limitations — stated, not glossed

- **No device and no live backend.** Every finding is source-, catalog- or
  build-derived. Where a device observation would settle something, the exact
  check is named.
- **No production data was read.** Row counts and population claims in the
  records are treated as dated statements and were not re-verified.
- **UI and visual behaviour is not assessed.** Layout, animation and
  accessibility rendering need a running app.
- **Core Data store contents were not read**, so C-103 stays unconfirmed here
  too.
- **`PracticeTimerView.swift` (5,196 lines), `ContentView.swift` (3,096),
  `MeView`, `AttachmentViewerView` and `MediaTrimView`** were read selectively
  around in-scope paths, not exhaustively.
- **The metronome, tuner, insight engine, Scores library and PDF subsetting**
  were touched only where they intersect the audio-session and dead-code sweeps.
- **No claim of whole-app safety is made or implied.** The findings describe the
  surfaces listed above and nothing else.

---

## 4. Commands run, with results

All builds used an **isolated derived-data path inside the session scratchpad**,
never the repository's `build/` directory and never the user's DerivedData.

```
xcodebuild -project MOTIVO.xcodeproj -scheme MOTIVO -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath <scratch>/dd-release build
```
**`** BUILD SUCCEEDED **`, exit 0.** 155 warning lines, **78 unique**: 77
compiler deprecation warnings plus one benign
`appintentsmetadataprocessor` "No AppIntents.framework dependency found" note.
**Zero errors and zero non-deprecation compiler warnings.**

```
xcodebuild test -project MOTIVO.xcodeproj -scheme MOTIVO -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MOTIVOTests -derivedDataPath <scratch>/dd-test
```
Result recorded in the audit report, Appendix A.

Read-only Python analysis over `supabase/schema/*.json` (policies, grants,
constraints, triggers, functions, columns). No network access to Supabase.

---

## 5. How this scope covers the Phase 6 remit

| Historical Phase 6 charter | Covered by |
|---|---|
| Obsolete backend code | WS 3 + 6 — dead `membership_control` cutover columns, the retired shadow-observer table, and a `Simulated*` service that is not simulated |
| AVFoundation deprecation sweep | WS 6 gives the full census; **WS 5 identifies which deprecated synchronous accessors carry a real main-thread cost**, so the sweep can be ordered by harm rather than by count |
| Architectural leftovers | WS 6 — 15 unreferenced types, a dead `AudioServices` recording path, dead `shouldResumeAfterRouteChange` state, vestigial C-41 plumbing |
| Release-critical risk the charter does not name | WS 1–3 — local data loss on list deletion, an unshare authorisation-probe claim that the protocol does not deliver, and the Connected privilege surface |

Routine audit choices inside this scope were taken without further approval, as
the brief allows. Nothing was expanded into implementation.
