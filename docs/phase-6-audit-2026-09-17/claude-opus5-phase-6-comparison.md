# Études — Phase 6 audit: comparison table (Claude Opus 5 side)

**For merging with the other auditor's report.** One row per issue, with a
stable identifier, so the two reports can be aligned without either being
rewritten.

**Baseline:** `feature/solo-connected` @ `2fd0f63`. **Auditor:** Claude (Opus 5),
Claude Code, 17 September 2026. Full report:
`claude-opus5-phase-6-audit.md`. Scope and coverage limits:
`claude-opus5-phase-6-scope.md`.

> **Before merging, resolve the filename collision.** My three brief-specified
> filenames (`claude-phase-6-scope.md`, `-audit.md`, `-comparison.md`) were
> already occupied by another agent's output when I came to write. I did not
> overwrite or read them. Confirm which file belongs to which auditor first.

**Kinds:** `defect` confirmed defect · `risk` plausible risk needing a named
check · `gap` evidence gap · `drift` documentation drift · `cleanup` optional
cleanup · `decision` product/legal · `clean` checked and found sound.

---

## Findings

| Area | ID | Conclusion | Evidence (file:line) | Sev / Confidence | Kind | Existing ID | Required next check |
|---|---|---|---|---|---|---|---|
| Data integrity — Lists | **F-1** | **Deleting a saved List does not delete it.** A list saved from the Practice Timer pad is mirrored into a legacy per-context key; the Tasks manager deletes only the global key, then merges the mirror back and re-persists it | `PracticeTimerView.swift:966-974`, `:947-961`; `TasksManagerView.swift:1378-1389`, `:1157-1161`, `:1136-1152`, `:1163-1180`; mechanism named in `SavedList.swift:131-132` | P2 / high on mechanism and reachability; not device-confirmed | defect | new (adjacent to Lists `e656752`; dual-write predates it, `c29a1ed`) | 3-tap device repro in audit §F-1, with the "created in the manager only" control |
| Connected lifecycle — unshare | **F-2** | **The demote PATCH is not the authorisation probe its comment claims.** `Prefer: return=minimal` makes a zero-match PATCH answer 204, so an RLS-denied demote reads as success; `posts_update_owner` is gated while `posts_delete_owner` is not, so the "worst case is a private row" property is not delivered for a server-unentitled owner | `BackendShim.swift:1785-1789` (claim), `:1802-1826` (code); `NetworkManager.swift:261`; correct idiom already present at `BackendShim.swift:874` and `ConnectedAttachmentSharing.swift:335`; `policies.json` | P2 / high that the claim is false, medium on how often the bad state is reached | defect (in the stated property) | **C-61** | Local stack, failing-first: unentitled owner's demote must stop reporting success. **Do not weaken enforcement or manufacture membership state** |
| Performance — media | **F-3** | **Deprecated synchronous AVFoundation accessors run inside SwiftUI view bodies**, one beside a synchronous `Data.write`. Turns C-22 from a count into a cost and prioritises the sweep | `SessionDetailView.swift:1151-1160` (in `ForEach` at `:1137`); `PostRecordDetailsView+Attachments.swift:336-346` (write at `:340`), `:1220`; also `PracticeTimerView.swift:4677`, `:4806` | P2 / high on mechanism, magnitude unmeasured | defect | **C-22** (consequence), same class as **C-3** | C-3's method: `xctrace --attach` on Release, 0 vs 8 audio attachments |
| Audio — drone | **F-4** | **No automatic drone restart exists anywhere.** `start` has exactly two call sites, both the member's button. QA8's automatic recovery therefore means the route-change invalidation **did not fire**, not that a recovery path ran. Latent: a route change that *does* alter an output UID or sample rate stops the drone permanently, signalled only by the button | `DroneControlStripCard.swift:36`, `:227`; `DroneEngine.swift:235-254`, `:241-246`, `:213-216`, comment at `:248`; `PracticeTimerView.swift:1592-1594` | P3 / high | gap resolved + risk | **C-96** (its flagged unknown) | One unplug, watching the drone button's highlight; then repeat with headphones instead of the mic |
| Audio — drone guard | **F-4b** | **C-96's defensive equality guard is still not implemented**, and no loop was reproduced here either | `PracticeTimerView.swift:1592-1594` (unconditional assign); metronome twin at `:1586-1590` | P3 / certain | gap | **C-96** | None; unchanged status confirmed |
| Audio — architecture | **F-5** | **`AudioServices`'s recording path is dead** — `configureSession(for:)` is only ever called with `.playback`, so `.recording`, `.videoPreviewPlayback` and `applyPreferredInputForRecording()` are unreachable. The file header documents the live USB-input policy through code that never runs | `AudioServices.swift:39`, `:49-56`, `:86-114`, header `:1-8`; only callers `PracticeTimerView+AudioPlayback.swift:36`, `:78`; live policy at `RecordingInputPolicy.swift:29-48` and `VideoRecorderView.swift:1533-1536`, `:1558-1563` | P3 / high | cleanup + drift | new | Release build after deletion |
| Connected — storage | **F-6** | **A failed delivery leaves an orphaned storage object.** Upload precedes deliver on both the Lists and attachment paths; nothing sweeps the object | `ConnectedAttachmentShareUI.swift:593-627`; path built at `ConnectedAttachmentSharing.swift:215-222`; insert policy `connected_attachments_insert_sender` | P3 / high | defect | **B-8** class, new instance | Local stack: force a deliver failure, confirm residue |
| Cleanup | **F-7** | **15 unreferenced top-level types**, zero references outside their own declaration across 176 sources and 70 test files. Swift emits no warning for an unused `private` type | `BackendShim.swift:2110`; `CommentsView.swift:1080`; `ConnectedAttachmentSharing.swift:91`; `ContentView.swift:2920`, `:3009`, `:3075`; `ContentViewRowSupport.swift:80`, `:296`; `MediaTrimView.swift:285`; `PeopleView.swift:787`; `PostRecordDetailsView+Attachments.swift:1329`; `ProfilePeekView.swift:442`, `:479`; `ProfileView.swift:166`; `TasksManagerView.swift:1436` | P3 / high | cleanup | new | Release build + unit suite |
| Cleanup | **F-8** | **`shouldResumeAfterRouteChange` is written twice and never read.** Its two siblings are read | `VideoRecorderView.swift:451`, `:1682`, `:1685` | P3 / certain | cleanup | new | Build |
| Architecture | **F-9** | **`SimulatedPublishService.deletePost` makes three live production calls** — a GET, storage DELETEs and a row DELETE — with the member's real bearer token. Four of the class's five methods are genuine stubs | `BackendShim.swift:323`, `:333-398`; selection at `:2444-2452`; token at `NetworkManager.swift:226-228` | P3 / high mechanism, no harm demonstrated | cleanup | new | Confirm nothing depends on delete working in `.local` mode |
| Records | **F-10** | **`AGENTS.md` is an untracked, silently divergent copy of `CLAUDE.md`**, missing the B-39/scope-011 deployment record, the 2026-09-17 invitation and teen-contact entries, C-34's scope correction and C-52's second recurrence. **Live hazard: it is the file a Codex-family agent reads by convention, during this very comparison** | `AGENTS.md` 196,311 B vs `CLAUDE.md` 203,137 B; diff | P2 / certain | drift + process | new | **Samuel's decision:** symlink, delete, or track |
| Records | **F-11** | **Three stale claims inside `CLAUDE.md`:** (1) the opening Phase 3 section says the cleanup worker is **v6**; it has been **v7** since 2026-09-15 and the same file says so at `:979`; (2) the CP-3 blocker about a hard-coded `lookupEnabled: true` is resolved; (3) the `AuthManager:596` reference is now `:804-807` (behaviour unchanged) | `CLAUDE.md:23` vs `:979` and `README-b39-scope011-deployment-results.md:23`; `AccountDirectoryService.swift:367-374`; `AuthManager.swift:804-807` | P3 / certain | drift | new | None — editorial |
| Records | **F-12** | **C-22's count is stale: 53 → 77 unique deprecations** (20 iOS 16, 27 iOS 17, 8 iOS 18, 22 iOS 26) | Clean Release build census, audit Appendix B | P3 / certain | drift | **C-22** | None |
| Audio/video | **F-13** | **Video recording stops on USB unplug, where audio recording recovers.** Same notification, opposite response; no device evidence either way | `VideoRecorderView.swift:1679-1687` vs `AudioRecorderView.swift:734-744` and `RecordingInputPolicy.swift:31` | P3 / high on source, untested on device | gap | adjacent to **C-97** | One video take with the CM-15, unplugged mid-take |
| Audio/video | **F-14** | **C-97 part (2) confirmed untouched.** The video recorder registers four observers and none of them is capture runtime-error, capture interruption or media-services reset; no missing-audio watchdog. The audio recorder has all three classes | `VideoRecorderView.swift:1616-1633`; contrast `AudioRecorderView.swift:686-691` and `AudioRecorderEvents.swift:8-14` | P3 / certain | gap | **C-97** | None. **Does not reopen QA7** — a successful ordinary take is not evidence of fault handling |

## Carried findings reconciled

| Area | ID | Conclusion | Evidence | Kind | Next check |
|---|---|---|---|---|---|
| Client | **C-12** | **Still open, confirmed at HEAD.** `showDeleteConfirm` is declared and read but **never set true**, so the alert never presents and `deleteSession()` is unreachable | `SessionDetailView.swift:203`, `:866`, `:1786` | defect | Decide: wire the confirm, or delete both |
| Client | **C-15** | **Still open, narrowed.** The store is live at 19 sites and does clear on one path and migrate on another; completeness of collection not established here | `PostRecordDetailsView+Attachments.swift:669`, `:775` | defect | Not assessed this pass |
| Client | **C-41** | **Outstanding half confirmed.** Writer deployed and client-wired; **no UI reaches it**, so a 13–17 member cannot opt in | `AccountPrivacyService.swift:185`; `functions.json` | decision | Product/legal call |
| Client | **C-102 / C-103** | **Unchanged, neither advanced nor contradicted.** C-103's deciding state is device-local Core Data, which this pass did not read | — | gap | Unchanged |
| Backend | **B-34** | Unchanged. Note for the record: **`shadow_enforcement_stat` is not dead** — `enforcement_gate` still writes to it on every gated call | `functions.json` | gap | Unchanged |
| Backend | **B-38** | **Confirmed present.** `authenticated` holds INSERT/UPDATE on `account_directory.avatar_version`; the stamping trigger is `BEFORE UPDATE OF avatar_key`, so a version-only PATCH is not re-stamped | `column_grants.json`, `triggers.json` | defect | Unchanged; a production privilege change needs its own scope |
| Backend | **Grandfather retirement** | **Completed as designed.** `membership_cutover` gone; `membership_control.cutover_at`, `.cutover_identity_count`, `.cutover_verified_at` now dead columns, exactly as predicted | `columns.json` | cleanup | Guarded DDL + B-23, separate authorisation |

## Checks that came back clean

Listed so the other report's silence on them can be read correctly — each is a
property a future change could break silently.

| Area | ID | Conclusion | Evidence |
|---|---|---|---|
| Connected privacy | **N-1** | **A recipient cannot repoint an inbox row at another member's storage object.** `authenticated` holds table-level UPDATE on every `connected_attachments` column and the policy's `WITH CHECK` pins only `recipient_user_id` — but the `connected_attachments_recipient_update_guard` trigger raises on any change to identity or payload metadata, and the `connected_attachments_sender_storage_path` CHECK is an independent second lock | `functions.json` (`enforce_connected_attachment_recipient_update`), `triggers.json`, `constraints.json`, `policies.json`, `column_grants.json` |
| Performance | **N-2** | **All 23 `enforcement_gate` references are wrapped `(select …)`; zero bare** — programmatically re-verified across all 33 policies. U6a measured the bare form at 278 ms vs 3.9 ms, and both forms are functionally correct, so this can only regress silently | `policies.json`, parsed |
| Video | **N-3** | **The 5-second writer watchdog does not double-complete.** `completed()` is called unconditionally and does run twice on a normal finish, but `assetWriter` is nil'd at `:1325` and both call sites guard on `assetWriter === writer` | `VideoRecorderView.swift:1254`, `:1271-1275`, `:1325` |
| Connected UX | **N-4** | **A send sheet cannot be dismissed mid-send**, so a delivery failure always has somewhere to report itself | `ConnectedAttachmentShareUI.swift:181` |
| Logging | **N-5** | **No credential or user content is logged in Release.** 92 `print` calls sit outside `#if DEBUG`; none interpolates a title, note, display name, email, token or response body. All 15 `NetworkManager` prints, including the `[SignedURL]` groups, are DEBUG-guarded | scripted `#if` nesting analysis + review |
| Release engineering | **N-6** | **The cleanup workflow on `main` is byte-identical to the branch copy**, so the "default branch only" arming gate holds as the record claims | `git diff main:… HEAD:…` → empty |
| Data | **N-7** | **Erase All removes saved Lists, including adopted copies** — the whole `UserDefaults` persistent domain is removed | `LocalFactoryReset.swift:51-56` |
| Data | **N-8** | **`LocalFactoryReset.perform` still has exactly two production callers** — the Phase 3 exit assertion holds | `ProfileView.swift:1846`, `:1919` |
| Membership | **N-9** | **`posts_delete_owner` is deliberately ungated**, so a lapsed member can still delete their own posts without re-subscribing — C-35's rule holding in the deployed policy | `policies.json` |
| Lists | **N-10** | **The deployed Lists constraints and the client agree exactly** — `.etudeslist` extension, `page_count = 0`, and `byte_count ≤ 131072` matching `ConnectedListPayload.maxBytes` | migration, `constraints.json`, `ConnectedListSharing.swift:18`, `ConnectedAttachmentSharing.swift:360-362` |
| Lists | **N-11** | **List adoption is owner-scoped on both sides of the await** — the scope is captured before the download, re-checked after, and re-checked again before the write | `ConnectedAttachmentShareUI.swift:858-866`, `:877-880` |
| Build / tests | **N-12** | **Release builds clean** (0 errors, 0 non-deprecation warnings) and **the unit suite passes: 534 passed, 0 failed, 3 deliberate self-reporting skips, across 71 suites**. `CLAUDE.md`'s "49 tests" is stale | audit Appendices A and B |

---

## Merge guidance

**Where the two reports agree**, take the union of the evidence — my references
are line-anchored to `2fd0f63` and should merge without translation.

**Where they disagree**, three of my findings rest on facts that are cheap to
re-check and should be settled by re-checking rather than by argument:

- **F-2** depends on PostgREST answering **204 to a zero-match PATCH** under
  `Prefer: return=minimal`. This project measured that for itself during C-43.
  If the other report disputes it, the local stack settles it in one request.
- **F-4** depends on `DroneEngine.start` having **exactly two call sites**. That
  is a grep, and it is the whole argument.
- **F-1** depends on `legacyTaskSetKeysForMigration()` generating the same key
  shape `PracticeTimerView.currentContextTaskSetsKey` writes. Compare
  `TasksManagerView.swift:1178-1180` with `PracticeTimerView.swift:842-846`.

**Where only one report has a finding**, check the other's coverage limits before
treating silence as disagreement. Mine are in
`claude-opus5-phase-6-scope.md` §3 — in particular I ran **no device, no live
backend and no running app**, so anything requiring those is absent from my
report by construction rather than by conclusion.

**One item should be actioned before the comparison rather than after: F-10.**
If the other auditor read `AGENTS.md` instead of `CLAUDE.md`, some of its
conclusions rest on a record that predates two production deployments.
