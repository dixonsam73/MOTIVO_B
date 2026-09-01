# Why do storage WRITE policies never observe? — PREDICTIONS, committed BEFORE measuring

**Filed 2026-09-01 from the U6a production shadow window. NOTHING BELOW IS A
RESULT.** Written first, in the D14/D15 style, so the outcome is scored rather
than read off the aftermath. Every number and verdict here can be wrong.

## The observation that prompted it

Across a deliberate two-identity exercise of the product in production — a
publish with an audio attachment, a feed read, an attachment play, two comments
and two follows — the shadow window recorded **48 observations across 11
surfaces**, and:

```
storage SELECT surfaces fired      3 of 3
storage INSERT/UPDATE surfaces     0 of 4   (never, not once)
```

**An object WAS created** in the `attachments` bucket at 2026-09-01 10:11:41,
under `users/<uid>/…`, with a non-null `owner` — so an authenticated identity
uploaded it — and `attachments_user_insert_auth` recorded **nothing**.

A clean split along read/write is not what a one-off looks like.

## THE TWO HYPOTHESES, AND THEY HAVE VERY DIFFERENT CONSEQUENCES

**(a) THE POLICY IS EVALUATED, BUT `auth.uid()` IS NULL THERE.** `shadow_observe`
returns `true` on its first branch when the uid is null and records nothing —
fail-open, by design. U6a would be behaving exactly as specified and the
*telemetry* would simply be blind on that path.

**(b) THE POLICY IS NOT EVALUATED AT ALL.** The row is written by a role that
bypasses RLS — most likely `storage.objects`'s owner, if
`relforcerowsecurity` is false. **This would be a PRE-EXISTING ENFORCEMENT GAP
THAT U6a MERELY REVEALED**, meaning four deployed storage policies do not do what
the schema implies, and it would be true today, before any U6a change.

**Why it must be settled before U6b and not during it.** U6b binds enforcement on
these policies. **Under (b), binding them changes nothing** — the protection the
schema implies would not exist, and a U6b that "passed" would have proved only
that it did not break anything. Under either hypothesis, **"no would-deny
observations on storage writes" must never be read as "storage writes are
safe."**

## PREDICTIONS

### Read-only, against production's catalog

| # | Prediction |
|---|---|
| **P-A1** | `storage.objects` has `relrowsecurity = true` and **`relforcerowsecurity = false`** |
| **P-A2** | `storage.objects` is owned by **`supabase_storage_admin`** |
| **P-A3** | `supabase_storage_admin` has **`rolbypassrls = false`** — it does not need the attribute, because a non-forced table's owner bypasses RLS anyway |
| **P-A4** | All four storage write policies **do** carry `shadow_observe` in production, so their silence is "not reached", never "not instrumented" |

**If P-A1 holds, (b) becomes the leading hypothesis on structural grounds
alone** — but it is not proven by it, because owner-bypass only matters if
storage-api actually performs the insert as the owner rather than as
`authenticated`. That is a runtime question and needs a runtime answer.

### The decisive experiment — LOCAL ONLY, and it is binary

On the local reproduction, replace `attachments_user_insert_auth`'s `WITH CHECK`
with **`false`** — a policy that can refuse everything — then attempt an
authenticated upload through the local storage API.

| # | Prediction |
|---|---|
| **P-B1** | **The upload SUCCEEDS anyway** → the policy is not evaluated → **hypothesis (b)** |
| | *The alternative, stated so the experiment can falsify me:* the upload is **refused** → the policy is evaluated → **hypothesis (a)**, and the blindness is `auth.uid()` being null |
| **P-B2** | A direct SQL `insert into storage.objects` executed as `authenticated` with `request.jwt.claims` set **DOES** fire the observer — the control that proves the policy and the observer both work when RLS genuinely applies |

**P-B2 is the control and it is not optional.** Without it, a null result in P-B1
is indistinguishable from a broken experiment — which is exactly the shape of the
U6a suite's defect 3, *a detection that could never fire reporting the thing it
never tested*, and of the first B-33 experiment, where `or true` folded away the
only thing being measured.

**The teardown is asserted, not assumed** — U6a's defect 4 was a teardown that
restored 23 policies and not the 9 functions, passed, and left the instance
broken. The restored policy is compared against the captured original.

### The directory RPC, same window, different question

`get_account_directory_by_user_ids` has never fired, through a feed open, a post
open, an attachment play and two comments. **That is G10's surface** — where
`search_account_directory` may gate on the viewer and this one must never gate on
the subject, or retained-comment attribution breaks.

| # | Prediction |
|---|---|
| **P-D1** | It **does** carry the observer in production — silence is "not called" |
| **P-D2** | The client calls it from a path none of the exercised actions reached |

## THE FIDELITY CAVEAT, STATED UP FRONT RATHER THAN AS A FOOTNOTE

**The local stack is the same software, not the same deployment.** B-23 exists
because that difference is real. A local result here is **evidence about
production, never proof of it**, and any finding that comes out of this must
carry that qualifier into the register — *verified against a faithful local
reproduction* — exactly as U2's four did.
