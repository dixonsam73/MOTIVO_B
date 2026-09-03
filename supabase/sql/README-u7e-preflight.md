# U7e — SCHEDULER SCOPE AND PREFLIGHT. NOTHING BUILT, NOTHING ACTIVATED. 2026-09-03

**No scheduler exists. `pg_cron` is 0 in production. No workflow file has been
created. Nothing in this document has been implemented.**

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

**Recommendation: a dedicated `CLEANUP_INVOKE_KEY` secret, accepted by the worker
alongside the service-role key**, so the scheduler's store holds a credential
whose entire capability is *"ask the cleanup worker to run"*.

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

**Cost, stated plainly:** this changes the deployed worker's authorisation path
and requires a redeploy plus a re-run of the auth probe. **The alternative — put
the service-role key in the scheduler and change no code — is available and
acceptable**, and it is the right choice if you would rather not touch that path
again. **The trade is blast radius versus not editing an audited security
boundary.** I recommend the narrower key; the decision is yours.

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
U7e-1   activate the schedule in mode "dry_run"     -> destruction IMPOSSIBLE
        proves: the cron fires, the credential works, the worker is reachable,
                the output is what a scheduled run looks like
   ⛔   separately authorised
U7e-2   flip the workflow body to mode "execute"    -> unattended destruction live
```

**A dry-run schedule cannot delete anything** — the worker's `dry_run` path makes
no Apple call, takes no lease and writes nothing, proven in production on
2026-09-02. So U7e-1 tests **the entire scheduler** — timing, credential,
reachability, logging — with the destructive capability structurally absent.

**A further consequence worth deciding deliberately:** if `execute` is live before
2026-11-01, **the first-ever production deletion happens unattended, with nobody
watching.** That is a poor first run for the most irreversible path in the system.
**Recommendation: keep the schedule on `dry_run` until G7 has been performed once
MANUALLY and scored**, then flip to `execute`. G7 then remains a supervised run
and the scheduler inherits a path already proven in production.

---

## 8. PREDICTION-FIRST ACCEPTANCE

### Verifiable immediately (U7e-1, dry-run schedule)

| ID | Prediction |
|---|---|
| **S-1** | The workflow fires within its scheduled window; the run log records a **200** |
| **S-2** | A scheduled `dry_run` returns `identities: 0` while nothing is due — **the correct no-op** |
| **S-3** | **Zero** `cleanup_claimed_at` set, **zero** `cleanup_completed_at`, and every global count unchanged across a week of scheduled runs |
| **S-4** | With the secret removed, the run gets **401** and **fails loudly** |
| **S-5** | With the workflow disabled, **no invocation occurs** |
| **S-6** | `pg_cron` remains **0** — the scheduler is outside the database, asserted, so U4's `A57f` **still passes unchanged** |
| **S-7** | If the narrower credential is adopted: correct invoke key → 200; wrong → 401; **absent from the environment → fails closed**, never a trivial match |
| **S-8** | Device A's schedule remains `2026-11-01 15:16:44+00` throughout, untouched by any scheduled dry run |

### Must wait for the first naturally due identity — G7, earliest 2026-11-01

| ID | Prediction |
|---|---|
| **S-9** | An `execute` run on a genuinely matured quarantine performs the cleanup and matches a prediction **committed before it** |
| **S-10** | The retention half holds in production — retained comment, directory row, `display_name`, `auth.users`, `membership`, `membership_binding` |
| **S-11** | `cleanup_completed_at` set, `pending_cleanup_at` NULL, lease cleared, no orphaned object |
| **S-12** | Third-party blast radius zero |

**S-9 to S-12 are G7. They are deferred, owned and dated — not blockers.**

**Unchanged and still honestly unexercised:** F-2, F-4, F-5 (storage-failure
paths). The 2026-09-03 refusal supplied no evidence for them, because no removal
was attempted. **No fault-injection machinery will be added for them.**

---

## 9. U7 AND PHASE 3 CLOSURE CRITERIA

**U7 CLOSES WHEN ALL OF THESE HOLD** — and four of five already do:

1. ✅ The cleanup primitive and born-lapsed floor deployed; **B-23 GATE MET**.
2. ✅ The worker deployed, its authorisation boundary measured in production.
3. ✅ Destructive behaviour verified locally against the full retention matrix — **75/75**.
4. ✅ **The authority path verified in production against genuine Apple**, including a correct refusal.
5. ⬜ **A scheduler running unattended, verified in `dry_run` (U7e-1).**

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
