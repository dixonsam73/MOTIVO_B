# P4-U7 / C-58 — INVESTIGATION AND PREDICTION

**Committed BEFORE any mutation.** Accepted checkpoints: client `7744027`,
server `dfba1d8`, U6 `8aaced4`.

C-58 is **P3, bounded product/UX, not a defect**. The current fallback is safe
and withdrawal works. The register **rejects the global fix** and adopts the
narrow one.

---

## 1. THE DEFECT IS REPRODUCED, NOT RESTATED

Measured on the local stack, lapsed viewer (`membership_state = expired`,
`connected_member = false`) holding an **approved** follow with an author who
has a directory row:

| | enforcement OFF | **enforcement ON** |
|---|---|---|
| `follows` rows visible to the viewer | 1 | **1** |
| attribution rows for the followed author | 1 | **0** |
| attribution rows for a stranger | 1 | 0 |
| `search_account_directory('Author')` | — | 0 |

**The viewer keeps the relationship row and loses the name**, so
`PeopleUserRow.displayName` falls through to
`"User • \(String(userID.suffix(6)))"` (`PeopleUserRow.swift:86`). Enforcement
is live in production, so this is current behaviour, not hypothetical.

**The mechanism is the VIEWER gate**, exactly as the row states — the deployed
RPC's only membership predicate is
`(select public.enforcement_gate('rpc.get_account_directory_by_user_ids'))`,
and `enforcement_gate` resolves to `connected_member_self()` when enforcement is
on. **There is no subject-side filter**, so G10 is intact and a lapsed author's
attribution still resolves for an entitled viewer.

---

## 2. FOUR SURFACES REACH A LAPSED VIEWER, NOT ONE

`follows_select_involved` is **ungated** and covers both directions
(`follower_user_id = auth.uid() OR followed_user_id = auth.uid()`), and the
client reads four lists from it:

| `BackendShim` | list | status |
|---|---|---|
| `:631` | Following | `approved` |
| `:659` | Followers | `approved` |
| `:686` | incoming requests | `requested` |
| `:713` | outgoing requests | `requested` |

---

## 3. THE DESIGN DECISION — `approved` ONLY, AND WHY

**Adopted:** resolution is additionally permitted when the viewer holds an
**approved** follow with the requested `user_id`, **in either direction**.

**REJECTED: keying on "any row the viewer can already SELECT".** That is the
literal reading of the register's criterion and it is tempting — its reach would
be exactly the rows the viewer already sees, so it could reveal no new
relationship by construction. It is rejected because **its safety would rest on
another policy staying as it is.** An unentitled viewer cannot manufacture a
relationship today only because `follows_insert_requester` carries
`enforcement_gate('follows.insert')` — measured, not assumed. Were that ever
ungated, "any visible row" would become a self-serve **UUID → identity oracle**:
request to follow any uuid, then resolve it. That is precisely the general
resolver B-5 hardened these RPCs against.

**`approved` makes the safety intrinsic instead of borrowed.** An unentitled
viewer cannot produce an approved row by any route: approval is a gated UPDATE
performed by the *other* party (`follows_update_approve_by_followed`). This is
B-24's own lesson applied — *an authority predicate must not contain a branch
whose safety rests on operational discipline*, or, here, on a neighbouring
policy.

**The accepted cost, stated rather than glossed:** incoming and outgoing
*requests* keep the `User • <suffix>` fallback for a lapsed viewer. That is
tolerable because a lapsed viewer **cannot approve anything anyway** — the
UPDATE is gated — so a request is not actionable beyond declining, and the
register's requirement is about *"a surviving follow relationship … allowed to
manage and remove it"*.

**Both directions are included** because Followers and Following are both
affected and both are manageable via the ungated `follows_delete_involved`.

---

## 4. THE CHANGE

One function, `CREATE OR REPLACE` — **signature and return type unchanged, so
grants are preserved and no DROP is needed** (unlike U5, which changed the
return type and had to restore grants explicitly).

```sql
  where auth.uid() is not null
    and ad.user_id = any(user_ids)
    and (
      (select public.enforcement_gate('rpc.get_account_directory_by_user_ids'))
      or exists (
        select 1 from public.follows f
        where f.status = 'approved'
          and ((f.follower_user_id = auth.uid() and f.followed_user_id = ad.user_id)
            or (f.followed_user_id = auth.uid() and f.follower_user_id = ad.user_id))
      )
    );
```

**It is purely ADDITIVE on the viewer axis.** The gate remains the first
disjunct, so it is still evaluated on every call — preserving
`shadow_enforcement_stat` telemetry — and an entitled viewer short-circuits to
exactly today's behaviour. **No row the gate would have returned is removed.**

**No client change.** The lists already render `overrideDisplayName` from
resolved directory accounts; supplying the row is sufficient.

---

## 5. PREDICTIONS

| # | prediction |
|---|---|
| **P1** | BEFORE: lapsed viewer + approved follow → **0** attribution rows *(reproduces C-58)* |
| **P2** | AFTER: same viewer → **1** row. **The unit.** |
| **P3** | AFTER: lapsed viewer, **no** relationship (stranger) → still **0**. No general resolver |
| **P4** | AFTER: lapsed viewer with only a **`requested`** relationship → still **0**. The deliberate boundary |
| **P5** | AFTER: **entitled** viewer resolving a **lapsed author** → **1**. The retention half (U6b-G1) is untouched |
| **P6** | AFTER: `search_account_directory` for the lapsed viewer → still **0**. D-7 undiscoverability preserved |
| **P7** | AFTER: prosrc contains neither `connected_member` nor `entitled_until` → U6b-J3 still **false**. **G10 preserved** |
| **P8** | EXECUTE grants on the RPC are byte-identical before and after |
| **P9** | Exactly one function definition changes; zero policy, table, column, trigger or grant delta |
| **P10** | `u6b/acceptance.sh` stays **64/0**; both builds and `MOTIVOTests` stay green |

**P3 and P4 are the discriminators.** Without them P2 would be satisfied by
simply ungating the RPC — the rejected global fix. They are what prove the
permission is *bounded by an existing approved relationship* rather than
granted at large.

---

## 6. WHAT THIS MUST NOT DO

- **Not broaden directory visibility.** `search_account_directory` is untouched;
  a lapsed member stays undiscoverable (D-7 / B-15).
- **Not weaken the Phase 3 membership model.** No policy changes, no membership
  predicate changes, the kill switch keeps working, and enforcement still
  decides every other surface.
- **Not gain a subject-side filter** (G10).
