# P4-U7 — DEPLOYMENT PREDICTION. COMMITTED BEFORE THE PRODUCTION RUN

Apply file: `supabase/sql/2026-09-05-u7-c58-follow-scoped-attribution.sql`.
Implementation checkpoint `c5499c1`. **Production not yet changed.**

## Pre-state, measured read-only immediately before handover

| fact | value |
|---|---|
| `get_account_directory_by_user_ids` def md5 | `d0d1322e926fa0c9c385c6272395c207` |
| `has_follow_scope` | **false** |
| enforcement_enabled | **true** (live) |
| identities | 17, **all unentitled** (`connected_member` false for every one) |
| approved follows | 4, **all with an unentitled follower** |
| requested follows | 5 |
| `account_directory` rows | 17 |
| `membership` rows | 1 |

**C-58 REPRODUCED IN PRODUCTION, read-only:** viewer `41aacc65` (unentitled)
holding an approved follow to subject `daed2252` (which has a directory row)
receives **0** attribution rows.

*(UUIDs recorded as `md5[0:8]` per the standing rule.)*

## Predicted output of the apply

One row, all eight guards having passed:

| column | predicted |
|---|---|
| `function_name` | `get_account_directory_by_user_ids` |
| `def_md5` | **`48e7f743196e3ed43438ce0a8c449ea6`** |
| `security_definer` | `t` |
| `anon_execute` | `f` |
| `authenticated_execute` | `t` |
| `service_role_execute` | `f` |
| `has_follow_scope` | `t` |
| `g10_violated` | `f` |

**The md5 is byte-exact to the locally rehearsed function** — the local stack was
confirmed byte-identical to production before the change
(`d0d1322e…`/`077f73f2…`), so an equal md5 afterwards means production received
exactly the rehearsed text, not merely something equivalent.

## Predicted post-state

| # | check | predicted |
|---|---|---|
| 1 | viewer `41aacc65` → subject `daed2252` (approved) | **0 → 1** |
| 2 | the same in the reverse direction | **1** |
| 3 | any viewer → a subject with **no** relationship | **0** |
| 4 | viewer → a **requested**-only subject | **0** |
| 5 | `search_account_directory` for an unentitled viewer | **0**, unchanged |
| 6 | grants anon/authenticated/service_role | `f/t/f`, unchanged |
| 7 | census: identities 17, directory 17, membership 1, follows 4+5 | unchanged |
| 8 | `search_account_directory` def md5 | `077f73f2…`, unchanged |

## ONE CHECK CANNOT BE MADE IN PRODUCTION, AND IT IS SAID BEFORE THE RUN

**"Entitled viewer → lapsed author remains unchanged" is NOT verifiable in
production: there are ZERO entitled identities.** Grandfathering is retired and
the single `membership` row is Sandbox, so `connected_member` is false for all
17. That check rests on the local rehearsal (`U7-D1`, and U6b's own `G1`), on
the byte-identical function text, and on the structural fact that the gate
remains the untouched first disjunct — an entitled viewer short-circuits before
the new clause is ever evaluated.

**Recorded as a stated limit, not folded into a pass.**
