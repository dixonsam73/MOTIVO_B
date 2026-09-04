# HISTORICAL `connected_attachments` RESIDUE CLEANUP — ACCEPTANCE

**Executed 2026-09-04. Prediction committed beforehand at `03f4a77`.**
**Every predicted value matched, including each intermediate step.**

---

## 1. WHAT THIS WAS — THE FOUR-PART RECORD, UNCHANGED FROM THE PREDICTION

1. **Confirmed historical beta/test residue by HUMAN identification.** Asked
   directly, the account holder answered: *"all six are test debris — none worth
   preserving."* **The database could not have supplied this** — no column
   records that an attachment was a test, both counterpart accounts are deleted,
   and the filenames are suggestive at best.
2. **They predate the current, fixed lifecycle path.** Created 2026-07-14 →
   2026-08-10; already present when B-22 measured them on **2026-08-13**, the day
   the `ca00189` rewrite was deployed.
3. **The current deployed mechanism removes `connected_attachments` rows on BOTH
   sides** — received on `recipient_user_id` (`delete_account_v1:138-140`), sent
   on `sender_user_id` (`:227-229`), header at `:21`. **This was NOT remediation
   of a currently reachable defect.**
4. **B-22 deliberately preserved this population at the time. This is an explicit
   LATER DISPOSITION on evidence that was not then available — and NOT a
   retroactive claim that B-22 was incorrect.** B-22 was right on what it knew:
   it declined to destroy content it could not identify. What changed is the
   identification, not the reasoning.

---

## 2. EXECUTION — PER ITEM, EACH VERIFIED BEFORE THE NEXT

Candidate set re-verified against the committed hashes immediately before
mutation: **6 of 6 rows matched, paired item `29c994f5` / `a70d8d26` confirmed.**
Raw ids and the raw path stayed **outside the repository**.

### 2.1 The paired operation — object BEFORE row

| step | action | `ca` | live | objects | ref | unref | **dangling** | predicted |
|---|---|---|---|---|---|---|---|---|
| start | — | 31 | 6 | 11 | 11 | 0 | 5 | — |
| **1** | delete object `a70d8d26` — HTTP **200**, object rows in `storage.objects` → **0** | 31 | 6 | **10** | **10** | 0 | **6** | ✓ exact |
| **2** | delete row `29c994f5` by explicit id — row → **0** | **30** | **5** | 10 | 10 | 0 | **5** | ✓ exact |

**`dangling` rises only at step 1 and is paid back at step 2**, exactly as
predicted. Object-before-row was chosen so the intermediate state is a *dangling
row* — an already-understood category — rather than an *unreferenced object*, the
B-8 category U4 had just emptied.

### 2.2 The five already-dangling rows — explicit id, one at a time

| row | remaining | `ca` total | expected |
|---|---|---|---|
| `c733af34` | **0** | 29 | 29 ✓ |
| `ab2d4b54` | **0** | 28 | 28 ✓ |
| `0b10d4cb` | **0** | 27 | 27 ✓ |
| `78646d9c` | **0** | 26 | 26 ✓ |
| `1f9cb972` | **0** | 25 | 25 ✓ |

**Six deletes, six explicit ids, one explicit path. No predicate sweep.**

### 2.3 Verification was against authoritative state only

Every check queried `storage.objects` / `public.connected_attachments`. **No HTTP
`GET` was used to establish absence** — U4 recorded a `GET` returning **200 after
a successful DELETE**, a false negative that stopped that run. That lesson was
applied here from the outset rather than rediscovered.

---

## 3. SETTLED STATE — EVERY PREDICTION MET

| measure | before | **after** | predicted |
|---|---|---|---|
| `connected_attachments` | 31 | **25** | 25 ✓ |
| live `connected_attachments` | 6 | **0** | 0 ✓ |
| soft-deleted | 25 | **25 of 25** | all ✓ |
| dangling live references | 5 | **0** | 0 ✓ |
| attachment Storage objects | 11 | **10** | 10 ✓ |
| referenced | 11 | **10** | 10 ✓ |
| unreferenced | 0 | **0** | 0 ✓ |
| `posts` / public / private | 101 / 101 / 0 | **101 / 101 / 0** | unchanged ✓ |
| distinct owners | 9 | **9** | ✓ |
| avatars / comments / follows / shares | 3 / 5 / 9 / 0 | **3 / 5 / 9 / 0** | unchanged ✓ |

---

## 4. REFERENCE INTEGRITY — BOTH DIRECTIONS, ENUMERATED

Each query **enumerates offenders**; all three returned **no rows at all**.

| # | check | result |
|---|---|---|
| 1 | unreferenced Storage objects | **none** |
| 2 | live `connected_attachments` referencing a missing object | **none** |
| 3 | live post attachment reference pointing to a missing object | **none** |

**The `attachments` bucket and its two referencing tables are now mutually
consistent in both directions.**

---

## 5. U4's UNMET CRITERION IS NOW SATISFIED — RECORDED HERE, NOT BACKDATED

U4 declined to claim *"no surviving live reference points to a missing object"*,
because **it was already false before U4 began** — 5 live `connected_attachments`
rows pointed at absent objects.

**It is now satisfied**, by check 2 above. **It is recorded as satisfied HERE, by
this explicit follow-on cleanup — NOT backdated into U4**, whose acceptance
correctly states the criterion was unmet at that time.

---

## 6. WHAT DID NOT CHANGE

- **No `posts` row, no Storage object other than `a70d8d26`, no avatar, no
  comment, no follow, no share.**
- **The 25 remaining `connected_attachments` rows are all soft-deleted** and were
  not touched.
- No client code, no policy, no schema, no membership state, no U6b enforcement
  change, no Device A action.

**U5 not started.** Remaining Phase 4: U5 (B-15 + C-34's version signal), U6
(C-51), U7 (C-58), U8 (copy / privacy disclosures), and exit condition 8 — the
Device A run, owning U2b's and U2s's production behavioural observations.
