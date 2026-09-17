# Claude review — Connected Lists backend

2026-09-17. **Review only.** No repo edit, commit, push, deployment or live mutation was
performed. Unrelated legal/invitation docs and app changes untouched.

## VERDICT: **GO**, subject to the four conditions in §6.

The change is correctly scoped, correctly guarded, and — the part that mattered most —
**satisfiable against the deployed schema**. Two checks could each have made it fail on
first contact with production; both were run and both pass. Five non-blocking findings are
recorded in §4, and §5 carries a **correction to this review**.

**CORRECTED 2026-09-17 after Codex review.** §5 originally asserted an oversized-List
orphan gap. **That was wrong and is withdrawn** — the size guard runs before any write or
upload. §5 now states what survives, which is narrower and not list-specific. **N-1 and N-2
are dispositioned by Codex** in §4.

**All seven reviewed-file SHA-256 hashes match the brief exactly.** Repo on
`feature/solo-connected` at `c43b168`.

---

## 1. The checks that could have broken this, and their results

These are the ones I would not deploy without, given this project's history.

### 1.1 `page_count = 0` is SATISFIABLE — verified, and it nearly wasn't

`connected_attachments` already carries `CHECK (page_count >= 0)`. **`0` is permitted.**

**Had that constraint been `>= 1`, the new List constraint would have been unsatisfiable
and every List delivery would have failed after a successful deploy** — a green apply and a
product that still cannot send. Checked, not assumed.

`CHECK (byte_count >= 0)` likewise admits the new `1..131072` range as a strict subset.

### 1.2 No NULL bypass — verified against deployed nullability

The new check is `mime <> list OR (byte_count … AND page_count = 0 AND storage_path LIKE …)`.
If any referenced column were nullable, a List row with a NULL would evaluate
`FALSE OR NULL → NULL`, **and a CHECK constraint passes on NULL** — the intended guarantee
would be silently unenforced. This is the project's own three-valued-logic lesson (D4/U3).

Deployed snapshot: `storage_path`, `mime_type`, `byte_count`, `page_count` are **all NOT
NULL**. The predicate is strictly two-valued. **No bypass exists.**

### 1.3 `page_count` DEFAULT is 1 — so the client must send 0 explicitly, and it does

An insert omitting `page_count` takes the default **1** and would be **refused**. Verified
coupling: `ConnectedListSharing.swift:23` passes `pageCount: 0`, and
`ConnectedAttachmentSharing.swift:~258` puts `reference.pageCount` in the delivery row.

### 1.4 The constraint tests `storage_path`, not `filename` — and the path does carry the suffix

Worth isolating because the client sets both, and only one is checked.
`safePathExtension` (`:360-362`) returns `localURL.pathExtension` **lowercased**;
`ConnectedListSharing.swift:18` creates the temp URL with `.appendingPathExtension("etudeslist")`;
the path is built at `:215` as `users/<uid>/connected/<assetID>.<ext>`.
So `storage_path` ends `.etudeslist` and `LIKE '%.etudeslist'` holds.

It also satisfies the **pre-existing** `connected_attachments_sender_storage_path` regex
`\.[A-Za-z0-9]+$` — `etudeslist` is alphabetic — and the identical regex in the sender
INSERT policy's `WITH CHECK`.

### 1.5 The diagnosis matches the observed failure

`attachments_user_insert_auth` `WITH CHECK` constrains **only** the enforcement gate,
`bucket_id`, the `users/` prefix and `folder[2] = auth.uid()` — **no MIME and no extension**.
So the bucket `allowed_mime_types` is the *only* thing refusing the upload, which is exactly
what `invalid_mime_type` reports and exactly what this change extends. The reported symptom
and the proposed fix are the same object.

## 2. Apply wrapper — sound, and it applies the right lesson

- **One transaction**, `lock_timeout 5s` / `statement_timeout 120s`.
- **PRE guard inside the transaction** pinning the exact existing constraint definition and
  the exact bucket configuration.
- **POST guard inside the transaction** asserting the bucket now carries the type and that
  **both** constraints are `convalidated`.
- **Ends with `SELECT 'Lists MIME enabled'`** — a row.

That last point is the U6a lesson honoured: an apply that returns no rows once disguised a
**complete no-op** reported as *"Success. No rows returned."* Here the verification row is
the success signal.

Two operational properties of `supabase db query --linked`, already established in this
project and directly relevant: a `RAISE EXCEPTION` **aborts the whole submission** so the
post-`COMMIT` `SELECT` does not run; and **the process exit code is `0` even then**.
**Score the response body, never `$?`.**

The single `ALTER TABLE … DROP …, ADD …, ADD …` is one statement, so validation happens in
one pass under one lock. All existing rows satisfy the re-added MIME check (it is a
superset), and no List rows exist, so the new check validates trivially.

**Re-running the apply is refused**, because the PRE guard pins the pre-apply array and
constraint. Fail-closed, correct.

**Migration/apply parity confirmed:** `20260917120000_connected_lists_mime.sql` is the same
guards and the same DDL, minus the explicit transaction and verification row.

## 3. Permissions, lifecycle and rollback

**No widening — verified structurally.** The change touches no policy, grant, function,
trigger, table or column. Lists are ordinary `connected_attachments` rows and therefore
inherit, unchanged:

- the sender INSERT policy's **approved-follow `EXISTS` requirement** (so Person/Ensemble
  eligibility and follow direction are exactly as today);
- `enforcement_gate` on both the storage insert and the row insert (**entitlement
  enforcement unchanged**);
- the recipient storage read, which joins `storage.objects` to
  `connected_attachments … recipient_user_id = auth.uid() AND deleted_at IS NULL`.

**Teen position, stated so it is not mis-assumed:** B-40 governs **follow requests**, not
attachments, and is untouched. Lists ride **existing approved follows**, so a 13–17 member
can send and receive them exactly as they can any attachment today. **This change neither
widens nor narrows the teen position** — but it is not a teen-restricted feature, and
nobody should read it as one.

**Lifecycle:** ordinary expiry retains sent attachments while a live recipient reference
remains (ref-counted on `deleted_at IS NULL`); account deletion removes the sender's sent
rows and objects. Neither path filters on MIME or extension, so Lists are carried without
change.

**Rollback is genuinely safe and better than its brief required.** It refuses if **either**
a List row **or** a `.etudeslist` / list-MIME object exists — two independent
representations, so a row without an object (or the reverse) still blocks. The row check
carries **no `deleted_at` filter**, so a **soft-deleted** List row also blocks, which is
right: a soft-deleted row still references a stored object. `array_remove` preserves order,
so the reverted bucket array should be byte-identical to the pre-apply value.

## 4. Non-blocking findings

**N-1 — the PRE guard does not pin the constraint the new check depends on.** It pins the
MIME constraint and the bucket, but not `connected_attachments_sender_storage_path`, which
is what actually governs the path shape `LIKE '%.etudeslist'` relies on. Nothing is wrong
today (§1.4), and the apply does not touch it. But if that regex ever changed, the guard
would still pass while the new constraint became unsatisfiable.

**DISPOSITIONED by Codex 2026-09-17: accepted as an assumption, pinned by fresh FULL
constraint and policy baseline validation immediately before apply, rather than by expanding
the reviewed migration.** That is a sound resolution — it covers the same risk without
re-opening a file whose hash has already been reviewed, and it catches any drift in the
regex, not merely the one constraint I named. **Closed.**

**N-2 — `LIKE '%.etudeslist'` is case-sensitive. CLOSED — the lowercase wire suffix is
intentional**, confirmed by Codex, and `safePathExtension` lowercases unconditionally. The
coupling is deliberate rather than incidental, so no change is wanted. Recorded only so a
future reader does not "fix" it into a case-insensitive form and weaken a deliberate
invariant.

**N-3 — pre-existing bucket/table divergence, informational.** The bucket allowlist contains
`audio/m4a`, which the **table** constraint does not. Pre-existing, not introduced here, out
of scope — but neither list is authority for the other, and a future reader comparing them
will find a discrepancy that this change did not cause.

**N-4 — rollback refuses on any unrelated allowlist change.** The guard pins the exact
14-element array, so if any other MIME type is added meanwhile, rollback stops with
"re-review required". Fail-closed and correct; flagged only so it is not mistaken for a
fault under time pressure.

**N-5 — the delta will appear in two snapshot files.** `constraints.json` (one modified, one
added on `connected_attachments`) and `storage_buckets.json` (allowlist **13 → 14**, verified
captured). `policies.json`, `functions.json`, `function_grants.json`, `table_grants.json`,
`column_grants.json`, `rls_enabled.json`, `triggers.json` and `columns.json` must all be
**unchanged**. **If anything else moves, stop and re-review.**

## 5. CORRECTION — the oversized-List gap I asserted does not exist

**WITHDRAWN.** This section originally claimed that a List over 128 KiB would upload
successfully and then be refused at the row insert, leaving an orphan. **That is false, and
the error was mine:** I read `ConnectedListUpload` and concluded "no size pre-check" without
following the call it opens with.

**The chain, read in full:**

```swift
// ConnectedListUpload.upload
let data = try list.encoded()                 // FIRST — throws .tooLarge
let url  = temporaryDirectory…                // not reached when oversized
try data.write(to: url, options: .atomic)     // not reached when oversized
return try await service.upload(…)            // not reached when oversized
```

```swift
// SavedList.swift:76-80
func encoded() throws -> Data {
    let data = try JSONEncoder().encode(validated())
    guard data.count <= Self.maxBytes else { throw ConnectedListError.tooLarge }
    return data
}
```

**The guard precedes the temp write and every network call**, so no object is ever created
for an oversized List. `validated()` runs first and independently bounds name (≤ 200 chars),
item count (≤ 500) and each line (≤ 4000 chars).

**The bounds are exactly equal on both sides, which is a positive worth recording.**
`ConnectedListPayload.maxBytes = 128 * 1024 = 131072` is precisely the constraint's upper
bound, and the server's `byte_count` is the size of the same bytes written verbatim to the
temp file — so client and server agree exactly, with no window between them. A payload of
exactly 131072 passes both. The lower bound is safe too: `validated()` forbids an empty name
and empty items, and JSON is never zero bytes, so `byte_count >= 1` always holds.

**What survives, stated narrowly and NOT attributed to list size.** `upload()` and
`deliver()` are two steps: if the object is written and the row insert then fails for a
**generic** reason — a dropped connection, a transient 5xx, an eligibility change mid-flight
— the object is left with no row, and there is no compensating remote delete. **This is a
pre-existing property of the whole Connected attachment flow, not something Lists
introduce**, and it is the same shape as the B-8 residue.

**The one list-specific consequence is operational, not correctness:** because the rollback
guard keys on `storage.objects` name and MIME, an orphan of that kind would **block
rollback** until dispositioned. Correct behaviour — it is refusing to strand a stored file —
but worth knowing before rollback is ever attempted under time pressure.

**No action is required for this deployment.**

## 6. Conditions on the GO

1. **Refresh the production baseline immediately before applying**, and — because the PRE
   guard aborts the whole submission — **run the PRE-guard predicates read-only first**, so a
   mismatch is discovered before the transaction rather than as a failed apply.
   **STATUS 2026-09-17: Codex reports the fresh live preflight matching all eight other
   surfaces plus functions, with the POLICY query retry still PENDING.** **The policy surface
   is the one N-1 now depends on** (see §4), so this condition is **not satisfied until that
   policy query returns and matches**.
2. **Confirm, read-only, that production holds zero List-MIME rows and zero `.etudeslist`
   objects** before applying — it makes the new constraint's validation trivially safe and
   establishes the rollback precondition at the same time. **Codex has confirmed it will run
   these explicitly.**
3. **Apply as ONE submission and score the response body**, requiring the literal
   `Lists MIME enabled` row. **Exit code 0 is not evidence.** Then recapture the schema and
   verify **exactly** the N-5 delta.
4. **Device verification is the real gate, and the local evidence does not substitute for
   it.** The delivery checks used **synthetic membership fixtures and temporary policy
   definitions** inside a rolled-back transaction — faithful, but not the deployed objects
   under a real JWT. One real send, one receive and one adopt across the two devices is what
   settles this. Until then, record the deploy as *applied and structurally verified*, not
   as *end-to-end verified*.

## 7. What I did not verify

- **No live production query was run** — every schema fact above comes from
  `supabase/schema/*.json` and committed migrations, so it is only as current as the last
  capture. Condition 1 exists for exactly that reason.
- **I did not execute the test scripts or any build**, and did not re-run the logs cited in
  the brief.
- **No device or Apple-path evidence**, consistent with the brief's own statement.
- **Older-client behaviour on receiving a List is unverified.** Samuel reports both devices
  are on the new build, so it is not a deploy blocker; I have not read the recipient path for
  graceful degradation on an unknown MIME.

**Findings are advisory. Deployment remains Codex's to execute under Samuel's existing
approval; nothing here changes that scope.**
