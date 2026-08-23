# U5b — establishment foundation, local suite

**Local and disposable only.** Inherits `u2/lib.sh`'s API_URL guard and
`u4/lib.sh`'s DB_URL guard; there is no flag to turn either off.

```bash
supabase db reset --local && ./supabase/tests/u5/run.sh
```

## The three suites

| | Answers | Where the evidence lives |
|---|---|---|
| `modules.ts` | **U5c** — does the claim boundary hold, and is the Set App Account Token taxonomy right? | Real edge runtime, fetch injected, no database, no network |
| `acceptance.sh` | **U5b** — does the SQL hold? Environment separation, the establishment writer, the two grants, F11 | Real local database |
| `e2e.sh` | **U5d** — **wiring, and the OUTBOUND CALL ORDER.** Does an authenticated request produce the right row, the right status, the right absence of a write, and the right sequence of Apple calls? | Real endpoint, real database, programmable Apple |

**`e2e.sh` is the only place A30 can be proven**, because A30 is an ordering
assertion: an implementation that establishes on the strength of the PUT's own
200 reaches an identical final row and is wrong. The stub records every request
and the suite asserts the sequence.

## The evidence boundary — read before recording anything from this suite

**`acceptance.sh` asserts the SQL-side PRECONDITION only** — that establishment
**refuses** on a token Apple has not confirmed as ours, whether Apple reports no
token (`A30pre`) or one belonging to nobody (`A31`). Those assertions are
labelled `A30pre*` so the distinction survives being skim-read.

**A30's local half is discharged in `e2e.sh`**, 2026-08-23, by asserting the
outbound sequence `GET -> PUT -> GET -> establish` (`E5d-A30c`), that at least
one read follows the PUT (`E5d-A30e`), and that the call immediately after the
PUT is a read rather than a write (`E5d-A30f`). **The genuine-Apple half remains
outstanding and discharges only against Apple.**

**A29 and A31 ARE exercised in full**, because both are decisions the database
makes on its own evidence: a token belonging to another live binding is refused
and recorded, and an orphan is distinguished from a mismatch.

## The assertion that would have been easiest to get wrong

`A60` is the one to keep. A **Sandbox-only identity that is in the cutover
snapshot** must derive `false`. Under the obvious fix — adding
`and m.environment = 'Production'` to the WHERE clause — the row set empties,
`bool_or` over an empty set is NULL, and the predicate falls through to the
**grandfather** clause, granting Production entitlement to a sandbox tester *by
the compatibility clause*. That is the exact inversion of invariant 8, reached by
the natural implementation. `A60c` is its purest form: the same row with every
derivation input NULL.

## Rules that hold here

- **An empty or uncreated fixture is not a pass.** Bindings are created and read
  back before anything depends on them.
- **A command exit status is not a pass.** Every assertion reads resulting state.
- Everything verified here is **"verified against a faithful local
  reproduction"**, never "verified in production".
