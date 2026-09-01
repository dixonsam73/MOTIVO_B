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

---

# RESULTS — 2026-09-01. THE PREDICTIONS ABOVE ARE UNCHANGED.

**7 of 8 predictions held. The one that failed is the one the whole investigation
was for, and BOTH committed hypotheses turned out to be wrong.**

| # | Predicted | Actual |
|---|---|---|
| P-A1 | `rls_enabled=true`, `rls_forced=false` | **HIT** |
| P-A2 | owner `supabase_storage_admin` | **HIT** |
| P-A3 | `rolbypassrls = false` | **HIT** |
| P-A4 | all 4 write policies carry the observer | **HIT** |
| **P-B1** | **upload succeeds → hypothesis (b)** | **FALSIFIED — the upload was REFUSED** |
| P-B2 | SQL control fires the observer | **HIT** |
| P-D1 | both directory RPCs instrumented | **HIT** |
| P-D2 | called from an unexercised path | **HIT**, and sharper — see below |

## (b) IS FALSE: THERE IS NO ENFORCEMENT GAP

With `attachments_user_insert_auth`'s `WITH CHECK` set to `false`, an
authenticated upload through storage-api was **rejected**:

```
HTTP 400  {"statusCode":"403","error":"Unauthorized",
           "message":"new row violates row-level security policy"}
```

**RLS genuinely gates the storage write path.** The pre-existing enforcement gap
I predicted does not exist, and U6b's binding on these policies will do real
work. That is the reassuring half and it was the more important question.

## (a) IS ALSO FALSE

`auth.uid()` is not NULL there. The policy's own predicate proves it: the
baseline upload passed
`lower((storage.foldername(name))[2]) = lower((auth.uid())::text)`, which cannot
succeed on a NULL uid.

## THE ACTUAL MECHANISM — the predicate runs and its side effects are discarded

**Proven with a sequence, because `nextval()` is not transactional and therefore
survives a rollback.** Across one HTTP upload:

```
before:  seq last_value=1  is_called=f   stat_rows=0
         upload HTTP 200
after:   seq last_value=2  is_called=t   stat_rows=0   object_created=1
```

**The observer ran exactly once. Its `INSERT` did not survive.** Consistent with
storage-api performing an RLS-checked insert whose effects are discarded and then
writing the real row through a path that bypasses RLS — `relforcerowsecurity` is
false and the owner is `supabase_storage_admin`, so owner-bypass is available.

Corroborated at both ends, so a null result cannot be mistaken for a broken
experiment: an **unconditionally-raising** observer makes the upload fail
**500 / P0001**, so the observer *is* reached; and the **SQL control** persists an
observation, so the write path works when RLS genuinely applies.

**This is a third mechanism neither hypothesis enumerated**, and it is the useful
kind of wrong: the two candidates I wrote down were "not instrumented" and "not
enforced", and the truth is *"instrumented, enforced, and the evidence thrown
away."*

## THE FIRST RUN OF THIS EXPERIMENT PROVED NOTHING, AND SAID SO

Three defects, all caught by reading the output rather than by review:

1. **`UID` is a readonly shell variable.** It silently became `501`, the OS uid,
   so every path and claim was wrong. Renamed `USERID`, and the script now
   asserts the value looks like a uuid before proceeding.
2. **The bucket enforces `allowed_mime_types`.** `application/octet-stream` was
   rejected 415, so no upload ever occurred and "0 observations" meant nothing.
3. **The control's stderr was suppressed**, so its failure — caused by (1) —
   was invisible. `0 rows` read exactly like a real negative.

**All three produced the same symptom the real finding produces: zero
observations.** That is precisely why P-B2 was written into the plan as a
mandatory control, and it earned its place on the first run.

## SECONDARY FINDINGS FROM THE SAME EVIDENCE

**Surface labels can be misattributed, and counts are not request counts.** All
permissive policies for the command are evaluated, so an `attachments` insert
also evaluates `avatars_insert_owner_only`: the SQL control recorded
**`storage.avatars_insert` and `storage.attachments_insert` at the same
microsecond**. Where an `OR` short-circuits, one of them is skipped — which is
why the production counters for `storage.attachments_recipient` (8) and
`storage.attachments_via_post` (6) diverge despite covering the same reads.

**A comment author reading their own comments is permanently invisible.**
`post_comments_select_visible` is `(auth.uid() = author_user_id) OR (observer AND
(owner OR recipient))` — Q1's deliberately open author branch is evaluated first,
so the `OR` short-circuits and the observer never runs. Correct behaviour, and a
blind spot nobody had stated.

**`get_account_directory_by_user_ids` is cache-gated.**
`AccountDirectoryService.swift:258` calls it only for identities **missing from
the local cache**. So G10's surface — where `search_account_directory` may gate on
the viewer and this one must *never* gate on the subject — is reached **only on a
cold cache**. Shadow evidence about U6b's most delicate change is therefore weak
**by construction**, not merely absent so far.

## WHAT THIS MEANS FOR U6b

1. **The shadow window can never produce a single observation about storage
   writes.** Their absence must never be read as safety.
2. **`would_deny` counts are lower bounds**, not request counts.
3. **A surface's silence has at least three causes** — never reached, allowed by
   an earlier `OR` branch, or observed-and-rolled-back — and only the first is
   what a reader assumes.

**A shadow window's silence is not evidence.** That belongs beside *zero
observations is not evidence of safety*: same error, one level down.

## TEARDOWN

Asserted after every probe, never assumed — U6a's defect 4 was a teardown that
silently did not happen. The policy was restored and matched against the captured
original; `shadow_observe` was restored from `pg_get_functiondef` and asserted to
contain the real body and no probe text; the probe sequence was dropped and its
absence asserted. **Local only. No production mutation at any point.**
