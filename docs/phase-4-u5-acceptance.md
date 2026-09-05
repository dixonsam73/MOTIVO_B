# P4-U5 — ACCEPTANCE. SERVER HALF COMPLETE; CLIENT HALF AWAITING CONFIRMATION

**2026-09-05. Prediction `a3e7a82`, amended `a5a7e7d`.** The SQL is **deployed
to production and independently verified**. **No client file has been touched**,
so C-34 is **not yet fixed on device** — the signal now exists; nothing consumes
it.

---

## 1. B-15 — DISPOSED ON MEASUREMENT, NOT IMPLEMENTED

**No SQL change. The 2-character floor stands.** The four points, as directed:

1. **2 is already the smallest product-valid floor.** Production carries **one
   2-character display name** and three of 3; a floor of 3 makes that member
   unsearchable by their complete name, and 4 breaks four of seventeen.
2. **Instrument discovery and name search are intentional product behaviour** —
   `PeopleView:499` advertises *"Search by name or instrument"*.
3. **Further resistance to systematic enumeration needs a different mechanism** —
   rate limiting / query budgeting, and/or a product decision about what the
   directory publishes.
4. **That work is not absorbed into U5. It is re-filed as B-37** (P3, Phase 6),
   which carries forward both preserve-exactly constraints.

**`LIMIT 20` IS NOT DESCRIBED AS A SECURITY CONTROL.** The investigation called
it *"the only structural control"*; **that is withdrawn, in the B-37 row itself.**
It is a per-query result cap — repeated queries still enumerate.

**Verified preserved in the deployed function:** `auth.uid() is not null` **true**,
self-exclusion **true**, D-U6-1 entitlement filter **true**, floor **still 2**.
**G10 verified: `get_account_directory_by_user_ids` has no `entitled_until` and
no `lookup_enabled` predicate** — a returned column only.

---

## 2. C-34 — THE VERSION SIGNAL IS DEPLOYED

`supabase/sql/2026-09-05-u5-avatar-version.sql`, run in the SQL editor, returned
exactly one row: `column_present 1, trigger_present 1, rpcs_updated 2`.

**That row was not treated as evidence.** Everything below was re-read from
production afterwards.

| check | result |
|---|---|
| `avatar_version` | `timestamp with time zone`, **nullable, no default** |
| trigger | `BEFORE UPDATE OF avatar_key` — **the narrow form, not blanket** |
| pre-existing `tg_directory_entitled_until` | **intact** |
| both RPC signatures | carry `avatar_version timestamp with time zone` |
| **grants after DROP+CREATE** | **`authenticated` only; anon, public, `service_role` all false** — B-15's hazard did not land on the RPCs |
| G10 | by-ids RPC still has **no subject-side filter** |
| backfill | **none — all 17 rows NULL** |

### 2.1 THE PRODUCTION DISCRIMINATOR

Run on one directory row (`md5[0:8] = 1fbf664a`) using **value-preserving
self-assignments**, so no content could change:

| step | version | content md5 |
|---|---|---|
| baseline | NULL | `61b7e215…` |
| `set location = location` — **unrelated column** | **still NULL** | `61b7e215…` |
| `set avatar_key = avatar_key` — **the replacement path** | **STAMPED** `07:07:51` | `61b7e215…` |

**The content md5 is identical at every step**, so the discriminator proved the
trigger without altering a single member-visible value. **16 of 17 rows stayed
NULL** throughout — no blast radius. The row was then restored to NULL.

This reproduces on production what was measured locally three ways and through
**real PostgREST**: `PATCH {"avatar_key": <same value>}` stamps, `PATCH
{"display_name": …}` does not.

---

## 3. A DEFECT I INTRODUCED, FOUND BY THE SNAPSHOT AND FIXED

**The migration guarded the two RPCs against B-15's default-grant hazard and
missed the new trigger function.**

`tg_stamp_avatar_version` was created by `CREATE OR REPLACE FUNCTION` and picked
up Supabase's default `public` EXECUTE — anon, authenticated and `service_role`
all **true**. The pre-existing `tg_set_entitled_until` is **revoked from all
three**, so mine was inconsistent with a deliberate precedent.

**Found by recapturing the schema snapshot and reading the diff**, not by review —
GUARD 6 only covered the functions I had thought to name.

**Practical risk was nil** (return type `trigger`; not RPC-callable; PL/pgSQL
refuses direct invocation) **and it was fixed anyway**, because a privilege
surface that is inherited rather than deliberate is exactly what B-15 warns
about. Four `REVOKE`s later both trigger functions are identical: **3 snapshot
entries each, `can_execute` false for all roles**.

**The trigger was then re-tested and still fires** — verified, not assumed, since
a revoke on the function is the kind of change that looks harmless and could not
be.

**`avatar_version`'s column grants match `avatar_key`'s exactly**
(INSERT/REFERENCES/SELECT/UPDATE for `authenticated` and `service_role`, nothing
for anon), so no new privilege shape. A member can therefore set their **own**
`avatar_version` directly — a self-inflicted extra refetch for other viewers, and
the trigger overwrites it whenever `avatar_key` is targeted.

---

## 4. GATES

| gate | result |
|---|---|
| **`u6b/acceptance.sh`** | **64 / 64** — including **G3** (the 2-character `'OK'` search still returns 1, so the floor is intact) and **G1** (attribution still resolves through the recreated by-ids RPC) |
| `u5/client-structural.sh` | **60 / 60** |
| `p4/u2s-acceptance.sh` | **12 / 12** |
| `p4/u2c-acceptance.sh` | **20 / 20** |
| `p4/u2b-acceptance.sh` | **16 / 16** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **16 / 16** |
| `p4/u1-baseline.sh` | 10 pass / its 6 documented flips |
| Debug + Release build, `MOTIVOTests` | **not re-run — no client file changed since `4ee7a0b`**, where both were green |

**`U2s-11` was re-pinned** to `6f6a3c0..4febb8b`. It asserted *"exactly one
snapshot file changed since the U2s prediction"*, true only while U2s was the
tip; U5 legitimately adds a column, a trigger and two signatures. Same policy as
the earlier pins — the historical claim is kept, bounded to its own unit.

## 5. PRODUCTION CENSUS — UNCHANGED

| measure | before | after |
|---|---|---|
| `account_directory` rows | 17 | **17** |
| `avatar_version` NULL / set | — | **17 / 0** |
| `posts` / private | 101 / 0 | **101 / 0** |
| distinct owners | 9 | **9** |
| `connected_attachments` rows / live | 25 / 0 | **25 / 0** |
| attachment objects / avatars | 10 / 3 | **10 / 3** |
| comments / follows | 5 / 9 | **5 / 9** |

## 6. WHAT IS NOT DONE — C-34 IS NOT YET FIXED ON DEVICE

**The signal exists and nothing reads it.** The client half is **not written**,
pending confirmation of the revised design, because two findings enlarged it
beyond the committed prediction (`a5a7e7d` §5a):

- **`.task(id:)` must carry the version**, or the long-lived feed row never
  re-runs its task and keeps the stale image in `@State`;
- **the cache-key format is duplicated in eight places**, two of them the
  owner's own **invalidation** sites, so the format must **not** change —
  the pipeline should invalidate on a version change instead, with
  `version: String? = nil` so untouched call sites still compile;
- **only the directory-sourced sites need it**; the four owner-side sites read
  `auth.backendAvatarKey` and already invalidate explicitly.

**C-34's TTL half remains Phase 5.**

## 7. REMAINING PHASE 4

**U5 client half** (above) · **U6** — C-51 · **U7** — C-58 · **U8** — copy and
App Store privacy disclosures · **exit condition 8** — the Device A run, owning
U2b's and U2s's production behavioural observations · **B-37**, newly filed.

Carried from Phase 3 and untouched: C-31, B-34, G7, B-11's production GRANT.
