# Études — Phase 6 independent deep audit

**Auditor:** Claude (Opus 5), Claude Code. **Date:** 17 September 2026.
**Baseline:** `feature/solo-connected` @ `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`.
**Scope, coverage limits and commands:** `claude-opus5-phase-6-scope.md`.

**This is a read-only pass. Nothing was implemented, committed, pushed or
deployed. No device was operated. No production mutation was made.** No Codex
output was read before this report was written; see §0 of the scope file for a
filename collision that needs resolving before the comparison.

---

## Executive assessment

**No P0 was found in the reviewed scope, and no defect was found that leaks one
member's Connected content to another.** The two hardest privacy questions I
posed — *can a recipient repoint an inbox row at somebody else's storage
object?*, and *did the shadow-telemetry gate regress into the per-row form that
was measured at 278 ms?* — both came back clean, and clean for a **structural**
reason rather than by luck. Those two negatives are recorded in §4 because they
are the ones a future change could break.

**Three findings are consequential.**

1. **A saved List that the member deletes comes back.** Not the received copies
   the Lists unit hardened — the member's **own** lists, through a legacy
   per-context mirror that the Practice Timer rewrites on every save and that
   nothing clears on delete. The Lists unit's own source comment names this
   exact mechanism, and the fix it shipped was correctly scoped to adopted
   copies; the pre-existing path underneath was left as it was. **Silent local
   data behaviour that contradicts an explicit user action, reachable in three
   taps, and untouched by any device QA run so far.** (F-1, P2.)

2. **The unshare protocol's "authorisation probe" does not probe.** `C-61`'s
   demote-then-delete says in its own comment that the leading `PATCH` makes a
   broken session or an unowned row *"fail before anything destructive is
   attempted"*. It is sent with `Prefer: return=minimal`, and PostgREST answers
   **204 for a PATCH that matched zero rows** — which is the precise fact this
   project *measured for itself* while fixing C-43. An RLS-denied demote is
   therefore read as success. The stated safety property — "the worst outcome of
   any later failure is a private row" — is not delivered in the one state where
   it matters. (F-2, P2.)

3. **Deprecated synchronous AVFoundation accessors are being called inside
   SwiftUI view bodies**, one of them alongside a synchronous `Data.write`.
   This is what turns C-22 from a warning count into a main-thread cost, and it
   is the same class as C-3. It also tells you which 77 deprecations to sweep
   first. (F-3, P2.)

**One carried unknown is resolved rather than restated.** C-96 and the QA8
record both flag that the drone's implementation note says a route change *stops
it for an explicit restart*, while the device showed automatic recovery, and
both correctly decline to infer a mechanism. **The source settles it: there is
no automatic restart anywhere.** `DroneEngine.start` has exactly two call sites
and both are the user's own button. The observation is therefore evidence that
the route-change invalidation **did not fire** on that unplug — not evidence of
a recovery path. That is a better outcome than either hypothesis, and it leaves
one latent behaviour worth knowing (F-4).

**Everything else is cleanup, documentation drift, or an evidence gap with a
named owner.** The Release build is clean — zero errors and **zero
non-deprecation compiler warnings** — and the unit suite passes (Appendix A).

**I am not claiming the app is safe.** I did not run it, did not touch a device
and did not read production data. This report describes the surfaces in §3 of
the scope file and nothing else.

---

## 1. Findings

Severity: **P0** critical · **P1** release blocker · **P2** important ·
**P3** improvement. Each finding states its kind: **confirmed defect**,
**plausible risk (named check)**, **evidence gap**, **documentation drift**,
**optional cleanup**, or **product/legal decision**.

---

### F-1 · P2 · Confirmed defect · Deleting a saved List does not delete it

**Existing ID:** new. Adjacent to the Lists work (`e656752`) but **pre-existing**
— the dual-write predates it (`c29a1ed`).

**Kind:** confirmed defect (source-traced; not device-observed).
**Confidence:** high on mechanism, high on reachability, **not device-confirmed**.

**Trigger.** Save a list from the Practice Timer tasks pad, then delete that list
in Profile → Tasks manager.

**Observed/predicted failure.** The list reappears — in the Tasks manager the
next time it is opened, and in the pad's saved-list picker immediately. It is
also **re-persisted to the authoritative key**, so it survives relaunch. The
member's explicit delete is silently undone with no error and no message.

**Call chain, absolute references.**

1. `MOTIVO/PracticeTimerView.swift:966-974` — `savePadSavedTaskSets` writes the
   whole library to `globalTaskSetsKey` **and** writes
   `SavedListLibrary.legacyMirror(sets)` to `currentContextTaskSetsKey`
   (`"practiceTasks_v1::<owner>::<activityRef><instSuffix>::saved_sets_v1"`,
   built at `:842-846`). Reached from `commitNewTaskSetFromPrompt`
   (`:1046-1033`) and `saveCurrentPadIntoLinkedTaskSet` (`:1035-1052`).
2. `MOTIVO/TasksManagerView.swift:1378-1389` — `deleteTaskSet` removes the set
   from the in-memory array and calls `saveSavedTaskSets`
   (`:1157-1161`), which writes **only** `globalTaskSetsKey`. **No per-context
   key is touched.**
3. `MOTIVO/TasksManagerView.swift:1136-1148` — `loadSavedTaskSets` iterates
   `legacyTaskSetKeysForMigration()` (`:1163-1180`, all activity refs × all
   instrument suffixes, which includes the pad's own context) and merges each
   into `merged`. The deleted set's `id` is no longer in the dedup set
   (`SavedListMergeIdentity`, `MOTIVO/SavedList.swift:140-152`) and its
   `sourceSendID` is `nil`, so only a content-signature collision with a
   *surviving* list could suppress it — normally none.
4. `MOTIVO/TasksManagerView.swift:1150-1152` — the merged result is written
   **back to `globalTaskSetsKey`**, making the resurrection authoritative.
5. `MOTIVO/PracticeTimerView.swift:947-961` — the pad's own loader merges the
   context key too, so the deleted list is visible there without any Tasks
   manager visit.

**Why this is not speculation.** The Lists unit documented the mechanism in the
source while fixing the *adopted-copy* half:

> `MOTIVO/SavedList.swift:131-132` — *"Adopted lists live only in v2. Mirroring
> them into a legacy context would resurrect a deleted copy when that context is
> opened later."*

`legacyMirror` (`:133-135`) filters `sourceSendID != nil` out of the context
mirror. **Received lists are protected. The member's own lists are not** — they
are exactly the rows `legacyMirror` keeps.

**Scope.** Own saved lists only. Adopted/received lists delete correctly; the
Lists unit is not implicated in the defect, only in having drawn the map to it.

**Reproduction (device, non-destructive, backend untouched).**
1. Practice Timer → tasks pad → type one line → **Save list**, name `ZZ-Test`.
2. Profile → Tasks manager → delete `ZZ-Test`.
3. Close the Tasks manager sheet and reopen it.
**Expected today: `ZZ-Test` is present.** Control: create `ZZ-Control` *inside*
the Tasks manager (never through the pad) and delete it — it should stay deleted,
because no pad save ever mirrored it.

**Smallest coherent remedy.** Make deletion authoritative across both keys:
`deleteTaskSet` removes the id from `globalTaskSetsKey` **and** rewrites every
key `legacyTaskSetKeysForMigration()` would later read, with that id excluded.
That is a client-only change, no schema, no backend. The larger and cleaner fix
— stop mirroring to per-context keys at all, since `globalTaskSetsKey` is
already authoritative — is a migration question and should be scoped separately.

---

### F-2 · P2 · Confirmed defect in a stated safety property · The unshare demote is not an authorisation probe

**Existing ID:** belongs on **C-61** (and its P4-U2a-2 acceptance record).
**Kind:** confirmed defect in the claim; the resulting bad state is a plausible
risk with a narrow trigger.
**Confidence:** high that the claim is false; medium on how often the bad state
is actually reached.

**The claim.** `MOTIVO/BackendShim.swift:1785-1789`:

> *"It also acts as an AUTHORISATION PROBE. Storage answers the same 'NoSuchKey'
> for an absent object, an RLS denial and a missing token, so deletion cannot
> tell those apart. Because the PATCH runs first, a broken session or a row we do
> not own fails before anything destructive is attempted."*

**The code.** `MOTIVO/BackendShim.swift:1802-1824` sends
`PATCH /rest/v1/posts?id=eq.<uuid>` with `"Prefer": "return=minimal"` and body
`{"is_public": false}`, then treats anything that is not a transport/HTTP error
as success (`:1821-1826`). `MOTIVO/NetworkManager.swift:261` classifies any
`200...299` as success, so **204 is success**.

**Why that is wrong, using this project's own measurement.** PostgREST answers a
zero-match write with 204 under `Prefer: return=minimal`. C-43 measured exactly
this and fixed it by switching to `return=representation` and counting rows —
see `MOTIVO/BackendShim.swift:859` and `:874`, and
`MOTIVO/ConnectedAttachmentSharing.swift:335`, which already carries the correct
pattern. **The repository contains the right idiom twice and the wrong one
here.**

**The reachable bad state.** `posts_update_owner` is
**gated** — `(select enforcement_gate('posts.update')) AND owner_user_id =
auth.uid()` (`supabase/schema/policies.json`) — while `posts_delete_owner` is
**ungated** (`owner_user_id = auth.uid()` alone). So for an owner whom the server
does not currently consider entitled:

- the demote PATCH matches zero rows → **204 → read as success**;
- `deletePost` (`:333-398` / the HTTP equivalent) then runs and is *fail-closed*
  on the storage step;
- if any storage delete fails, the function returns failure with the post row
  **still `is_public = true`** — the exact state C-61 exists to prevent — and the
  queue retries with the same broken probe.

Client-Connected-but-server-unentitled is not a hypothetical state in this
project: the U5 invariant explicitly accepts *"a few denied requests in the first
seconds of a cold launch"*, and the 2026-09-05 device QA ran in precisely that
configuration (`docs/phase-4-device-qa-acceptance.md`: Connected engaged via
Sandbox, `connected_member` false). Scope 011 narrows but does not remove it —
B-39 revocation, an unestablished membership row and propagation lag all
reproduce it.

**Secondary consequence of the same mechanism.** The comment's "a row we do not
own fails" half is also false for the same reason: a PATCH against another
member's post id matches zero rows and reports success.

**Reproduction.** Local stack only (the brief forbids production writes). With
`enforcement_enabled = true` and a member whose `connected_member()` is false,
issue the demote PATCH exactly as `:1813-1819` does and observe **204**; then
read the row back and observe `is_public` unchanged. The control is the same
PATCH as an entitled owner: 204 **and** `is_public = false`. **The two are
indistinguishable to the client today, which is the finding.**

**Smallest coherent remedy.** On that one PATCH, send
`Prefer: return=representation`, require exactly one row in the response, and
return a distinct failure otherwise — byte-for-byte the shape already used at
`BackendShim.swift:874`. The queue's "no retry cap, no backoff" behaviour then
does the right thing: the withdrawal stays owed until it genuinely converges.
**Correct the comment in the same change**, because the comment is what the next
maintainer will implement from.

---

### F-3 · P2 · Confirmed defect · Synchronous AVFoundation and file writes inside SwiftUI view bodies

**Existing ID:** gives **C-22** a consequence; same class as **C-3**.
**Kind:** confirmed defect (structural); magnitude not measured.
**Confidence:** high on mechanism, unquantified on user-visible cost.

**Trigger.** Opening a session detail, or the post-record details screen, for a
session carrying audio attachments — and then any state change that
re-evaluates the body.

**Sites.**

- `MOTIVO/SessionDetailView.swift:1151-1160`, inside
  `ForEach(others, id: \.objectID)` (`:1137`): `AVURLAsset(url: u)` then
  `CMTimeGetSeconds(asset.duration)`. `duration` is the **synchronous accessor
  deprecated in iOS 16**; it parses the container header from disk on the
  calling thread, and the calling thread here is the main actor inside a view
  body.
- `MOTIVO/PostRecordDetailsView+Attachments.swift:336-346`, inside
  `ForEach(audioOnly)` (`:330`): the same synchronous `duration`, **and**
  `try? att.data.write(to: url, options: .atomic)` at `:340` — a synchronous
  write of the attachment's bytes, in a view body, whenever the surrogate file
  is absent.
- Further synchronous `duration` / `copyCGImage` calls on main-actor paths at
  `MOTIVO/PracticeTimerView.swift:4677`, `:4806`, `:4811`;
  `MOTIVO/PostRecordDetailsView+Attachments.swift:1220`;
  `MOTIVO/MediaTrimView.swift:1159`, `:1333`; `MOTIVO/VideoRecorderView.swift:1503`,
  `:1594`, `:1605`.

**Why it matters beyond tidiness.** C-3 measured this exact family on device —
19.1 MB → 53.2 ms, 278.7 MB → 322.9 ms — and its conclusion was that the real
cost is *"the same bytes rewritten to `tmp` on every single foreground"*, not the
one-off latency. `:340` is that pattern moved inside a body, where re-evaluation
is driven by SwiftUI rather than by the user.

**Reproduction / focused test.** Open a session with several audio attachments
and toggle any unrelated state on the same screen (a favourite, a title edit)
while sampling the main thread. C-3's own method applies: `xctrace --attach` on a
Release build, comparing a session with 0 audio attachments to one with 8.

**Smallest coherent remedy.** Compute duration **once**, off the body: resolve it
in a small `@State` cache keyed by attachment id, populated from a `.task` using
`load(.duration)`. Move the surrogate write out of the body to the existing
`ensureSurrogateFilesExistForViewer()` (already called on tap at
`PostRecordDetailsView+Attachments.swift:350`). **This is the batch that makes
the AVFoundation deprecation sweep worth doing**, and it bounds it: fix the
main-actor sites first, leave the rest as warnings.

---

### F-4 · P3 · Evidence gap resolved, plus one latent behaviour · The drone has no automatic restart

**Existing ID:** **C-96** (its flagged unknown) and
`docs/usb-audio-drone-device-qa-2026-09-17.md` check 6.
**Kind:** resolves an evidence gap; the latent behaviour is a plausible risk.
**Confidence:** high on the source claim.

**What both records flagged.** C-96's implementation note says a route change
*"stops the drone for an explicit restart"*; QA8 observed the drone stop briefly
and **restart automatically at the correct pitch**. Both records correctly
declined to infer a mechanism.

**What the source says, exhaustively.** `DroneEngine.start(frequency:volume:)`
has **exactly two call sites in the entire app**, and both are the member's own
button:
`MOTIVO/DroneControlStripCard.swift:36` (expanded strip) and `:227`
(compact trigger). There is **no `onChange(of: droneIsOn)` anywhere**, and the
only other consumer of engine state is
`MOTIVO/PracticeTimerView.swift:1592-1594`, which *mirrors* `isRunning` into
`droneIsOn` and starts nothing.

Meanwhile every failure path is terminal: `installObservers`
(`MOTIVO/DroneEngine.swift:235-254`) calls `invalidate(token)` → `hardStop()` on
interruption, route change, `AVAudioEngineConfigurationChange` and media-services
reset, and the comment at `:248` says so — *"Recreate the format/engine on the
next explicit start. No automatic restart."*

**Therefore the QA8 observation is not evidence of a recovery path. It is
evidence that the invalidation did not fire.** The route-change guard is
`MOTIVO/DroneEngine.swift:241-246`: it invalidates only if
`routeIdentity() != initialRoute` **or** the engine has stopped, and
`routeIdentity()` (`:213-216`) is built from the **output** port UIDs plus the
session sample rate. Unplugging a USB *microphone* need change neither. The
audible gap is then the audio-hardware route transition, not a stop.

**The latent behaviour this leaves.** On any route change that *does* alter an
output UID or the session sample rate — headphones in or out, AirPods
connecting, a USB interface with outputs — **the drone stops and never
restarts**, and the only signal to the member is the button reverting to its
inactive state. That is the designed behaviour, so it is not a defect; it is
**undocumented to the user and untested on device**.

**The check that settles both, in one unplug.** Start the drone with the CM-15
connected and **watch the drone button's active highlight** through the unplug.
If it stays highlighted throughout, the engine never stopped and this analysis is
confirmed. If it flicks to inactive and back, something restarts it and the
source does not explain it — which would be a genuinely new finding. Then repeat
with **wired or Bluetooth headphones** instead of the mic: the prediction is that
the drone stops and stays stopped.

**Also confirmed, unchanged:** C-96's *separate defensive equality guard* is
**still not implemented** — `MOTIVO/PracticeTimerView.swift:1592-1594` assigns
`droneIsOn = running` unconditionally. **No loop was reproduced here either**, and
the metronome line directly above it (`:1586-1590`) has the same shape and has
run through device QA. Recorded, not escalated.

---

### F-5 · P3 · Confirmed gap (dead code documenting a live policy) · `AudioServices`'s recording path never runs

**Existing ID:** new. Phase 6 "architectural leftovers".
**Kind:** optional cleanup with a documentation hazard.
**Confidence:** high — established by exhaustive call-site search.

`MOTIVO/AudioServices.swift:39` `configureSession(for:)` is called from exactly
two places, **both `.playback`**:
`MOTIVO/PracticeTimerView+AudioPlayback.swift:36` and `:78`. Therefore:

- `SessionContext.recording` (`:49-51`) and `.videoPreviewPlayback` (`:53-56`)
  are unreachable;
- `applyPreferredInputForRecording()` (`:86-98`) and
  `setPreferredInputIfNeeded` (`:100-114`) are called **only** from that
  unreachable branch.

**Why it is worth naming rather than just deleting quietly.** The file's header
(`:1-8`) documents the app's USB-input policy — *"recording: allowBluetoothA2DP
(output), preferred input USB > built-in"* — and the code implementing that
sentence is dead. The **live** implementations are
`MOTIVO/RecordingInputPolicy.swift:29-48` (audio, with verification) and
`MOTIVO/VideoRecorderView.swift:1533-1536`, `:1558-1563` (video, without). This
is precisely the area QA7 just exercised, so anyone reading `AudioServices.swift`
to understand what was tested reads a dead implementation.

**Remedy.** Delete the two unreachable cases and the two unreachable functions,
and move the header's policy sentence to `RecordingInputPolicy.swift`, whose
`preferred(in:)` actually expresses it. Zero behaviour change; verify by a
Release build.

---

### F-6 · P3 · Confirmed defect · A failed delivery leaves an orphaned storage object

**Existing ID:** the **B-8** orphan class; new instance, now also on the Lists
path.
**Kind:** confirmed defect (structural), no data loss, no privacy exposure.
**Confidence:** high.

`MOTIVO/ConnectedAttachmentShareUI.swift:593-627` uploads first and delivers
second, for both lists (`:609-611`) and existing attachments (`:616-622`). If
`deliver` fails — offline between the two calls, or the recipient's approved
follow revoked between selection and send, in which case the whole multi-row
INSERT is refused by `connected_attachments_insert_sender` — the object written
to `users/<uid>/connected/<assetID>.<ext>`
(`MOTIVO/ConnectedAttachmentSharing.swift:215-222`) **stays, with no row
referencing it**. Nothing sweeps it. B-8's clean-up (2026-09-04) removed four
objects of exactly this shape.

The member does see the error: the sheet cannot be swipe-dismissed while sending
(`.interactiveDismissDisabled(isSending)`, `:181`), which is correctly handled.
The residue is invisible.

**Remedy.** On `deliver` failure, delete the just-uploaded object before
surfacing the error. The sender already holds the privilege —
`attachments_user_delete_auth` permits DELETE on `users/<own uid>/%` and is
ungated. Best-effort; failure to clean up should not change the message shown.

---

### F-7 · P3 · Optional cleanup · Fifteen unreferenced top-level types

**Existing ID:** new; Phase 6 "architectural leftovers".
**Kind:** optional cleanup. **Confidence:** high (each has zero references
outside its own declaration, across all 176 sources and all 70 test files).

| Type | Declared at |
|---|---|
| `SimulatedPostCommentService` | `MOTIVO/BackendShim.swift:2110` |
| `CommentContinuationMetaRow` | `MOTIVO/CommentsView.swift:1080` |
| `AttachmentSharePageScope` | `MOTIVO/ConnectedAttachmentSharing.swift:91` (`public`) |
| `StatsBannerView` | `MOTIVO/ContentView.swift:2920` |
| `BackendPostRow` | `MOTIVO/ContentView.swift:3009` |
| `PeoplePlaceholderView` | `MOTIVO/ContentView.swift:3075` |
| `VideoOrIconTile` | `MOTIVO/ContentViewRowSupport.swift:80` |
| `NonImageTile` | `MOTIVO/ContentViewRowSupport.swift:296` |
| `VideoPreview` | `MOTIVO/MediaTrimView.swift:285` |
| `ResponsesPostDetailHost` | `MOTIVO/PeopleView.swift:787` |
| `VideoPlayerSheet` | `MOTIVO/PostRecordDetailsView+Attachments.swift:1329` |
| `StatChip` | `MOTIVO/ProfilePeekView.swift:442` |
| `FlexibleChipsView` | `MOTIVO/ProfilePeekView.swift:479` |
| `SettingRow` | `MOTIVO/ProfileView.swift:166` |
| `TasksManagerImportLauncherSheet` | `MOTIVO/TasksManagerView.swift:1436` |

Three `_Previews` types were excluded as legitimate. **Swift emits no warning for
an unused `private` type**, which is why these survived a clean build.
`TasksManagerImportLauncherSheet` and `AttachmentSharePageScope` are worth a
glance before deletion — they look like abandoned entry points for features
that were later scoped differently.

**Remedy.** One deletion commit, verified by a Release build and the unit suite.
No behaviour change is possible by construction.

---

### F-8 · P3 · Optional cleanup · Dead resume state in the video recorder

`MOTIVO/VideoRecorderView.swift:451` declares `shouldResumeAfterRouteChange`. It
is **written at `:1682` and `:1685` and read nowhere**. Its two siblings
(`shouldResumeAfterInterruption`, `shouldResumeAfterResignActive`) are both read.
Deleting it makes explicit what is currently only implicit: **after a route
change there is deliberately no resume.**

---

### F-9 · P3 · Confirmed gap (architectural leftover) · `SimulatedPublishService` is not simulated

`MOTIVO/BackendShim.swift:323` declares `SimulatedPublishService`. Four of its
five methods are genuine stubs. `deletePost` (`:333-398`) is not: it issues a
live `GET /rest/v1/posts`, live storage `DELETE`s for every attachment ref, and a
live `DELETE /rest/v1/posts` — through `NetworkManager`, which attaches the
member's real bearer token (`MOTIVO/NetworkManager.swift:226-228`).

It is selected when `currentBackendMode()` is neither `.backendPreview` nor
`.backendConnected`, or HTTP config is absent
(`MOTIVO/BackendShim.swift:2444-2452`). **No harm is demonstrated** — the
combination of a non-Connected mode with a live session and configured backend
is unusual, and the requests are owner-scoped — but a class whose name asserts
it does not touch the network performing three destructive production calls is
exactly the kind of leftover Phase 6 exists to remove, and the kind of thing the
next reader will trust the name of.

**Remedy.** Move that implementation to `HTTPBackendPublishService` (which
already holds the equivalents) and make the simulated one a stub like its
siblings. **Verify first** that no shipping path depends on delete working in
`.local` mode; if one does, that dependency is itself the finding.

---

### F-10 · P2 · Documentation drift · `AGENTS.md` is a stale copy of `CLAUDE.md`

**Kind:** documentation drift with a live process hazard.
**Confidence:** certain (byte comparison).

`AGENTS.md` (untracked, 196,311 bytes) and `CLAUDE.md` (203,137 bytes) differ.
`AGENTS.md` is missing, among other things:

- the whole **B-39 / scope-011 production deployment record of 2026-09-15**,
  including the three deployment gates and the Sandbox-entitlement amendment;
- the **2026-09-17 teen inbound-contact proposal** and the standalone
  **invitations direction** — the two things most likely to be
  misread as settled or unsettled;
- **C-34's scope correction of 2026-09-16** (five sites, not the app) and the
  sixth-site device verification;
- **C-52's second recurrence** (`3d49c4c`, 2026-09-09) and the
  `SchemeConfigurationGuardTests` enforcement that followed.

An agent reading `AGENTS.md` therefore receives a record that predates two
production deployments and two corrections — **and this is not theoretical,
because `AGENTS.md` is the file a Codex-family agent reads by convention.** The
comparison exercise this audit feeds into is being run by two agents, and one of
them may be working from it.

This is the failure mode `CLAUDE.md` names against itself repeatedly: *"a durable
document asserting a repository fact is not evidence of that fact."*

**Remedy (needs Samuel's decision, not a code change).** Either make `AGENTS.md`
a symlink to `CLAUDE.md`, or delete it and rely on `CLAUDE.md`, or commit it and
keep them in sync deliberately. Leaving an untracked, silently divergent second
copy of the project's authoritative record is the one option with no upside.

---

### F-11 · P3 · Documentation drift · Three stale claims inside `CLAUDE.md`

**Kind:** documentation drift. **Confidence:** certain.

1. **`CLAUDE.md:23`** — *"the daily 03:17 UTC job invokes `membership_cleanup_v1`
   **v6**"*. It was redeployed to **v7** on 2026-09-15 as part of B-39's
   `derive.ts` parity — stated in this same file at `:979` and in
   `supabase/sql/README-b39-scope011-deployment-results.md:23`. **The file
   contradicts itself, and the stale half is in the opening Phase 3 section — the
   first thing a new session reads**, which is the exact pattern the file's own
   2026-08-30 correction warns about.
2. **The CP-3 blocker text** — *"`AuthManager:618` calls `upsertSelfRow` with
   `lookupEnabled: true` HARD-CODED … CP-3 cannot work until that literal is
   addressed"* — **is resolved**. `upsertSelfRow` no longer takes the parameter
   and no longer sends the column
   (`MOTIVO/AccountDirectoryService.swift:367-374`). The text reads as an open
   blocker.
3. **`AuthManager:596`**, cited for the empty-display-name guard that mints an
   `auth.users` row with no directory row, is now
   **`MOTIVO/AuthManager.swift:804-807`**. The **behaviour is unchanged and the
   condition is still reachable** — only the reference is stale.

---

### F-12 · P3 · Register correction · C-22's deprecation count

`C-22` records *"53 deprecated AVFoundation and SwiftUI APIs"*. Measured on this
baseline from a clean Release build: **77 unique deprecation warnings**, in four
generations — **20 × iOS 16**, **27 × iOS 17**, **8 × iOS 18**, **22 × iOS 26**.
Full list in Appendix B. The growth is mostly iOS 26 arrivals
(`Text` `+` concatenation, `UIScreen.main`, `AVMutableVideoComposition`,
`interfaceOrientation`) that did not exist when C-22 was filed.

**Do not sweep by count.** F-3 identifies the subset with a demonstrated cost;
the rest are warnings on a deployment target (iOS 26.4) where every one of these
APIs still functions.

---

### F-13 · P3 · Evidence gap · Video recording behaviour on USB unplug is untested and differs from audio

**Existing ID:** adjacent to **C-97 part (2)**; the asymmetry itself is new.
**Kind:** evidence gap with a source-derived prediction.

QA8 established that **unplugging the CM-15 during an audio take continues
seamlessly on the phone mic, and reconnecting switches back**. The video recorder
does something different, from the same notification:

- Audio: `MOTIVO/AudioRecorderView.swift:734-744` re-runs
  `RecordingInputPolicy.applyAndVerify`, which falls back to the built-in mic
  (`MOTIVO/RecordingInputPolicy.swift:31`) and continues.
- Video: `MOTIVO/VideoRecorderView.swift:1679-1687` — on
  `.oldDeviceUnavailable` while `state == .recording`, it calls
  **`stopRecording()`**, ending the take.

**Prediction:** unplugging the CM-15 during a **video** take ends the recording
and offers whatever was captured. That may well be the right product behaviour —
it is not called a defect here — but it is the opposite of what QA7/QA8 just
established for audio, and **no device evidence exists for it either way**.

**Check:** one video take with the CM-15, unplugged mid-take. One observation
settles it.

---

### F-14 · P3 · Confirmed gap, reconfirmed · C-97 part (2) is untouched

`MOTIVO/VideoRecorderView.swift:1616-1633` registers exactly four observers:
`AVAudioSession.interruptionNotification`, `routeChangeNotification`,
`UIApplication.willResignActiveNotification`, `didBecomeActiveNotification`.

**Absent, as C-97 states:** `AVCaptureSessionRuntimeError`,
`AVCaptureSessionWasInterrupted` / `InterruptionEnded`,
`AVAudioSession.mediaServicesWereResetNotification`, and any missing-audio
watchdog. By contrast the **audio** recorder has all three classes of handling —
`MOTIVO/AudioRecorderView.swift:686-691` (media-services reset) and
`MOTIVO/AudioRecorderEvents.swift:8-14` (`audioRecorderDidFinishRecording` and
`audioRecorderEncodeErrorDidOccur`), which is C-95's work.

**Nothing here reopens QA7.** QA7 is evidence about ordinary operation; this is
about faults, and a successful ordinary take is not evidence of fault handling.
`automaticallyConfiguresApplicationAudioSession` remains at its default, and
changing it still needs its own proposal and a fresh-install before/after
comparison.

---

## 2. Carried-finding reconciliation

| ID | Position after this audit | Evidence |
|---|---|---|
| **C-12** — `SessionDetailView.deleteSession()` unreachable | **Still open; confirmed at HEAD.** `showDeleteConfirm` is declared at `SessionDetailView.swift:203` and **read only** at `:866`; nothing anywhere sets it `true`, so the "Delete Session?" alert never presents and `deleteSession()` (`:1786`) is unreachable | exhaustive search of the symbol |
| **C-15** — `PDFSelectedPagesStore` unscoped, never collected | **Still open, narrowed.** The store is widely live (19 call sites) and *does* clear on one path (`PostRecordDetailsView+Attachments.swift:669`) and migrate on another (`:775`). Whether collection is complete was not established here | source |
| **C-22** — deprecated APIs | **Open; count corrected 53 → 77** (F-12), and a priority subset identified (F-3) | Release build census |
| **C-41** — vestigial discovery plumbing | **Outstanding half confirmed.** `account_privacy_set_lookup_v1` is deployed and the client writer is wired (`AccountPrivacyService.swift:185`); **no UI reaches it**, so a 13–17 member still cannot opt in | source + `supabase/schema/functions.json` |
| **C-61** — durable unshare | **Implemented, but its stated safety property is not delivered.** See F-2 | `BackendShim.swift:1785-1826` |
| **C-96** — drone pitch / route handling | **Its flagged unknown is RESOLVED by source** (F-4): no automatic restart exists, so the observation means the invalidation did not fire. **The defensive equality guard remains not implemented**, and no loop was reproduced here either | `DroneEngine.swift`, `DroneControlStripCard.swift:36,227`, `PracticeTimerView.swift:1592` |
| **C-97** — video capture fault handling | **Part (1)** keeps its QA7 device evidence. **Part (2) confirmed still open** (F-14), plus a new untested asymmetry (F-13) | `VideoRecorderView.swift:1616-1687` |
| **C-102 / C-103** | **Unchanged.** C-103's deciding state is device-local Core Data, which this pass did not read. Neither was advanced or contradicted | — |
| **B-8** — orphaned storage objects | **Class recurs on the Lists path** (F-6) | `ConnectedAttachmentShareUI.swift:593-627` |
| **B-16** — `post_comment_views` orphans | Not re-examined; no evidence either way from this pass | — |
| **B-34** — shadow-window blindness | **Unchanged and still an observability limitation.** Note for the record: `shadow_enforcement_stat` is **not** dead — `enforcement_gate` still writes to it on every gated call | `supabase/schema/functions.json` |
| **B-37** — directory enumeration | Unchanged; not re-measured | — |
| **B-38** — `authenticated` can write `avatar_version` | **Confirmed present.** `authenticated` holds INSERT/SELECT/UPDATE/REFERENCES on `account_directory.avatar_version`, and `tg_directory_avatar_version` is `BEFORE UPDATE OF avatar_key`, so a PATCH touching only `avatar_version` is not re-stamped | `column_grants.json`, `triggers.json` |
| **Grandfather retirement** | **Completed as designed.** `membership_cutover` is gone; `membership_control.cutover_at`, `.cutover_identity_count`, `.cutover_verified_at` remain as **dead columns**, exactly as `CLAUDE.md` predicted. Candidate Phase 6 backend cleanup | `columns.json` |

**Release blockers vs work that can wait.** Nothing found here is a release
blocker on its own. F-1 is the one I would not ship without fixing, because it
contradicts an explicit user action and destroys nothing visibly. F-2 and F-3
are important but bounded. Everything else can wait for a cleanup batch. The
standing release blockers remain the ones already owned elsewhere — C-31, the
Phase 4 exit conditions, and the legal/DPIA gates — none of which this audit
touches.

---

## 3. Product and legal decisions (raised, not resolved)

- **Invitations** — `docs/connected-invitations-direction.md` and
  `docs/private-connection-invitations-scope-2026-09-17.md` are proposals with
  uncommitted edits. **Not implemented, not approved, not legally cleared.**
  B-40 remains deployed and was not weakened, inspected for weakening, or
  redeployed.
- **Teen inbound-contact revision** — pending legal review. No engineering
  finding here depends on it.
- **C-41's missing UI** — a 13–17 member cannot opt in to discovery because no
  screen reaches the deployed writer. Whether that is acceptable at launch is a
  product/legal call, not an engineering one.
- **F-10's `AGENTS.md`** — needs a decision (symlink, delete, or track), not a
  code change.

---

## 4. Checks that came back clean

Recorded because each is a property a future change could silently break, and
because "we looked and it held" is worth as much as a finding.

| # | Property | How it was established |
|---|---|---|
| **N-1** | **A recipient cannot repoint an inbox row at another member's storage object.** This was the sharpest privilege question available: `authenticated` holds table-level UPDATE on **every** column of `connected_attachments`, and `connected_attachments_update_recipient`'s `WITH CHECK` pins only `recipient_user_id`. The path is closed **structurally** by the `connected_attachments_recipient_update_guard` trigger (`enforce_connected_attachment_recipient_update`), which raises on any change to `id`, `asset_id`, `sender_user_id`, `recipient_user_id`, `storage_bucket`, `storage_path`, `filename`, `mime_type`, `byte_count`, `page_count` or `created_at`, and forbids un-setting `saved_to_scores_at` or `deleted_at`. The CHECK constraint `connected_attachments_sender_storage_path` is a second, independent lock | `policies.json`, `column_grants.json`, `table_grants.json`, `constraints.json`, `functions.json`, `triggers.json` |
| **N-2** | **All 23 `enforcement_gate` references are wrapped as `(select …)`; zero bare.** U6a measured the difference as 278 ms against 3.9 ms at 5,000 rows, and both forms are functionally correct — so this can only regress silently. Programmatically re-verified across all 33 policies | `policies.json`, parsed |
| **N-3** | **The video writer's 5-second finish watchdog does not double-complete.** `VideoRecorderView.swift:1271-1275` calls `completed()` unconditionally, so it does run twice on a normal finish — but `handleRecordingFinishedSuccessfully` sets `assetWriter = nil` at `:1325`, and both `completed()` (`:1254`) and the watchdog (`:1272`) guard on `assetWriter === writer`. No duplicate staging is possible | source trace |
| **N-4** | **A send sheet cannot be dismissed mid-send**, so a delivery failure always has somewhere to report itself — `.interactiveDismissDisabled(isSending)`, `ConnectedAttachmentShareUI.swift:181` | source |
| **N-5** | **No credential or user content is logged in Release.** 92 `print` calls sit outside `#if DEBUG`; every one was screened and none interpolates a title, note, display name, email, token or response body. All 15 `NetworkManager` prints — including the three `[SignedURL]` groups that echo a signed URL — are inside `#if DEBUG` (`NetworkManager.swift:238-256`, `:413-417`, `:442`, `:453-457`, `:528-532`, `:578-582`). The unguarded remainder logs error objects and absolute file paths | scripted `#if` nesting analysis + manual review |
| **N-6** | **The unattended-cleanup workflow really is armed from the default branch.** `.github/workflows/membership-cleanup.yml` exists on `main` and is **byte-identical** to the branch copy, so the "runs only from the default branch" gate is satisfied as the record claims | `git diff main:… HEAD:…` → empty |
| **N-7** | **Erase All removes saved Lists, including adopted copies** — `LocalFactoryReset.swift:51-56` removes the whole `UserDefaults` persistent domain, which covers `practiceTasks_saved_sets_v2::<owner>` | source |
| **N-8** | **`LocalFactoryReset.perform` still has exactly two production callers** (`ProfileView.swift:1846`, `:1919`), the Phase 3 exit assertion. The only other references are two tests | exhaustive search |
| **N-9** | **`posts_delete_owner` is deliberately ungated**, so a lapsed member can still delete their own posts without re-subscribing — C-35's rule, holding in the deployed policy | `policies.json` |
| **N-10** | **The Lists MIME and metadata constraints are coherent with the client.** The client's temp file carries the `.etudeslist` extension (`ConnectedListSharing.swift:18`), `safePathExtension` derives the storage extension from it (`ConnectedAttachmentSharing.swift:360-362`), and the deployed `connected_attachments_list_metadata` CHECK requires `storage_path LIKE '%.etudeslist'`, `page_count = 0` and `byte_count` in 1…131072 — which `ConnectedListPayload.maxBytes` (131072) matches exactly | migration + `constraints.json` + client |
| **N-11** | **List adoption is owner-scoped on both sides of the await.** `loadAttachment` captures the owner scope before the download and re-checks it after (`ConnectedAttachmentShareUI.swift:858-866`), and `saveToLists` re-checks again before writing (`:877-880`). A sign-out mid-download cannot write another identity's library | source |

---

## 5. Proposed fix batches

**Not implemented. Each needs its own scope and authorisation.** Ordered by
value, with dependencies and validation.

### Batch A — local data integrity (smallest, highest value)
- **F-1** saved-list deletion.
- **Scope:** `TasksManagerView.deleteTaskSet` plus whatever it must call to clear
  the per-context keys. Client only. No schema, no backend, no migration.
- **Dependencies:** none.
- **Validation:** a unit test in the existing style asserting that a set written
  to both keys and then deleted does not survive `loadSavedTaskSets()`; then the
  three-tap device reproduction in F-1 with its control.
- **Needs Samuel's decision:** whether to do the *narrow* fix (clear the mirror
  on delete) or the *structural* one (stop mirroring at all), which is a
  migration question for members who have per-context data today.

### Batch B — the unshare authorisation probe
- **F-2** only.
- **Scope:** one header and one response check in
  `BackendShim.unsharePost`, plus correcting the comment that states the false
  property. Client only; the server is already correct.
- **Dependencies:** none. It uses a pattern already shipped twice in this file.
- **Validation:** local stack, failing-first — an unentitled owner's demote must
  go from "reported success" to "reported failure and still queued", with an
  entitled owner's demote unchanged. **Do not manufacture membership state and do
  not weaken enforcement to test this**; the local stack's enforcement flag is
  the supported route.

### Batch C — main-thread media work (bounds the AVFoundation sweep)
- **F-3**, and only the main-actor sites it names.
- **Scope:** `SessionDetailView.swift:1151-1160`,
  `PostRecordDetailsView+Attachments.swift:336-346` and `:1220`. Duration moves
  to a cached async load; the surrogate write moves out of the body.
- **Dependencies:** none, but it **supersedes** any general "fix the iOS 16
  `duration` deprecations" task, so do this before C-22 is scoped.
- **Validation:** C-3's own method — `xctrace --attach` on Release, 0 vs 8 audio
  attachments, before and after.

### Batch D — Phase 6 cleanup (zero behaviour change by construction)
- **F-5** dead `AudioServices` recording path (move the policy comment to
  `RecordingInputPolicy`), **F-7** fifteen unreferenced types, **F-8** dead
  resume flag, and the three dead `membership_control` cutover columns.
- **Dependencies:** the backend column drop is a production DDL change and must
  go through the usual guarded-SQL, rehearsal and B-23 gate procedure. **Keep it
  in a separate authorisation from the client deletions.**
- **Validation:** Debug and Release builds plus the unit suite for the client
  half; B-23 for the backend half.

### Batch E — leftovers with a judgement call
- **F-6** orphan cleanup on failed delivery, **F-9** `SimulatedPublishService`.
- **Dependencies:** F-9 needs confirmation first that nothing relies on delete
  working in `.local` mode.
- **Validation:** local stack; a deliberately-failed deliver must leave no
  object.

### Batch F — records, needing decisions rather than code
- **F-10** `AGENTS.md` (symlink / delete / track — **Samuel's call**),
  **F-11** three stale `CLAUDE.md` claims, **F-12** C-22's count, and the
  register updates for C-12, C-61, C-96 and C-97 in §2.
- **Do this one first.** It is free, it removes a live hazard during the very
  comparison this audit feeds, and F-10 may be affecting the other auditor right
  now.

### Not proposed
- Any change to B-40, enforcement, cleanup arming, or membership state.
- Any broad deprecation modernisation beyond Batch C.
- Any device operation, reset or personal-data cleanup.
- Anything touching the invitation proposals.

---

## Appendix A — test run

```
xcodebuild test -project MOTIVO.xcodeproj -scheme MOTIVO -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MOTIVOTests -derivedDataPath <scratch>/dd-test
```

**`** TEST SUCCEEDED **`, exit 0. 537 test cases across 71 suites:
534 passed, 0 failed, 3 skipped.**

The three skips are deliberate and self-reporting — C-87's reproduction tests
guard with `XCTSkipUnless(exercised, …)`
(`MOTIVOTests/SyncQueueOrderingTests.swift:410`, `:433`, `:455`), so they
announce a non-exercised sequence rather than passing vacuously. **They are not
counted as passes here.**

This is a **useful baseline for a Phase 6 cleanup batch**: any of Batches A–E can
be validated against 534/534 with 0 failures at `2fd0f63`. Note that `CLAUDE.md`
records "49 tests" as of 2026-09-07 — that figure is stale by an order of
magnitude and is one more item for Batch F.

The suite is a deliberately narrow instrument — pure logic, policy tables and
source-text assertions. **It is evidence about what it asserts and not about
the surfaces in §1**, none of which it covers.

## Appendix B — Release deprecation census

Clean Release build, isolated derived data, `** BUILD SUCCEEDED **`.
**78 unique warnings: 77 deprecations + 1 benign AppIntents note. Zero errors,
zero non-deprecation compiler warnings.**

| Generation | Count | Dominant APIs |
|---|---|---|
| iOS 16 | 20 | `AVAsset.duration`, `.tracks(withMediaType:)`, `.naturalSize`, `.preferredTransform`, `exportPresets(compatibleWith:)` |
| iOS 17 | 27 | `AVCaptureVideoOrientation`, `videoOrientation`, `isVideoOrientationSupported`, `onChange(of:perform:)` |
| iOS 18 | 8 | `copyCGImage(at:actualTime:)`, `exportAsynchronously(completionHandler:)`, `AVAssetExportSession.status` / `.error` |
| iOS 26 | 22 | `Text` `+` concatenation, `UIScreen.main`, `AVMutableVideoComposition` family, `interfaceOrientation` |

By file: `VideoRecorderView.swift` 25, `MediaTrimView.swift` 14,
`MeView.swift` 3, `PostRecordDetailsView*.swift` 4,
`PracticeTimerView.swift` 3, `SessionDetailView.swift` 2, `CommentsView.swift` 3,
remainder single occurrences of `Text` `+` across row views.
