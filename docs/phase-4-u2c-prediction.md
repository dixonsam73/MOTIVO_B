# P4-U2c — PREDICTION, COMMITTED BEFORE ANY CHANGE

**Written 2026-09-04 at `3642e9c`, BEFORE any implementation or test change.**

**Finding, from source investigation: the architecture ALREADY GUARANTEES the
invariant. U2c is therefore ASSERTIONS ONLY — no production code, no defensive
conditional.**

---

## 1. THE TOPOLOGY, TRACED RATHER THAN ASSUMED

**Post-attachment upload has exactly one chain, and every link is single-entry.**

| link | evidence |
|---|---|
| `uploadStorageObject` | 1 declaration (`BackendShim:1251`) + **1 call site** (`:1009`) |
| that call site is **inside `uploadPost`** | enclosing `func` of `:1009` is `uploadPost` at `:873` |
| `loadIncludedAttachments` | 1 declaration + **1 call**, also inside `uploadPost` |
| **`uploadPost` has ONE caller in the entire app** | `SessionSyncQueue:264` (the only non-declaration reference outside comments and the simulated stub) |
| that caller is **guarded** | `:247-262` — `if payload.op == .unshare { … continue }` sits immediately above it, so `:264` is reached **only** for a non-`.unshare` item |
| `.unshare` **never touches an upload primitive** | `unsharePost`'s body contains `is_public` and `deletePost` and **none** of `uploadStorageObject`, `loadIncludedAttachments`, `uploadPost` |

**So: private content cannot reach Storage because the only door is inside
`uploadPost`, `uploadPost` has one caller, and that caller is behind a
guard-and-`continue` on the operation.**

### 1.1 THE ONE REPRESENTABLE DIVERGENCE, AND WHY IT IS ALSO CLOSED

The `op` boundary is on the **operation**, not on `isPublic`. A payload with
`op: .publish` **and** `isPublic: false` is *representable*, and it would reach
`uploadPost` — writing `is_public: false` **and uploading its attachments**.
That is precisely the mirror defect, in a state no current path constructs.

**It is closed at the call sites, and closed in a way that can be asserted:**

| call site | payload | publish call |
|---|---|---|
| `AddEditSessionView` | `isPublic: isPublic` (`:2073`) | `shouldPublish: isPublic` (`:2094`) |
| `PostRecordDetailsView` | `isPublic: visibility` (`:1830`) | `shouldPublish: visibility` (`:1840`) |

**Both pass the SAME IDENTIFIER to both parameters.** Existence and visibility
cannot diverge because they are literally the same value. **That symmetry is the
real guarantee, and asserting it is stronger than any runtime `guard`** — a guard
would silently swallow the divergence, whereas the assertion fails loudly the
moment a future edit lets the two arguments drift apart.

### 1.2 SCOPE — WHAT THIS INVARIANT IS *NOT* ABOUT

Three other Storage writers exist and are **legitimately outside** it:

- **`ConnectedAttachmentSharing:215`** — attachments sent directly to named
  recipients (`connected_attachments`). `architecture.md` lists these in Domain 3
  by design; they are not post attachments and have no `isPublic`.
- **`NetworkManager:502/558`** — avatars, i.e. the public identity row.
- **`DebugViewerView:365`** — **`#if DEBUG` (opened at `:13`)**, as are both of
  its presentation sites (`SessionDetailView:324`, `ContentView:1702`). **Not
  compiled into Release**, and Release is the only configuration that can
  transact.

**Claiming "no attachment ever uploads for private content" without this scoping
would be false.** The invariant is about **post** attachments.

---

## 2. WHAT U2c WILL AND WILL NOT DO

**WILL:** add one structural suite, `supabase/tests/p4/u2c-acceptance.sh`,
pinning every link above, plus behavioural coverage of the four required cases.

**WILL NOT:** add any production code. No `guard payload.isPublic else` in
`uploadPost`, no check in `flushNow`. The chain is already single-entry and the
call sites are already symmetric; a runtime conditional would be **redundant by
construction** and would convert a loud structural failure into a silent
runtime one.

**WILL NOT** reopen U2b's failed synthetic Core Data positive control. §1 gives a
**stronger** proof than that fixture could have: a topological argument covers
*every* payload, where a fixture covers one. U2b's acceptance §4.1 already
records the control as not obtained.

---

## 3. PREDICTED ASSERTIONS

| id | asserts | predicted |
|---|---|---|
| U2c-1 | `uploadStorageObject` — 1 decl + 1 call | **2** |
| U2c-2 | that call is inside `uploadPost` | **1** |
| U2c-3 | `loadIncludedAttachments` — 1 decl + 1 call | **2** |
| U2c-4 | that call is inside `uploadPost` | **1** |
| U2c-5 | `uploadPost` call sites app-wide (code, comments stripped) | **1** |
| U2c-6 | that caller is in `SessionSyncQueue` | **1** |
| U2c-7 | the `.unshare` guard precedes it and `continue`s | **1** |
| U2c-8 | `unsharePost` contains no upload primitive | **0** |
| U2c-9 | AESV passes the same identifier to `isPublic:` and `shouldPublish:` | **1** |
| U2c-10 | PRDV likewise | **1** |
| U2c-11 | no Release-compiled post-attachment upload outside the chain | **0** |
| U2c-12 | `DebugViewerView`'s upload is `#if DEBUG` | **1** |
| U2c-13 | `LocalFactoryReset.perform` still 2 callers | **2** |
| U2c-14 | `posts_insert_owner` still has no `is_public` guard — U2s not started | **0** |

## 4. PREDICTED BEHAVIOURAL COVERAGE

The four required distinctions. **Three are already covered and must stay
green**; one is added.

| case | expected | where |
|---|---|---|
| new **private/Share-OFF** session — never enters `.publish`, never reaches `uploadPost` | no row, no object, **no `.publish` item** | existing `SharedOnlyUploadTests` |
| **Thought** — same | no row | existing |
| **existing shared → unshared** — enters `.unshare`, may demote/delete, **never** invokes upload | row and objects removed | existing (`UnshareDurabilityTests`, `SharedOnlyUploadTests`) |
| **Share ON** — continues through `.publish`, retains legitimate upload capability | row created, public, dequeued | existing |
| **NEW:** a `.unshare` item whose post still has attachment refs **removes** them and uploads nothing | objects deleted, none created | added by U2c |

## 5. STANDING GATES — ALL EXPECTED GREEN

Debug + Release build; `MOTIVOTests` (38 + the new case); `u5/client-structural`
60/60; `u2a` 16/16 (pinned); `u2a2` 22/22; `u2b` 16/16; `u1-baseline` 11 + its 5
documented flips.

## 6. OUT OF SCOPE

- **U2s is not started** — `posts_insert_owner` unchanged (U2c-14).
- **No production change, no membership state, no U6b enforcement change, no
  Device A action.**
- **U2b's device verification stays pending** — Phase 4 exit condition 8.
