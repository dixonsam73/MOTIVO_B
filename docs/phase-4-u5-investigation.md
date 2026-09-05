# P4-U5 — INVESTIGATION. B-15 IS SCOPE-CHANGING; C-34's DESIGN IS SETTLED

**2026-09-05, at `4ee7a0b`. READ-ONLY — no source, schema, policy or production
change. No prediction committed yet.**

**Headline: B-15's proposed lever cannot be moved.** The register and the scope
record both frame B-15 as *"tightening the substring floor"*. **Measurement says
the floor is already at the product's minimum and raising it buys nothing
measurable while breaking search for real members.** Reported before any
prediction, per the method.

---

## 1. B-15 — WHAT THE DEPLOYED FUNCTION ACTUALLY DOES

`search_account_directory(q)`, read from **production**:

| element | value |
|---|---|
| floor | `char_length(btrim(q)) >= 2` — on the **whole query**, not per token |
| `account_id` | `lower(account_id) like token || '%'` — **prefix**, anchored |
| `display_name` | `lower(display_name) like '%' || token || '%'` — **substring, unanchored** |
| `instruments` | `like '%' || token || '%'` — **substring, unanchored** |
| tokens | whitespace-split; **every** token must match somewhere |
| cap | `limit 20`, `order by account_id nulls last, user_id` — **no pagination parameter** |

Both load-bearing constraints are present and were left untouched:
`auth.uid() is not null`, and the D-U6-1 subject-side entitlement filter that
`get_account_directory_by_user_ids` deliberately lacks (G10).

## 2. THE FLOOR IS INERT — MEASURED, NOT ARGUED

Production directory: **17 rows**, all with `display_name` and `instruments`, 14
with `account_id`.

**Exhaustive alphabetic sweeps, simulating the deployed predicate:**

| sweep | distinct rows reached |
|---|---|
| all 676 two-character tokens | **17 of 17** |
| all 17,576 three-character tokens | **17 of 17** |

**Raising the floor from 2 to 3 changes the enumeration outcome by nothing.** It
multiplies an automated attacker's query count by 26 and stops there.

**Each predicate reaches everything on its own, at 2 characters:**

| predicate alone | reach |
|---|---|
| `instruments` substring | **17 / 17** |
| `display_name` substring | **17 / 17** |
| `display_name` **word-prefix** (a tighter alternative) | **17 / 17** |
| `account_id` prefix | **14 / 14** (all rows that have one) |

**So anchoring `display_name` would not help either** — 676 two-letter prefixes
cover the start of every name. A single bigram already returns up to **9 of 17**
rows, and **128 of 676** bigrams match something.

## 3. THE FLOOR CANNOT BE RAISED WITHOUT BREAKING REAL SEARCH

Display-name lengths in production:

| length | members |
|---|---|
| **2** | **1** |
| 3 | 3 |
| 5+ | the rest |

**A floor of 3 makes one existing member unsearchable by their complete display
name. A floor of 4 breaks four of seventeen.** Shortest `account_id` is 3
characters, with two accounts at ≤3.

**Two-character surnames are ordinary — Ng, Li, Wu, Xu, An, Oh — so this is an
inclusion cost, not an edge case.** The product's own minimum is 2, which is
exactly where the floor already sits.

**Answer to "determine the smallest meaningful floor from product behaviour":
it is 2, and it is already deployed.**

## 4. INSTRUMENT DISCOVERY IS AN ADVERTISED FEATURE, NOT A LEAK

`PeopleView:499` — the search field placeholder reads **"Search by name or
instrument"**. Bulk reachability *by instrument* is therefore **intended product
behaviour**: instrument vocabulary is small and closed, so "find a cellist"
necessarily returns every cellist.

**B-15's "the whole directory can be enumerated by any authenticated user" is
partly a description of a feature.** Removing instrument matching would be a
product change, not a security fix, and is not proposed.

## 5. WHAT ACTUALLY CAPS BULK EXTRACTION — AND THE REGISTER DIDN'T CREDIT IT

`limit 20` with a deterministic `ORDER BY` and **no offset/cursor parameter**.
An attacker cannot paginate past the first 20 matches of any query; they must
find 20-row-sized slices. At 17 rows this never binds, which is why it is
invisible today — **at scale it is the only structural control in the function.**

The controls that would genuinely bite are **rate limiting / query budgeting**,
which a SQL function cannot express, and **reducing what the directory
publishes**, which is a product decision.

## 6. RAISING THE FLOOR ALSO BREAKS AN ACCEPTED U6b ASSERTION

`supabase/tests/u6b/acceptance.sh:117`:

```
U6b-G3  search_account_directory('OK')  ->  expect 1
        "...while an entitled member remains discoverable"
```

The fixture is `('$A_OK','aok','A OK')`, matched by
`lower(display_name) like '%ok%'`. **`'OK'` is two characters, so a floor of 3
returns 0 and U6b-G3 fails.** That assertion is part of the accepted U6b
enforcement evidence, so changing it is not free.

## 7. THE HONEST LIMIT OF THIS MEASUREMENT

**n = 17.** At seventeen rows *any* exhaustive sweep reaches everything, so these
numbers cannot by themselves separate *"the floor is inert"* from *"the directory
is tiny"*.

**The structural argument is what carries the conclusion, and it is scale-free:**
unanchored substring matching over a closed alphabet means no floor short of the
shortest real name excludes a sweep, and the shortest real name is 2. The
per-query yield measurements are the part that is n-dependent, and they are
labelled as such.

---

## 8. C-34 — THE VERSION SIGNAL. FLOW ESTABLISHED END TO END

| step | current state |
|---|---|
| upload | `NetworkManager:500` → `users/<uid>/avatar.jpg`, `x-upsert: true` — **overwrites in place**, so no stale duplicate accumulates |
| directory write | `AccountDirectoryService.updateSelfAvatarKey` PATCHes **only** `avatar_key`, to `rest/v1/account_directory?user_id=eq.<uid>` |
| **the defect** | on a *replacement* that PATCH writes **the identical value**, because the key is content-invariant |
| read | both RPCs return `avatar_key`; neither returns any version |
| model | `DirectoryAccount` has `avatarKey`, no version field |
| cache | `RemoteAvatarPipeline.fetchAvatarImageIfNeeded` builds `cacheKey = "avatars|<avatarKey>"` — `NSCache`, `countLimit 256`, **no TTL** |
| render | **9** call sites of `fetchAvatarImageIfNeeded` |

**`account_directory` has no `updated_at` column** — columns are `user_id,
account_id, display_name, lookup_enabled, location, avatar_key, instruments,
follow_requests_enabled, entitled_until`.

### 8.1 A change-detecting trigger WOULD NOT FIRE, and that is the trap

`account_directory` already carries one `BEFORE INSERT OR UPDATE` trigger
(`tg_directory_entitled_until`), so a version-stamping trigger is a natural
extension of an existing pattern.

**But the obvious condition is wrong.** A trigger keyed on
`NEW.avatar_key IS DISTINCT FROM OLD.avatar_key` **never fires on a
replacement**, because the key is unchanged by design. **The trigger must stamp
on the UPDATE itself, not on a value change.**

### 8.2 Proposed smallest design

1. **`account_directory.avatar_version timestamptz`** (nullable), stamped by a
   `BEFORE UPDATE` trigger — **unconditionally, not on value change** (§8.1).
2. Both RPCs return it. **`get_account_directory_by_user_ids` gains a returned
   column only — no subject-side filter, G10 untouched.**
3. `DirectoryAccount` gains the field; `fetchAvatarImageIfNeeded` takes it and
   folds it into the cache key.

**Deliberately fails toward OVER-stamping.** An unconditional stamp also fires on
unrelated profile edits, costing other members one extra avatar refetch.
**Over-stamp = a wasted fetch; under-stamp = the stale avatar C-34 is about.**
The safe direction is the cheap one, so the trigger is not made clever.

**Rejected: content-addressed storage keys** (`avatar-<uuid>.jpg`), which would
invalidate every cache with *zero* client change — but the key convention is
locked, RLS pins the object name, and it would **accumulate stale objects**,
trading away a property the register explicitly credits.

**TTL is Phase 5 and nothing here touches it.**

---

## 9. WHAT IS NEEDED BEFORE IMPLEMENTATION

**C-34 is ready to predict and implement.**

**B-15 needs a decision**, because its stated lever is inert and its stated fix
would cost real functionality. **No prediction is committed and nothing is
mutated** pending that direction.
