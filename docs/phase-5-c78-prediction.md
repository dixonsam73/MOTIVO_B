# C-78 — PREDICTION, COMMITTED BEFORE MUTATION. AN IMPORTED AUDIO FILE KEEPS ITS NAME.

**At `09d6f59`, 2026-09-10.** Account-holder decision, same day: an imported
audio file seeds its **source filename stem** as its initial audio title —
`Again.wav` → `Again` — and remains renameable. **Existing attachments are not
migrated. Imported video is OUT of scope** and is filed separately (C-80).

---

## 1. THE REGISTER'S PROPOSED FIX WAS WRONG — CORRECTED BEFORE IMPLEMENTING

C-78 as filed proposed *"a one-line widening"* of `stageData`'s
`kind == .file || kind == .pdf` condition. **That writes
`stagedAttachmentDisplayNames_temp`, which becomes `Attachment.displayName` — and
no audio-title reader consults it.** Traced, not assumed:

| Reader | Reads |
|---|---|
| `AddEditSessionView` inline caption (`+Attachments:665`) | `persistedAudioTitles_v1` → `stagedAudioNames_temp` |
| `AddEditSessionView` viewer title (`:951`) | same two maps |
| `AddEditSessionView` commit filename (`:503`) | `stagedAudioNames_temp`, else the UUID |
| `AddEditSessionView` reopening a saved session (`:297`) | **the persisted file's stem**, seeded into `stagedAudioNames_temp` |
| `PostRecordDetailsView` viewer title (`:87`) | `stagedAudioNames_temp`, else "Audio clip" |
| `PostRecordDetailsView` commit (`:757`, `:781`) | `stagedAudioNames_temp` → filename stem **and** `persistedAudioTitles_v1[finalID]` |
| `SessionDetailView` (`:960`, `:466`) | persisted title, else **the file stem** |

**So the working fix is to seed `stagedAudioNames_temp` at staging**, the map the
Save-as-New path already seeds (`AddEditSessionView+Attachments:1300`). Everything
downstream already exists.

## 2. DESIGN

- `AttachmentImportPolicy` gains the rule: `importedAudioTitle(kind:displayName:)`
  (trimmed stem iff `.audio`, else `nil`) and
  `seedImportedAudioTitle(stagedID:kind:displayName:defaults:)`, which writes
  `stagedAudioNames_temp[stagedID]` **only if no entry exists**.
- **Both** `stageData` bodies call it once, **before** `stagedAttachments.append`,
  so the first render after staging already sees the title.
- `Attachment.displayName` is **untouched** — still `.file`/`.pdf` only.

**Which callers pass a name — the inventory.** Six `stageData` call sites exist.
Only the two **file-importer** paths pass `displayName`
(`AddEditSessionView+Attachments:432`, `PostRecordDetailsView+Attachments:688`).
The PhotosPicker paths (`AddEditSessionView:741`, `PostRecordDetailsView:1337`)
pass none, and the camera paths (`:770`, `:1361`) stage `.image`. **So only
file-imported audio changes. Recordings keep their own naming path.**

## 3. PREDICTION

**P1 — the guard FAILS on today's implementation.** `ImportedAudioTitleTests`:
`testBothStageDataBodiesSeedTheImportedAudioTitle` and
`testSeedingIsCalledFromExactlyTheTwoImportPaths` **fail at `09d6f59`**;
`testNeitherStageDataWritesTheAudioNamesMapDirectly` passes (a regression guard
against the rule being copied into a view).

**P2 — `AddEditSessionView` import.** Importing `Again.wav`: the staged caption
reads **Again**; after Save the file persists as `Documents/Again.wav`; the
session detail row reads **Again**; reopening the editor still reads **Again**
(from the stem, `:297`).

**P3 — `PostRecordDetailsView` import.** Same, and additionally
`persistedAudioTitles_v1[finalID] = "Again"`.

**P4 — still renameable.** A rename in the viewer before Save overwrites the
seeded entry through the existing path (`:1060`); the seed never runs again for
that staged id.

**P5 — duplicate names are handled by the existing rule, unchanged.** A second
`Again.wav` persists as `Again-1.wav` (`AttachmentStore.uniqueFilename`). Via
`PostRecordDetailsView` it still reads **Again** (persisted title wins); via
`AddEditSessionView` it reads **Again-1** after reopening, because that view
persists no title and the stem is the fallback. **Pre-existing behaviour for
named recordings, recorded rather than changed.**

**P6 — nothing else changes.** Recordings, photo-library items, images, video,
PDF and `.file`: no seed. `Attachment.displayName` unchanged.

**P7 — server effect, stated precisely.**
- **Publish: none.** `display_name` is PDF-only (`BackendShim:1305`) and Storage
  paths are ids only (`:1327`).
- **Explicit direct send of that attachment: YES, and this corrects my earlier
  "stays on the device".** `ConnectedAttachmentShareUI:505–508` builds `filename`
  and `attachment_name` from the viewer's resolved title, and
  `ConnectedAttachmentSharing:251–259` writes both to `connected_attachments`.
  Today an imported audio file sends `filename = <UUID>` and
  `attachment_name = "Recording"`; after C-78 it sends **`Again`** for both.
  **That is the path named recordings already take**, it happens only on an
  explicit member send of that specific attachment, and the value sent is the
  title the member sees.

**P8 — no migration.** Previously imported attachments keep their UUID stems.

**P9 — verification.** Debug and Release clean on clean derived data, **warning
delta zero against 187 / 175**. Structured census: **208 declared, 208 passing**
(200 + 3 structural + 5 behavioural).

**P10 — non-vacuous.** Removing the call from `PostRecordDetailsView.stageData`
fails both counting tests; reverted afterwards.

## 4. DEVICE CHECK — REQUIRED BEFORE C-78 CLOSES

Device B, **Études Dev (Debug)** is sufficient: no StoreKit, no account state,
nothing destructive, no production contact.

1. **New session → attach file → a named WAV** (e.g. `Again.wav`). The staged
   audio shows **Again** before Save.
2. Save. The Journal's session detail shows the audio as **Again**; the debug
   sheet shows the persisted file as `Again.wav` (or `Again-<n>.wav`).
3. Reopen the session in the editor: still **Again**.
4. **Repeat 1–2 through the post-record path** (finish a practice timer → Post
   Record Details → attach file). Detail shows **Again**.
5. **Rename control:** rename a freshly imported file before saving → the rename
   wins.
