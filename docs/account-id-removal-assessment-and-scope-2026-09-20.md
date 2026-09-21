# Account ID / @handle — assessment and proposed removal scope

**Revision 2, 20 September 2026.** Claude, read-only. Revised against Codex's scope review;
**seven corrections accepted in full**, and one further hazard found while checking them (§8.1)
that neither party had raised.

**Read at `05ad6a8`.** `HEAD` and `origin/feature/solo-connected` both
`05ad6a8cc470bf2dfb5e1e5733fca45174c1008b`, zero ahead / zero behind. Working tree carries the
untracked Phase 6 / audit documents and two modified invitation documents; **none was modified
by this work.**

**No implementation, commit, push, production query, schema change or device action has been
performed.** SQL statements describe the checked-in migration text and the committed
`supabase/schema/` snapshot. Production row counts are **B-37's recorded measurement**, not a
query run in this window.

**Status: CODEX LOCAL IMPLEMENTATION ACCEPTANCE GRANTED, 20 September 2026, at the 18 source +
8 test hashes in the evidence manifest. SAMUEL'S FINAL SIGN-OFF IS PENDING.**

**Uncommitted. Unpushed. No production, schema, credential or device action. NO device QA and
NO rendering acceptance — the structural tests prove WIRING only. PHASE 6 REMAINS OPEN, and
this unit closes nothing.** No further source or test changes and no reruns; the bytes are
fixed.

**Codex's evidence qualification:** it read the positive-control transcripts and **did NOT
independently verify the original control runs**. Pruned bundles and transcribed output are
weaker evidence and are not interchangeable with the final bundle. **Acceptance rests on the
final reproducible tests and builds, the reviewed production wiring and the fixed hashes.**

**Evidence record: `docs/account-id-removal-evidence-2026-09-20.md`.**
**Artifact directory: `/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/c657c407-b562-4523-b151-9170cc9ae8a2/scratchpad/evidence/`** (session-scoped; the evidence record reproduces the
accounting in full so nothing depends on it surviving).

**Headline results:** full `MOTIVOTests` **1000 passed / 0 failed / 6 skipped**; Debug and
Release both SUCCEEDED; warning delta attributable to this change **zero**, by attribution.
Five positive controls each applied, observed failing, and restored by hash.

**Two boundary corrections, both recorded rather than tidied:** a first targeted selection
silently matched nothing for three classes because it named a FILE (superseded by a corrected
12-class run), and a **sixth** existing test file, `C70WiringPinTests.swift`, was outside the
reviewed boundary and failed the first full run — converted with Codex's approval. **The
boundary is therefore 18 source files and 6 existing test files, plus 2 new test files.**

**Approved by Codex, 20 September 2026, for bounded local implementation under
Samuel's overnight delegation.** Codex read the complete revision and
independently verified the source delimiters, the setup freshness path, the eight handle
subtitle sites and the five non-handle overrides. **Approval is for local implementation only:
no commit, no push, no production statement, no device action, and Samuel signs off at the
end.** Codex's clarifications are folded in at §0.1 and applied throughout.

---

## 0. What changed in this revision

| # | Codex correction | Disposition |
|---|---|---|
| 1 | Retained server search is not inert; don't claim global elimination | **Accepted.** §6.1 rewritten; three overclaims withdrawn in §5 |
| 2 | An invitation token proves possession, not intended-person identity | **Accepted.** "Strictly better" withdrawn; §2.3 rewritten |
| 3 | 17 source files, not 14; name test and new files; include CommentsView | **Accepted.** §7.1, §7.3, §9. My 14+3 split was a presentational dodge and is corrected |
| 4 | Preserve non-handle override subtitles; bound the formatter; widen tests | **Accepted.** §7.2 — **five** non-handle call sites found and listed by line |
| 5 | Keep setup freshness and all C-70 guards; explain any guard removed | **Accepted, and it is not the pure redundancy it looks like** — §7.4 |
| 6 | Don't rerun the unchanged baseline | **Accepted and independently verified:** `d0d7812` and `05ad6a8` are docs-only |
| 7 | Classify every affected test; no hiding coverage in a total | **Accepted.** §9, by test name |

**Also corrected without being asked: there are eight handle subtitle call sites, not seven.**
Codex is right and my first revision miscounted. The eighth is `FollowingListView.swift:449`,
a second list in the same file.

### 0.1 Codex clarifications folded in at approval — applied, not merely recorded

1. **A source-reading test proves WIRING, not rendering.** Every structural assertion in §9.5
   and §8.1 inspects source text. It establishes that a call site passes what it is supposed to
   pass; it does **not** establish that SwiftUI rendered anything. Described that way
   throughout, and the word "renders" is not used of a source-reading test.
2. **§9.3 mixed tests with a helper.** Of its seven entries, **six are tests** and one
   (`row(...)` / `selfRow(...)`) is a **fixture-helper edit**. Final accounting separates them,
   and **the three Coordinator conversions required by §8.1's re-anchoring are counted
   explicitly** rather than folded into the helper line.
3. **Discovery statements stay conditional.** Knowing a handle does not guarantee finding
   anyone: `search_account_directory` still requires an authenticated caller, subject
   entitlement under `enforcement_active()`, and `account_privacy_discoverable`. Every
   enumeration statement in §6.1 is conditional on those gates.
4. **Requests are not approved relationships.** §4's disclosure paragraph is corrected: the
   People → Requests row shows a **pending, unapproved** inbound request, so it is not an
   "already-approved-relationship context".
5. **All row counts are dated evidence.** B-37's 14-of-14 against 17 rows is a measurement of
   its own date, not a present-day census.
6. **The @ mismatch and handle matching remain callable.** The new client still forwards
   arbitrary search text to the unchanged RPC, so a member typing a handle still matches the
   handle branch, and typing `@handle` still misses it. **No global resolution is claimed and
   no fix is attempted in this unit.**
7. **Positive controls run on isolated disposable copies or carefully restored local
   mutations, with no overlapping build.** Each intentional failure and its restoration is
   recorded, and acceptance runs against the final restored bytes.
8. **No catch-all test deletion.** Classification, evidence and coordinator surfaces are kept
   unless §9 scopes them out by name.

---

## 1. Recommendation

**Remove the user-facing handle, client-side only, and ship a replacement subtitle in the same
unit.** Leave the `account_id` column, its constraints, its RPC output and the
`search_account_directory` handle branch exactly as deployed.

**The replacement subtitle is a condition. If it is cut, I do not recommend proceeding** (§4).

---

## 2. What handles actually do

### 2.1 Live functionality — four things

| # | Function | Where |
|---|---|---|
| **F1** | A search axis: `lower(account_id) like token \|\| '%'` — a **prefix** match, where `display_name` and `instruments` are substring matches | `20260920130000_b37_literal_search_and_budget.sql:287` |
| **F2** | The only secondary line in a people row, at **eight** call sites | `PeopleUserRow.swift:93-99` + §7.2 |
| **F3** | A sort tiebreaker in two follower lists and the server's `order by account_id nulls last` | `ContentViewRowSupport:638`, `SessionDetailView:2191` |
| **F4** | A line on the profile preview and the avatar viewer | `ProfilePeekView:161, 204, 338` |

**F2 is load-bearing and easy to miss.** `PeopleUserRow.subtitle` falls back to
`ProfileStore.location(for: userID)` when no override is passed — but `setLocation` is only
ever called for the owner's own backend ID or `nil` (`ProfileView:1646, 2497, 2515`;
`AuthManager:830`; `ProfileStore:203, 268`). That fallback therefore resolves to `""` for every
other member. **In practice the row is `Name` + `@handle`, or `Name` and nothing.**

### 2.2 What they do not do — verified

- **No authority.** `account_id` appears in no foreign key, no RLS policy, and exactly two
  functions. Checked against `constraints.json`, `policies.json`, `functions.json`. Ownership,
  follows, posts, comments, shares and permissions are UUID-keyed and stay so.
- **Already optional.** `account_id` is `is_nullable: YES`; B-37's sweep reached **14 of 14**
  by the handle branch against **17** rows, so three production rows already carry NULL. A
  handle-less member is an existing rendered state.
- **Mentions do not use them.** `CommentsView` regex-matches `(?<!\w)@[A-Za-z0-9_\.]+` in free
  text, styles it, and on tap shows an alert reading *"Mention tapped. Future: open profile or
  start reply with …"*. It never consults `account_directory`.
- **No links.** No URL schemes, no `onOpenURL`, no associated domains.
- **No invitation implementation.** Two copy strings and three unrelated comments.
- **Not stable.** A rename releases the old value for reuse; no alias history, no interval.
- **Silently unavailable for non-Latin names.** `autoAccountIDBase` folds then filters to
  `[a-z0-9_]` and requires ≥3 characters, so many names yield `nil` with no fallback.

### 2.3 Invitations — left unresolved, deliberately

`docs/private-connection-invitations-scope-2026-09-17.md` (unauthorised, unapproved and
**protected — not modified here**) uses the account ID for recipient confirmation.

**Revision 2 withdraws the claim that an opaque token would be "strictly better".** Codex is
right: **a token establishes possession of the link, not that the holder is the intended
person.** Neither mechanism establishes intended-person identity on its own; a handle adds a
human-checkable string, a token does not. **Removing handles constrains that design space, and
this document does not resolve it.** Invitation design remains open, protected, and outside
this unit. Stated as a consequence for Samuel to weigh, not argued away.

---

## 3. Dependency trace

### 3.1 Database — untouched in full

`account_id` (nullable), `account_directory_account_id_key` (UNIQUE), `account_id_format`,
`account_id_lowercase`, `search_account_directory`, `get_account_directory_by_user_ids`.
**No policy, foreign key, trigger or grant references the column.** Nothing here changes.

### 3.2 Client — generation, write, storage

Generation (`autoAccountIDBase:178`, `autoAccountIDCandidate:189`,
`autoGenerateAccountIDIfMissing:776-859`, `performGenerationWrite:876+`), the sanitiser
(`:164`), the payload key and its two parameters (`:526-528`, `:665`), setup-time generation
(`AppSetUpView:375-396`), the background backfill with its three state vars and two reset
blocks (`AuthManager:257-259, 639-681, 1338-1341, 1395-1398`), the handle in the snapshot
republish (`AuthManager:833-844`), handle hydration (`AuthManager:748-749, 773-774`), and the
local accessors (`ProfileStore:150-165`).

**`ProfileStore.accountIDKey` and its removal inside `purge` at `:371` are retained**, so an
upgraded device still clears the legacy key on factory reset.

### 3.3 Client — editing and display

`ProfileView` field block (`:766-813`), `normalizeAccountID` (`:1718-1726`), `accountIDText`
and its assignments (`:393, 1291, 1364, 2017, 2280, 2366, 2539, 2544`), the generation trigger
and its two state vars (`:420-421, 1962-2019`), the snapshot field (`:1776, 1786-1788, 1804,
1903`); the eight subtitle sites; `ProfilePeekView`'s three renders and its
`directoryAccountID` parameter with its seven passing sites; the two handle sort tiers.

### 3.4 Copy

`ProfileView:774` (field label), `:159` (`"Allow handle lookup"`), `:1032` (discovery
explanation), `DirectorySyncFailure:52` (collision copy — §6.2). `PeopleView:516` already reads
*"Search by name or instrument"* and needs no change.

### 3.5 `DirectoryWriteOutcome.swift` needs no edit — stated so the count can be checked

It contains eight `account_id` references and **none requires changing**.
`expectation(from:)` derives `.accountID` **only when the payload carries the key**
(`:187`), and `matches(_:_:)` compares only derived fields — the file's own comment already
says an omitted key asserts nothing. With the key never sent, the machinery degrades correctly
by construction. **This is why the file is absent from the 17.**

---

## 4. What members lose

**Verified:**

- **Searchable:** `display_name` (substring), `instruments` (substring), `account_id` (prefix).
- **NOT searchable: location.** Returned and rendered; never matched. Stated flatly because the
  direction note could be read as assuming otherwise.
- **Visible in a search row today:** avatar, display name, `@handle` — **not** instruments,
  **not** location.
- **Visible on `ProfilePeekView`:** avatar, name, handle, location, Instruments section.

**The loss is real and narrow.** Two members called *Sam Dixon* are today distinguished only by
`@samueldixon` and `@samueldixon2`, because the allocator derives from the name and appends
2…10. That tells you the rows are different accounts; it does not tell you which is your
teacher.

**Meanwhile instruments and location are already fetched on every search response and
discarded.** The handle occupies the slot where the recognisable information would go. Removing
it and rendering that information makes those rows better than today and repairs the dead
`ProfileStore.location(for:)` fallback.

**Disclosure delta, named.** Of the eight sites, seven are already-approved-relationship
contexts (followers, following, requests, follower pickers, Connected-people picker). Only
`PeopleView:567` search results are stranger-facing, and there the subject has opted into
discovery, is entitled, and already has location and instruments in the same payload, rendered
one tap later. **The payload does not change; only how early it renders.** Codex remains free
to scope the subtitle to non-search rows.

---

## 5. Why remove — with three overclaims withdrawn

**Withdrawn from revision 1, per Codex correction 1:**

- ~~"retires one enumeration axis"~~ → **It does not.** Existing handles remain in the table and
  remain matched by the unchanged branch under unchanged B-37 gates and budgets. What changes is
  only that the new client stops **generating, writing and displaying** them, so no *new* values
  are published and the app stops teaching members their handles.
- ~~"retires a unique-namespace obligation"~~ → **Not globally.** The UNIQUE constraint and the
  existing values persist, so squatting and reuse questions are **deferred**, not retired. They
  would only be retired by a later server decision this unit does not take.
- ~~"resolves Codex findings 1–4 by construction"~~ → **Only for the new client.** Findings 1–4
  cease to be reachable through new-client behaviour; they remain live for any old client still
  installed, and finding 5 (rename/reuse policy) is deferred rather than answered.

**What genuinely stands:**

1. It removes an entire client lifecycle — generation, the ten-candidate allocator, the
   backfill, collision handling, cross-device republication — whose four open findings all live
   in that lifecycle.
2. It removes the silent non-Latin-name failure from the shipping path.
3. It matches the product. `ConnectedIntroductionView` promises *"No likes. No public follower
   counts. No engagement algorithms."* An `@handle` is the one piece of social-network grammar
   in the app.
4. It puts recognisable information where a member actually chooses a person (§4).

**Against — the one honest argument:** the handle is today the only per-row disambiguator. §4
answers it, and the answer is a condition on the scope rather than a reason to retain.

**Where I hold:** if the subtitle replacement is cut, I do not recommend proceeding.

---

## 6. Compatibility

**No column dropped, no constraint dropped, no migration, no production statement.** Dropping
the column is neither necessary nor safe to decide here and is not proposed.

### 6.1 The retained server branch is **not inert** — corrected

Codex is right and revision 1 was wrong to call it inert. Precisely:

- The `account_id` prefix branch stays live and continues to match the **existing** stored
  handles, under **unchanged** B-37 escaping, tab/empty-token closure, and the 10-per-60s /
  120-per-60min budget.
- **Anyone who already knows a handle can still find its owner**, and systematic enumeration by
  handle prefix remains possible within those budgets, exactly as today.
- Old clients continue to display handles and so continue to teach them.
- **What this unit changes is the publication rate, not the exposure of what is published.**

Removing the branch, or NULLing the column, is a **separate later server unit** with its own
rehearsal, guards and rollback, and is explicitly out of scope.

### 6.2 Decisions

| Concern | Decision |
|---|---|
| `account_id` column and constraints | Retained; existing values retained |
| `search_account_directory` | Unchanged — see §6.1 |
| `get_account_directory_by_user_ids` | Unchanged; keeps returning `account_id` |
| `DirectoryAccount.accountID` + `CodingKey` | **Retained.** The RPCs still return it; removing the key would be a needless compatibility risk. It becomes decoded-but-unrendered, and one test pins that |
| `DirectoryWriteEvidence.selectedColumns` | **Retained unchanged**, including `account_id`. One list builds `select=` and requires response keys; churning it moves C-70's evidence machinery for no gain (§3.5) |
| `.accountIDTaken` classification | **Retained.** The unique constraint is live and an old client can still collide, so the classifier keeps attributing correctly rather than degrading to `.failed`. **Its user-visible message becomes the neutral non-attributing copy**, because the new client has no Account ID field — C-70(a)'s own rule applied consistently |
| Older installed clients | Never publicly released (CLAUDE.md; B-36), so this is the known Release installs. An old client keeps displaying and republishing its cached handle. **No clobber is introduced:** the new client never sends the column and PostgREST leaves an unsent column untouched |
| Local `profile.<uid>.account_id_v1` | Unread after upgrade; still purged by `ProfileStore.purge` |
| `order by account_id nulls last` | Unchanged; tends toward `user_id`, which is stable and never rendered |

---

## 7. Scope

**Client-only. One unit. No SQL, migration, policy, grant, production statement, device run,
commit or push.**

### 7.1 Boundary — exactly 17 source files, 18 with CommentsView

| # | File | Change |
|---|---|---|
| 1 | `AccountDirectoryService.swift` | Remove generation, allocator, sanitiser, generation write, the `account_id` payload key and the `accountID:`/`includeAccountID:` parameters. Keep `DirectoryAccount.accountID` |
| 2 | `AuthManager.swift` | Remove backfill, its 3 state vars, its 2 reset blocks, the republished handle, handle hydration |
| 3 | `AppSetUpView.swift` | §7.4 |
| 4 | `ProfileStore.swift` | Remove the two accessors; keep `accountIDKey` + the `purge` line, commented as legacy cleanup |
| 5 | `ProfileView.swift` | Remove field block, `normalizeAccountID`, `accountIDText`, generation trigger and state, snapshot field, two copy strings. **Keep `:841`'s `directorySyncMessage` block, `localStorageIsUsable`, Retry, reset and identity guards, and the scoped `authChallenge` at `:1914`** |
| 6 | `PeopleUserRow.swift` | Add the pure `DirectorySubtitle` formatter (§7.2) and use it as the fallback |
| 7 | `PeopleView.swift` | Two handle sites (`:452, :567`); **preserve `:273, :303, :365`** |
| 8 | `FollowersListView.swift` | `:89`; drop `directoryAccountID:` at `:96` |
| 9 | `FollowingListView.swift` | Two handle sites (`:136, :449`); **preserve `:241`**; drop `directoryAccountID:` at `:143` |
| 10 | `ContentViewRowSupport.swift` | `:730`; drop the handle sort tier `:638-643` |
| 11 | `ContentViewSessionRow.swift` | Drop `directoryAccountID:` `:882` |
| 12 | `ContentViewRemotePostRowTwin.swift` | Drop `directoryAccountID:` `:518` |
| 13 | `SessionDetailView.swift` | `:2248`; drop the handle sort tier `:2191-2199` |
| 14 | `BackendSessionDetailView.swift` | Drop `directoryAccountID:` `:274` |
| 15 | `ConnectedAttachmentShareUI.swift` | `:394`; **preserve `:458`** |
| 16 | `ProfilePeekView.swift` | Remove three `@handle` renders and the `directoryAccountID` property/parameter |
| 17 | `DirectorySyncFailure.swift` | Neutralise the collision message; keep the classification |
| 18 | `CommentsView.swift` | §7.3 |

**No new source file**, deliberately: the formatter is a file-level `public enum
DirectorySubtitle` inside `PeopleUserRow.swift`, which keeps it pure and unit-testable without
a view while holding the boundary at exactly the count Codex stated. If Codex prefers a
separate file, that is an 18th/19th file and a one-line change to this table.

### 7.2 The subtitle formatter

**Consumes only `DirectoryAccount.instruments` and `DirectoryAccount.location` as returned.**
No new fetch, no discovery gate, no location search, no owner-local fallback for another
person, no fabricated value.

Rule: trim every instrument, drop blanks, take the **first two** non-empty instruments joined
by `", "`, append `" +N"` when more remain; then location, trimmed, dropped when blank; join
the two parts with `" · "`. **All-empty yields `""`, so the row has no second line to show** —
which is already today's behaviour for the three NULL-handle rows, not a new state.

**The eight handle sites pass the formatter. The five non-handle overrides are untouched:**
`ConnectedAttachmentShareUI:458` (recipient count), `PeopleView:273` (attachment name), `:303`
("Shared a post"), `:365` (response post subtitle), `FollowingListView:241` (ensemble member
count).

### 7.3 CommentsView — bounded completion, included

Remove the placeholder mention affordance: the tokeniser and `mentions(in:)` (`:294-334`), the
styled rendering (`:416-441`), the chip rows (`:1174-1186`, `:1293-1305`), the `tappedMention`
state (`:57`) and the alert (`:548-552`).

**The stored comment text is unchanged** — no migration, no rewriting, no stripping. A comment
containing `@someone` still displays that text verbatim, as plain text. **Ordinary reply,
composer, target selection, send, actions and accessibility labels are untouched**; only the
mention-specific `accessibilityLabel("Mention …")` on the removed chips goes with them.

### 7.4 `AppSetUpView` — and why one guard removal is not pure redundancy

**Keep:** `upsertSelfRow` (minus `accountID:`), `mayApplyEffects`/`isFresh`, and the
`ConnectedSetupDecision.next` switch with all three branches. **Remove:**
`autoGenerateAccountIDIfMissing`, the second `identityGeneration == capturedGeneration` guard,
and the adoption block.

**`capturedGeneration` then has no remaining reader** — `mayApplyEffects` is passed
`result.generation`, not `capturedGeneration` — so leaving it produces an unused-value warning.
It is removed, and the explanation is that it existed **solely** to re-establish freshness
across the *second* await, which no longer exists.

**This is not purely redundant, and the scope says so rather than discovering it in review.**
`C70DirectoryWriteCallerPolicyTests.testOnCompleteIsReachedOnlyPastTheGuards` anchors on that
exact string preceding `onComplete()`. **The protection survives** — with one await left,
`mayApplyEffects` plus the `.abandonSilently` branch already stand between the write and
`onComplete()` — **but its expression changes, so the test is converted, not retired** (§9).

---

## 8. Risks

### 8.1 Highest risk, found while checking Codex's review, raised by neither party

**Three surviving C-70 protection tests use the removed function's NAME as a source-text
delimiter.** `C70DirectoryWriteCoordinatorTests.syncBody()` (`:352-357`) bounds its extract
with `"private func attemptAccountIDAutoGenerationIfNeeded"`. Remove that function and
`syncBody()` returns `""`, failing
`testEveryUIEffectSitsBehindBothFreshnessGuards`,
`testTheSkipTokenIsConfirmedOnlyOnAnEvidencedWrite` and
`testTheSkipTokenIsInvalidatedWhenADifferingWriteIsSubmitted`.

**The failure mode that matters is not the red test — it is the careless repair.** Widening the
extract or deleting the guard would make three real C-70 protections pass vacuously.

**Proposed handling:** re-anchor the end marker to
`"private func persistAvatarToBackendIfPossible"`, the next function after removal; **and prove
non-vacuity for all three by demonstrating each still fails when its guard is removed from
`ProfileView`.** A re-anchored protection test is a protection test that has been edited, and it
is offered to Codex as such.

### 8.2 Others

| Risk | Handling |
|---|---|
| Removing the field also removes C-70's failure surface | `:841` is a **separate** `mayShowMaintenanceSurface` block from `:766`. A test pins that the sync-message BLOCK is still WIRED (source text); it does not establish that SwiftUI drew it |
| A non-handle subtitle is swept up | Five sites listed by line in §7.2; a test asserts each call site still PASSES its own string (source text), not that it was drawn |
| Subtitle widens disclosure on search results | §4. Payload unchanged; render moves one screen earlier. Codex may scope it narrower |
| "Handles removed" later read as "column dropped" | §6 is explicit and the unit writes no SQL at all |

---

## 9. Tests — explicit classification

### 9.1 Retire with the feature — **5**, each with its surviving coverage named

| Test | Why | What still covers the underlying protection |
|---|---|---|
| `C70DirectoryWriteTransportTests.testGenerationWritesOnlyTheHandleAndOnlyWhileItIsAbsent` | subject removed | — (the behaviour ceases to exist) |
| `…TransportTests.testGenerationStopsSilentlyWhenTheFilterMatchesNothing` | subject removed | — |
| `…TransportTests.testGenerationRetriesOnlyOnAnEvidencedHandleCollision` | subject removed | — |
| `C70DirectoryWriteEvidenceTests.testGenerationExpectsOnlyTheHandle` | subject removed | `testOmittedKeysAreNotCompared` keeps the omission rule |
| `C70DirectoryWriteCallerPolicyTests.testHandleAdoptionAfterGenerationIsGuardedAgain` | subject removed | `testTheSetupTailConsumesFreshnessAndNotJustTheOutcome` + the converted `testOnCompleteIsReachedOnlyPastTheGuards` |

**Declared coverage loss, not hidden in a total:** the three Transport tests exercised a
network-shaped behaviour that ceases to exist, so their coverage is **genuinely removed rather
than relocated**, and nothing replaces it. That is correct for a removed feature and is stated
plainly.

### 9.2 Retire, its generic sibling named — **1**

`C70DirectoryWriteCoordinatorTests.testHandleAdoptionIsGuardedAgainstNewerIntentAndIdentity`
inspects `attemptAccountIDAutoGenerationIfNeeded`, which is removed. The generic protection —
every UI effect behind both freshness guards — is held by
`testEveryUIEffectSitsBehindBothFreshnessGuards`, **which is itself being re-anchored (§8.1)
and must therefore be demonstrated non-vacuous in the same run.**

### 9.3 Convert — **7**

| Test | Conversion |
|---|---|
| `…TransportTests.testAnExistingRowEditIsAnOwnerBoundPatchAskingForEvidence` | extend: **the PATCH body carries no `account_id`** |
| `…TransportTests.testNothingMatchedFallsThroughToGatedCreation` | extend: **the missing-row creation body carries no `account_id` either** |
| `…TransportTests.testANamedHandleCollisionIsTypedAndKeepsItsOwnCopy` | drop the removed `accountID:` helper argument; assert the 23505 is **still typed** `.accountIDTaken` and that its copy now **names no field** |
| `…TransportTests` helpers `row(...)` / `selfRow(...)` | keep the `accountID:` fixture parameter — it models the **server's** response, which still carries the column |
| `DirectorySyncFailureTests.testCollisionKeepsItsOwnCopy` | re-expressed: classification preserved, copy neutral |
| `DirectorySyncFailureTests.testNoNonCollisionFailureNamesTheAccountID` | strengthened to **no** failure naming the field |
| `C70DirectoryWriteCallerPolicyTests.testOnCompleteIsReachedOnlyPastTheGuards` | re-anchored to the surviving freshness decision (§7.4) |

### 9.4 Stay unchanged — the protections that must survive

All four scoped-401 tests (`…TransportTests:295, 311, 325, 337`); every identity, generation and
sequence guard (`:352, 442, 455, 474, 493`); the evidence machinery (`:404, 412, 422, 432`);
`testNoPrivacyOrAvatarColumnIsSentOrRequested:214`;
`EvidenceTests.testSelectListAndRequiredColumnsShareOneDefinition:95`; the remaining Coordinator
and CallerPolicy suites; the remaining nine `DirectorySyncFailureTests`.

### 9.5 New — two files

| File | Contents |
|---|---|
| `MOTIVOTests/DirectorySubtitleTests.swift` | The four presence cases; **whitespace-only instruments and location**; **non-Latin instruments and locations**; **one, two, three and many instruments** with the `+N` bound; a very long instrument name; ordering stability |
| `MOTIVOTests/AccountIDRemovalTests.swift` | A structural guard that no generation entry point, handle render site or handle write site survives (in the style of `C5f-12`, `U8-A1`); a **compatibility** test that an RPC payload still carrying `account_id` decodes without error; a test that each of the five non-handle overrides still PASSES its own string; a test that `:841`'s sync-failure block is still wired. **All of these read source text and prove WIRING, not rendering.** |

**The behavioural payload assertions go into the existing `C70DirectoryWriteTransportTests`
rather than a new file**, because that suite already drives `upsertSelfRow` through a stubbed
transport and therefore exercises **real production payload construction**, which is what Codex
asked for.

### 9.6 Positive control

**One, meaningful, named in advance:** restore the `account_id` key in `directoryPayload` and
show `testAnExistingRowEditIsAnOwnerBoundPatchAskingForEvidence`'s new assertion **fail**. That
proves the assertion observes the payload the shipping writer actually builds rather than a
fixture — the same discriminator U2a used.

---

## 10. Validation

1. **Baseline is reused, not rerun.** `8b54ba6` recorded **972 passed / 0 failed / 6 skipped**
   and a clean final Release. **Independently verified in this window:** `d0d7812` touches
   three files under `docs/`, `05ad6a8` touches one — **both docs-only**, so `05ad6a8`'s source
   is byte-identical to `8b54ba6`'s and that evidence stands.
2. **Targeted suites during implementation**, then **one final full `MOTIVOTests` run** plus
   **Debug and Release builds** against the finished bytes.
3. **Test accounting reported as retired / converted / new / unchanged**, per §9 — never as a
   raw total.
4. **Warning delta compared against the existing accepted logs.** A baseline rebuild only if a
   specific unresolved warning actually requires one.
5. **Structural census** of remaining handle sites: expected zero render, zero write, zero
   generation.
6. **Positive control recorded** (§9.6), including the §8.1 non-vacuity demonstrations.
7. **No device QA, no production statement, no commit, no push.** Local acceptance only, held
   for Codex and then for Samuel.

### 10.1 Out of scope

Invitations of any kind; age, band or B-40 work; sharing, recorder or feed work; any server
change; any `search_account_directory` change; dropping or NULLing `account_id`; device QA;
Phase 6 closure.
