# U6a GATE — RESULTS, 2026-08-30

**A gate in U4a's and U5a's sense: re-runnable experiments plus their
consequences, not an implementation.** No policy was altered, no grant left
changed, no function survives, no schema exists. Every experiment runs inside a
transaction that rolls back, or restores the production posture explicitly, and
each one ends by asserting its own residue is zero.

**Local B-23 reproduction only.** All four deployed migrations applied, 33
policies, 7 membership tables. **No production read, no production mutation, no
deploy, no device action, no grandfather-clause change.**

```bash
./supabase/tests/u6a/execute-in-policy.sh        # 1  EXECUTE in a policy qual
./supabase/tests/u6a/predicate-shape.sh          # 1b what shape may the predicate take
./supabase/tests/u6a/inventory-complete.sh       # 2  inventory completeness, both directions
./supabase/tests/u6a/shadow-mechanism.sh         # 3  can the shadow predicate record
./supabase/tests/u6a/predicate-cost.sh 500       # 4  cost, single shape
./supabase/tests/u6a/predicate-cost-shapes.sh    # 4b bare vs scalar subquery
```

---

## RESULT 1 — U3's load-bearing comment is WRONG, and deploying it as written
## would have taken Connected down for every member

The U3 migration asserts, in a comment and nowhere else:

> `connected_member()` needs no grant at all: at U6 it is evaluated inside RLS
> policy expressions, which run as part of the query rather than as a direct
> call — so it decides what clients may see while remaining unreachable BY them.

**Measured: EXECUTE **is** checked, against the INVOKING role, for functions
referenced from a policy qual.** `connected_member()` has EXECUTE revoked from
`authenticated`, so a policy consulting it raises

```
ERROR:  permission denied for function connected_member
```

**for every member, entitled or not.** Not a mis-scoping — a total Connected
outage on the first query after U6b binds.

**The claim is isolated to EXECUTE by three controls, not asserted:**

| | Ungranted | Result |
|---|---|---|
| A | `connected_member()` — SECURITY DEFINER, returns false on this fixture | permission denied |
| B | SECURITY DEFINER twin returning **true** | permission denied — so it is not "the predicate was false" |
| C | plain invoker-rights twin returning **true** | permission denied — so it is not a SECURITY DEFINER quirk |
| D | **C again, with EXECUTE granted and nothing else changed** | **rows returned** |
| E | `connected_member()` with EXECUTE granted | evaluated, returned false — the grant is the whole difference |

E's grant is revoked again inside the same script and the revocation is asserted.

### The first revision of this experiment was defective and said the opposite

It wrote the qual as `connected_member(...) or true`, so that a merely-false
predicate could not be mistaken for a privilege error. **Postgres folds
`or true` to a constant and never evaluates the function.** The run returned 2
rows and "proved" EXECUTE was not checked. **The defensive clause destroyed the
only thing being measured, and it failed in the reassuring direction** — it
agreed with the comment it was sent to test.

---

## RESULT 1b — the obvious fix creates a membership oracle. Three shapes measured

| Shape | Viable | Evidence |
|---|---|---|
| **S1** inline `exists (select 1 from public.membership …)` in the qual, no function call | **NO** | `ERROR: permission denied for table membership`. Table privileges in a qual are checked as the invoker too, and U3 revoked `authenticated` from every membership table |
| **S2** ZERO-ARGUMENT SECURITY DEFINER wrapper over `auth.uid()`, granted to `authenticated` | **YES** | Evaluates cleanly, denies correctly, and its SECURITY DEFINER body reaches the still-ungranted `connected_member(uuid)` inside |
| **S3** grant `connected_member(uuid)` directly | **works, and is dangerous** | As `authenticated` it **answered for a uuid the caller had no relationship to**. Granting it turns the entitlement predicate into a membership oracle over the whole user base, callable as a PostgREST RPC |

**S2 is the adopted shape.** It has no argument to aim, so the oracle cannot be
built from it — the safety is structural rather than a rule somebody follows.

---

## RESULT 4 / 4b — the predicate's cost is a property of HOW IT IS WRITTEN

| rows | `is_member() and …` | `(select is_member()) and …` |
|---|---|---|
| 500 | **24.65 ms** — per-row Filter | **0.638 ms** — InitPlan |
| 5000 | **278.52 ms** — per-row Filter | **3.925 ms** — InitPlan |

Unenforced baseline at 500 rows: 0.458 ms. **So the subquery form costs ~0.18 ms
per query and does not scale with the corpus; the bare form costs 11.3× more for
10× the rows.**

**STABLE is not a caching promise.** It guarantees stability within a statement;
it does not make the planner evaluate the function once. An uncorrelated scalar
subquery does, because it becomes an InitPlan.

> **STANDING RULE FOR U6: every entitlement predicate in a policy MUST be written
> `(select …)`. A bare call is a performance defect that grows with the corpus,
> and it is invisible in review because both forms are correct.**

This is checkable rather than remembered — see G4-S3 below.

---

## RESULT 3 — the shadow mechanism, and it works

G4 wants "per denied request, which clause would have decided it". **RLS gives no
denial event**: a SELECT policy filters silently, and expressions do not write.

**The InitPlan is the hook.** Written `(select shadow(...))` the predicate is
evaluated exactly once per query per table — which is the natural granularity for
a shadow record.

| Measured | Result |
|---|---|
| Can a VOLATILE SECURITY DEFINER function INSERT while called from a SELECT policy? | **Yes** |
| Does VOLATILE destroy the InitPlan? | **No** — still hoisted, still once per query |
| Log rows produced by one query, `(select …)` form | **exactly 1** at both 500 and 5000 rows |
| Log rows produced by one query, bare form | **500** and **5000** — one per scanned row |
| Cost of the recording form | 2.33 ms @500, 5.62 ms @5000 (≈1.7 ms over the non-recording predicate) |
| Clause named for an identity with no row and no snapshot entry | `unknown`, `would_deny = true` |

**PostgREST's per-request hook was also checked and is NOT the answer here.**
`pgrst.db_pre_request` is unset, and `authenticator`'s role config carries only
timeouts. It could be set — but it fires once per HTTP request with no knowledge
of *which surface* was touched, so it cannot answer G4's actual question. The
in-predicate hook can.

### The shadow log MUST be an aggregate, not an append-only log

One row per query per gated surface is **unbounded durable write amplification on
every read**. B-29 filed exactly this shape once already, and both
`membership_notification_reject_stat` and `membership_binding_conflict` are
bounded by construction — a key plus a counter.

**So: key `(user_id, surface, decided_clause, hour)`, increment a counter.**
Bounded by identities × surfaces × clauses × hours, and it answers every question
G4 asks. An append-only log answers no additional question and grows without
limit.

---

## WHAT THIS GATE DID NOT SETTLE

- **GATE-SUBJECT has no safe predicate.** Quarantine's "invisible to other
  members" and `search_account_directory`'s undiscoverability are gates on the
  SUBJECT, and S2 has no argument to express one while S3 is an oracle. **This is
  D-U6-1 in the inventory and it blocks the quarantine-visibility half of U6.**
- **Nothing about real traffic.** Every number here is from a synthetic fixture
  on a local reproduction. The shadow window itself is what measures production.
- **Nothing about the client.** No client build was touched or run.
- **G11 remains unrun**, and it is an entry condition for U6b, not U6a.

---

## PROPOSED REGISTER ROW — **NOT YET FILED**, awaiting a decision

Result 1 is a defect in a deployed artefact's durable comment, and U6 would have
implemented from it. Proposed as **B-33**, P1, Phase 3:

> **B-33 — U3's migration comment asserts that a function in an RLS policy qual
> needs no EXECUTE grant, and it is false.** The comment reads "`connected_member()`
> needs no grant at all: at U6 it is evaluated inside RLS policy expressions …
> so it decides what clients may see while remaining unreachable BY them", and
> U3 revokes EXECUTE from all four roles on that basis. **Measured on the local
> reproduction 2026-08-30: EXECUTE is checked against the invoking role for
> functions referenced from a policy qual**, isolated from SECURITY DEFINER and
> from predicate value by three controls and a grant/revoke discriminator. A U6
> that implemented the comment as written would have raised
> `permission denied for function connected_member` on every Connected query for
> every member, entitled or not. **No defective implementation ever existed** —
> found by executing the claim before writing the policy, which is the only way
> it could have been found, since the comment is correct-sounding and the
> function is genuinely unreachable as a direct call. The adopted fix is a
> zero-argument SECURITY DEFINER wrapper granted to `authenticated`; granting the
> uuid-taking form instead would have created a membership oracle (see D-U6-1).
> `connected_member(uuid)` itself stays ungranted and unchanged.

---

# PROPOSED U6a IMPLEMENTATION PLAN — FOR REVIEW. NOT IMPLEMENTED.

**U6a denies nothing.** That is not a policy of the unit, it is a property of its
predicate: the shadow function returns `true` unconditionally and has no branch
that can return anything else. Enforcement is U6b.

## Schema changes — three objects, and that is the whole delta

| Object | Shape | Grants |
|---|---|---|
| `public.membership_shadow_stat` | Aggregate table. PK `(user_id, surface, decided_clause, bucket_hour)`, plus `would_deny boolean`, `observations bigint`, `first_seen`, `last_seen` | **none to any client role** — same posture as every membership table |
| `public.connected_member_self()` | Zero-argument, STABLE, SECURITY DEFINER, `search_path = ''`. Body: `select public.connected_member((select auth.uid()))` | EXECUTE to `authenticated` **only** |
| `public.membership_shadow_observe(p_surface text)` | VOLATILE, SECURITY DEFINER, `search_path = ''`. Records the decision, **returns `true` always** | EXECUTE to `authenticated` **only** |

**`connected_member(uuid)` is not modified and not granted.** Neither is
`membership_state(uuid)`. The uuid-taking forms stay server-private, which is
what keeps S3's oracle unbuildable.

**No policy is altered in U6a-step-1.** The predicate is added to policies in
U6a-step-2 as `(select public.membership_shadow_observe('<surface>'))`, which is
`true` for everyone — so the visible behaviour of all 33 policies is unchanged,
and that is assertable rather than promised.

## API changes

**None.** No Edge Function, no client change, no new client-reachable RPC beyond
the two EXECUTE grants above, neither of which takes a user id.

## Rollout order

1. Schema only. No policy touched. Verify B-23 delta matches a committed prediction.
2. Attach the shadow predicate to the **GATE-VIEWER** surfaces named in
   `docs/u6-enforcement-inventory.md`, and to nothing else.
3. Open the window. **Predictions committed before it opens.**
4. Read the aggregate against those predictions.

**The eight SECURITY DEFINER RPCs get the same shadow call in their bodies**, or
U6a measures two-thirds of the surface and reports it as the whole.

## EXACT ACCEPTANCE CRITERIA FOR G4

**Structural — asserted on the catalog, before the window opens:**

| # | Assertion |
|---|---|
| **G4-S1** | Every gated surface's shadow predicate returns `true` on every path. `membership_shadow_observe` contains exactly one `return`, and it is `true`. Proven by execution against a non-member fixture, not by reading |
| **G4-S2** | Row counts through every gated surface are **identical** with the predicate attached and detached, for an entitled identity, a lapsed identity, a Sandbox-only identity and a snapshot identity. **This is the assertion that makes "shadow" mean something** |
| **G4-S3** | **No bare predicate call.** Every `qual`/`with_check` mentioning the shadow function matches `(select ` immediately before it. Result 4b is a 71× performance cliff that both forms pass functionally |
| **G4-S4** | `connected_member(uuid)` and `membership_state(uuid)` remain EXECUTE-revoked for `anon`, `authenticated` and `service_role`. **The oracle stays unbuildable** |
| **G4-S5** | Zero client role holds any privilege on `membership_shadow_stat` |
| **G4-S6** | `service_role` still `bypassrls`, and both destructive Edge Functions are reachable and unchanged — **C-35 cannot regress under enforcement** |
| **G4-S7** | The aggregate is bounded: repeated identical decisions increment `observations` and create no new row. Asserted by issuing N queries and reading a row count of 1 |

**Behavioural — read from the window:**

| # | Assertion |
|---|---|
| **G4-B1** | Every observation names exactly one clause from `membership_state()`'s five: `entitled`, `expired`, `sandbox_only`, `grandfathered`, `unknown` |
| **G4-B2** | **Zero observations decided solely by `grandfathered`.** This is U6b's entry condition and the number B-11's stage-2 gate reads |
| **G4-B3** | **`sandbox_only` observations are reported separately and excluded from every conclusion about real users.** This is the whole reason D4 added the fifth state |
| **G4-B4** | Every `would_deny = true` observation is attributable to an identity and a surface, and reconciles against `membership` — no unexplained denials |

**G4 PASSES when S1–S7 and B1, B3, B4 hold. G4-B2 is NOT a pass condition for
G4** — it is U6b's entry condition, and conflating them is how one metric came to
stand for four questions. A window that observes grandfather-only decisions is a
*successful* G4 and a *blocked* U6b.

**What G4 cannot prove, restated so it is not cited for it later:** anything
about identities that generated no traffic. A dormant pre-cutover subscriber
produces zero observations, and zero observations is not evidence of safety —
that is G11's question, and G11 has never been run.
