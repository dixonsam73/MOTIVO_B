# Études — Data Architecture

This document contains three kinds of statement, and they carry different weight:

**Architectural boundaries** (Domains 1–4) — settled, and should almost never
change. Reopening one requires genuine new evidence, not a preferred design.

**Product principles** — guide judgement where the answer isn't obvious. Stable
in direction, but applied case by case.

**Designed future work** (Threads, Playback rate) — the design is agreed; the
implementation and timing may still evolve. Treat the reasoning as binding and
the details as revisable.

---

Four domains. The boundaries are permanent; the engine for Domain 2 is deferred
to M14.

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

**Roadmap:** M14 will sync this domain. Decisions taken early so it is not
foreclosed — per-record modification timestamps, a sync-tolerant shape for the
Scores library, stable attachment identity rather than path-as-identity.

---

## Domain 2 — Personal cloud (future optional iCloud sync, M14)

**Contains:** a user-controlled mirror of Domain 1, opt-in.

**Why:** continuity across the user's own devices. Not a sharing mechanism.

**Owner:** the user, in their own iCloud account, against their own quota.
Études never has access — the developer cannot read it even in principle.

**On membership expiry:** entirely unaffected. No relationship to Connected. A
user who never pays can use it. Durability is never gated on monetisation.

**Roadmap:** M14, after M13. iPad creates the need for multi-device continuity;
sync satisfies it.

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
| All local data | Untouched | Erased, because the user asked |

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
Thoughts are Sessions, so they already carry `threadLabel` structurally — which
means manuscript pages, if they land as Thoughts in M13, inherit thread
membership at no cost.

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

**Secondary:** Scores, manuscript Thoughts and eventually Task Sets would all
reference the same thread. Each holding its own copy of a string makes rename
an N-way update and lets a typo silently fork one thread into two.

**Latent benefit:** the tint system already resolves colour by thread. With an
entity, thread colour could be chosen rather than derived.

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
string to a Thread entity with Scores, manuscript pages, Task Sets and resume
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

## Why M13

Entity conversion, manuscript-pages-as-Thoughts and the sync groundwork are one
coherent piece of foundation work rather than three. Together they mean one
migration, one set of lifecycle decisions, and M14 inheriting a model designed
to sync rather than adapted to it.

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
than it appears — or unnecessary. Let the first real consumer prove what shape
the seam needs rather than designing it in advance. If both are on the horizon,
letting M13 iPad drive it produces a better-shaped seam than a Shortcut would.