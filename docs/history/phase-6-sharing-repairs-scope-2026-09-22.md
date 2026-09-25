# Sharing repairs — bounded scope for review (revision 2)

22 September 2026 · `feature/solo-connected` @ `5c77beb` · **DESIGN ONLY**

Claude, on Samuel's bounded authorisation; revised after Codex's review of revision 1.
**Nothing here is approved, implemented or measured.** No application or test code was
edited, no migration written, nothing deployed, configured, purchased or deleted.

**What changed in revision 2.** Revision 1 proposed five items as scope. After review, **one
is ready and it is small hardening; the rest need bounded design before any of them is
implementable.** Two of its claims were wrong and are corrected below rather than softened.
No architecture is assumed necessary; no general asset registry is proposed.

---

## 0. Corrections to revision 1

**C1 — R1-b did not close either characterisation, and I presented it as though it did.**
Its convergence condition was "retry until the owner's own read shows the post absent". That
read can return absent *before* the late commit, after which the marker clears and the
correction is gone — the original defect, one level up. It also guarded only
`noRowMatched`, while the second characterisation
(`P6I02WithdrawalOutcomeTests:246`) acknowledges `rowDeleted`. And a marker written when an
error is *reported* does not exist at all if the process dies mid-publish, so it would have
to be written **before dispatch**, which is a change to the queue's write path, not an
addition beside it.

**C2 — supersession does not cancel a request already sent.** I offered it as the protection
against a correction outranking a deliberate newer share. It protects the *queue*; it cannot
recall a dispatched delete. `OperationBinding.isStillCurrent` re-checks generation, factory
reset, store health and current owner — **not the intent revision** — so a publish admitted
before a newer intent continues through its remaining phases.

**C3 — S3's "no reachable sequence in the current app" was wrong.** Corrected in §3.

**C4 — P5 does not resolve uncertain outcomes.** Retracted in §2b.

**C5 — "the common case" for direct-send failures was unmeasured.** Retracted.

Revision 1's §0 reconciliation of my earlier over-broad and overly-small proposals stands and
is not repeated here.

---

## 1. S1 — unknown late completion, now understood as a family

### What is characterised

`MOTIVOTests/P6I02WithdrawalOutcomeTests.swift:224` and `:246` characterise a request the
server has received but not committed while the client has been told it failed. **These are
characterisations, not production incidents**, and their commit timing must not be altered to
make any repair look like closure.

The same unknown-completion premise generates a family, all on **one device, one post, with
queue flights sequential from the client's point of view**:

- **Withdrawal defeated** — an unresolved publish commits after an acknowledged withdrawal
  (`noRowMatched` *and* `rowDeleted`).
- **Reference restored** — an earlier reference PATCH reports transport failure but commits
  later, restoring a reference that a subsequent publish had deliberately excluded (the
  member had just made that attachment private).
- **Bytes overwritten** — an unresolved object upload commits after a later edit and
  re-publish, overwriting newer bytes, because the path is deterministic and uploads carry
  `x-upsert: true`.

They are **variants of one problem and must not become a second work programme.** No second
device, restore or sync premise is needed for any of them.

### Completed protections — do not re-verify for discovery

Single-flight `flushNow`; per-(owner, post) revisions so a superseded intent is neither sent
nor acknowledged; generation invalidation on factory reset; owner binding re-evaluated before
every request, refresh and retry; store-halt re-checked per item; no retry cap on a
withdrawal; demote-before-delete; the saved-choice recovery barrier; and S2b's accepted case
showing that **Share OFF during an in-flight upload already converges**. *Re-running these as
regression after any future edit is expected; what is excluded is re-running them for
discovery.*

### The structural limit

Every variant is a request the client has already sent and cannot recall, whose outcome it
cannot learn. **No client-side mechanism can order it.** A client mitigation can only widen
the window in which a correction happens; it cannot make one. That is a property of the
problem, not of any particular design.

### Therefore: a decision, not a default recommendation

**Option S1-X — defer, and say so.** Change nothing. State in the guarantees that a
withdrawal is confirmed against the server's answer at that moment and that Études cannot
order a request whose outcome it never learned. Cost: nothing. Buys: nothing.

**Option S1-Y — client mitigation.** A pre-dispatch durable marker per (owner, post) recorded
*before* any publish request, cleared only on a definitive outcome; withdrawals withheld from
acknowledgement on **both** `noRowMatched` and `rowDeleted` while a marker exists; retries on
a stated schedule. **Exact benefit:** catches a late commit that lands *before* the
confirming read, and only then. **It does not close any of the three variants**, does not
catch a commit after the read, does nothing if the member never returns, and cannot recall a
correction already sent. **Cost:** a change to the queue's write path, durable state written
on every publish, and a retry schedule — noticeably more than revision 1 implied, for a
partial window.

**Option S1-Z — a tightly bounded server ordering design, scoped only.** Commission a design
whose stated job is that no request issued before a withdrawal can take effect after it, and
that a deliberate later share is unaffected. It is the only option that can close the family,
including the reference and byte variants, which S1-Y does not touch at all. **Not
pre-approved, not sized, and not a minimum.** Scoping it is a decision about whether to spend
design effort, not about implementing anything.

**S1-Z's boundary, stated so it cannot drift.** Its job is ordering the existing same-device
late-completion family while preserving the queue, revision and ownership model. It is **not**
a vehicle for a general publication and retirement system, an asset registry or an
immutable-version scheme, and §2's retirement work is **not** to be folded into it. If a
design proposal grows beyond ordering, that is a new decision, not a detail of this one.

**My recommendation is not S1-Y by default.** On value per cost, S1-Y buys a partial window
at a real cost in the most load-bearing file in the client; S1-Z is the only thing that buys
the guarantee. If the guarantee is not a launch promise, **S1-X plus honest wording is the
proportionate answer**, and S1-Y is not worth its cost in between.

---

## 2. S2 — retention hygiene

Separable from §1 and **lower urgency, which is not the same as harmless**. Every item here
is a deletion, so the failure direction of a bad repair is destroying something still needed,
and retaining is the safer of the two errors. But retention has its own cost: access issued
before an attachment was excluded may still work, and what Études tells a member about
removing something is a promise retention does not keep. "Retain by default" is a rule about
which mistake to prefer, not a claim that retained bytes are fine.

### 2a. Attachment made private or removed on an already-shared session

**Current behaviour.** `loadIncludedAttachments` (`BackendShim.swift:1317`) skips private and
consented-omitted attachments; the re-publish PATCHes the new reference set and deletes
nothing. The object remains at `users/<owner>/<postID>/<attachmentID>.<ext>`.

**Harm.** Bytes remain that the member believes are no longer shared. No *new* authorisation
is granted — `attachments_select_via_visible_post` requires the path to be in that post's
current references — but whether a link or cached response issued earlier stays usable is
**unknown**, so this is retention beyond intent and possibly a residual-access window.

**Why revision 1's repair is not implementable as written.** Three defects, all Codex's:

1. `patchPostAttachments` (:1590) sends `Prefer: return=minimal` and treats **every 2xx as
   success**. A zero-row PATCH — membership denied through `posts_update_owner`'s gate, or the
   row concurrently deleted — is indistinguishable from an applied one. Retiring old paths on
   that basis can delete objects while the row still names them. A validated owner-scoped
   result is required first, using the existing `SingleRowRepresentation.classify`. *This is
   not the withdrawn F-2 remedy: that concerned the ungated owner DELETE, where demanding a
   row would have broken a lapsed member's withdrawal (C-35). A publish PATCH already
   requires entitlement, so validating it costs a lapsed member nothing.*
2. **Old paths are known only between the read and the delete.** If the PATCH commits and the
   app then dies, or the delete fails, the next publish reads only the new references and the
   old paths are lost for ever. Promising a retry needs a small durable pending-retirement
   record; without one the repair is **best-effort and must be described that way**.
3. **`JournalDeleteBackendStep.run` calls `publish.deletePost` directly and only afterwards
   supersedes the queue**, so a journal delete is outside queue flight and is not serialised
   with a publication in progress. Traced consequence, one device, ordinary use: the publish
   uploads its objects; the journal delete fetches references that do not name them yet and
   deletes the row; the publish's reference PATCH then affects zero rows, is read as success
   and is acknowledged — leaving **uploaded objects with no row, and no local session left to
   name them**. That is a concrete in-app route to exactly the retention this section is
   about, and prefix scoping does not address it.

**Status: bounded design needed.** Ordering must be traced and settled before any deletion is
written, and retention stays preferable to an unsafe delete.

### 2b. Failed or uncertain direct send

**Current behaviour.** `ConnectedAttachmentSharing.upload` (:199) mints a fresh `assetID`,
POSTs the object with `x-upsert:false`; `deliver` (:241) is a separate row INSERT;
`ConnectedAttachmentShareUI.send` (:616) surfaces the error and leaves the object. A retry
mints a new `assetID`, so each attempt adds an object. Frequency is **unmeasured**.

**The seven objects observed in production are plausible beta residue of unknown origin.**
They justify no scope, size no repair and authorise deleting nothing.

**B1 — delete only on a rejection that establishes no row was written.** Narrower than F-6's
withdrawn remedy, which deleted on any reported failure. **Not implementable as stated:** the
classification is the whole content of the repair and needs review against recorded response
shapes, and it must consider the operation's own history — `NetworkManager` retries a 401
once, so a rejection observed on one attempt does not by itself characterise the operation.
Timeouts, cancellations and unclassifiable responses are never rejections.

**B2 — retracted as revision 1 described it.** An existence function returning `true` proves a
reference exists **now**; `false` proves absence **now** and nothing about a later commit. A
SQL function cannot atomically span an ordinary Storage API deletion and an unrestricted later
INSERT. **P5 does not resolve uncertain outcomes** and that claim is withdrawn. A durable
record of the intended bytes and exact recipient set still has independent value — it is what
any later resolution would need — but resolution itself needs coordinated publication and
retirement ordering, which is §1's S1-Z, not a lookup.

### 2c. Failed final reference update

No repair proposed, unchanged. A reported failure may be a committed PATCH whose response was
lost, so deleting the uploads can break a live post — F-6's withdrawn remedy, not
reintroduced. Recorded as a known limitation.

---

## 3. S3 — corrected

Revision 1 said no reachable sequence exists in the current app. **That was wrong**, and the
absolutes it rested on are withdrawn:

- The revision guard is checked **before** admission; `OperationBinding.isStillCurrent` does
  not check it afterwards, so a publish admitted before a newer intent runs its remaining
  phases regardless.
- An acknowledged supersession does not cancel a request already sent.
- The journal delete runs **outside** queue flight (§2a.3).
- "Requires two sources or devices" is unsupported: the reference-restoration and
  byte-overwrite variants are same-device, same-post sequences.
- A deliberate re-share on a restored device authorises **new** bytes and intent. It does not
  license a stale earlier operation overwriting them.

**None of this establishes a release blocker, and none of it expands the architecture.** All
of it folds into §1 as variants and constraints: any correction must not outrank a deliberate
newer intent, and no repair may assume the client can order its own sent requests.

---

## 4. Corrected recommendation

### Ready now

**R1-a — do not acknowledge an unsent simulated withdrawal.** In Connected or Preview mode
without HTTP configuration, `BackendEnvironment.publish` falls back to
`SimulatedPublishService`, whose bound `unsharePost` returns `.simulatedUnverified`, which
`flushOnce` acknowledges (`SessionSyncQueue.swift:1003`). Hold it instead. Deterministic, not
a race. **Release reachability: configuration-fault hardening, not an observed ordinary
failure.** The bundle bootstrap is non-DEBUG, so a released build *attempts* configuration —
which is not proof that every release bundle is configured, and the unconfigured state is
therefore **not excluded**. It should not be labelled user-facing essential; it is cheap
insurance against a state we have not ruled out. Client-only; `SessionSyncQueue.swift`; unit coverage
only; no device action.

That is the whole of what is ready.

### Needs bounded design before it is implementable

- **D1 — withdrawal ordering.** Decide between S1-X, S1-Y and scoping S1-Z (§1). Everything in
  the S1 family depends on this decision, including reference restoration and byte overwrite.
- **D2 — retirement safety.** Validated owner-scoped PATCH results, a durable
  pending-retirement record if retries are promised, and the journal-delete ordering trace,
  before any object deletion is written (§2a).
- **D3 — direct-send rejection classification.** What establishes that no row was written,
  given a 401-retry history (§2b).

### The decision to put to Samuel

These are **two separable decisions, not one scope**:

1. **Withdrawal guarantee.** Is "once withdrawn, no earlier request can bring it back" a
   product promise? If yes, only S1-Z can deliver it and scoping it is the next step. If no,
   S1-X plus honest wording is proportionate, and S1-Y is not worth its cost.
2. **Retention hygiene.** Optional and deferrable. The default is retain. If it is wanted, D2
   and D3 come first and the existing production residue stays an operator disposition,
   handled separately and never as justification for the repair.

## 5. What this document does not establish

Not a minimum safe release and it does not size one. Nothing here is measured. No item closes
the S1 family. Provider retention, cache and physical-byte behaviour are untouched. The
existing queue, revision and ownership model, the saved-choice recovery, the restore
protections, the ungated owner withdrawal, the local-data boundary and the expiry-versus-
deletion rules are preserved by every option above, by design.
