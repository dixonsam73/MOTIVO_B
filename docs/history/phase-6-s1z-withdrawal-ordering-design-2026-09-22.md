# S1-Z — server-enforced withdrawal ordering: bounded design (revision 2)

> **READ THE REVIEW STATUS BELOW FIRST. This revision is NOT approved and its guarantees are withdrawn.**

22 September 2026 · `feature/solo-connected` @ `5c77beb` · **DESIGN ONLY, NOT APPROVED**

Claude, for independent Codex review. **No application or test code was edited, no migration
written or executed, nothing deployed, configured, purchased or deleted.** SQL below is
illustrative prose. Risks addressed are **characterised and code-supported, never observed
hosted incidents**, and no test's late-commit timing is changed.

---

# REVIEW STATUS — NOT APPROVED, NOT IMPLEMENTATION-READY

**Second Codex review, 22 September 2026: revision 2 is NOT signed off.** RPC mediation is
accepted as a better *candidate* than revision 1's trigger, and nothing more. **Six
counterexamples falsify the guarantees this document states**, and they are recorded here
before the design text so no reader reaches §9 believing it stands.

**Withdrawn here and now, in advance of the next revision:**

- **V1, V2 and V3 are NOT closed by this document.** Every closure claim below — §3, §6 and the
  guarantees in §9 — is withdrawn.
- **The effort position is "unavailable", not "gated on three things".** §12's framing is
  withdrawn with it.
- **HOLD.** No concurrency fixture is to be run, no implementation begun. A further bounded
  design pass is needed; none of what follows is for Samuel to adjudicate, because all of it is
  engineering correctness.

## Unresolved findings

**A — pruning reintroduces reminting.** Pruning a request mapping at or below the fence makes a
delayed `mint(T1)` a *miss*, which then mints above the fence. Permanent idempotence and bounded
pruning cannot both be claimed without an independent stale-request rejection rule. §2's
"bounded" and §3's idempotence claim are both withdrawn.

**B — the withdrawal's target is wrong in three ways.** (i) A target captured at enqueue can lag
an in-flight mint: the queue knows E1 while the current publish's mint commits E2, and E2 is
never fenced. (ii) A **null-target `begin` is not safe on one install**: its own completion is
unknown, so it can arrive after a re-share and fence E2. Last-intent replacement prevents
*dispatch*, not a call already sent — the same class as the problem this design exists to solve,
and §3's one-install safety claim is withdrawn. (iii) `begin(target E1)` against a row at E2
returns **E2's references unconditionally**, so the client deletes E2's files while `finalise`
correctly preserves E2's row. **Cleanup authority must be tied to the exact withdrawn
publication; a global `withdrawn_epoch` is not the operation's target.**

**C — fencing is not hiding, and the references are not durable.** `begin` raises a write fence
and never demotes. `posts_select_public_or_owner` contains no fence predicate — verified: it does
not mention `publish_epoch` — so a stalled file removal leaves withdrawn content **visible** to
followers. §5's removal of demote-before-cleanup is wrong and demote must be preserved. Separately,
holding the references only on the mutable `posts` row means a deliberate new share overwrites
them, so §5's crash-and-retry convergence claim is **false** unless those references survive
independently.

**D — V3 is not closed, in the scoped same-device case.** An upload at E1 whose outcome is
unknown, retried at the same E1 with changed bytes, is later overwritten by the original. Both
carry E1, so epoch path isolation does nothing. §6's claim is withdrawn, and "a retry should
publish what the member now has" is **not fresh consent** and must not stand in for it.

**E — the DELETE trade is not what §4 claims, and was not mine to accept.** A legacy direct
DELETE raises **no fence**, so an upgraded in-flight publish can recreate the post after an old
build's withdrawal — a larger residual than "a newer row removed". And the compatibility benefit
is largely illusory: `unsharePostImpl` PATCHes `is_public = false` first and **returns early on
failure** (`BackendShim.swift:1860`), so with UPDATE revoked an old build's *unshare* never
reaches its DELETE at all. **One refinement, offered as fact rather than defence:** the *journal
delete* path is `deletePostImpl`, which carries no demote, so that one does still function for an
old build. The distinction to draw next time is **entitlement-independent withdrawal for updated
clients**, not compatibility with every old beta. §4's recommendation is withdrawn.

**F — the request identity does not cover the first operation.** `JournalDeleteBackendStep.run`
calls backend deletion **before** queue supersession, and a `requestID` minted only in
`noteNewIntent` therefore does not exist for it. Intent must be checked **before each phase**,
not once at binding. And §10's "the handoff record carries the whole payload" does not establish
a durable request-identity lifecycle across replay and migration; that lifecycle has to be
specified.

**Two further corrections.** §3's "exactly one lock object, so no deadlock cycle" is **stronger
than the sketch establishes** — the publish path also takes `posts` row locks and mapping-row
locks, with FK and trigger interactions and background workers touching the same rows; the
absolute is withdrawn. And the entitlement check must be re-implemented on
`post_set_attachments_v1` as well, not only `post_publish_v1`.

**Agreement.** I agree with every finding above. The only thing I add is the E refinement, and it
narrows my error rather than excusing it.

---

## 0. The headline: revision 1's trigger design cannot meet the guarantee

Codex asked me to say so if that were true. It is.

- **A `BEFORE UPDATE` trigger cannot require an epoch on an UPDATE.** `NEW` is the resulting
  row, so a PATCH that omits `publish_epoch` presents the OLD value, which is `NOT NULL` and
  already above the fence. An older client could therefore still alter references and metadata
  on an upgraded row. The `NULL` refusal only ever covered INSERT.
- **A row trigger does not fire for a PATCH that matches no row.** Revision 1's claim that the
  journal-delete race would become "an explicit refusal instead of a silent zero-row success"
  was **false**, and is withdrawn.
- Revision 1 also **never required the epoch to be one the server had issued**, so any large
  integer would pass.

The RLS old/new limitation was a reason not to use RLS. It was not a reason to choose a
trigger. **The smallest defensible replacement is a narrow authorised mutation surface: the
publish-path writes to `posts` go through `SECURITY DEFINER` functions, and the direct
INSERT/UPDATE privilege that lets a client bypass them is revoked.** A typed return is then
available for free, which §4 needs anyway.

Everything below is that design. Four further corrections to revision 1 are folded in:
**choiceToken is not a request identity** (§1), **R-c is reachable and is closed by protocol,
not by argument** (§3), **withdrawal needs a target fence** (§3), and **the withdrawal must not
regress today's working object cleanup** (§5).

---

## 1. Identity: a durable request id, not the choice token

Revision 1 made `choiceToken` the authorisation subject. That was wrong on evidence:
it is optional (`SessionSyncQueue.swift:162`), journal-delete withdrawals carry none (:681
onward), and the enqueue merge keeps an older token against a changed payload
(`merged.choiceToken = payload.choiceToken ?? existing.choiceToken`, :589). It is **provenance,
and a useful input; it is not an immutable publication identity.**

**`requestID: UUID`, minted in `noteNewIntent`** — the one place that already runs on every
enqueue and every merge, and that already mints the in-memory revision. So the request id is
**the durable twin of the existing revision**, not a parallel concept: any change to a post's
queued intent mints a new one; a retry of unchanged intent keeps its own. Journal-delete
withdrawals get one by construction, because they go through the same enqueue.

Optional with a `nil` default, decoded explicitly — the `op` / `authorisedOmissions` /
`choiceToken` precedent. A legacy item with no request id **cannot be dispatched** and is held,
for the same reason unattributable work is held today.

## 2. State

- `posts.publish_epoch bigint not null default 0` — existing rows land at 0; minting starts at 1.
- `post_publish_control(owner_user_id, post_id, current_epoch, withdrawn_epoch, updated_at)`,
  PK `(owner_user_id, post_id)`. **Survives the row's deletion — this is the tombstone, and it
  is why the absent-row withdrawal can be fenced at all.**
- `post_publish_request(owner_user_id, post_id, request_id, epoch)`, PK `request_id`. The
  durable token→epoch mapping revision 1 lacked. **Bounded:** a row whose `epoch <=
  withdrawn_epoch` can never authorise anything again and is pruned by the withdrawal that
  fenced it, so the table holds at most the live requests of live posts. This is not a registry
  of content; it is one integer per outstanding intent.

Both tables: RLS enabled, **no client policy, no table privilege for `authenticated`**. Reached
only through the functions below — the discipline U5b established for
`ensure_membership_binding()`.

## 3. Operations

All five take **exactly one lock object**, the control row, first:

```
insert into post_publish_control(owner_user_id, post_id) values (auth.uid(), p_post_id)
  on conflict do nothing;
select * from post_publish_control
  where owner_user_id = auth.uid() and post_id = p_post_id for update;
```

One lock, acquired first by every writer, so there is no acquisition order to get wrong and no
deadlock cycle to construct. The `on conflict do nothing` is what makes "no control row yet"
an ordinary case rather than a race; a concurrent insert that wins simply means the `select …
for update` blocks and then finds the row. Under READ COMMITTED this serialises mint, publish
and withdrawal for one post, which is the only serialisation this protocol needs. **Transaction
proximity is not serialisation and is not being relied on.** §7 states how this is accepted,
and it is not by a stub.

**`post_publish_epoch_v1(p_post_id, p_request_id) -> bigint`**
Mapping hit → return that epoch, unchanged. Miss → `current_epoch + 1`, write the mapping,
advance `current_epoch`, return. Idempotent per request id, which is what revision 1's single
`choice_token` column could not do: T1→E1, T2→E2, retry T1 now returns **E1**, not a fresh E3.

**`post_publish_v1(p_post_id, p_request_id, p_fields jsonb) -> typed`**
Resolves the epoch **from the mapping** — the client never supplies a number, so an arbitrary
large epoch is unrepresentable. Refuses if the request is unknown, if its epoch `<=
withdrawn_epoch`, or if it is below the row's current epoch. Otherwise upserts the row and sets
`publish_epoch`. It re-implements the two `posts_insert_owner` conjuncts internally —
`enforcement_gate('posts.insert')` and `is_public = true`, with owner from `auth.uid()` — because
a `SECURITY DEFINER` function bypasses RLS and that entitlement check must not be lost in the
move. **That transfer is the single most security-critical part of this design and needs
review on its own.**

**`post_set_attachments_v1(p_post_id, p_request_id, p_refs jsonb) -> typed`**
Same fence. Returns `applied` / `no_row` / `refused(reason)`. **This is what makes a zero-row
outcome visible**, which no trigger could do.

**`post_withdraw_begin_v1(p_post_id, p_through_epoch bigint) -> (withdrawn_epoch, refs, row_present, row_epoch)`**
Raises `withdrawn_epoch` to `greatest(withdrawn_epoch, coalesce(p_through_epoch,
current_epoch))`, prunes mapping rows at or below it, returns the row's references **without
deleting anything**.

**`post_withdraw_finalise_v1(p_post_id, p_through_epoch) -> (row_deleted)`**
Deletes the row **only if `posts.publish_epoch <= withdrawn_epoch`**.

`p_through_epoch` is the withdrawal's **target fence**, captured when the withdrawal is
enqueued. Revision 1 had none, so a delayed old withdrawal would have deleted a newer
deliberate share — Codex's counterexample, now answered by an exact transition: a re-share at
E2 above the fence is neither deleted by `finalise` nor covered by `begin`. When the client
cannot know a target (a ledger-candidate withdrawal for a post this install never published),
`p_through_epoch` is `null`, meaning "whatever is current at the call". **Stated limit:** a
null-target withdrawal cannot be fenced against a re-share made between enqueue and dispatch.
On one install the queue's last-intent replacement removes that case; across installs it
remains, and this design does not claim otherwise.

### The two calls cannot be merged, and that is the crux

A single "mint and publish" call would leave nothing recorded when its outcome is unknown, so a
later withdrawal could not fence it and it could still commit — V1 again. Separating them is
what lets the withdrawal see the intent.

**The client rule that closes R-c: a publish write is never sent without a *confirmed* epoch,
and an unknown mint outcome is re-minted with the same request id until confirmed.** Because
minting advances `current_epoch` before any publish can carry it, any later withdrawal's
`greatest(current, withdrawn)` fences it. The residue Codex identified — a mint committing
after a withdrawal — then records an epoch **that nothing will ever carry**, because the queue
item that would have carried it was replaced by the withdrawal and never dispatched. Harmless,
and stated as a dependency on the queue's last-intent replacement rather than hidden.

Eager minting at Save does not remove this and Codex is right that revision 1 implied it did;
it only moves the same unresolved-mint window earlier, at the cost of refusing offline saves.
**Lazy mint at first dispatch is therefore the proposal**, on the merits rather than by default.

## 4. Bypass, legacy builds and the cutover

**`authenticated` loses INSERT and UPDATE on `posts`.** That, not a trigger, is what stops a
client writing around the fence, and it closes the omitted-column hole completely.

**`authenticated` keeps DELETE**, deliberately. `posts_delete_owner` is ungated so a lapsed
member can withdraw without re-subscribing (C-35), and **there are existing beta and device
builds** — revision 1's "no installed base" was false and is withdrawn. Revoking DELETE would
take withdrawal away from those installs, which is the one capability that must never regress.
**Accepted residual, stated: an older install's stale DELETE can still remove a newer row.** The
alternative — revoke DELETE and route it through `post_withdraw_finalise_v1` — closes that and
costs older installs their withdrawal until they update. I recommend keeping DELETE open and
recording the residual; it is a narrow trade and it is the safer direction.

A trigger is retained **only as a backstop for `service_role` and `postgres`**, where no RPC
mediates. It is not the fence.

**Cutover.** Existing rows sit at epoch 0 and acquire a control row lazily on first mint. Older
client builds can no longer publish or PATCH; they can still withdraw. `DebugViewerView:505`
PATCHes `posts` directly and would stop working — Debug-only, noted rather than worked around.

## 5. The withdrawal must not regress cleanup that works today

Revision 1 deleted the row inside one RPC and returned no references, so the object paths
existed only in a response that could be lost. **That would have regressed ordinary successful
cleanup, which is not optional garbage collection.** Withdrawn.

The two-phase shape preserves today's order while still fencing first:

1. `post_withdraw_begin_v1` — fence raised, references returned, nothing destroyed.
2. Client deletes the objects, fail-closed, with the existing already-absent semantics.
3. `post_withdraw_finalise_v1` — row deleted.

Response loss or process death at any point leaves the `.unshare` item queued; a retry re-runs
`begin` (idempotent, returns the references again), finds objects already absent (success), and
finalises. **Converges, keeps fail-closed, and the fence is up from step 1.**

## 6. Storage, and exactly what path isolation does and does not buy

Database ordering is not a Storage completion fence: an upload admitted before a withdrawal can
commit afterwards, whatever a policy said at admission.

Path isolation — `users/<owner>/<postID>/<epoch>/<attachmentID>.<ext>` — buys two things and
they are worth stating separately:

- a stale **upload** carrying an old epoch writes to its own prefix and cannot reach a newer
  publication's bytes;
- a stale **delete** carries old-epoch references and therefore cannot reach newer objects
  either. Revision 1 missed this second benefit, and it is the mitigation for the
  owner-prefix delete bypass in §4.

**It does not make content immutable, and no such claim is made.** `uploadPostImpl` reloads the
attachments from Core Data on each attempt, so a retry at the same epoch may upload different
bytes — which is intended, since a retry should publish what the member now has. Per-attempt
isolation would make an object per attempt and is rejected: it manufactures retention, which is
§2 of the scope document and unapproved.

**Cost, unchanged from revision 1:** each new epoch writes to a fresh prefix, so the previous
epoch's objects become unreferenced. Path isolation converts V3 from corruption into retention.
Given the §4 delete-bypass benefit I now recommend taking it rather than leaving it as an open
choice, and the retention it creates stays owned by the separate, unapproved retirement work.

## 7. Verification — two instruments, for two different claims

**Backend concurrency is accepted on a real local Postgres**, not a stub: concurrent sessions
issuing mint, publish, withdraw and finalise against one `(owner, post)`, with the original
delayed timings preserved, asserting the lock is taken by every writer, that no interleaving
admits a fenced epoch, that a newer share survives a delayed withdrawal, and that no deadlock
arises. **A stub that assumes the desired fence proves nothing about the database**, and
revision 1 implied otherwise.

**Client behaviour is accepted on the existing suite.** `P6I02WithdrawalOutcomeTests`' two OPEN
BLOCKER cases are the instrument; **their commit timing is unchanged** and what changes is the
stub's modelled server response. They invert from "passes while the blocker reproduces" to
"passes because the late commit is refused". Added: a stale request id refused; a re-share after
withdrawal admitted; a delayed withdrawal not deleting a newer share; `no_row` from
`post_set_attachments_v1` surfaced rather than read as success; the two-phase withdrawal
converging after a simulated death between phases; a legacy item with no request id held.

**Device.** The entitled hardware share-and-withdrawal run **has already happened — 2026-09-16,
recorded in `phase-4-exit-assessment.md` §2.1, row and object removed.** Revision 1's claim that
an entitled identity is an outstanding prerequisite was stale and is withdrawn; it is not
re-proposed. What a *new protocol* needs is its own regression on hardware after implementation,
which is a different thing from re-running completed discovery.

## 8. Rollback, honestly

Revision 1's kill switch admitted every write. **That is a capability rollback, not a privacy
rollback: it reopens exactly the stale writes the fence exists to refuse.** Two modes, and the
default matters:

- **`paused` (the safe fallback).** New publishes refused; **withdrawal continues to work**.
  Fails closed in the privacy direction. Cost: members cannot share until it is lifted, and
  queued publishes accumulate — which is a visible product outage, not a silent one.
- **`open` (capability rollback).** Everything admitted, stale writes included. Available, but
  only as a deliberate act with that consequence stated.

Full removal is a DDL rollback of the migration, rehearsed with the apply in the U6a/U6b shape.

## 9. Guarantees this supports — with the overclaims removed

1. When you stop sharing something, an earlier attempt of ours cannot bring it back.
2. If you remove an attachment from something you shared, an earlier attempt cannot restore it.
3. Sharing again later is a new choice and is not blocked by an earlier withdrawal. *(Not "always
   works": it is subject to being signed in, entitled and online, like any share.)*
4. A withdrawal made offline is pending until it reaches the server and does not survive
   uninstalling Études or losing the phone first.

**Limits, published rather than implied.** A link or cached copy already issued may remain
readable; **we do not know the upper bound for this deployment** and the vendor's documented
figure is not an end-to-end measurement. We ask the provider to delete files and cannot prove
when bytes or provider backups are destroyed. An older install can still withdraw, and its
stale withdrawal can remove a newer share (§4). Guarantee 1 covers Études-issued requests, not
anything already downloaded.

## 10. Affected surfaces

**Client.** `SessionSyncQueue.swift` (request id minted in `noteNewIntent`, persisted, held when
absent; the withdrawal's target fence captured at enqueue; a typed refusal that is neither retry
nor success). `BackendShim.swift` (`uploadPostImpl`, `patchPostMetadata`,
`patchPostAttachments`, `unsharePostImpl`, `deletePostImpl` move to the RPCs; the 409 idempotence
heuristic is retired with the direct POST). `JournalDeleteBackendStep.swift` (two-phase
withdrawal). `PublishService.swift`, `SharingHandoff.swift` — unchanged; the handoff record
carries the whole payload, so saved-choice recovery keeps working by construction.

**Backend.** One migration: column, two tables with RLS and no client policy, five functions and
their grants to `authenticated`, the `service_role` backstop trigger, the pause/open switch, and
the `authenticated` INSERT/UPDATE revoke on `posts`. One statement in `delete_account_v1`
removing the departing member's control and request rows, inside its existing fail-closed
sequence. **`membership_cleanup_v1` must advance the fence for every post it deletes** — resolved
here rather than left as a question, because retaining a control row without advancing its fence
does not invalidate pending authority, which was the whole reason for retaining it.

**Preserved:** single-flight queue, revisions and identity ownership, saved-choice recovery,
backup-exclusion and install-stream restore protections, ungated owner withdrawal, every
local-data boundary, and the expiry-versus-account-deletion rules apart from the two statements
named.

## 11. Alternatives

| | Option | Verdict |
|---|---|---|
| Trigger-mediated (revision 1) | | **Rejected — §0.** Cannot require an epoch on UPDATE, does not fire on zero-row, cannot bound the epoch to one issued |
| RPC-mediated with revoked INSERT/UPDATE | | **Proposed** |
| RPC-mediated, also revoking DELETE | | Closes the stale-delete residual; takes withdrawal from existing beta installs. Rejected on that cost (§4) |
| Client-supplied epoch, no mint | | Rejected: a withdrawal could only fence epochs already **committed**, so an issued-but-uncommitted publish would pass |
| Tombstone keyed on post id only | | Rejected: bricks legitimate re-sharing |
| Client-only mitigation (S1-Y) | | Partial for V1, nothing for V2 or V3 |

## 12. Effort — not defensible yet, and this is exactly what is missing

Revision 1's ranges are withdrawn: the design changed shape, and ranges for a design that could
not meet its guarantee were worthless.

Three things gate an estimate, none of which needs Samuel to adjudicate anything technical:

1. **The concurrency acceptance result** on a real local Postgres (§7). It decides whether the
   single-lock protocol holds as written or needs a stronger isolation level.
2. **A complete reachability audit of every `posts` writer**, so the revoke's blast radius is
   known rather than assumed. Known so far: five publish-path writers in `BackendShim.swift`
   (`:1120`, `:1570`, `:1603`, `:1711`, `:1845`), two reads (`:1957`, `:2070`), and
   `DebugViewerView:505`.
3. **Review of the entitlement transfer** in `post_publish_v1` (§3), which moves two
   security-critical conjuncts out of RLS.

Shape, not size: the backend resembles U6b's binding unit plus B-38's guard; the client is
larger than revision 1 implied, because the publish transport changes rather than gaining a
field. I am not attaching numbers to that until (1) and (2) are done.

## 13. What this does not do

It does not recall a request already sent. It does not make content immutable. It makes no claim
about physical erasure, provider backups, or revoking a link or cached response already issued —
and it depends on nothing Supabase has not answered, so SU-478356's silence changes none of it.
It does not address leftover-file cleanup, direct-send uncertainty, or the seven beta-residue
candidates. It is not a release approval and not an established minimum.
