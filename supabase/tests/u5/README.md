# U5b — establishment foundation, local suite

**Local and disposable only.** Inherits `u2/lib.sh`'s API_URL guard and
`u4/lib.sh`'s DB_URL guard; there is no flag to turn either off.

```bash
supabase db reset --local && ./supabase/tests/u5/acceptance.sh
```

## What U5b is, and what it deliberately is not

U5b is the **SQL foundation** for ownership establishment. It adds one table,
one function, two grants, and replaces two helpers. It creates **no Edge
Function**, makes **no Apple request**, schedules nothing and deletes nothing.
`_shared/appstore` work is **U5c**; the attest endpoint is **U5d**.

## The evidence boundary — read before recording anything from this suite

**A30 IS NOT DISCHARGED HERE.** A30 is *"the legacy claim calls Set App Account
Token and re-reads Apple before writing membership"*. Both halves are HTTPS round
trips that must never happen inside a transaction (B-30), and neither exists yet.

What this suite asserts is the **SQL-side precondition only**: that establishment
**refuses** on a token Apple has not confirmed as ours — whether Apple reports no
token at all (`A30pre`) or reports one belonging to nobody (`A31`). That is what
makes the claim path impossible to short-circuit in the database. It is a
prerequisite for A30, not A30, and the assertions are labelled `A30pre*` so the
distinction survives being skim-read.

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
