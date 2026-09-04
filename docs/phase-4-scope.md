# PHASE 4 — SHARED-ONLY ARCHITECTURE. SCOPE RECORD.

**Status: SCOPE APPROVED. P4-U1 AND P4-U2a COMPLETE 2026-09-04.** U1 measured
and mutated nothing (`docs/phase-4-u1-baseline.md`); **U2a fixed C-60** — two
predicates in `PublishService`, verified against a faithful local reproduction
with the pre-fix run failing as the discriminator, zero production delta
(`docs/phase-4-u2a-acceptance.md`). **U2b, U2c, U2s, U3, U4, U5, U6, U7 and U8
have not started**: no client code, SQL, policy, production row or storage
object has been changed by this phase. This document is the durable record of
what Phase 4 is agreed to contain, in the same form as Phase 3's U0.

**Working branch:** `feature/solo-connected`. **Phase 3 closed 2026-09-03.**

---

## 1. The scope, restated

Phase 4 makes the deployed product match a promise the project has already
written down twice — **invariant 2**, *"If nobody else can see it, it does not
belong on Supabase"*, and `docs/architecture.md`'s Domain 3 definition, which
states that Domain 3 **"does not contain: unshared sessions, private notes,
attachments not explicitly included."**

Four agreed parts, from `CLAUDE.md`'s phase list:

1. **Shared-only uploads.**
2. **Purge historic unshared rows.**
3. **Remove the accidental analytics mirror** — the same defect as (1), named
   from the server's side.
4. **Align onboarding, settings and App Store privacy disclosures.**

Plus the register rows already owned by Phase 4: **B-8**, **B-15** (carrying
B-2's surviving half), **C-51**, **C-58**, **D-1**, **D-2**, **C-32** (jointly
with RC), and **C-34's version-signal half** (its TTL half stays Phase 5).

---

## 2. WHAT WAS MEASURED BEFORE SCOPING

**Seven findings, each measured rather than reasoned. Three of them change the
shape of the phase, and one dissolves a task the phase list assumes exists.**

### F-1 — THE MIRROR IS A LIVE, UNGUARDED CAPABILITY, AND NO PRIVATE POPULATION EXISTS AT THE MEASURED BASELINE

Read-only production census, 2026-09-04:

| | |
|---|---|
| `posts` total | **101** |
| `is_public = true` | **101** |
| `is_public` not true | **0** |
| distinct owners | **9** |
| range | 2026-03-02 → 2026-09-01 |

**There is no private population to purge at this measurement.** The phase
list's "purge historic unshared rows" describes a population that does not exist
**at the measured baseline**. The mechanism is nonetheless real and unguarded —
see F-2 and F-4 — so the client fix is still required.

**THIS MEASURES THE PRESENT POPULATION AND IT DOES NOT ESTABLISH HISTORY. STATE
IT NO MORE STRONGLY THAN THAT.** An earlier revision of this document said
production "has never exercised" the mirror and that "nothing private was ever
mirrored." **Neither is supported by the evidence recorded here**, and the
correction is kept visible rather than quietly applied.

**Why the stronger claim cannot be made, established rather than assumed.**
`public.posts` carries no history affordance: `created_at`/`updated_at` and
nothing else — **no soft delete, no tombstone, no audit column**. A read-only
enumeration of `information_schema.tables` (2026-09-04) confirms **no audit or
history table exists** for post writes anywhere in the `public` schema; the only
history-bearing tables are `membership_notification` (Apple's stream),
`membership_notification_reject_stat` and `shadow_enforcement_stat`, none of
which records a post write. **So a private post created and later deleted —
by an unshare, or by account deletion — would leave no trace, and the census
could not distinguish that from one that never existed.**

**The strongest supported statement is therefore:** *no private post rows exist
at the measured production baseline, and no private population exists to purge
at that measurement.* Everything the phase needs follows from that; the
historical claim was never load-bearing and is withdrawn.

**Do not read "zero" as "already fixed."** No gate produces that zero — the code
path is complete and would upload a private post today. **Task 2 therefore
becomes MEASURE-THEN-PURGE, and the measurement is worthless if inherited from
this document** — it must be re-run immediately before and after the client fix
lands (P4-U1, P4-U3).

### F-2 — ALWAYS-PUBLISH WAS DELIBERATE, AND ITS MOTIVATING DEFECT IS ALREADY FIXED

`AddEditSessionView.swift:2084` and `PostRecordDetailsView.swift:1836` both pass
`shouldPublish: true` as a literal. This is not an oversight. Commit
**`ec75a3c`** (2026-01-30, *"Fix PRDV share OFF defaulting in sync queue"*)
changed `shouldPublish: isPublic` → `shouldPublish: true` and recorded the
intent in the file header: *"Decouple publish vs share: always publish
session-backed post; is_public reflects Share toggle; eliminate stub posts from
Share OFF."*

**The defect it was fixing was a sync-queue merge bug, and that bug was fixed in
the same commit** — `SessionSyncQueue.swift:114`, *"explicit private always
wins"*, which stops a stub enqueue forcing `isPublic` back to true. So the
motivating reason for always-publish no longer holds.

**That is a reason to proceed, not a licence to skip verification.** Reverting
re-enables the `shouldPublish: false` branch, which has not executed in
production since January. F-3 is what is waiting there.

### F-3 — THE UNSHARE PATH DOES NOT DELETE IN PRODUCTION. THIS IS THE PHASE'S BIGGEST HAZARD

`PublishService.swift:197` and `:292` both gate the `deletePost` call on
`mode == .backendPreview`. Connected mode is **`.backendConnected`**
(`AppModeManager.swift:51`). `SessionSyncQueue.flushNow` correctly handles both
modes (`:174`); the delete does not.

**So a naive revert of F-2 — flipping `shouldPublish: true` back to
`isPublic` — would make un-sharing stop enqueueing WITHOUT deleting the row that
is already there.** The post would remain on the server, invisible to the user,
permanently. That is precisely the residue Phase 4 exists to remove, created
silently by the change meant to remove it.

**The delete path itself is well built and is not the problem.**
`BackendShim.deletePost` (`:1389`) fetches the attachment refs, deletes each
storage object, and **fails closed** — it refuses to delete the post row if the
objects cannot be removed. It is correct code wired to the wrong mode.

**Ordering consequence, and it is forced rather than preferred: the delete
gating must be fixed and verified BEFORE the publish condition is flipped.**

### F-4 — ATTACHMENTS UPLOAD WITH NO `is_public` CHECK, BUT THE DEFAULT IS FAIL-CLOSED

`BackendShim.uploadPost` calls `loadIncludedAttachments` (`:940`) and uploads
whatever it returns. There is **no `payload.isPublic` test anywhere in that
path**. The only filter is per-attachment: `AttachmentPrivacy.isPrivate` (`:1126`).

**The default is private** — `AttachmentPrivacy.swift:72` returns `map[key] ?? true`,
and an unresolvable key returns `true` at `:70`. So the exposure is narrow and
requires a specific sequence: the user explicitly marks an attachment as
included, **then** leaves or turns the session's Share toggle OFF. The session is
invisible to everyone; the media object is on Supabase Storage regardless.

**State this narrowly. It is not "all private media uploads."** Overstating it
would be the same error the register warns about under C-47 — a confident
mechanism that survives until someone checks the premise.

**It is subsumed by the U2 fix and must still be asserted separately.** Once
private posts are never enqueued, `uploadPost` never runs for them and the
attachments never upload. But that makes the attachment safety a *consequence*
of the publish gate rather than a property of the attachment path, so it needs
its own assertion or a later refactor silently reopens it.

### F-5 — THE JOURNAL RENDERS FROM CORE DATA ONLY. THIS IS WHAT DE-RISKS THE PURGE

`ContentView.swift:1050` computes `backendFeedStore.minePosts` for the `.mine`
scope, which looks as though the Journal is server-backed. **It is not.** Every
`.mine` render branch consumes `localRows` exclusively — `journalWeekSections`
(`:1132`) and `journalYearSections` (`:1223`) both take `localRows`. The remote
array flows only into `liveFeedItems` → `renderFeedItems`, which is gated
`selectedScope == .all`.

`minePosts` is otherwise read only by `PeopleView:380/730/775` and
`ContentView:1678`, all of which are **lookups by `postID` for shared posts**,
and by `DebugViewerView`.

**So removing private posts from the server is invisible in the app.** That is a
measured property of the render path, not an assumption — and it is the single
fact that makes the purge safe. **Re-verify it if the feed is refactored.**

### F-6 — FOUR UNREFERENCED STORAGE OBJECTS (B-8)

| bucket | objects | referenced | unreferenced |
|---|---|---|---|
| `attachments` | 15 | 11 | **4** |
| `avatars` | 3 | — | — |

`connected_attachments`: 31 rows, **6 live** (`deleted_at is null`). Post
attachment refs: 10.

Reference set computed as B-8 requires — the union of `posts.attachments` paths
and **live** `connected_attachments.storage_path`, with liveness read from
`deleted_at`, **never from the `users/<uid>/` path prefix**. B-8's own warning is
that the prefix carries the *sender's* uid and a dead sender is the correct state
for a preserved asset; B-22 already produced one false positive that way.

**The volume is trivial and the risk is entirely in the heuristic.**

### F-7 — C-57's PHASE CELL READS `4` AND THE ROW IS RESOLVED

C-57 (403 collapsing a locally entitled client into Solo) was **resolved and
device-verified 2026-09-02** with a before/after on the same device. Its Phase
cell still reads `4`.

**It owes Phase 4 nothing.** Recorded here rather than silently corrected, for
the same reason C-9's stale `3` was left in place: the tagged-row denominator
must stay mechanically recomputable from the cells, and quietly aligning it
destroys the distinction between "tagged" and "open".

### F-8 — THE DURABILITY BOUNDARY, AND THE ORDERING THAT DECIDES IT

**Investigated read-only / source-only, 2026-09-04, because "an old build can
re-upload" was recorded as a hazard note and a hazard note is not a closure
condition.**

**(a) What accepts a private post write today.** One policy, and nothing else:

```
posts_insert_owner  INSERT  WITH CHECK
  ((SELECT enforcement_gate('posts.insert')) AND (owner_user_id = auth.uid()))
```

There is **no `is_public` predicate anywhere on the write path** — not in the
policy, not in a CHECK constraint, not in a trigger. Worse, the column is
**`is_public boolean NOT NULL DEFAULT false`**, so the schema default is the
privacy-unsafe value: an insert that merely *omits* the column creates a private
row. The shipping client always sends it explicitly, so this is latent rather
than active — but it means the server currently has no opinion at all.

**(b) THE ORDERING, WHICH IS WHAT MAKES A SERVER GUARD SUFFICIENT.** In
`BackendShim.uploadPost` the post row is written **before** any Storage object:

| step | line |
|---|---|
| `POST rest/v1/posts` | `:901` |
| non-409 failure → **`return .failure(e)`** | `:921` |
| `patchPostMetadata` | `:926` |
| `loadIncludedAttachments` | `:940` |
| `uploadStorageObject` | `:969` |

**So a server-side rejection of the post row returns at `:921`, upstream of the
attachment loop, and the old client never uploads the Storage objects at all.**
That is the decisive result: it means a guard on the row also covers the media,
which was the open question. It is a property of the existing control flow, not
of anything Phase 4 adds — **re-verify it if `uploadPost` is reordered.**

Only 409 is treated as "already created and continue" (`:917`), and an RLS
refusal is 403, a constraint refusal 400. **Neither can be mistaken for the
idempotent path.**

**(c) No client-version mechanism exists, so Option B is not cheap.** The client
sends **no version signal of any kind** — a source sweep finds no
`CFBundleVersion`/`CFBundleShortVersion` read, no `X-Client`/app-version header
and no custom `User-Agent` anywhere in `MOTIVO/`. `CLAUDE.md` separately records
that **both configurations are hard-coded `1.0 (131)` and never incremented**, so
a build cannot even be *identified*, let alone gated. A minimum-build route would
require three new mechanisms — incrementing build numbers, adding a version
header, and a server-side minimum-version check — to obtain what one policy
clause obtains.

---

## 2a. THE DURABILITY DECISION — OPTION A, NARROWED TO INSERT

**Adopted: backend defence-in-depth, as a single clause on the existing insert
policy.**

```
posts_insert_owner  WITH CHECK  ... AND (is_public = true)
```

**Why this is the smallest architecture that makes the invariant durable:**

- **It covers Storage for free**, by F-8(b)'s ordering — no separate storage
  policy, no bucket rule, no cleanup coupling.
- **It neutralises the `DEFAULT false` fail-open** in F-8(a) at the same time.
- **It converts a build-tracking problem into a server-side invariant.** The
  closure question stops being *"has every pre-U2 build been retired?"* — which
  is unfalsifiable on a cohort of personal devices — and becomes *"can any client
  create a private post row?"*, which is **measurable from the server, once,
  independently of which builds exist.** That is strictly stronger than the
  informal tester-behaviour assumption it replaces.

**IT MUST NOT SIT BEHIND THE MEMBERSHIP KILL SWITCH, and the surrounding code
invites exactly that mistake.** `enforcement_gate` returns `true` when
enforcement is inactive, so the added clause applies in both switch positions —
which is correct, because **this is a privacy invariant, not membership
enforcement**. Do not wrap it in `enforcement_active()` to match the neighbouring
U6b pattern; a rollback of membership enforcement must not re-open the mirror.

### UPDATE IS DELIBERATELY EXCLUDED, AND THE OBVIOUS SYMMETRIC CLAUSE IS A DEFECT

A matching `is_public = true` on `posts_update_owner` looks like completeness and
is **harmful**. An old client's un-share is a PATCH setting `is_public = false`;
blocked, that PATCH **fails and the post stays PUBLICLY VISIBLE to followers**
while the member believes they have unshared it. That is a worse outcome than the
residue it would prevent — a privacy regression with a success-shaped UI.

**The un-share path is fixed on the client instead (U2a), where it belongs**,
because only the client can delete the Storage objects first —
`BackendShim.deletePost` (`:1389`) already removes every referenced object and
**fails closed**, refusing to delete the row if any object survives. A
server-side trigger that deleted the row on `is_public → false` would strand
those objects and manufacture B-8 orphans.

### THE CONSEQUENCE FOR PRE-U2 CLIENTS, STATED RATHER THAN DISCOVERED

A stale build attempting a private post receives a refusal. `SessionSyncQueue`
treats **only** 409 as success (`:186-206`), so the item **stays queued and
retries on each flush**. The result is a stuck queue entry on stale builds, no
data loss, and the content remaining local — **the fail-closed direction, which
is the one we want.** It should be verified in QA rather than met as a surprise.

**What Option A does NOT do.** It does not remove the client fix; U2 is still
required, because a server refusal is a backstop and not a user experience. It
does not purge anything. It does not touch `get_account_directory_by_user_ids`,
membership, or any U6b surface.

---

## 3. THE UNITS

**Ordering is forced by dependency in three places and is not a preference.**

### P4-U0 — this document

The scope record. No code.

### P4-U1 — MEASUREMENT BASELINE — **COMPLETE 2026-09-04**

**Evidence: `docs/phase-4-u1-baseline.md`.** Censuses re-run read-only at
`78e2002` and **identical to the scoping run**: 101 posts / 101 public / **0
private**, 9 owners; 15 attachment objects with **4 unreferenced**, pinned by
`md5(name)[0:8]` so no production UID enters the repository. B-8's reference-set
method is written down verbatim for U4 to reuse. Structural baseline
`supabase/tests/p4/u1-baseline.sh` **16/16**; `MOTIVOTests` **15/15**; U5
client-structural **60/60**; Debug and Release both **BUILD SUCCEEDED**. The
Phase 3 carry-forward — `LocalFactoryReset.perform`, exactly two callers — is
**verified and pinned by count** (a naive grep says 3; the third is a doc
comment). Predictions for U2, U2s and U3 are committed there.

**Why it is a unit and not a preamble:** the phase's central measurement — that
no private post rows exist — is a statement about a **moving population**, not
about history (F-1). Inherited from this document a month from now it is an
assertion; re-measured at the moment of the fix it is evidence. Phase 3 learned
this four times (C-52 and three repeats): **a durable document asserting a fact
is not evidence of that fact.**

### P4-U2 — SHARED-ONLY UPLOADS

The core of the phase. Three sub-units, in this order:

- **U2a — fix the delete gating (F-3). COMPLETE 2026-09-04**, C-60 Resolved.
  `docs/phase-4-u2a-acceptance.md`. As scoped: make the unshare path delete in
  `.backendConnected`, not only `.backendPreview`; verify against a real unshare
  before anything else changes. **This was the precondition for U2b being safe
  rather than harmful**, and it is now met.
- **U2b — make publish conditional.** `shouldPublish: isPublic` at both call
  sites, restoring the pre-`ec75a3c` semantics now that its motivating defect is
  independently fixed. Editing a shared session to unshared must delete the row
  and its storage objects; saving a private session must upload nothing.
- **U2c — assert the attachment gate (F-4).** A structural assertion that no
  upload path is reachable for a payload with `isPublic == false`, so the
  property survives a later refactor of `uploadPost`.

**Thoughts are the sharpest case and belong in U2's acceptance.**
`AddEditSessionView.swift:1829` sets `isPublic = false` unconditionally in
thought mode, and the publish block is guarded only by
`appModeManager.canShareWithFollowers`. A Thought saved while Connected is
today a private server row. It is the most personal content the app holds.

### P4-U2s — THE SERVER-SIDE SHARED-ONLY GUARD

**The durability half of U2, adopted at §2a.** One clause added to
`posts_insert_owner`'s `WITH CHECK`: `AND (is_public = true)`.

**Deploy it AFTER U2 ships and BEFORE U3's purge.** After U2, because deploying
it first would make the *current* build's Thought-and-Share-OFF saves start
failing against a client that has no better path — a self-inflicted incident.
Before U3, because the purge is only durable once the state cannot be recreated.

**Not behind the kill switch. INSERT only.** Both constraints are argued at §2a
and both are easy to "improve" into defects.

**Verification is a deploy-time gate, not a code review.** Follow the U6a/U7
pattern that this project already paid for: a guard inside the transaction
asserting the state it has just produced, and a final `SELECT` that returns a
row, so *"Success. No rows returned."* becomes the symptom rather than the
disguise. `supabase db query --linked` is single-statement and cannot carry it.

### P4-U3 — PURGE, CONDITIONAL ON U1

If U1 measures zero, this unit is a **recorded no-op with evidence**, which is
the strongest available outcome and must be written as such — not omitted, and
not dressed up as a completed purge.

If it measures non-zero, purge **by explicit id**, the way B-22 was done, with a
prediction committed beforehand. **Never a liveness-predicate sweep** — that is
B-8's trap and B-22's recorded false positive.

**A purge is only durable once no device running a pre-U2 build remains.** An
old build re-uploads on its next save. The cohort is nine owners, all
pre-release beta (B-36), so this is controllable — but it is a real ordering
constraint, not a formality.

### P4-U4 — B-8 STORAGE ORPHAN CLEANUP

Four objects at F-6. Encode B-8's liveness rule as a guard in the cleanup itself,
not as a comment above it.

### P4-U5 — B-15 DIRECTORY ANTI-BROWSE, WITH C-34's VERSION SIGNAL

The deployed function already carries the marker:
`char_length(btrim(q)) >= 2 -- Prevent browse behaviour. Weak; B-15, Phase 4.`

**Two standing warnings apply and both are load-bearing.** `ad.user_id <> auth.uid()`
is self-exclusion and **not** a security control; the `auth.uid() is not null`
test is what makes the function survivable and **must not be removed while
tightening the floor**. And `get_account_directory_by_user_ids` must keep **no**
subject-side filter — that is G10, and it is why undiscoverability and retained
attribution can coexist.

C-34's version-signal half (a content version on `avatar_key` so a replaced
avatar invalidates other members' caches) is grouped here because it is the same
`account_directory` surface. **C-34's TTL half stays Phase 5.**

### P4-U6 — C-51 RUNTIME VERIFICATION

The one route that can still reach upload selection with stale paths: a publish
enqueued in `SessionSyncQueue` that flushes after a container rotation. Needs
fault injection.

**U2 shrinks this surface without closing it** — private sessions never enqueue,
so only shared ones can carry a stale path into a queued flush. Note the
interaction; do not claim it as a resolution.

### P4-U7 — C-58 FOLLOWER ATTRIBUTION FOR A LAPSED VIEWER

P3, bounded, product/UX. Not a defect; the current fallback is safe and
withdrawal still works. The global fix is explicitly rejected in the row.

### P4-U8 — COPY AND DISCLOSURE ALIGNMENT

D-1, D-2, C-32, and the App Store privacy labels.

**Must be last, and that is forced.** C-32's own cell says the copy cannot be
finalised before the upload change lands. Writing it earlier would describe an
app that does not exist yet — which is the failure mode this phase is correcting.

**D-2 dissolves under U2** and should be recorded as dissolved rather than
implemented.

---

## 4. EXPLICITLY OUT OF SCOPE

- **C-34's TTL half** — Phase 5.
- **B-16** (`post_comment_views` orphans) — Phase 6.
- **C-41** (dead `lookup_enabled` plumbing) — Phase 6. Related to U5 by subject,
  not by dependency; pulling it in would widen the phase for tidiness.
- **M14 / personal iCloud sync** — deliberately deferred; its absence is not a
  defect.
- **The four carried Phase 3 obligations** — G7, C-31, B-34, and the production
  GRANT on B-11. None is unblocked by Phase 4 and none is owned by it.
- **Renaming MOTIVO → Etudes** — not release work.

---

## 5. REGISTER IMPACT

| Row | Disposition under Phase 4 |
|---|---|
| **B-8** | Owned — P4-U4 |
| **B-15** (carrying B-2's surviving half) | Owned — P4-U5 |
| **C-51** | Owned — P4-U6 |
| **C-58** | Owned — P4-U7 |
| **D-1**, **C-32** | Owned — P4-U8. C-32 is joint with RC |
| **D-2** | Expected to **dissolve** under U2, not to be implemented |
| **C-34** | Version-signal half owned (U5); TTL half stays Phase 5 |
| **C-57** | **Resolved already.** Stale phase cell — F-7 |
| **C-60** | **FILED 2026-09-04 by this scoping pass** — F-3's unshare/delete defect. Owned by P4-U2a |

**C-60 is filed rather than absorbed into U2's description**, because it is a
distinct defect with a distinct mechanism — the mirror is *what is uploaded*,
C-60 is *what is not removed* — and a unit description is not a register row.

### C-31 IS NOT TOUCHED BY THIS PHASE, AND THAT IS CHECKED RATHER THAN ASSUMED

**C-31 (Production Billing Grace) remains an OPEN carried release obligation,
owned outside Phase 4.** Verified 2026-09-04: its register row is unmodified by
this pass, it appears in §4 among the carried Phase 3 obligations, and **no
Phase 4 unit reads, resolves, renumbers or depends on it.** Phase 4 touches the
publish path, storage cleanup, the directory function and customer-facing copy;
**none of those is an App Store Connect configuration**, which is what C-31 is.

Recorded explicitly because C-31 is exactly the shape of obligation that gets
absorbed by accident: it is a *configuration* promotion with a **24-hour
propagation window** and no code artefact, so nothing in the repository fails
when it is forgotten. **Its 24-hour propagation must still elapse before any
grace-dependent lifecycle QA is run or scored** — unchanged by this phase, and
restated here so that a Phase 4 QA pass does not silently inherit it.

---

## 6. ENTRY AND EXIT

**Entry conditions — all met:** Phase 3 closed; the client structural harness
exists and is the right instrument (`supabase/tests/u5/client-structural.sh`,
comment-stripped assertions on client source); `MOTIVOTests` runs since C-54;
production is readable read-only via single-statement `supabase db query --linked`.

**Exit conditions:**

1. No path uploads a post with `isPublic == false`, asserted structurally.
2. Un-sharing deletes the row and its storage objects in `.backendConnected`,
   device-verified.
3. The production census re-run after the fix shows zero private posts, with the
   pre-change number recorded beside it.
4. **DURABILITY — THE CONDITION THIS PHASE MUST NOT CLOSE WITHOUT.** *No client,
   of any build, can create a private post row.* Demonstrated **positively**, by
   a rejected write, not inferred from a census reading zero: with the U2s guard
   deployed, an attempted `is_public = false` insert is **refused**, and the
   refusal is observed. **A post-fix census reading zero is NOT sufficient
   evidence for this condition** — that is the exact failure this condition
   exists to prevent, since a stale build could recreate the state the day after
   the census. Whichever build produced the attempt is irrelevant, which is the
   point of solving it server-side (§2a).
5. Zero unreferenced attachment objects, or each survivor explicitly
   dispositioned.
6. Onboarding, settings and App Store privacy disclosures describe the shipped
   upload behaviour.
7. **`LocalFactoryReset.perform` still has exactly two callers.** This is a Phase
   3 exit assertion that Phase 4 must not break.

**Explicitly NOT an exit condition: "every pre-U2 build has been retired."**
Under §2a it is not needed — the invariant is enforced where it can be measured
rather than assumed of a set of personal devices. **Had Option B been adopted it
would have been condition 4**, and this is where it would have been recorded.

---

## 7. HAZARDS, RANKED

1. **F-3.** A naive revert creates permanent invisible residue while appearing to
   fix the problem. Mitigated by the forced U2a → U2b order.
2. **A purge that precedes the U2s guard** silently refills. Ordering at P4-U2s.
   Note this hazard is **retired by §2a** rather than merely managed — it is kept
   here because it returns in full if the guard is dropped from the phase.
3. **B-8's path-prefix heuristic** destroys exactly what B-1 protects. Recorded
   in the row; encode it as a guard.
4. **Removing B-15's `auth.uid() is not null` test** while tightening the floor
   would return the whole directory to any holder of the shipped anon key.
5. **Writing U8's copy before U2 lands** describes an app that does not exist.
6. **Adding the symmetric `is_public = true` clause to `posts_update_owner`** —
   it looks like completeness and is a privacy regression. See §2a.
7. **Wrapping the U2s guard in `enforcement_active()`** to match the neighbouring
   U6b pattern, which would let a membership rollback re-open the mirror.
