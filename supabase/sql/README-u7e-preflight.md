# U7e — SCHEDULER. IMPLEMENTED LOCALLY, NOT ACTIVATED. 2026-09-03

**ACCEPTED WITH FIVE DECISIONS, 2026-09-03, AND NOW IMPLEMENTED LOCALLY.**
`pg_cron` is still 0 in production. No production secret exists, the worker has
**not** been redeployed, and the workflow is on a **feature branch**, where
GitHub never runs a schedule. Nothing is activated.

**The four ratified decisions that changed this plan:**

1. **G7 is the named deferred operational verification**, not a closure blocker,
   and its stale `allowlisted` wording is corrected **with the superseded text
   preserved** — §1 and `docs/qa-plan.md` G7.
2. **`membership_cleanup_v1` accepts ONLY `CLEANUP_INVOKE_KEY` from outside.**
   The service role key is **no longer accepted** — §2.
3. **GitHub Actions daily is accepted for launch**, with its 60-day inactivity
   auto-disable recorded as an **operational risk**, not designed around — §6.
4. **The finished state is `mode: execute`, not a permanent dry run** — §7.

---

## 1. WHAT THE RECORD ACTUALLY REQUIRES — U7d RECONCILED

**Three distinct claims, which the record deliberately keeps apart:**

| Claim | Status | Evidence |
|---|---|---|
| **Destructive cleanup IMPLEMENTATION behaviour** | **DISCHARGED, locally** | `u7/e2e-worker.sh` **75/75** against the real worker, real database, real storage objects and a programmable Apple — the full retention matrix including reference-counted shared attachments, B-19 retention, avatar ordering and third-party blast radius |
| **Genuine PRODUCTION authority behaviour** | **DISCHARGED, in production, 2026-09-03** | Claim → live Apple read (proved by `renewal_info_signed_date` moving to a signature Apple produced minutes earlier, through the pinned anchor) → applied through the canonical writer → gate → **refusal, zero deletion** |
| **Destructive execution in production on a genuinely matured 60-day quarantine** | **NOT AVAILABLE** | Requires real elapsed time. Earliest `2026-11-01 15:16:44+00` |

### Does the record require the third before closure? NO — and here is the reading

**`docs/qa-plan.md` Q8 is the row that speaks to it:**

> | Q8 | Apple confirming non-entitlement → the expiry-specific policy runs | **Local for the full retention matrix, and once for real at G7** |

So the record does contemplate one real run, as **G7**. Three things about G7
decide how it should be classified, and none of them is a reinterpretation:

1. **G7 IS A PLAN, NOT A PASS CONDITION.** Its own section header states it:
   *"Recorded 2026-08-16 at U0. NONE OF THESE HAS BEEN RUN. Every row below is a
   plan. No PASS state is recorded anywhere in this section."* No text anywhere
   makes G7 a precondition of U7 or Phase 3 closing.

2. **G7's stated mechanism WAS REJECTED FOUR DAYS AFTER IT WAS WRITTEN.** G7 reads
   *"Expiry cleanup on Device A's account, **allowlisted**"* — the D4 per-identity
   allowlist, **rejected outright on 2026-08-20** because it put a shippable
   exception inside the predicate defining paid access. **G7 as written presumes a
   mechanism that does not and will not exist.** This is the C-52 shape again: a
   document written under a rule that later changed and was never re-read.
   **Recorded, not silently corrected** — see §10.

3. **THE PROJECT ALREADY HAS A PRECEDENT FOR EXACTLY THIS SHAPE, AND IT IS
   BINDING RATHER THAN ANALOGOUS.** Gate 6 part 3 — the production GRANT path at
   the first real subscription — is *"unobtainable before public release and is
   **NOT** a bind precondition"*, and **B-11 was RESOLVED with it outstanding**.
   Phase 1 closed carrying C-36, B-4, B-12 and B-13; Phase 2 closed carrying C-51;
   CLAUDE.md states that *"Phase 3 is explicitly allowed to close"* with a bounded
   obligation outstanding, because *"forcing removal to fit a phase boundary would
   be the opposite of the discipline that says no obligation may be ownerless."*

**CONCLUSION: the calendar-dependent production deletion is a NAMED DEFERRED
OPERATIONAL VERIFICATION, not an implementation blocker.** It is **G7**, which
already exists — **no new release gate is invented**. Its owner is U7, its
earliest date is `2026-11-01 15:16:44+00`, and its precondition is now simply
*time*, since the worker, the authority path and the schedule are all in place.

**U7d is therefore a PASS on everything obtainable**, with G7 carried.

---

## 2. THE CREDENTIAL BOUNDARY — DECIDED FIRST, BECAUSE IT ELIMINATES OPTIONS

**RATIFIED CONSTRAINT: no service-role credential may be stored in, or readable
from, PostgreSQL.**

| Option | Verdict |
|---|---|
| **`pg_cron` + `pg_net`, key in a table or `ALTER DATABASE SET`** | **REJECTED.** The key becomes readable by anything that can read that table or setting |
| **`pg_cron` + `pg_net`, key in Supabase Vault** | **REJECTED, and this is the one that looks compliant and is not.** `vault.decrypted_secrets` is a view any sufficiently privileged role can select from. Encrypted at rest is not the property being required — the requirement is that **PostgreSQL cannot read it**, and Vault exists precisely so that it can |
| **Supabase dashboard "Cron"** | **REJECTED — it is `pg_cron` + `pg_net` underneath.** Choosing it through a UI does not change where the credential lives |
| **External scheduler holding the credential outside the database** | **ADOPTED** |

**This also keeps a property U7c fought for.** `service_role` holds **zero** table
privilege on all six membership tables and **cannot execute
`connected_member(uuid)`** (B-33). Putting its key inside the database would make
the one role that cannot read membership able to invoke the thing that deletes on
membership grounds, from inside the database, forever.

### The narrower credential — RECOMMENDED, and it is the only worker change U7e needs

A scheduler holding the **service-role key** holds a credential that can do
**anything** in the project. For invoking one endpoint that is far more authority
than the job needs.

**RATIFIED AND IMPLEMENTED: `CLEANUP_INVOKE_KEY` is the ONLY externally accepted
credential. The service role key is refused.** The preflight proposed accepting
both; the decision went further, and further is right.

```ts
const ok = (!!presented) && (
  (SERVICE_ROLE && secretEquals(presented, SERVICE_ROLE)) ||
  (INVOKE_KEY   && secretEquals(presented, INVOKE_KEY))
);
if (!ok) return json(401, …);
```

**THE HAZARD TO DESIGN AGAINST, NAMED NOW:** an **unset** `CLEANUP_INVOKE_KEY`
must never make the comparison trivially succeed. AUTH-10 already established
that an absent `SERVICE_ROLE_KEY` fails **closed** (500, no work); the second
branch must fail closed the same way, which is what the explicit truthiness
guards above are for. **`auth-probe.sh` gains cases for: invoke key correct →
200; invoke key wrong → 401; invoke key absent from the environment while a
caller presents anything → 401/closed.**

**BE PRECISE ABOUT WHAT REFUSING `service_role` BUYS, BECAUSE IT IS EASY TO
OVERCLAIM — and this sentence is the one to re-read before anyone cites this
design as a protection it is not.**

**It does NOT protect the data from a service-role holder.** Anyone with that key
can delete the same posts, rows and storage objects directly, and nothing at this
layer could prevent that. What it buys is narrower and still real:

- **The scheduler holds a credential that can do nothing else.** This is the
  primary win, and it comes from the dedicated key existing.
- **No other tool or script that happens to carry `service_role` can trigger an
  unattended destructive run by accident.** A single-purpose door for a
  single-purpose job.

**Cost, paid:** the deployed worker's authorisation path changed, so it needs a
redeploy and the probe re-run. Both are done locally; the redeploy is a listed
production activation step.

---

## 3. THE SMALLEST SCHEDULER ARCHITECTURE

**A scheduled GitHub Actions workflow that makes one HTTPS POST.**

```
GitHub Actions (cron)  --HTTPS POST + secret-->  membership_cleanup_v1
   secret lives in GitHub's encrypted store            (already deployed)
   never in PostgreSQL, never in the repo
```

**Why this and not something cleverer:**

- **The credential lives where the constraint requires** — outside the database,
  in a store built for it, injected as an environment variable at run time.
- **Zero new infrastructure and no new server code.** The worker exists, is
  deployed, and already requires `mode: "execute"` to be named explicitly.
- **Every run is logged and auditable** with its request and response, which a
  `pg_cron` job is not without building logging for it.
- **Two independent kill switches**: disable the workflow, or delete the secret.
  Either stops unattended execution immediately, and **neither touches membership
  state** — unlike U6's kill switch, nothing needs to be un-bound.
- The repository already exists and is the project's own home.

**Not adopted, and why:** a `launchd`/`cron` job on the account holder's Mac keeps
the credential local but makes unattended cleanup depend on one laptop being
awake — a scheduler that silently does not run is the failure mode this whole
unit is most exposed to (§6).

**The workflow is roughly fifteen lines**: `on.schedule`, one `curl`, and a step
that fails the run if the HTTP status is not 200 so a broken credential is loud.

---

## 4. CADENCE — DAILY, AND WHY THAT IS AMPLE

**Proposed: once daily.**

- **The fuse is 60 days.** Daily granularity means at most ~24 hours of latency on
  a 1,440-hour timer — **1.7%**. The content simply persists a few hours longer,
  which is the safe direction.
- **Weekly would also be defensible and is worse for one reason**: a broken job is
  discovered a week later instead of a day later. **Cadence here is a monitoring
  decision more than a timeliness one.**
- **More often than daily buys nothing and costs Apple API calls**, lease churn
  and log noise. Cleanup is not latency-sensitive by construction.
- **Volume is trivial** — one identity today, and the batch limit is 25.

**Deliberately NOT tuned to the quarantine.** Nothing should ever compute the
schedule from the 60 days; the worker already refuses anything not genuinely due,
as it did on 2026-09-03.

---

## 5. CONCURRENCY WITH THE ONE-HOUR LEASE

**Daily cadence and a one-hour lease cannot interact**, and that is the point of
choosing them independently:

- Two scheduled runs are 24 hours apart; the lease expires after 1. **Overlap is
  impossible unless a single run exceeds 24 hours**, which would itself be the
  alarm.
- The lease still earns its place for the two cases it was built for: a **manual**
  invocation racing the scheduled one, and a **hung** run — where the claim
  expires on its own and the identity returns to the candidate set.
- **A refused identity holds its lease for up to an hour.** At daily cadence this
  has **zero** effect. **Accepted as harmless, and no release-on-refusal machinery
  will be added** — releasing eagerly would make the refusal path write, which
  this unit has twice chosen against.

---

## 6. FAILURE, RETRY, AND THE ONE THAT ACTUALLY MATTERS

**No retry logic will be built, because retry already exists structurally.**
Completion is written **last**, so any failed or partial run leaves the identity a
candidate and **the next day's run re-reads Apple and re-authorises from
scratch**. A failed HTTP call, a 500, a hung request, an aborted identity — all
converge on "try again tomorrow, from the beginning".

**THE REAL RISK IS NOT A FAILING JOB. IT IS A SILENTLY ABSENT ONE**, and there is
a specific, well-documented instance of it that lands squarely on this design:

> **GitHub disables scheduled workflows after 60 days of repository inactivity.**

**That interval is the same order as the quarantine.** A repository that goes quiet
after release is exactly the condition under which the scheduler stops and nothing
says so — and the symptom is *content that should have been cleaned up quietly
persisting*, which nobody notices because nothing breaks.

**Mitigation is required and is part of U7e, not an afterthought:** the workflow
must fail loudly on a non-200, and its liveness must be observable — the simplest
sufficient check being that a human or a periodic review confirms the job ran, or
a heartbeat visible outside GitHub. **This is named now precisely because the
failure is invisible by construction.**

---

## 7. IS ACTIVATION ITSELF DESTRUCTIVE?

**Not when nothing is due — and that is structural, not hopeful.** With zero
eligible identities the selector returns no rows and the worker does nothing: no
Apple call, no write, no deletion. Today Device A is **not** due
(`2026-11-01 15:16:44+00`), so a scheduler activated now would do nothing at all
for eight weeks.

**But activation is exactly what makes destruction possible with nobody
watching**, and that is the whole risk this unit introduces.

**Therefore, and this is a real risk boundary rather than copied U6 ritual:**

```
U7e-1   schedule live with CLEANUP_MODE unset -> dry_run   destruction IMPOSSIBLE
        proves: the cron fires, the credential authenticates, the worker is
                reachable, and the scheduled output is what it should be
   ⛔   separately authorised
U7e-2   set repository variable CLEANUP_MODE = execute     unattended execute live
```

**The two are separated by a repository VARIABLE, not by a code change**, so
neither activation nor rollback needs a commit, a redeploy, or a merge. Unsetting
`CLEANUP_MODE` returns the schedule to `dry_run` immediately.

**A dry-run schedule cannot delete anything** — the worker's `dry_run` path makes
no Apple call, takes no lease and writes nothing, proven in production on
2026-09-02. So U7e-1 tests **the entire scheduler** — timing, credential,
reachability, logging — with the destructive capability structurally absent.

### DECISION 4 — THE FINISHED STATE IS `execute`. MY RECOMMENDATION WAS OVERRULED, AND CORRECTLY

**This section previously concluded:**

> *"Recommendation: keep the schedule on `dry_run` until G7 has been performed
> once MANUALLY and scored, then flip to `execute`."*

**RATIFIED 2026-09-03: dry-run is an ACTIVATION AND VERIFICATION STEP, not a
resting state.** Once the invocation and configuration are verified, U7e's
intended final state is `mode: execute`. Leaving a finished product parked in a
mode that cannot do its job, waiting on a calendar, is not a safety measure — it
is an unfinished deployment.

**The justification is the architecture already demonstrated in production, not
optimism.** `execute` mode **cannot** authorise cleanup from a stale or
operator-written timestamp: it must refresh Apple, apply canonical state through
the writer, and re-evaluate authority first. That is exactly what happened on
2026-09-03 — a manual `execute` on a deliberately-advanced schedule **refused**,
and the reconciliation overwrote the artificial value with Apple's own derived
one. **An unattended `execute` today has no genuinely due identity to act on, and
could not manufacture one.**

**The residual — that the first production deletion would then be unattended —
is real, accepted, and bounded:** it applies to one disposable beta identity whose
blast radius is already measured and authorised, and G7 remains the scored
observation whenever it lands. **It is not a reason to ship a scheduler that
cannot run.**

---

## 8. PREDICTION-FIRST ACCEPTANCE — COMMITTED BEFORE IMPLEMENTATION

### 8a. LOCAL, verifiable now (this unit)

| ID | Prediction | Measured |
|---|---|---|
| **L-1** | no header → 401 | **401** |
| **L-2** | empty bearer → 401 | **401** |
| **L-3** | anon key → 401 | **401** |
| **L-4** | junk bearer → 401 | **401** |
| **L-5** | cleanup key **+1 char** → 401 | **401** |
| **L-6** | cleanup key **−1 char** → 401 | **401** |
| **L-7** | a wholly wrong secret → 401 | **401** |
| **L-8** | **the SERVICE ROLE key → 401** — the inversion, and the point of the change | **401** |
| **L-9** | a genuine signed user JWT → 401 | **401** |
| **L-10** | the correct cleanup key → **200** (not vacuously refusing) | **200** |
| **L-11** | scheme prefix optional, as `appstore_reconcile_v1` | **200** |
| **L-12** | `GET` → 405 | **405** |
| **L-13** | key **UNSET**, correct key presented → **401** fail closed | **401** |
| **L-14** | key **UNSET**, **empty** credential → 401 (two empties never match) | **401** |
| **L-15** | key UNSET, no header → 401 | **401** |
| **L-16** | key UNSET, service role presented → 401 | **401** |
| **L-17** | the full worker e2e still passes under the new credential | **75/75** |
| **L-18** | the workflow YAML parses, has exactly one daily schedule, a concurrency group and read-only permissions | **parses; `17 3 * * *`; group `membership-cleanup`; `contents: read`** |
| **L-19** | `pg_cron` remains **0**; U4's `A57f` still passes | **0, passes** |

### 8b. PRODUCTION, at activation (each step human-authorised)

| ID | Prediction |
|---|---|
| **S-1** | Redeployed worker: correct invoke key → **200**; service role key → **401**; no header → **401** |
| **S-2** | With the workflow on the default branch and the secret set, the schedule **fires within its window** and logs **HTTP 200** |
| **S-3** | A scheduled `dry_run` returns `identities: 0` while nothing is due — the correct no-op |
| **S-4** | Across scheduled runs: **zero** `cleanup_claimed_at`, **zero** `cleanup_completed_at`, every global count unchanged |
| **S-5** | Secret removed → the run **fails loudly**, calls nothing |
| **S-6** | `CLEANUP_MODE` unset → the run uses **`dry_run`**, never execute |
| **S-7** | Workflow disabled → **no invocation** |
| **S-8** | Device A's schedule stays `2026-11-01 15:16:44+00` throughout |
| **S-9** | `pg_cron` remains **0** — the scheduler is outside the database |
| **S-10** | With `CLEANUP_MODE=execute` and nothing due, a scheduled run **still deletes nothing** — the authority path refuses, exactly as it did manually on 2026-09-03 |

### 8c. G7 — deferred, owned, dated (earliest 2026-11-01)

| ID | Prediction |
|---|---|
| **G7-1** | An `execute` run on a genuinely matured quarantine performs the cleanup and matches a prediction **committed before it** |
| **G7-2** | Retention holds in production — retained comment, directory row, `display_name`, `auth.users`, `membership`, `membership_binding` |
| **G7-3** | `cleanup_completed_at` set, `pending_cleanup_at` NULL, lease cleared, no orphaned object |
| **G7-4** | Third-party blast radius zero |

**F-2, F-4 and F-5 remain honestly unexercised.** No fault-injection machinery
will be added for them.

## 9. U7 AND PHASE 3 CLOSURE CRITERIA

**U7 CLOSES WHEN ALL OF THESE HOLD** — and four of five already do:

1. ✅ The cleanup primitive and born-lapsed floor deployed; **B-23 GATE MET**.
2. ✅ The worker deployed, its authorisation boundary measured in production.
3. ✅ Destructive behaviour verified locally against the full retention matrix — **75/75**.
4. ✅ **The authority path verified in production against genuine Apple**, including a correct refusal.
5. ⬜ **A scheduler running unattended and verified in production (U7e).**

**PHASE 3 CLOSES CARRYING EXACTLY ONE NEW OBLIGATION: G7** — the supervised
production destructive run on a naturally matured quarantine, owner U7, earliest
`2026-11-01 15:16:44+00`. **This is the existing G7 row, not a new gate.**

Phase 3 would then close carrying **G7**, plus the pre-existing **C-31**
(Production Billing Grace) and **B-34** (telemetry blindness), and Gate 6 part 3
on B-11. **No obligation is ownerless, which is the rule that matters.**

---

## 10. ONE DOCUMENTATION DEFECT FOUND, NOT SILENTLY FIXED

**`docs/qa-plan.md` G7 says "allowlisted".** That word refers to the D4
per-identity allowlist **rejected on 2026-08-20**, four days after G7 was written.
G7 therefore describes its own precondition in terms of a mechanism that will
never exist, and a future reader could conclude G7 is blocked on building one.

**It is not corrected here**, because correcting it is a documentation change and
this is a preflight. **Flagged for your decision** — the correction is one clause:
G7 needs no allowlist, because Device A's identity is `sandbox_only`, is already
denied by enforcement, and its cleanup is authorised by the ordinary path that
refused on 2026-09-03.

---

## 11. NOTHING WAS BUILT

No workflow file, no secret, no schedule, no worker change, no `pg_cron`.
U6 untouched, C-58 not started, no cleanup fixture manufactured.

---

## 12. LOCAL IMPLEMENTATION RESULT — 2026-09-03

**Implemented locally. Not deployed, not activated, no production secret created.**

| Suite | Result |
|---|---|
| **u7 `auth-probe.sh`** | **16 / 0** — the full matrix in §8a |
| **u7 `e2e-worker.sh`** | **75 / 0** — unchanged under the new credential |
| u7 `acceptance-primitive.sh` / `acceptance-bornlapsed.sh` | 47 / 0 · 20 / 0 |
| u3 · u6a · u6b · u5 client-structural | 91 / 0 · 3 / 0 · 64 / 0 · 60 / 0 |
| u4 full (modules · acceptance · e2e) | 73 / 0 · 99 / 0 · 43 / 0 — **ALL GREEN** |
| u5 full | **ALL GREEN** |
| Workflow YAML | parses; one daily schedule `17 3 * * *`; concurrency group; `contents: read` |
| `pg_cron` | **0** — U4 `A57f` unchanged |

**19 of 19 local predictions (L-1 … L-19) matched. Nothing was repaired forward.**

### The three activation steps, each requiring human authorisation

| # | Act | Effect | Reversal |
|---|---|---|---|
| **A1.1** | Set the Supabase secret **`CLEANUP_INVOKE_KEY`** to a freshly generated value | Nothing yet — the deployed worker does not read it | Overwrite or delete the secret |
| **A1.2** | **Redeploy** `membership_cleanup_v1` | The worker accepts the new key and **stops accepting the service role key** | Redeploy the previous version |
| **A1.3** | Verify the production authorisation boundary | — | — |
| **A2** | Set repository variable **`CLEANUP_FN_URL`**, add repository secret **`CLEANUP_INVOKE_KEY`**, and put the workflow on the **default branch** | The daily schedule begins, in **`dry_run`** — deletion structurally impossible | Disable the workflow, or delete the secret |
| **A3** | Set repository variable **`CLEANUP_MODE = execute`** | Unattended execute becomes live | Unset the variable — back to `dry_run`, no commit or redeploy |

**ORDER CORRECTED 2026-09-03, BECAUSE THIS SECTION CONTRADICTED ITSELF.** The
table said *"set the secret … then redeploy"* while the paragraph beneath it said
*"between the redeploy and the secret being set, the worker refuses every
caller"* — describing the **opposite** order, and describing a window that must
not be created at all.

**THE SECRET IS SET FIRST, AND THE REDEPLOY SECOND.** In that order there is no
window in which a redeployed worker expects a key that does not exist. The
reverse order would produce a live endpoint refusing **every** caller until the
secret landed — fail-closed, so not dangerous, but a self-inflicted outage on the
destructive path and exactly the kind of avoidable state a sequencing note exists
to prevent.

**A1 MUST COMPLETE BEFORE A2.** GitHub must never hold a credential the worker
does not yet accept.

**GITHUB RUNS SCHEDULED WORKFLOWS ONLY FROM THE DEFAULT BRANCH.** The file is on
`feature/solo-connected`, so **the cron cannot fire at all until it is merged**.
That is a real third gate, and it is also the trap: anyone waiting for a schedule
that is not on `main` will wait forever with no error to read.

### Operational risk, recorded rather than engineered around

**GitHub disables scheduled workflows after 60 days of repository inactivity** —
the same order as the quarantine, with an invisible symptom: content that should
have been cleaned up quietly persists, and nothing breaks. **Accepted for launch
on the ratified decision not to build a second scheduler platform to eliminate
it.** The mitigation is that the job **fails loudly** on any non-200 and writes a
run summary, so its liveness is observable to anyone who looks — and the honest
statement is that **someone must look.**

---

## 13. A1 EXECUTED — 2026-09-03. THE WORKER NOW ACCEPTS ONLY THE INVOCATION KEY

**A1.1 → A1.2 → A1.3, in that order, so no window existed in which a redeployed
worker expected an unset key.**

### A1.1 — the secret

A **256-bit random hex** value (`openssl rand -hex 32`) was generated, written to
`~/.etudes-secrets/cleanup_invoke_key` (**dir 700, file 600**, outside the
repository, the same location and posture as the Apple `.p8`), and set as the
Supabase Edge Function secret `CLEANUP_INVOKE_KEY`. **The value was never
printed, never echoed, never placed on a command line and is not in the
repository.** It reached Supabase through a mode-600 env file that was deleted
immediately afterwards.

**It is stored locally deliberately: A2 needs the same value as a GitHub
repository secret**, and a key nobody can retrieve would have to be rotated at
A2 rather than reused.

### A1.2 — the redeploy

`supabase functions deploy membership_cleanup_v1` — **only that function was
deployed.**

**EVERY FUNCTION'S VERSION NUMBER MOVED, AND ONLY ONE FUNCTION'S CONTENT DID.**
This is the phenomenon **U5 recorded and causally attributed**: `secrets set`
bumps every function's version with **every SHA unchanged**, while
`functions deploy` touches only the named one. Verified here on `updated_at`
rather than taken on trust:

| Function | v | Content last updated |
|---|---|---|
| `membership_cleanup_v1` | **3** | **2026-09-03 11:17:45Z** ← today |
| `appstore_reconcile_v1` | 4 | 2026-08-23 21:09:43Z |
| `membership_attest_v1` | 2 | 2026-08-23 21:09:43Z |
| `appstore_notifications_v1` | 3 | 2026-08-20 12:23:49Z |
| `revoke_apple_identity_v1` | 4 | 2026-08-13 17:47:41Z |
| `delete_account_v1` | 10 | 2026-08-13 12:06:37Z |

**Five functions kept their original deploy dates**, so nothing but the cleanup
worker changed. `ezbr_sha256` prefixes are recorded in the commit for future
comparison. All six remain `ACTIVE` with `verify_jwt=false`.

### A1.3 — production authorisation boundary

| | Presented | Result |
|---|---|---|
| **P-AUTH-1** | no credential | **401** |
| **P-AUTH-2** | empty bearer | **401** |
| **P-AUTH-3** | wrong credential | **401** |
| **P-AUTH-4** | cleanup key **+1 char** | **401** |
| **P-AUTH-5** | cleanup key **−1 char** | **401** |
| **P-AUTH-6** | **the SERVICE ROLE key** — returned **200** before A1 | **401** |
| **P-AUTH-7** | the project **anon key**, a genuinely valid project JWT | **401** |
| **P-AUTH-8** | a user-shaped JWT | **401** |
| **P-AUTH-9** | `GET` with the correct key | **405** |
| **P-AUTH-10** | **the correct cleanup key** | **200**, `identities: 0`, `claimed: false`, `deleted: false` |

**P-AUTH-6 is the property A1 exists to create**, and it is now true in
production.

**One honest limit on P-AUTH-8.** Minting a *genuinely signed* production
end-user JWT would require a real user credential, which I neither have nor
should use. What was sent is user-shaped but not signed by the production secret.
**The genuinely-signed case is covered locally** — `auth-probe.sh` AUTH-9 signs a
real token with the local GoTrue secret against **identical code** and gets 401 —
and **P-AUTH-7 covers the stronger production half**: a token with a *valid*
project signature is refused. Together the property holds; neither alone would
carry it.

### Nothing was mutated

State captured immediately before and after A1.3 is **identical in every field**:
`auth.users` 17, posts 101, comments 5, follows 9, attachment objects 15,
`pending_cleanup_at` `2026-11-01 15:16:44+00`, `cleanup_completed_at` **NULL**,
`cleanup_claimed_at` and `renewal_info_signed_date` still carrying yesterday's
P5 values, conflicts 0, enforcement **true**, `pg_cron` **0**.

**`identities: 0` is the correct dry-run answer** — Device A's schedule returned
to Apple's own derived value during yesterday's refusal, so nothing is due.

---

## 14. A2 PREFLIGHT — THE BRANCH QUESTION, AND WHY A2 SHRANK

### The repository's actual state

| | |
|---|---|
| Default branch | **`main`**, at `1f0e090` — *"1.0-build-128 for TestFlight"* |
| Working branch | `feature/solo-connected` |
| Divergence | **`main` is 0 commits ahead; the feature branch is 311 commits ahead** |
| Difference | **239 files, +60,814 / −1,282** |

**`main` predates all of Phase 1, 2 and 3.** The entire membership architecture —
every migration, both audits, all six Edge Functions' source, the whole test
suite — exists only on the working branch.

**MERGING `feature/solo-connected` INTO `main` WOULD BE A RELEASE-SHAPED EVENT OF
311 COMMITS, AND IT MUST NOT HAPPEN BECAUSE A CRON NEEDS A FILE.** That merge may
well be intended eventually; it is an independent decision about releasing the
product, and coupling it to scheduler activation would be exactly the ad-hoc
release strategy to avoid.

### The workflow needs nothing from the repository

Measured, not assumed: the file contains **zero** references to repo code — no
`actions/checkout`, no build step, no script path, no dependency. It makes one
HTTPS call to an endpoint that is already deployed. **It therefore applies
cleanly to `main` on its own and behaves identically there.**

### THE "FINDING THAT MAKES A2 SMALLER" WAS WRONG — CORRECTED 2026-09-03

**This section previously claimed:**

> *"`workflow_dispatch` runs from ANY branch containing the workflow file. Only
> the `schedule` trigger is restricted to the default branch. So the entire
> workflow path can be verified by manual dispatch on `feature/solo-connected`,
> with nothing on `main` at all."*

**THE FIRST SENTENCE IS HALF TRUE AND THE CONCLUSION DRAWN FROM IT IS FALSE.**
GitHub registers the `workflow_dispatch` **event** only from a workflow file
present on the **default branch**. Until the file is on `main` the workflow is not
dispatchable at all — it does not appear in the Actions UI and the API's
`POST /actions/workflows/{id}/dispatches` has nothing to address. **Once it IS on
the default branch, dispatch may then select any branch**, which is the true half
that the false conclusion was built on.

**Verified against this repository:** `origin/main` contains **0** workflow files,
so no dispatch of `membership-cleanup.yml` is currently possible from any branch.

**CONSEQUENCE: A2.1 AND A2.2 INVERT.** The one-file PR to `main` is not the last
step of A2 that a green dispatch unlocks — it is the **first**, and it is the
precondition for any dispatch at all. **The "verify everything before touching
`main`" sequence is not available**, and no amount of care in ordering the other
steps recovers it.

**What does NOT change:** the merge is still **one self-contained CI file** from a
branch cut off `main`, never the 311-commit working branch; the schedule still
resolves to **`dry_run`** while `CLEANUP_MODE` is unset, so the file being on
`main` cannot delete anything; and both kill switches remain.

### Proposed A2, in two parts

| Step | Action | Touches `main`? |
|---|---|---|
| **A2.1** | Push the branch (4 commits, see below). Add repository **secret** `CLEANUP_INVOKE_KEY` (the value in `~/.etudes-secrets/cleanup_invoke_key`) and repository **variable** `CLEANUP_FN_URL`. Then **manually dispatch** the workflow on `feature/solo-connected` and confirm: HTTP **200**, mode resolves to **`dry_run`**, `identities: 0`, UUIDs redacted in the log, and **no lease, no completion, no count change** | **No** |
| **A2.2** | Only once A2.1 is green: put **only** `.github/workflows/membership-cleanup.yml` on `main` via a **one-file PR branched from `main`** — not a merge of the working branch. The daily schedule then begins, in `dry_run` | **One file** |

**A2.2 is the smallest correct action**: one self-contained CI file, one PR, no
product code, no coupling to a release decision. If the working branch is later
merged to `main` for its own reasons, the file is already there and the merge is
a no-op for it.

**One consequence to accept knowingly:** between A2.2 and any future release
merge, `main` carries a workflow whose worker source lives on another branch. The
file's own header explains what it invokes and that the worker is deployed to
Supabase, so it is self-describing rather than mysterious — but it is a real
oddity and it is better named than discovered.

### Four commits are unpushed, and I cannot push them

`4383144`, `e30b189`, `90fb6b6`, `1e9db64`. **`git push` fails from this shell** —
`could not read Username for 'https://github.com': Device not configured` — which
is an environment limitation rather than a credential problem, and `fetch` works
normally. **A2.1 requires these to be on the remote**, so pushing them is the
account holder's step.

---

## 15. STOPPED AFTER A1

**A2 and A3 not performed.** No GitHub secret, no repository variable, no
dispatch, nothing on `main`, `CLEANUP_MODE` unset, `pg_cron` 0.

---

## 16. A2 COMPLETE — THE SCHEDULER IS LIVE IN `dry_run`. 2026-09-03

### Configuration and the one-file default-branch change

Repository **secret** `CLEANUP_INVOKE_KEY` and **variable** `CLEANUP_FN_URL`
created; **`CLEANUP_MODE` left unset**. Configuration deliberately preceded the
workflow reaching `main`, so no window existed in which a live scheduled workflow
lacked its credential.

PR **#1**, `chore/cleanup-scheduler` -> `main`, merged at **`6e600c9`**. Verified
independently of the PR: the **entire** diff from the previous `main` is
`A .github/workflows/membership-cleanup.yml`, and the blob is **byte-identical**
(`6b3f9ec`) to the reviewed and locally-tested file. **No Phase 3 history reached
`main`.**

**Verified in the blob ON `main`**, not in a working copy: triggers `schedule` +
`workflow_dispatch`; cron `17 3 * * *`; **dispatch inputs null** with **zero
`inputs.` references**, so there is no second route to execute; unset
`CLEANUP_MODE` resolves to `dry_run`; `execute` is an explicit opt-in case; UUID
redaction present; non-200 fails the run; `permissions: contents: read`.

### GitHub run #1 — manual dispatch

Success. Trigger `workflow_dispatch`, resolved mode **`dry_run`**, response
`ok:true, mode:dry_run, claimed:false, deleted:false, identities:0, results:[]`,
**no production UUID in the output**.

### Independent production verification — SCORED ON THE DATABASE

**Every field byte-identical to the baseline captured before the dispatch:**
users/posts/comments/follows **17 / 101 / 5 / 9**; storage **15 / 3**;
`connected_attachments` **31**; directory **17**; `pending_cleanup_at`
**`2026-11-01 15:16:44+00`**; `cleanup_completed_at` **NULL**;
`cleanup_claimed_at` `2026-09-03 08:14:36` — **no new lease**;
`membership.updated_at` `08:14:37`; `renewal_info_signed_date` `08:14:36.792`;
conflicts **0**; enforcement **true + active**; `pg_cron` **0**.

**Two of those are load-bearing and are not count checks.**
`renewal_info_signed_date` unchanged proves **no Apple call was made** — any live
read moves it. `membership.updated_at` unchanged proves **no write occurred**.
Together they establish the dry run's non-mutating claim **from the database
side**, independently of what the worker or the workflow reported.

**A2-c PASSES. A2 CLOSES.** The daily schedule is live at 03:17 UTC and resolves
to `dry_run`; it can delete nothing while `CLEANUP_MODE` is unset. `pg_cron`
remains **0** — the scheduler is outside the database, so U4's `A57f` is
unaffected.

### A LOCAL GIT INCIDENT DURING THIS STEP, RECORDED BECAUSE THE LESSON IS REUSABLE

The account holder's own push/PR left this working copy checked out on
`chore/cleanup-scheduler`. I did not re-check the branch before committing, and
`git add -A` on a branch carrying **`main`'s** `.gitignore` swept up 249 paths
that the feature branch correctly ignores — Xcode `build/` output, `xcuserdata`,
Supabase CLI cache, regenerated test `.work/` scratch, and **`supabase/.env`,
which contains `SERVICE_ROLE_KEY`**.

**Nothing was pushed and nothing left the machine** — the commit was unreachable
from every remote ref, confirmed against live `ls-remote` output before any
recovery action. It was discarded by moving the branch pointer back to
`origin/chore/cleanup-scheduler`, which deletes nothing from disk.

**Three lessons, and the middle one generalises furthest:**

1. **`git add -A` is unsafe on any branch whose `.gitignore` differs from the one
   the working tree was built under.** The same tree is "clean" on one branch and
   full of committable junk on another.
2. **A verification loop that cannot fail is worse than none.** My first check
   used `git rev-parse "<ref>:<path>"` to test file existence and reported every
   file as present — because `rev-parse` **echoes unmatched input** instead of
   failing, so the `|| echo ABSENT` fallback never fired. It produced a confident,
   uniform, entirely wrong answer, caught only because a second count disagreed.
   **`git cat-file -e` is the correct existence test**, and two methods
   disagreeing is a result, not noise.
3. **Re-read the branch immediately before committing**, not merely after
   switching.
