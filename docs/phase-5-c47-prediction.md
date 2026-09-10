# C-47 — OPTION B. PREDICTION, COMMITTED BEFORE MUTATION

**At `bf16e39`, 2026-09-10.** Account-holder decision the same day: **Option B**
— attachment titles describe local Journal data, must not depend on Connected
identity, and must survive sign-out; factory reset may still remove them. **New
writes are keyed by the attachment's unique ID, never by filename/stem; the
name-based fallback is not expanded; existing per-identity titles stay readable
through the existing merge, with no bulk migration.** C-80 and C-81 out of scope.

---

## 1. Inventory — every title store touch, measured at HEAD

**Direct writes to a title store: 7.**

| Site | Store | Key |
|---|---|---|
| `AddEditSessionView+Attachments:1073` (audio rename) | shared `persistedAudioTitles_v1` | attachment ID |
| `AddEditSessionView+Attachments:1091` (video rename) | shared `persistedVideoTitles_v1` | attachment ID |
| `SessionDetailView:537` (video rename) | **per-identity** `…:<uid>` | attachment ID |
| `PostRecordDetailsView+Attachments:792` / `:813` (commit) | shared | final attachment ID |
| `PostRecordDetailsView+Attachments:798` / `:819` (commit fallback) | shared | **stem** — reached only if the created attachment has no id |

**Readers.** `SessionDetailView.loadPersistedTitles` and
`BackendShim.persistedDisplayNameForAttachment` merge **shared + per-identity,
per-identity WINS**. `AddEditSessionView.loadPersisted{Audio,Video}Titles` read
the **shared store only**.

**Removal.** `AuthManager.signOut` removes the current identity's two per-identity
stores (`:1206-1214`). `LocalFactoryReset` wipes the whole defaults domain, the
shared stores and **every** per-identity store by prefix.

## 2. The three defects this fixes

1. **Audio rename in `SessionDetailView` is discarded for every member** — the
   handler returns for anything but video/PDF, after the viewer has already
   shown the new title.
2. **Video rename there is dropped with no identity** (never-signed-in Solo) —
   `sessionDetailNamespaceUserID` is nil.
3. **Sign-out erases `SessionDetailView`-edited video titles** — the only store
   it writes is the per-identity one sign-out deletes.

## 3. Design

- **One writer:** `AttachmentTitlePersistenceKeys.writeLocalTitle(_:kind:attachmentID:defaults:)`.
  It sets or removes the title in the **shared** store keyed by
  `attachmentID.uuidString`, **and removes that one attachment's entry from every
  per-identity store of that kind** — otherwise an older per-identity value would
  win the readers' merge and hide the new title. Only the renamed attachment's
  entry is touched; nothing is migrated.
- **`SessionDetailView.onRename`:** audio and video both go through the writer;
  **no identity is required**. The attachment is still located as today; the
  **key** is its id.
- **`AddEditSessionView`'s two rename writes and `PostRecordDetailsView`'s two
  ID-keyed commit writes** move onto the same writer — one place decides where a
  title lives (the one-of-N lesson). Their observable behaviour is unchanged.
- **`PostRecordDetailsView`'s two stem-keyed fallbacks are left exactly as they
  are** — not expanded, not converted.
- **`signOut()` no longer removes title stores.** Factory reset is unchanged.
- **Readers are unchanged**, so existing per-identity titles stay readable.

**Consequence worth stating:** an audio title renamed in `SessionDetailView` now
persists, so — like every saved audio/video title (C-78's corrected P7) — it is
included as `display_name` when the member deliberately publishes that
attachment. Accepted behaviour.

**Pre-existing, unchanged, recorded:** `AddEditSessionView` reads the shared
store only, so a video title that an older build wrote to a per-identity store
is still not shown there. Not migrated, by instruction.

## 4. PREDICTION

**M1 — pre-change run of `LocalAttachmentTitleTests`:**
- `testSessionDetailRenamePersistsAudio` — **FAILS**;
- `testSessionDetailRenameNeedsNoIdentity` — **FAILS**;
- `testSignOutPreservesAttachmentTitles` — **FAILS**;
- `testEveryTitleWriteGoesThroughTheSharedWriter` — **FAILS** (7 direct writes,
  2 allowed); its stem-keyed half (exactly 2) **passes**;
- `testFactoryResetStillRemovesTitles` — **PASSES** (regression guard).

**M2 — after:** all pass, plus three behavioural tests of the writer: writes by
id with **no identity**; clears that id — and only that id — from **every**
per-identity store; an empty title removes it everywhere.

**M3 — warnings unchanged: Debug 177 / Release 165**, set identical modulo line
numbers.

**M4 — census 229 / 229** (221 + 8).

**M5 — device, Device B, Études Dev (Debug) is sufficient:** open a saved
session's detail view, rename an **audio** attachment, close the viewer, reopen
it — **the new title is still there** — then leave the session and come back.
**The sign-out case is NOT device-tested**, by decision; it rests on the source
guard and the writer's behaviour. The no-identity case rests on the behavioural
test.
