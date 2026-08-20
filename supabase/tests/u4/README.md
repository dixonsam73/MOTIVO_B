# U4 — ingestion and reconciliation, local suite

**Local and disposable only.** `lib.sh` refuses any non-localhost `DB_URL`, and
`u2/lib.sh` refuses any non-localhost `API_URL`. There is no flag to turn either
off.

```bash
supabase db reset --local && ./supabase/tests/u4/run.sh
```

## Three suites, deliberately separate

They answer different questions, and a pass in one must never be read as
covering another.

| | Answers | Where the evidence lives |
|---|---|---|
| `modules.ts` | Do the verifier, the derivation rules and the Apple API client behave? **Q6's failure modes exist ONLY here** — 5xx, timeout, malformed body and the rest cannot be induced against Apple, so `fetch` is injected | Real edge runtime, no database, no network |
| `acceptance.sh` | Does the SQL hold? Privilege boundary, ordering, dedupe, quarantine arithmetic, and the B-24/B-25 refusals | Real local database |
| `e2e.sh` | **Wiring.** Does an HTTP request to the real function produce the right row, the right status code and the right *absence* of a write? | Real function, real database |

## The one deliberate difference from production, and why it is in a copy

Our fixtures are signed by a throwaway test CA, so against the shipping anchor
they would — correctly — all fail. The alternative would be an environment
variable that relaxes the trust anchor, and **a production-reachable switch on
the one control that makes an unauthenticated endpoint safe is exactly what must
not exist.**

So `e2e.sh` writes a work-dir copy of `apple_root_ca_g3.ts` carrying the test
root, and **every other byte is the shipping source**, at the same directory
depth so the module graph resolves identically. The happy path is therefore
proven against a faithful *copy*, never against Apple.

## Rules that hold here

- **An empty or uncreated fixture is not a pass.** `E0` asserts the binding
  exists before anything depends on it — the first version inserted and
  discarded the result, the unique token collided with another suite's, and
  three assertions failed in a way that looked like a defect in the writer.
- **A command exit status is not a pass.** Every assertion reads resulting state.
- **Fixtures are relative to the real clock.** A frozen epoch was used first and
  aged past `now()`, so every fixture derived as EXPIRED and a correct writer
  scheduled quarantine. A fixture that says "thirty days from now" must mean it.
- Everything verified here is **"verified against a faithful local
  reproduction"**, never "verified in production".

## The U5 stand-in, and why it is a fixture rather than a code path

**U4 cannot create a `membership` row** — `membership_apply_state_v1` is
UPDATE-only and there is no `INSERT INTO public.membership` anywhere in the
migration. So both `acceptance.sh` and `e2e.sh` first assert the *refusal*
(mapped, complete, and still `ignored`/`unestablished` with zero rows), then
insert an authoritative row **directly**, labelled as standing in for U5's
establishment protocol, and go on to test refresh — which is all U4 claims to do.

`A47f` asserts the same rule structurally, over `pg_get_functiondef`, so it
cannot drift back into the code without failing.

## What is NOT covered

- **Any mapped identity in production.** Until U5 sets an `appAccountToken`, no
  real notification can map, so the mapped path is exercised locally and nowhere
  else. That is an acceptance-window property, not a permanent one.
- **A genuine Apple-signed payload.** See `../u4a/README.md`; B-28 discharges at
  U4i.
- **Reconciliation against Apple.** The client is exercised against an injected
  `fetch`. The first real call happens at U4i.
