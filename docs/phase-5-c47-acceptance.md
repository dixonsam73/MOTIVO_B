# C-47 — OPTION B. RESOLVED, DEVICE-CONFIRMED 2026-09-11.

> **M5 GREEN — Device B, Release build.** An audio attachment renamed from a
> saved session's detail view kept its new title across closing and reopening
> the viewer and across leaving and returning to the session. **Run on the
> corrected code** — including the 2026-09-11 fix that made
> `ContentView.loadFeedPersistedTitles` read-only (see
> `docs/phase-5-l-closeout-acceptance.md`). **The sign-out case was
> deliberately not device-tested**; it rests on the source guard and the
> writer's behavioural tests.
>
> *Previous banner, preserved:* "C-47 stays open until the Device B audio
> rename/reopen check (M5) passes. Nothing below is device evidence." §1–§4 were
> written before the device check and before the `ContentView` correction; the
> correction is recorded in the close-out acceptance, not rewritten into them.

Prediction and guards: `docs/phase-5-c47-prediction.md`, committed at `0dbe8cf`
**before mutation**. C-80 and C-81 not touched. No production, ASC, enforcement
or age-state mutation.

## 1. Result

| | Prediction | Outcome |
|---|---|---|
| **M1** | four guards FAIL pre-change; stem count and factory reset PASS | **MET EXACTLY** — structured: *5 reported, 4 Failed, 1 Passed*. The direct-write count read **7**, matching the inventory; the stem-keyed half read **2** and passed; factory reset passed |
| **M2** | all pass, plus the three writer tests | **MET** |
| **M3** | Debug 177 / Release 165, set unchanged | **MET** — both, warning set identical modulo line numbers |
| **M4** | 229 / 229 | **MET** — **229 declared, 229 passed**, structured census |
| **M5** | Device B audio rename → close → reopen persists | **OUTSTANDING** |

## 2. What changed

- **`AttachmentTitlePersistenceKeys.writeLocalTitle`** — the one writer. Shared
  store, keyed by attachment id; clears **that id only** from every per-identity
  store so an older per-identity value cannot win the readers' merge.
- **`SessionDetailView.onRename`** — audio **and** video, **no identity
  required**. The attachment is located as before; the **key** is its id.
- **`AddEditSessionView`** (2 rename writes) and **`PostRecordDetailsView`**
  (2 id-keyed commit writes) — onto the writer. Five call sites in all.
- **`PostRecordDetailsView`'s two stem-keyed fallbacks — untouched and pinned**
  by the guard, so the name-based mechanism cannot grow.
- **`AuthManager.signOut`** — no longer removes title stores. **Factory reset is
  unchanged** and still removes the shared stores, every per-identity store, and
  the whole defaults domain.
- **Readers unchanged** — existing per-identity titles stay readable through the
  merge; **nothing was migrated.**

## 3. Recorded, not changed

`AddEditSessionView` reads the shared store only, so a video title an **older**
build wrote to a per-identity store is still not shown in the editor — until the
member renames it, at which point the writer moves it to the shared store.
Pre-existing, and not migrated by instruction.

## 4. Device check (M5)

**Device B, Études Dev (Debug) is sufficient** — no StoreKit, no account change.
1. Open a **saved** session from the Journal (session detail, not the editor).
2. Open an **audio** attachment in the viewer, rename it, close the viewer.
3. Reopen it — **the new title is still there**.
4. Leave the session and come back — **still there**.
