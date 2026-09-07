# P5-E / CP-2 — SERVER PREDICTION. 2026-09-07

**REVISED 2026-09-07 ON REVIEW — §3.2's ENFORCEMENT WRAPPING WAS A DEFECT AND IS
WITHDRAWN.** My proposed wrapping would have let the **subscription** kill switch
switch off **child-safety** privacy. It is replaced by an unconditional conjunct.
See **§3.4**, which is the authority for the boolean shape; the rest of the design
is unchanged.

**PREPARATION ONLY. NO PRODUCTION MUTATION. `SELECT`-only measurement plus one
read-only impersonation probe.** For review.

Design authority: `docs/phase-5-b-cp1-design-r2.md` r3. Baseline: CP-1 as
deployed (`9a1f604`), under the universal **iOS 26.2** invariant (`c41c842`).

---

## 1. CONSUMER ENUMERATION — MEASURED, NOT ASSUMED

| changed function | consumed by |
|---|---|
| **`search_account_directory(text)`** | **NOTHING in the database.** Zero policies, zero functions. It is a client-facing RPC only |
| **`follow_requests_open(uuid)`** | **Exactly ONE policy:** `follows_insert_requester` — `follows` / **INSERT** / role `authenticated` |

`follows_insert_requester`'s `with_check`, as deployed:

```
enforcement_gate('follows.insert')
AND follower_user_id = auth.uid()
AND status = 'requested'
AND follow_requests_open(followed_user_id)
```

**`follow_requests_open` is a TOP-LEVEL CONJUNCT, not nested inside the gate** —
the U2s lesson. So tightening it survives the kill switch rather than evaporating
with it.

**Blast radius is therefore two functions and one INSERT policy.** No SELECT
policy, no feed path, no attribution path.

---

## 2. THE OVER-DETERMINATION TRAP — THE MOST IMPORTANT MEASUREMENT HERE

**Measured today, impersonating Samuel via `set_config('request.jwt.claims', …)`:**

| input | value |
|---|---|
| `enforcement_active()` | **true** |
| `connected_member_self()` (viewer) | **FALSE** |
| `account_directory` rows with `entitled_until > now()` | **0** |

**Consequences that must not be misread:**

1. **`enforcement_gate(…)` returns FALSE for every identity**, because enforcement
   is active and nobody is entitled. Both `search_account_directory` and
   `follow_requests_open` begin with that gate, so **today search returns nothing
   and follow requests are refused for everyone — regardless of privacy state.**
2. **CP-2-R1's `coalesce(..., true)` hazard is REAL but CURRENTLY UNREACHABLE.**
   It is masked by the gate. **It becomes reachable the moment any identity is
   entitled** — which is exactly when minors could exist. **The fix is still
   required; the record must not imply it is live today.**
3. **Every naive discriminator would pass vacuously.** A test that observes "not
   discoverable" after CP-2 proves nothing, because it was already not
   discoverable for two other reasons.

**This is the Phase 4 device-QA lesson exactly** — *"the zero is
over-determined… an ENTITLED viewer would have seen zero too"* — and §6's
fixtures exist solely to remove the over-determination.

---

## 3. THE CHANGES

### 3.1 Two new helpers — the override rule lives in ONE place

```sql
create function public.account_privacy_discoverable(target_user_id uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select coalesce((
    select p.lookup_enabled
       and not (p.age_band = 'band_13_17'
                and p.lookup_set_under_band = 'band_18_plus')
      from public.account_privacy p
     where p.user_id = target_user_id), false);
$$;

create function public.account_privacy_requests_open(target_user_id uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select coalesce((
    select p.follow_requests_enabled
       and not (p.age_band = 'band_13_17'
                and p.follow_requests_set_under_band = 'band_18_plus')
      from public.account_privacy p
     where p.user_id = target_user_id), false);
$$;
```

**`coalesce(..., FALSE)` — the inverse of the defect being fixed.** Absence and
unresolved state both resolve **protective**, by the shape of the expression
rather than by a branch.

**Both granted to NOBODY** — `anon`, `authenticated` and `service_role` all
revoked, exactly as `connected_member(uuid)` and `membership_state(uuid)` are.
**B-33's rule: a per-subject privacy oracle must be structurally unbuildable by a
client.** They are reachable only from inside the two `SECURITY DEFINER`
functions below, which run as their owner.

**One rule, two call sites, zero duplication.** Inlining the override twice is
how the stored-vs-effective distinction drifts, and drift here fails permissive.

### 3.2 `search_account_directory` — one added conjunct

```sql
      and public.account_privacy_discoverable(ad.user_id)
```

**Added, nothing removed.** The existing `entitled_until` filter (D-U6-1) and its
`enforcement_active()` guard are **untouched**, so a lapsed member stays
undiscoverable for its own independent reason. `LIMIT 20`, the 2-character floor,
self-exclusion and token matching are all unchanged.

**~~Kill switch: wrap the new conjunct the same way D-U6-1 is.~~ WITHDRAWN —
see §3.4.** The conjunct is **unconditional**. Copying D-U6-1's wrapping was
reasoning by analogy from an *entitlement* filter to a *child-safety* filter, and
the two do not share a kill switch.

### 3.3 `follow_requests_open` — CP-2-R1

```sql
-- BEFORE (deployed): missing row -> TRUE (permissive)
select enforcement_gate('rpc.follow_requests_open') and coalesce(
    (select ad.follow_requests_enabled from public.account_directory ad
      where ad.user_id = target_user_id), true);

-- AFTER
select (select public.enforcement_gate('rpc.follow_requests_open'))
   and public.account_privacy_requests_open(target_user_id);
```

**`account_directory.follow_requests_enabled` ceases to be consulted** and joins
`lookup_enabled` as a dead column. **Measured: both surviving rows carry `true`,
so removing it widens nothing** — the preference simply moves to its
server-authoritative home.

**The gate stays FIRST and unchanged.**

---

### 3.4 THE KILL SWITCH MUST NOT REACH CHILD SAFETY — CORRECTION

**THE INVARIANT, ADOPTED:** *the kill switch may relax entitlement gating, and
must never relax child-safety privacy.*

**My §3.2 proposal violated it.** Evaluated mechanically over the full input
space:

```
PROPOSED:  gate(E,Vent) AND (NOT E OR Sent) AND (NOT E OR P)
```

With `E = false` the third conjunct collapses to **TRUE**, so **P — the entire
privacy decision — is discarded**. A 13–17 member who has never opted in becomes
**discoverable to any caller, entitled or not**, in **all four** enforcement-off
combinations. Same for an 18+ member who deliberately opted out.

```
REVISED:   gate(E,Vent) AND (NOT E OR Sent) AND P          -- P unconditional
```

**`follow_requests_open` needed no change** — as proposed it is
`gate AND account_privacy_requests_open(target)`, already an unwrapped conjunct.
**Only `search_account_directory` was wrong.**

#### Direct answer to the question asked

> **Does `enforcement_active = false` ever make an otherwise protected 13–17
> member discoverable or open to follow requests?**

**Under the PROPOSED shape: YES — for discovery, in every enforcement-off case.
Under the REVISED shape: NO, for either surface.** A protected member stays
protected whatever the enforcement flag says.

#### Why the "half-roll-back" argument does not apply

D-U6-1 is wrapped so that disabling enforcement **restores the pre-enforcement
world** — correct for a filter whose whole subject is entitlement. **Child-safety
filtering has no pre-enforcement world to restore to**: it did not exist before
CP-2 and is not part of the entitlement incident the switch was built for.

**And no second flag is being added.** A boolean that disables child-privacy
filtering would be **a shippable exception inside the predicate that defines
child safety** — precisely what **D4 rejected outright** when U5a proposed an
allowlist inside `connected_member()`, on the grounds that an authority predicate
must not contain a branch whose safety rests on operational discipline.
**CP-2's rollback is restoring two function definitions byte-compared — a
deliberate migration, not a flag anyone can flip.**

#### PRE / POST truth tables

`E` = `enforcement_active()` · `Vent` = viewer entitled · `Sent` = subject
entitled · `P` = effective privacy (`account_privacy_discoverable`).

**`search_account_directory` — does the subject appear?**

| privacy state | E | Vent | Sent | PRE | PROPOSED | **REVISED** |
|---|---|---|---|---|---|---|
| no privacy row | T | T | T | ✅ | ❌ | **❌** |
| no privacy row | **F** | any | any | ✅ | **⚠️ ✅** | **❌** |
| 13–17 opted out | T | T | T | ✅ | ❌ | **❌** |
| 13–17 opted out | **F** | any | any | ✅ | **⚠️ ✅ VIOLATION** | **❌** |
| 13–17 opted **IN** | T | T | T | ✅ | ✅ | **✅** |
| 13–17 opted **IN** | F | any | any | ✅ | ✅ | **✅** |
| 18+ opted in | T | T | T | ✅ | ✅ | **✅** |
| 18+ opted in | F | any | any | ✅ | ✅ | **✅** |
| 18+ opted out | T | T | T | ✅ | ❌ | **❌** |
| 18+ opted out | **F** | any | any | ✅ | **⚠️ ✅** | **❌** |
| any | T | F | any | ❌ | ❌ | **❌** |
| any | T | any | F | ❌ | ❌ | **❌** |

**`follow_requests_open` — may a stranger create a follow request?**

| privacy state | E | Vent | PRE | **REVISED** |
|---|---|---|---|---|
| no privacy row | T | T | ✅ | **❌** |
| no privacy row | T | F | ❌ | **❌** |
| no privacy row | **F** | any | **⚠️ ✅** | **❌** |
| 13–17 opted out | T | T | ✅ | **❌** |
| 13–17 opted out | **F** | any | **⚠️ ✅** | **❌** |
| 13–17 opted **IN** | T | T | ✅ | **✅** |
| 13–17 opted **IN** | F | any | ✅ | **✅** |
| 18+ opted in | T/F | T / any | ✅ | **✅** |
| 18+ opted out | T | T | ✅ | **❌** |
| 18+ opted out | **F** | any | **⚠️ ✅** | **❌** |

#### A sharper statement of the CP-2-R1 hazard than §2 gave

§2 said the `coalesce(..., true)` defect is *"currently unreachable"* because the
gate is false for everyone. **That is true only while enforcement is ACTIVE.**
The table shows `follow_requests_open` returning **TRUE for every subject,
including row-less ones, to any caller**, the moment `enforcement_enabled` is set
false. **The hazard is one boolean away, not one subscription away** — which
strengthens the case for CP-2-R1 rather than weakening it.

## 4. TEN BEHAVIOURAL PREDICTIONS

**"PRE (mechanism)" = what the deployed code does WHEN THE GATE PASSES**, i.e.
with an entitled viewer and subject. **As observed in production today every PRE
cell is closed by over-determination (§2)** — which is why the mechanism column,
not the observation, is what CP-2 changes.

| # | scenario | PRE (mechanism) | **POST** | changed? |
|---|---|---|---|---|
| **1** | **no `account_privacy` row** | discoverable; **requests OPEN** (`coalesce → true`) | **not discoverable; requests CLOSED** | **YES — both** |
| **2** | 13–17, default / no opt-in | discoverable; requests open | **not discoverable; requests closed** | **YES** |
| **3** | 13–17 after explicit discovery opt-in (`set_lookup_v1(true)` as a teen) | discoverable | **DISCOVERABLE** — `lookup_set_under_band='band_13_17'`, override does not fire | no (correctly) |
| **4** | 13–17 follow requests: (a) default; (b) opted in as teen; (c) `true` inherited from an adult classification | open in all three | **(a) closed · (b) OPEN · (c) CLOSED by the override** | **YES for (a),(c)** |
| **5** | 18+ discovery on (initial default) | discoverable | **discoverable** | no |
| **6** | 18+ discovery off (`set_lookup_v1(false)`) | **discoverable — the column is consulted by nothing** | **NOT discoverable** | **YES** |
| **7** | lapsed / unentitled member | undiscoverable via `entitled_until` | **undiscoverable — now for TWO independent reasons** | no (reinforced) |
| **8** | row-less identity (no `account_directory` row) | not discoverable (nothing to match); **requests OPEN** — the exact CP-2-R1 defect | not discoverable; **requests CLOSED** | **YES — requests** |
| **9** | attribution for an otherwise undiscoverable member | resolves | **RESOLVES, UNCHANGED** | **no — required** |
| **10** | Samuel ↔ Steve approved follow | intact | **INTACT** | **no — required** |

### Scenarios 9 and 10 are the ones CP-2 must NOT change

**9 — `get_account_directory_by_user_ids` is untouched.** Attribution keeps **no
subject-side filter** (G10, re-verified in P4-U7): a member you already follow
still renders by name even when nobody can *find* them. **Discoverability and
attribution are separate RPCs, and that separation is what makes this possible.**

**10 — the Samuel↔Steve fixture survives by construction.** CP-2 changes one
SELECT path and one **INSERT** policy on `follows`. It touches **no UPDATE or
DELETE path**, so an **already-approved** row is unreachable by the change.
Neither identity needs to create a new follow request for Phase 4's conditions 2,
8 or C-34.

**A consequence to state rather than discover:** after CP-2, **nobody can send
Samuel or Steve a follow request** (scenario 1 — they have no privacy row). That
is correct fail-protective behaviour, is reversible by declaring a band at CP-3,
and does not affect their existing approved follow.

---

## 5. DISCRIMINATORS — EACH MUST FAIL AGAINST DEPLOYED CP-1

**A discriminator that cannot fail before the change is not evidence.** Each row
states what the *current* deployed code returns under the same fixture.

| # | discriminator | on CP-1 today | after CP-2 |
|---|---|---|---|
| **D1** | entitled viewer searches an entitled subject with **no privacy row** | **1 row (FOUND)** | **0 rows** |
| **D2** | same subject given `band_18_plus` (default `lookup_enabled=true`) | 1 row | **1 row** |
| **D3** | subject `band_13_17`, default | 1 row | **0 rows** |
| **D4** | subject `band_13_17` then `set_lookup_v1(true)` | 1 row | **1 row** |
| **D5** | subject `band_18_plus` then `set_lookup_v1(false)` | **1 row — the column is consulted by nothing** | **0 rows** |
| **D6** | subject `band_18_plus`, `set_lookup_v1(true)`, then band moved to `band_13_17` | 1 row | **0 rows — the override** |
| **D7** | `follow_requests_open(subject-with-no-privacy-row)` | **TRUE** | **FALSE** |
| **D8** | `follow_requests_open` for `band_13_17` default | true | **false** |
| **D9** | `follow_requests_open` after `set_follow_requests_v1(true)` as a teen | true | **TRUE** |
| **D10** | real INSERT into `follows` as requester against a no-privacy-row target | **succeeds** | **refused by RLS** |
| **D11** | `get_account_directory_by_user_ids` for an undiscoverable subject | resolves | **resolves — UNCHANGED** |
| **D12** | Samuel↔Steve approved follow still present and resolvable | 2 rows | **2 rows** |
| **D13** | `has_function_privilege(authenticated, account_privacy_discoverable)` | n/a — absent | **FALSE** |
| **D14** | **kill switch ON** (`enforcement_enabled=false`), 13–17 opted-out subject, searched by an **unentitled** viewer | **FOUND** | **0 rows** |
| **D15** | **kill switch ON**, 18+ opted-out subject | **FOUND** | **0 rows** |
| **D16** | **kill switch ON**, `follow_requests_open(no-privacy-row subject)` | **TRUE** | **FALSE** |
| **D17** | **kill switch ON**, 13–17 opted-**IN** subject | FOUND | **FOUND — the switch does not over-restrict either** |

**D14–D17 EXIST BECAUSE OF §3.4 AND WOULD HAVE PASSED UNDER MY WITHDRAWN
WRAPPING** — D14, D15 and D16 fail against the PROPOSED shape as well as against
deployed CP-1, so they discriminate the corrected boolean from the defective one,
not merely new-from-old. **D17 is the counter-control:** the switch must not make
an opted-in member vanish either.

**Flipping `enforcement_enabled` is the single most sensitive thing this suite
does.** It runs **inside the same rolled-back transaction**, is never committed,
and is invisible to other sessions under read-committed. **It must never be left
set.**

**D1, D5 and D7 are the load-bearing ones.** D1 and D7 prove absence flipped from
permissive to protective; **D5 proves `lookup_enabled` became operative at all**,
since today it is a column no deployed code reads. **D6 is the only one that can
distinguish r3's override from a naive "band decides" implementation.**

**D11 and D12 are negative controls.** If either moves, CP-2 has broken
attribution or the Phase 4 fixture, and the run stops.

---

## 6. EPHEMERAL FIXTURES — NO PERSISTED AGE ROWS FOR SAMUEL OR STEVE

**Every discriminator runs inside ONE transaction that ends in `ROLLBACK`.**
Nothing below survives the run.

**The mechanism is measured and available:** `auth.uid()` resolves from
`request.jwt.claims`, and `set_config('request.jwt.claims', …, true)` is
transaction-local — **confirmed today**, acting as Samuel with `uid_resolves =
true`.

To defeat the over-determination of §2 the fixture must, inside the transaction:

1. **impersonate a viewer** via `set_config`;
2. **make the viewer entitled** — insert a `membership` row (`Production`, future
   `renewal_date`) so `connected_member_self()` is true and the gate passes;
3. **make the subject entitled** — so `entitled_until > now()` and D-U6-1 does not
   mask the result. **`account_directory.entitled_until` is maintained by
   `tg_set_entitled_until`, so the directory row must be TOUCHED after the
   membership insert for the trigger to re-derive it. This is a fixture-
   construction detail to verify at implementation, not to assume;**
4. **insert the `account_privacy` rows** the scenario needs;
5. run the assertion;
6. **`ROLLBACK`.**

**Two consequences stated plainly.** The fixture manufactures *membership* and
*entitlement* — which production does not have — **for the sole purpose of making
the privacy clause the only variable**. And **`enforcement_gate` writes to
`shadow_enforcement_stat`**, so a behavioural run produces telemetry; the
rollback is what keeps the 75-row baseline intact. **A discriminator run outside
a transaction would silently move a measured table.**

**Samuel and Steve receive no persisted `account_privacy` row at any point.**
Where a scenario needs a bandless or row-less identity they can serve as-is,
because that is their real state.

---

## 7. PREDICTED SCHEMA DELTA

| surface | before | **after** | delta |
|---|---|---|---|
| `functions` | 39 | **41** | **+2 new, 2 MODIFIED** |
| `function_grants` | 117 | **123** | **+6** (3 rows × 2), all client roles **false** |
| `columns` / `constraints` / `policies` / `triggers` / `rls_enabled` / `table_grants` / `column_grants` / `storage_buckets` | — | **unchanged** | **0** |

**Unlike CP-1, CP-2 MODIFIES deployed objects**, so the rollback is not a drop:
`search_account_directory` and `follow_requests_open` must be **restored
byte-compared** to their committed snapshot definitions, as U6a's rollback was.
The two helpers are then dropped.

**Rollback order:** restore the two functions first, drop the helpers second — the
reverse would leave a deployed function referencing a missing one.

## 8. WHAT CP-2 DOES NOT DO

- **No client change.** CP-3 owns the band question, the discoverability control
  and the three-layer `lookupEnabled: true` hazard.
- **`get_account_directory_by_user_ids` untouched.**
- **No policy added, removed or modified** — `follows_insert_requester` is
  affected only through the function it already calls.
- **No age row is created for anyone**, in production or persistently.

## 9. STATUS

**NOTHING APPLIED. Awaiting review.**
