# Études — Data Architecture

This document contains three kinds of statement, and they carry different weight:

**Architectural boundaries** (Domains 1–4) — settled, and should almost never
change. Reopening one requires genuine new evidence, not a preferred design.

**Product principles** — guide judgement where the answer isn't obvious. Stable
in direction, but applied case by case.

**Designed future work** (iPad and private sync, Threads, Playback rate) — the
design is agreed; the implementation and timing may still evolve. Treat the reasoning as binding and
the details as revisable.

---

Four domains. The boundaries are permanent; the engine for Domain 2 is deferred
to M14, which ships with the iPad release (M13).

Governing test: **if nobody else can see it, it does not belong on Supabase.**

---

## Domain 1 — Local journal and media

**Contains:** sessions, thoughts, notes, audio/video/photo attachments, the PDF
Scores library, instruments, activities, threads, tasks, ensembles, favourites,
timer state, insights.

**Why:** this is the product. Études is complete and fully usable with no
account, no network and no membership.

**Owner:** the user, solely. No other party holds a copy by default.

**On membership expiry:** untouched. Permanently. The strongest invariant.

**Roadmap:** M14 will sync this domain. The foundation it needs (Scores and
the other UserDefaults-held library data in Core Data, stable asset identity
instead of absolute paths, visibility independent of identity) ships first as an
iPhone update. See *iPad and private sync* below.

**Visibility is not identity.** Which records appear in the journal must not
depend on Connected sign-in, the Apple subject, subscription state or install
ID. Today it does: Solo sessions are ownerless, custom instruments and
activities carry a per-install `local:<UUID>`, and Connected sign-in re-owns
ownerless sessions (`adoptOwnerlessLocalSessionsIfNeeded`). Stage 1 removes
owner filtering from the local library and stops the re-owning.

---

## Domain 2 — Personal cloud (future optional iCloud sync, M14)

**Contains:** a mirror of Domain 1 in the user's private iCloud database, on
by default, media included. Device-local state stays out of it (see
*iPad and private sync*, below).

**Why:** continuity across the user's own devices. Not a sharing mechanism.

**Owner:** the user, in their own iCloud account, against their own quota.
Études never has access — the developer cannot read it even in principle.

**On membership expiry:** entirely unaffected. No relationship to Connected. A
user who never pays can use it. Durability is never gated on monetisation.

**Roadmap:** M14 is released together with M13 (iPad). iPhone and iPad must
present one coherent journal from the first public iPad release; a
separate-device journal is not an acceptable product.

**Durability model — three layers, not one. Settled in Phase 2.**

- **Ordinary Apple device backup and restore provides baseline single-device
  durability** for the whole local Études library: journal, attachment media,
  Scores and adopted copies.
- **M14 provides optional cross-device private-library synchronisation.**
- **Connected/Supabase carries interpersonal and shared data only.**

**M14 must never be required for recovery of an ordinary local Études library.**
If it were, durability would depend on an unshipped feature, and every user
without it would be one device failure away from losing everything. That is why
the backup decision is Phase 2 and not M14, and it is why M14 should not be
described as a "convenience" — it is a different capability, not a weaker version
of backup.

---

## Domain 3 — Connected sharing and collaboration (Supabase)

**Contains, and only contains:** sessions explicitly shared and the attachments
explicitly included with them; attachments sent directly to named recipients;
the social graph; comments and private replies; the public identity row
(display name, handle, location, instruments, avatar); references to received
attachments.

**Does not contain:** unshared sessions, private notes, attachments not
explicitly included, the Scores library, tasks, threads, insights, timer state.

**Owner:** mixed, deliberately — which is why expiry is not uniform.

**REAFFIRMED 2026-08-16 AT THE PHASE 3 ENTRANCE. This table is NOT superseded,
and it nearly was.** It states the **expiry** rule. The 2026-08-13 revision
(`c4f6d0f`, `dac78af`) that made a departing member's own backend UGC deletable
was scoped to **explicit account deletion** by its own text, and justified by
Apple's **account-deletion** guidance, which says nothing about subscription
expiry. No commit in that revision touched this file. A later reconciliation
(`0f5896d`, 2026-08-14) nonetheless amended QA C7 to assert that expiry "must
match `delete_account_v1`'s deployed semantics" — an inference, not a decision,
and one the same cell simultaneously declared open. **That inference is
withdrawn.** Expiry and explicit account deletion are two deliberately distinct
lifecycle policies; see the Phase 3 retention matrix in `CLAUDE.md`.

| Data | On expiry | On explicit account deletion |
|---|---|---|
| Own posts + included attachments | Deleted (local originals survive) | Deleted |
| Post shares, sent and received | Deleted | Deleted |
| Own received-attachment references | Deleted | Deleted |
| Social graph | Edges removed both directions | Removed |
| `post_comment_views` as viewer | Deleted | Deleted |
| Avatar object | Deleted; `avatar_key` cleared only after the object is provably gone | Deleted |
| Directory discoverability | **Removed — the member becomes undiscoverable** | n/a |
| **`account_directory` row** | **RETAINED, with `display_name` intact** — retained comments need an author | Deleted |
| **`auth.users`** | **RETAINED** — deleting it would be an account deletion nobody requested | Deleted, strictly last |
| Comments on others' posts | **Retained** — part of someone else's history | Deleted (`author_user_id` alone) |
| Attachments sent to others | **Retained** while live recipient references exist | Deleted |
| Comments by others, merely addressed to them | Retained | Retained (B-19) |
| All local data | Untouched | **Target (Stage 1): untouched**, with deleting the private journal offered as a separate optional step. **Today:** the single "Delete Account & All Études Data" action erases the device, because after sign-out the journal filters would hide sessions re-owned to the deleted identity |

**Two rows are new rather than changed**, and they were always implied by the
others: the identity must survive expiry, because the table already retained
comments that need an author, and because the settled rejoin model reuses it.
"Handle released and regenerable" is therefore withdrawn for expiry — the row is
retained and made undiscoverable instead.

---

## Domain 4 — Membership lifecycle and backend identity

**Authority is split, deliberately:**

- **Client StoreKit entitlement → access only.** Solo vs Connected UI.
  Reversible, self-correcting, cheap to get wrong.
- **Apple's App Store Server Notifications → irreversible cleanup only, and
  only to SCHEDULE it.** Authoritative, server-to-server, immune to local cache
  state. **Notifications never execute cleanup.** A live authoritative read from
  Apple immediately before destruction is required; if it cannot be obtained,
  cleanup does not run and is retried later.

Apple's billing grace period absorbs card failures at the right layer. **Stated
as design intent rather than as fact: Billing Grace is a configured App Store
Connect feature and is NOT yet enabled (C-31).** Until it is, a card failure
produces billing retry with no grace, and Apple's own service formula treats that
as **not entitled** — `isInBillingRetryPeriod` entitles only *combined with* an
unexpired `gracePeriodExpiresDate`. Phase 3 enables it **Sandbox-first** and
promotes it to production only after handling is accepted.

On genuine expiry Apple notifies the server; the server schedules Domain 3
cleanup behind a 60-day quarantine and performs it only after a live Apple read
confirms non-entitlement; the client independently drops to Solo. Neither waits
on the other.

Membership reaches into exactly one domain. Paying or not changes what you can
*share*, never what you *have*.

---

# Local durability matrix — what participates in Apple backup

**Settled in Phase 2 (C-4), 2026-08-15.** Locations are relative to the app
container.

The **Control** column matters as much as the policy. Only rows marked *Études*
are decided by our code — those, and only those, are owned by `BackupPolicy`.
Rows marked *iOS* are ordinary platform behaviour that we deliberately do not
touch; rows marked *Platform* are excluded by iOS regardless. Documenting all
three together is useful; pretending the code owns all three would not be.

| # | Data class | Location | Kind | Backup | Control |
|---|---|---|---|---|---|
| 1 | Core Data journal | `App Support/MOTIVO.sqlite` (+`-wal`,`-shm`) | Permanent | Included | iOS |
| 2 | Attachment media | `Documents/*.{m4a,mp4,mov,jpg,heic,pdf,…}` | Permanent | **Included** | Études |
| 3 | Scores library PDFs | `Documents/Scores/*.pdf` | Permanent | **Included** | Études |
| 4 | Scores index, favourites, resume | `UserDefaults` `scoreLibrary_v2` | Permanent | Included | iOS |
| 5 | Adopted received scores | as #3 | Permanent, recipient-owned | **Included** | Études |
| 6 | Per-attachment privacy map | `App Support/AttachmentPrivacy.json` | Permanent (intent) | Included | **Études** (see below) |
| 7 | Local comments | `App Support/CommentsStore.json` | Permanent | Included | iOS |
| 8 | Local avatar | `App Support/Profiles/<uid>-*` | Permanent | Included | iOS |
| 9 | Profile name/location/instruments | `UserDefaults` `profile.*` | Permanent | Included | iOS |
| 10 | Received Connected attachments | `App Support/ReceivedConnectedAttachments/` | Backend-derived cache | **Excluded** | Études |
| 11 | Staging media + `staged.json` | `App Support/MOTIVO/Staging/` | Staging scratch | **Excluded** | Études |
| 12 | Timer staged video | `App Support/MOTIVO/PracticeTimer/` | Scratch | **Excluded** | Études |
| 13 | Pending publish queue | `App Support/MOTIVO/SessionSyncQueue_v1.json` | Operational | **Excluded** | Études |
| 14 | In-flight video capture | `Documents/motivo_vid_*.mov` | Transient | **Excluded** | Études |
| 15 | Surrogates, exports, PDF subsets | `tmp/` | Temporary | Excluded | Platform |
| 16 | Avatar/thumbnail caches | in-memory `NSCache`; `Library/Caches` | Cache | Excluded | Platform |
| 17 | Auth tokens | Keychain (`WhenUnlocked`) | Credential | Restores | iOS |

**Row 5 is why Scores are backed up at all.** An adopted score is recipient-owned
permanent data and is **not** reconstructible — under the revised deletion rule
the sender's account deletion removes the backend object. Excluded, "adoption"
would not mean what the product says it means.

**Row 10 carries a Phase 4 dependency, recorded rather than implemented.**
Excluding received attachments rests on the object remaining fetchable while its
row lives, which is B-8's storage-orphan lifecycle. If Phase 4 changes what a
live row guarantees, this row is revisited.

**Row 6's Control is Études, not iOS, and the distinction was earned by
remediation D3.** The U4 move alone would have left inclusion resting on the
platform default plus the accident that the legacy file happens to carry no
item-level flag today. `moveItem` **preserves** extended attributes — proven
directly, not assumed — so anything that had ever flagged the legacy file would
have ridden the exclusion into the new location silently, and outside the
reconciliation pass's traversal roots, which cover only `Documents` and
`Documents/Scores`. Études therefore now **actively asserts inclusion** at this
path on all three routes by which a file can arrive there: after the migration
move, after adopting a pre-existing destination, and after every `saveMap` write
(`.atomic` writes via a replacement inode, so the flag is re-applied per write
rather than assumed to persist). The invariant is that **a permanent privacy map
at this location is backup-eligible however it got there.**

**Row 13 is deliberate:** a restored device must not inherit historical
pending-publish intent.

**`Application Support/MOTIVO/` is scratch, and now honestly so.** It holds rows
11–13 and nothing permanent. Row 6 used to live there and was excluded by
accident, which is the whole reason the directory's meaning had to be made
explicit.

## Backup-exclusion semantics — established empirically, 2026-08-15

`isExcludedFromBackup` resolves by **ancestor walk**, not attribute inheritance.
The extended attribute exists only on the item explicitly flagged, but everything
beneath a flagged directory reports excluded — items that existed before the flag
was set and items created after, at any depth. Two consequences are load-bearing:

1. **There is no per-item "include" override.** A child of an excluded directory
   cannot be exempted. This is why row 6 had to *move*.
2. **A child's own flag survives its parent being un-flagged.** So clearing a
   directory does not make individually-flagged contents eligible — which is
   exactly the state `Documents/Scores/` was in.

**Standing rule: never rely on ancestor resolution for the outcome we care
about.** Exclusion may lean on it; *inclusion* must guarantee both that no
ancestor is flagged and that no item flag remains.

**All of that describes what the URL API reports. It is not evidence about what
Apple's backup daemon copies** — only QA F1/F2 settle that.

---

# Threads — future model (M13 foundation)

**Status: designed and agreed, parked until M13. Not M11 work.**

## Today

`Session.threadLabel` is a free-text string. A thread exists exactly as long as
some session carries that string; `ThreadPickerView` offers previously-used
labels as suggestions. There is no Thread record, no identity, no lifecycle.
Thoughts are Sessions, so they already carry `threadLabel` structurally.
Handwritten pages do **not** land as Thoughts: they are Sketches, a separate
object (see *iPad and private sync*).

**Not part of the iPad/sync release.** A thread string on a Session syncs
without a reconciliation problem, because it is just an attribute of a synced
record. Colour no longer needs an entity either: it is derived
deterministically from the normalised name (see *iPad and private sync*). The
entity conversion below waits until rename/merge is actually built.

## Why Threads become first-class entities

**The primary architectural reason is sync rather than referential tidiness.**
Stable identity is what makes CloudKit reconciliation, cross-object references
and future relationships robust. Two devices independently creating "Recital
prep" and "recital prep", or one renaming while another adds a session, leave
conflict resolution nothing to match on but text that happens to agree. A
stable UUID merges cleanly; a string requires inventing a reconciliation rule
and getting it right. Referential consistency remains a meaningful secondary
benefit: one identity, one rename, one colour and one relationship rather than
duplicated strings spread across multiple domains.

**Secondary:** Scores, Sketches and eventually Task Sets would all
reference the same thread. Each holding its own copy of a string makes rename
an N-way update and lets a typo silently fork one thread into two.

**Latent benefit:** with an entity, thread colour could be chosen rather than
derived. Until then colour is a deterministic function of the normalised name.

## Design principle

**Threads must continue to feel emergent, not administered.** They appear when
you name them, recede when nothing references them, and never become an object
the musician has to manage. Entity status buys stable identity for sync and
cross-object references — it must not surface as a management screen.

## Rules

**Auto-create, with normalisation.** Naming a thread creates the entity if none
matches. Matching is case- and whitespace-insensitive, reusing the existing
entity rather than minting a near-duplicate.
`PersistenceController.normalized()` already implements this pattern for
instruments and activities — reuse it. Without normalisation, entities *lose*
the free deduplication string-keying gave for nothing, and two identical-looking
threads in the picker are worse than today's behaviour.

**Automatic removal is local visibility, never a synced delete.** A thread with
no references on this device is simply not shown or offered. The entity row
persists. A propagated delete would reintroduce at the identity layer exactly
the instability entities were meant to remove — a delete resolving against a
live reference on another device, and recreation-by-name minting a different
UUID. With local-only garbage collection, once another device's session syncs
over, the thread reappears without anything being resurrected.

**Rename is the one affordance worth keeping, and it should be contextual.**
Impossible today, so nobody expects it. With entities it becomes both possible
and correct — one rename, all references follow. Put it where the thread is
already visible (long-press the thread pill, or the thread filter header), not
in a management screen.

**Renaming onto an existing name merges into it.** That is what users will
assume, and without it rename recreates the duplicate-name problem that
normalisation exists to prevent.

## The feature that prompted this: Scores ↔ Threads

**Explicit intent plus derived reality.** A Score carries one optional *primary*
Thread, assigned explicitly from the Scores library — because musicians organise
before they practise, and six recital scores imported today belong together
before a single session exists. Everything else is derived from usage: session
count, last worked, page resume, and the other threads the score has genuinely
been used in.

Keeping the primary distinguishable from the derived list is deliberate and
semantically richer than a multi-select. It preserves the difference between
what the musician *meant* and what actually *happened*. If multiple explicit
assignments are ever added, the primary should remain distinguishable rather
than becoming the first item in an array.

**One primary to start with.** Extending one-to-many later is a migration;
contracting many-to-one is a data-loss conversation with users.

**Placement.** Score organisation belongs in the Scores library, alongside
rename, favourite and delete — *not* in the Score Viewer. The viewer is the
practice surface: Timer-owned, deliberately minimal, used while holding an
instrument. Organisational admin does not belong in the moment of playing.

**Where the value is experienced, in order:**

1. **Thread → Score, in the Journal.** The thread filter gains a header card
   showing the primary score with resume, session count and last worked. This
   is where "everything about this piece" materialises. Build it as an enriched
   version of the existing filter, not a new destination.
2. **Thread-aware resume.** Picking a thread when starting a session opens the
   right score at the page you left. Probably the part felt most often.
3. **Score → Threads, in the library.** The reverse lookup, and where the
   explicit primary is assigned.
4. **Thread filter in the Scores library.** Useful past roughly fifty scores.
   Last, and only if search proves insufficient.

**Orphan threads must be representable.** A thread pinned to a score with no
sessions is legitimate — planning a recital before playing a note.
`ThreadPickerView` must offer threads from *both* sources, or the musician
retypes the name and a typo silently forks it. A thread filter with no sessions
should read as "nothing logged yet — here are your scores".

## The chip interaction is the specification

The Thread chips in `PracticeTimerView` do not merely assign a thread. Tapping
one animates it gently to centre while the other suggestions fade, and when the
session finishes and `PostRecordDetailsView` opens, that Thread is already
selected.

The interaction itself is the contract. The underlying model may evolve from a
string to a Thread entity with Scores, Sketches, Task Sets and resume
state, but none of those architectural changes should be visible to the
musician. The implementation changes; the feeling of the interaction does not.

This does not feel like tagging or organising. It feels like quietly committing
to a musical context before beginning — one small decision, carried forward
through the workflow without further questions. It is the clearest expression in
the app of *reducing ceremony between the musical impulse and the musical
record*.

A refactor judged by "does the chip still feel the same" is one that can be
verified by using the app for five minutes.

## Thread selection prepares the primary Score

Once a Thread has an associated primary Score, selecting the Thread chip should
quietly prepare that Score — not open it, not interrupt, just have it ready.

The machinery already exists. `ScoreLibraryStore` holds `activeScoreID` and
`lastViewedPage`, both persisted, and `ScoresLibraryView` already renders an
active-score section with **Resume** at the top of the library. So this may be
no new UI at all: selecting a thread sets `activeScoreID`, and tapping Scores a
few moments later lands on that score's Resume card at the correct page.

**Two guards, both of which turn invisible assistance into invisible
interference if missed:**

- **Never overwrite a manual choice.** If the musician has already opened a
  score this session, tapping a thread chip must not silently swap it. Prepare
  only when nothing is active, or when the active score was not manually chosen
  since.
- **Preparing is not opening.** `markOpened()` sets `activeScoreID` *and* stamps
  `lastOpenedAt`, which drives library recency. Preparation must set the active
  score without touching the timestamp, or tapping a chip reorders the library
  as though the score had been used. The store does not currently draw this
  distinction.

**This is why the explicit primary exists.** Derived usage gives a *list* of
threads a score has been used in; you cannot act on a list, because there is no
choice in it. The single deliberate assignment is what lets the app act on the
musician's behalf without guessing. The primary is not a convenience — it is the
thing that makes the most Études-feeling behaviour in the feature possible.

## Sequencing

Two string referencers (sessions and scores) migrate in a single pass, so
building Scores ↔ Threads before the entity conversion is acceptable if the
score stores its thread label the same way a session does.

**The third referencer is where the cost tips. Hold Tasks ↔ Threads until after
the entity conversion.** If built, follow the same shape as Scores: a thread
optionally references one saved Task Set, so starting a "Recital prep" session
loads the tasks you always do for it. One explicit link, everything else
derived. Note that Tasks are currently per-session plus reusable saved sets with
no thread dimension — this is the only item in the convergence picture that adds
a relationship rather than reading one that already exists.

## Timing

Originally bundled into M13 with manuscript-pages-as-Thoughts and the sync
groundwork. That bundle is superseded: sync groundwork is Stage 1 of the
iPad/sync plan, manuscript pages are Sketches, and the entity conversion is not
needed for sync. Scores ↔ Threads can use a normalised thread string on the
Score, per *Sequencing* above.

---

# iPad and private sync — agreed plan (M13 + M14)

**Status: design agreed 2026-09-24 (Samuel, with Claude and Codex reviews).
Not started, and no iPad work before the iPhone release.** The object model,
sequencing and product decisions below are settled. The CloudKit media route
is preferred, but it's conditional on the Stage 0 proof.

## Principle

On iPhone, Études is in your pocket and is mostly about starting and capturing
a session. **On iPad it sits on the music stand:** the score is often the main
thing on screen and the app recedes around it. The iPad gets its value from
making existing Études concepts better for real musical work, not from new
product categories.

**Out of scope:** notation editing or recognition, playback of notation, a DAW,
repertoire management, generic productivity features, and new social features.

## Navigation

- **Wide windows:** a sidebar with **Practice · Journal · Scores · Insights ·
  Feed**, and Settings/Profile at the foot. Profile stops being an overlay.
- **Narrow windows** (Split View, Slide Over, narrow Stage Manager): fall back
  to today's iPhone layout (the `appRoute` switch).
- **Opening the app** goes straight to Practice.
- **Scores** is a top-level area and contains a **Sketches** section.
- **People is not a top-level destination.** It is reached from a Feed toolbar
  button, profiles and search. The request badge moves onto the Feed item.
- **Journal:** a list with the selected session shown beside it. Filters move
  into the toolbar or list header. When nothing is selected, the summary is
  shown. No inspectors or extra hierarchy.
- **Connected on iPad works fully at launch:** comments sit beside the post
  rather than in a sheet, profile peeks become popovers, and it uses native
  iPad presentation. It is adapted, not redesigned.

## Practice

- **The score is the page and the practice controls sit over it.** This
  reverses today's arrangement, where `PDFScoreView` is a full-screen cover
  over the timer.
- **Two layouts, chosen by available width** (not orientation, and there is no
  mode switch):
  - **Music stand:** the score dominates, with a minimal controls bar showing
    elapsed time, thread or piece, record, thought/sketch, metronome, tuner,
    add attachment and end session.
  - **Workspace:** the score, with Sketch, Thought or session tools beside it.
- **Bluetooth page turners** are in v1. Pedals send arrow or page keys to the
  existing single-page `PDFView`. Keyboard shortcuts come last.
- **`PracticeSessionController`** is a narrow extraction from
  `PracticeTimerView`. It covers start, pause and resume; elapsed time; the
  active draft; recovery; staged attachment references; task state; which
  scores and pages were used; staging of ink and Sketch links; finish to
  review; and confirmed discard. Views keep layout, sheets, animation and the
  iPhone-vs-iPad presentation. This is not a rewrite of the audio or video
  recorders. It passes only if the T1–T7 behaviours in the QA plan feel the
  same.

## Apple Pencil: rules

- **Markup mode.** Scores are read-only until Markup is entered, by a Pencil
  tap or a Markup button. A finger always turns pages; only the Pencil draws.
  Leaving Markup asks **Save / Don't Save / Cancel**. The Sketch editor works
  the same way.
- **Only explicit saves persist.** Creative edits don't survive just because a
  session was running. Each Save creates a new immutable revision and advances
  the live layer.
- **Editable present plus immutable history.** The live layer stays fully
  editable: new ink adds to what's there, and marks from earlier sessions can
  be erased. A session's snapshot keeps the **full** state of the page at its
  last save in that session, not just the strokes added.
- **Snapshots are written only when the session is committed.** Each page
  saved during the session gets one snapshot, pointing at its last saved
  revision. A save made outside any session creates no snapshot.
- **Discarding a session** drops its staged snapshots and Sketch links. Saved
  Score ink and saved Sketches remain. The timer never owns creative work.
- **Crash recovery.** If the app crashes or is killed mid-edit, the unsaved ink
  is kept on the device only and offered back as "Restore unsaved markings?". A
  crash is not a decision to discard.
- **iPhone in the first iPad release** shows ink and Sketches read-only. There
  is no iPhone editing in v1.
- **Sketch paper in v1** is manuscript/staff or blank only. No tablature, chord
  grids or instrument templates.
- **Nothing is flattened into a PDF** and the source PDF is never modified.
  Associating a Sketch with a Score does not insert pages into its PDF.

## Object model

All of this lives in Core Data. The **Cloud** configuration syncs through
`NSPersistentCloudKitContainer`; the **Local** configuration never syncs.
Relationships cannot cross the two stores, so local records refer to cloud
records by UUID.

| Entity | Store | Notes |
|---|---|---|
| Session | Cloud | Existing entity. Gains explicit `kind` (practice or thought), which replaces the `isThought` guess. `isPublic` stays as sharing *intent*. `ownerUserID` is kept for reconciliation only. `sharingHandoff` moves to the Local store. |
| Attachment | Cloud | Belongs to one Session and points at an Asset instead of an absolute `fileURL`. Titles, `includeInShare` and cover choice move onto it from UserDefaults and `AttachmentPrivacy.json`. |
| Asset | Cloud | Metadata for immutable bytes: ID, kind, size, SHA-256, content type. Trimming creates a new Asset. |
| Score | Cloud | Existing UUID kept. `libraryState` (in library / removed), `pdfAsset`, title, favourite, dates, resume page, cover page, optional primary thread (a normalised string). |
| SessionScore | Cloud | Session ↔ Score, with selected pages and used pages. Replaces the score-use Attachment rows and `pdfSelectedPages_v1`. |
| Sketch | Cloud | `libraryState`, template (manuscript or blank), optional title, optional `score` (the piece it is filed with). |
| InkPage | Cloud | One drawable surface: a Score page (tied to the PDF asset it was drawn on) or a Sketch page. Holds geometry and `currentRevision`. |
| InkRevision | Cloud | Immutable drawing data, one per Save. Revisions that nothing references are garbage-collected. |
| InkSnapshot | Cloud | Session + InkPage → InkRevision. Immutable. |
| SessionSketch | Cloud | Session or Thought ↔ Sketch, with a role (created, edited or attached). |
| Lists, ensembles, favourites | Cloud | Move from UserDefaults to entities. |
| Instrument, UserActivity, UserInstrument, Tag, Profile | Cloud | Given CloudKit-safe defaults. Tag's uniqueness constraint is replaced by de-duplication. Seeded rows get deterministic IDs (UUIDv5 of the normalised name) and Profile a fixed ID. |
| AssetCache | Local | Asset ID, relative path, and state (pending upload, uploaded, downloading, available, evicted), plus the last error. |
| Sharing handoff, publication mappings, publish queue | Local | Device-specific, as today. |
| Migration ledger, quarantine, unsaved-ink recovery | Local | |

**Two concurrent saves** (two iPads, before sync catches up): each creates a
revision, and the most recent save becomes current. Any snapshot keeps the
other one. This is accepted for v1.

## Scores, Sketches and history

- **One Sketch, several contexts, never duplicated.** Where a Sketch *lives*
  (`Sketch.score`, or on its own in the Sketches section) is separate from
  where it *appeared in history* (`SessionSketch`).
- **A Thought is a Session**, so "add to Thoughts" creates a Session of kind
  `thought` with a `SessionSketch` link. The Sketch itself is not copied.
- **The save sheet** offers **This session · Current score · Add to Thoughts**.
  In a session that uses a score, the first two are selected by default. None
  is required, because a Sketch can stand alone.
- **Linking a Sketch to a session or Thought** pins its saved state at that
  moment. The journal entry shows that state and offers "Open current version".
- **Example: Monday and Thursday.** On Monday a Sketch is saved to the session
  and the score. On Thursday it is opened from the score, developed and saved,
  and Thursday's session gets its own link and snapshot.
- **Deletion when past sessions reference the object.** The confirmation says
  how many sessions reference it and offers:
  - **Remove from library, keep history** (the default). `libraryState`
    becomes removed; the PDF asset, ink and snapshots are kept; history still
    renders; and "Add back to library" is available from the session. Removed
    items still use iCloud storage.
  - **Delete everywhere, including history.** Removes the object, its
    SessionScore or SessionSketch rows, ink, snapshots and asset. The sessions
    themselves remain.
- **Deletion when nothing references the object** is a normal delete.

## Colours

- **Thread, instrument and activity colours** are deterministic, and the
  UserDefaults slot maps are no longer used.
- **Hash:** 64-bit FNV-1a over the same normalised name used for thread
  matching, with a salt per domain. Never Swift `hashValue`, which is seeded
  randomly on every launch.
- **Palette:** about 18 muted tones spread evenly in a perceptual colour space.
  Lightness and saturation match the slate/green identity, with separate light
  and dark variants. Current tint colours are reused where they fit, and the
  palette stays clear of the destructive red and the thought-paper fill.
- **Collisions** remain possible and are accepted, because a name always
  appears beside its colour. A one-time colour change for existing users is
  accepted.

## Sync and media

- **Records:** `NSPersistentCloudKitContainer`, private database, with history
  tracking on.
- **Bytes** (Score PDFs, audio, video, images): a separate app-owned zone,
  with one `CKAsset` record per Asset ID.
  - **Upload** goes through a durable local queue that survives relaunch.
  - **Download** is by record ID, on demand. Scores and recent items are
    fetched ahead of time.
  - Assets are immutable and referenced from synced records, so the asset zone
    needs no change feed.
  - Assets are deleted only as a result of an explicit user deletion. There is
    no automatic orphan sweep in v1.
- **Media is app-managed Études content**, not Files documents. iCloud Drive is
  not used.
- **Media syncs by default.** There is no silent compression or degradation to
  make sync succeed.
  - Each item shows one of: In iCloud, Uploading, **Not in iCloud** (storage
    full or upload failed, with retry), Downloading, Available.
  - The original stays on the device until its upload is confirmed.
- **Clearing downloaded media** only evicts bytes whose upload is confirmed.
  It never touches records.
- **Switching iCloud accounts** stops sync and holds local data unsynced. One
  account's journal is never uploaded into another account.
- **Without an iCloud account** the journal works locally, and it shows
  plainly that it isn't syncing. Solo needs no account.
- **Device backup is unchanged and still the baseline.** Sync is not backup,
  because deletions sync too.

**What stays local:**
- live timer, draft and staging state (a session in progress belongs to one
  device)
- the publish queue, sharing handoff and publication mappings
- Connected caches (comments, feed, follows and received attachments are
  refetched)
- Keychain tokens (sign in to Connected on each device)
- per-device display preferences
- unsaved ink
- the migration ledger

## Connected isolation

- **Publishing commands are created only by the code handling the user's own
  action** on that device, never by watching Core Data changes. Changes
  imported by sync are tagged with the importer's author, and every observer
  that could reach Connected ignores them.
- **Sync can never cause** publishing, re-publishing, directory or profile
  writes, or any other backend effect.
- **Signing in to Connected** no longer re-owns journal entries. Publication
  identifiers stay in the Connected domain.
- **A device not signed in to Connected** can't update a shared post. Its
  edits save to the journal, and it says "sign in to Connected on this device
  to update the shared post".
- **Connected media limits** are unchanged by sync. There is a 50 MiB published
  limit per file, enforced server-side (B-45). Oversized files are trimmed,
  replaced or kept private. Any future publishing compression creates a
  separate derivative and never replaces the private original.

## Destructive and ending actions

Five separate behaviours, never combined into one confirmation. Every
confirmation states what happens to this device, iCloud, other devices and
Connected data.

| Action | This device | iCloud | Other devices | Connected/public |
|---|---|---|---|---|
| Subscription ends | unchanged | unchanged | unchanged | visibility and expiry rules only |
| Delete Connected account | journal kept; Connected tokens, caches, queue and mappings cleared; returns to Solo | unchanged | journal unchanged | backend deletion as in the Domain 3 table |
| Clear downloaded media | uploaded bytes evicted; records kept | unchanged | unchanged | unchanged |
| Remove from this device | sync stopped, then local wipe (blocked or explicitly warned if anything is Not in iCloud) | unchanged | unchanged | unchanged |
| Delete my journal everywhere | wiped | both zones deleted | wiped on next contact; never re-uploaded | separate; not implied |

- **Settings offers both** Remove from this device and Delete my journal
  everywhere.
- **The Connected deletion flow** ends with a clearly separate, optional
  "Also delete your private journal?" step. Before sync exists, that step is a
  local wipe.
- **`LocalFactoryReset` becomes the local wipe only.** "Delete everywhere" is
  its own path. The `CLAUDE.md` invariant about its callers is rewritten when
  Stage 1 lands.

## Migration and first sync

- **Restartable and idempotent**, with a step ledger in the Local store. Old
  sources (UserDefaults keys and JSON files) stay read-only until a validation
  pass succeeds (counts, hashes, files present). A copy of the store is kept
  until then.
- **Missing or unreadable content** becomes an explicit missing state, never an
  empty library.
- **Ownership triage:**
  - Records with no owner, and records owned by the currently valid Connected
    identity, join the journal.
  - Records owned by identities the backend confirms were deleted are treated
    as dead and join too, with no user-visible ownership state.
  - Only a genuinely conflicting **surviving** identity is quarantined: kept
    local-only, never synced, merged or deleted. There is no reconciliation UI
    in v1 unless testing shows it happens.
- **A locally empty device is not evidence that there's no journal.**
  Onboarding asks CloudKit whether the journal zone exists and, if it does,
  waits for the import ("Bringing in your journal…") without seeding anything.
  Seeding is effectively irreversible, so it needs server evidence (invariant
  3).
- **Deterministic seeded IDs plus a de-duplication pass** handle devices that
  already have a library, including iPads that ran the iPhone app in
  compatibility mode.

## Sequencing

0. **Architecture proof.** A disposable CloudKit container on two devices. The
   test covers:
   - iCloud account scope and switching accounts
   - multi-GB video against Apple's size limits (and whether files need
     splitting into chunks)
   - uploads in the background and after the app is killed
   - iCloud storage full, rate limiting, cellular and Low Data Mode
   - first import and seeding
   - delete-everywhere while another device is offline
   - concurrent ink revisions
   - Connected isolation

   The ink and Sketch record types are included, because the production
   CloudKit schema only accepts additions once deployed. Nothing reaches
   production.
1. **iPhone data foundation**, a public update with no new features:
   - explicit `kind`
   - Score, SessionScore and Asset
   - library data moved out of UserDefaults and JSON files
   - identity-independent visibility and ownership triage
   - the Connected-deletion split
   - deterministic colours
   - Sketch and ink entities in the model, with no UI yet

   Full rigour and a Codex review. It ships early on purpose, so the migration
   settles before anything depends on it.
2. **Practice controller**, as an iPhone update with identical behaviour.
3. **Sync**, internal and TestFlight only: the complete model, including ink
   written by an internal iPad build.
4. **The iPad release, with sync going public:**
   - adaptive shell, top-level Scores and Sketches, score-first Practice
   - page turners and Journal list/detail
   - Markup, Sketches and snapshots, and read-only viewing on iPhone
5. **Connected adaptations, in the same release:** comments beside posts,
   People from Feed, popovers, then keyboard shortcuts.

---

# Playback rate — agreed scope (Phase 5)

**Status: designed and agreed. Sequenced at the end of Phase 5, after the
staged-video measurement, so the media area is touched once.**

## Rationale

This enhances an existing review loop rather than introducing a new capability.
The workflow already exists: Practice → Record → Save → AttachmentViewerView →
Review → continue practising. Making review at reduced speed effortless is
expected to increase how often musicians record themselves, which serves the
product's emphasis on honest reflection rather than measurement.

## Scope

- **AttachmentViewerView only.** PracticeTimerView unchanged.
- **Audio and video both.** Slow-motion video matters as much as audio for
  reviewing bowing, hand position, embouchure or stick technique.
- **Playback behaviour is consistent regardless of media origin.** Whether
  media is local or Connected should not change what the musician can do. A
  musician is simply reviewing a recording; capability differences based on
  storage location read as bugs rather than product decisions. The
  implementation may involve separate playback paths, but the user experience
  should remain identical. If supporting both paths ever proves genuinely
  disproportionate, defer the feature rather than ship inconsistent behaviour.
- **Discrete rates: 50%, 75%, 100%.** Musicians think in steps, and a discrete
  control is far less fiddly on a small screen while holding an instrument.
- **No A/B looping.** Genuinely larger work. Follows later if valuable.
- **TestFlight exposure before release.**

## Implementation notes

Two APIs. `AVPlayer` backs remote audio (`RemoteAudioPlayerController`) and both
video paths; `AVAudioPlayer` backs local audio (`AudioPlayerController`). One
implementation covers three of the four surfaces.

**Pitch preservation is not optional.** 75% at the wrong pitch is worse than
useless — it is actively misleading. `AVAudioPlayer` requires `enableRate`,
after which pitch is preserved. `AVPlayer` requires `audioTimePitchAlgorithm`
set explicitly on the player item; do not rely on the default. Verify by ear on
real recordings.

**`AVPlayer.play()` resets rate to 1.0.** Transport currently uses
`play()`/`pause()` with no direct rate manipulation, so the selected rate must
be tracked and reapplied after resume. The failure is silent and passes a casual
first test.

**Rate must not carry into `MediaTrimView`.** Trim points set against distorted
timing would be wrong.

**Decide the immersive-chrome relationship.** The viewer hides controls during
immersive video playback (`isImmersiveVideoPlaybackActive`,
`immersivePlaybackChromeVisible`). Slow-motion review is exactly when a musician
may want to change rate mid-playback without summoning full chrome.

**Rate persistence.** Suggested: remember within a viewing session, reset on app
launch.

---

# Product Principles

Distinct from the architectural invariants above. The invariants are about data
and authority — falsifiable, near-absolute, checkable against code. These are
interaction and product judgements. Both matter; conflating them would dilute
the invariants.

## Reduce the ceremony between the musical impulse and the musical record

The test for any proposed feature: **does this shorten the distance between
having a musical impulse and having it recorded?**

The app should quietly understand context from decisions the musician has
already made, rather than repeatedly asking the same questions. It should infer
where it reasonably can, while never overriding explicit user intent. Invisible
assistance is preferable to additional interaction.

Corollaries:

- **A reminder is not friction reduction.** It is a different mechanism, aimed
  at motivation or guilt, which is what Études exists to avoid.
- **Live state is fine; historical state is guilt.** "Continue Practice"
  reflects something happening now and is useful. "Last practised: 9 days ago"
  reflects something that did not happen, and no neutral phrasing stops that
  being a reproach. This is why Live Activities are welcome and a streak widget
  would not be.
- The principle applies at both ends of the loop: easier to *begin* practising,
  and easier to *finish honestly*. An unfinished session is a journal-integrity
  problem, not just untidiness.

## No engagement mechanics

No likes, reactions, follower totals, popularity counts, rankings,
recommendations, algorithmic feeds, engagement scoring, trending content or
growth mechanics. Verified absent at audit and to remain so. Favourites are
private bookmarks; the feed is strictly chronological; profile metrics are
owner-only.

## Future platform entry points

All expressions of the ceremony principle rather than separate features, in
priority order:

1. **Shortcuts / Siri / Action Button** — "Start an Études practice session",
   plus **Quick Thought** as two separate shortcuts (Record / Type) so the user
   can bind whichever suits how they work. Quick Thought is a new entry point to
   an existing data type, not a new type — but it needs a genuinely minimal
   capture surface, because routing to `AddEditSessionView` in thought mode
   defeats the purpose.
2. **Live Activities / Dynamic Island** — current session presence, and
   crucially finishing without hunting for the app.
3. **Widget** — aggressively boring. "Start Practice" / "Continue Practice".
   No statistics, no streaks, no last-practised date.
4. **Apple Watch** — remote control only. Start, Pause, Finish, elapsed time.
   No attempt to recreate PracticeTimerView. Most valuable for wind players,
   singers and bowed strings, where the phone is genuinely out of reach.

**Shared precondition, deliberately not scheduled speculatively.** All four need
session lifecycle callable from outside `PracticeTimerView`. Note that timer
*state* is already externalised (`TimerDefaultsKey` in UserDefaults,
`TimerStateRecovery`, `PracticeTimerStore`), so the extraction may be smaller
than it appears — or unnecessary. **The iPad is now the first consumer:** Stage 2
of the iPad/sync plan extracts a narrow `PracticeSessionController`, which these
entry points should reuse rather than define their own.