# C-65 — INVESTIGATION. STOPPING FOR A DECISION BEFORE MUTATION.


> **SCOPE CLARIFIED 2026-09-10.** Everywhere this file says "an attachment the member selected", read
> **an attachment the member explicitly marked share-enabled**. Attachments are default-private with a
> per-attachment private-eye control, and `loadIncludedAttachments` skips every private one — so a private
> local attachment of any size never enters the publish path and is not "omitted" by it. C-65's invariant
> was always about the explicitly-shared set; this states it rather than leaving it implied.

**Inspected at `bbe0651`, 2026-09-09. No code changed.**
**Stopping under the standing rule:** *"If investigation shows that
blocking/retrying the entire publish creates a worse established invariant, stop
and report rather than forcing this product decision through the wrong
mechanism."* It does, at the current failure site — and a second established
decision contradicts the new invariant.

---

## 1. The six questions, answered from source

**(a) Where preparation failure becomes the deliberate skip.**
`BackendShim:1056` — `guard let prepared = prepareAttachmentForRemoteUpload(item)
else { … continue uploadLoop }`. The `else` **always** continues; the PDF branch
only adds a `print`.

**(b) What the durable queue considers success/failure.**
`SessionSyncQueue.flushNow` (`:293`–`:299`): `.success` → **dequeue**, gone
forever. `.failure` → **stays queued**, retried on every launch/foreground.
There are exactly **two** states. HTTP 409 is coerced to success so the queue
cannot stick.

**(c) What retry/error state already exists.**
No retry cap, no backoff, no attempt counter, no error field — by deliberate
design (P4-U2a-2: *"Abandoning an owed privacy withdrawal after N attempts is
the wrong failure"*). **"Queued and not yet converged" is an established,
accepted state in this architecture**, which is why using it for a preparation
failure would be consistent rather than novel.

**(d) Whether the member already has a failure surface. NO — CONFIRMED.**
The only reader of queue state is `DebugViewerView:973`, which is `#if DEBUG`
and **absent from Release**. `PublishService` surfaces **nothing** on failure —
no error line, no alert, no throw. The queue is `ObservableObject` with
`@Published items`, so a surface *could* be built, but none exists.

**(e) Whether retry can succeed without duplicate publication. YES, end to end.**
Post insert: a 409 is treated as created and execution continues into upload +
PATCH (`:1015`). Storage upload sends **`x-upsert: true`** (`:1338`) — *"Allow
safe retries (idempotent paths)"*. The attachment PATCH is idempotent. **Retry
is already safe by construction.**

**(f) Whether the same shape exists for non-PDF paths.**
**For *preparation*: no.** `prepareAttachmentForRemoteUpload` returns `nil` only
on the PDF branch; every non-PDF returns a value, so the second
`continue uploadLoop` is dead code today.
**But a second silent-partial-success path DOES exist and is not PDF-specific —
see §3.**

---

## 2. THE BLOCKER: at the current site, returning failure is WORSE

**Measured ordering inside `uploadPost`:** the post row is `INSERT`ed at
`:1000`; `loadIncludedAttachments` runs at `:1038`; the skip is at `:1056`.
**The post row already exists by the time a preparation failure is discovered.**

So returning `.failure` at the skip site would produce:
- a **published post, visible, with its media missing** — the exact outcome the
  invariant rejects, unchanged; **plus**
- an item that retries on **every** foreground, forever, for a failure that may
  be deterministic.

**Strictly worse than today.** That is the wrong mechanism.

### The smallest behaviour that actually satisfies the invariant

**Hoist preparation ahead of the post INSERT.** `loadIncludedAttachments` needs
only `payload.sessionID` (`:1201`–`:1205`) and touches nothing the INSERT
creates, so preparing every included attachment *first* is feasible with no new
architecture. Then:

- **all prepare** → proceed exactly as today;
- **any fails** → return `.failure` **before any row is created**. Nothing is
  published, the item **stays queued**, and it retries on the next foreground —
  the established convergence path, identical in shape to the unshare rule.

That converts *"falsely complete"* into *"observably incomplete and retryable"*
using only semantics the queue already has. **No new notification or error
architecture.**

### The residual this leaves, named rather than hidden

**A permanently unrenderable attachment never converges.** The queue has two
states — done, and try again — and **no third state meaning "this needs your
attention"**, with no Release surface to show one (§1d).

Whether that matters depends on the real failure mix, which is **not measured**:
a **missing or unresolvable file** (P4-U6's container rotation) is transient and
retry fixes it; a **corrupt or encrypted PDF** is permanent and retry never
will. `AttachmentStore.generatePDFThumbnail` returns `UIImage?` with no error, so
the two are not distinguishable at that call — though **file existence is cheaply
checkable** if you want the split drawn.

**Note the member's perception is unchanged either way**, and that is what makes
this acceptable: a queued-but-unconverged publish already looks shared locally,
because `isPublic` is the member's own toggle. That is the established offline
behaviour the project chose deliberately, not something this change introduces.

---

## 3. A CONTRADICTION WITH AN ESTABLISHED DECISION — your call

**`BackendShim:1088`–`:1094` silently skips OVERSIZED attachments** and keeps
the publish alive, with `skippedOversizedCount` and the comment
*"Option B: skip oversized attachments, but keep the publish alive for valid
ones."*

**That is the same shape the invariant now forbids** — the member selected the
attachment, it cannot be published, the publish reports success and says
nothing — and unlike the PDF case it is **not PDF-specific and was decided
deliberately**. It is also **permanent by nature**: retrying a file that exceeds
the limit can never succeed, so the queue-failure mechanism above is the wrong
answer for it.

**I have not touched it.** Reporting per instruction rather than improvising.

---

## 4. What I need from you

1. **Approve the hoist-then-fail design** (§2) as C-65's fix, accepting that a
   permanently unpreparable attachment leaves the item queued indefinitely — and
   that this residual gets its **own row** rather than a new surface invented
   here. *(Recommended.)*
2. **Decide the oversized skip (§3):** leave "Option B" standing as an explicit
   carve-out from the invariant, or bring it into scope — which would need a
   member-facing surface, because retry cannot help it.
3. Optional: whether to split **transient (file missing) from permanent
   (unrenderable)** by a cheap `fileExists` check, so only the transient class
   retries.

**Nothing is implemented. C-66, C-68 and C-69 remain untouched and unverified.**
