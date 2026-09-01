# GATE 6 — ENFORCEMENT-PATH QA WITH A SANDBOX IDENTITY. DESIGN ONLY, 2026-09-01

**NOTHING IS IMPLEMENTED OR DEPLOYED.** No schema, no flag, no row, no policy.
U6b has not begun.

## 0. THE PROBLEM, STATED PRECISELY

After U6b binds, `connected_member()` gates the API. **Device A holds a Sandbox
subscription, so it reads `sandbox_only` and is denied server-side — while its
client still shows the full Connected UI**, because `AppMode` resolves from local
StoreKit and never consults the server. Every API call refused behind a working
UI. That is the project's only device QA route, and binding breaks it.

**D4 is not up for revision.** Production `connected_member()` means Production
entitlement only; a Sandbox row must never make it return true; **and there is no
exception mechanism inside the predicate.** D4 already rejected a
`membership_sandbox_tester` allowlist — bounded and self-expiring — because *an
authority predicate must not contain a branch whose safety rests on operational
discipline.* Every option below is measured against that, not around it.

## 1. THE REFRAME THAT MAKES THIS TRACTABLE

**Gate 6 is not "make Sandbox count as entitlement". It is "test the GRANT
path".** Enforcement has two directions and they are not equally hard:

| Direction | Failure mode | Testable in production **today**? |
|---|---|---|
| **DENY** — unentitled identity refused | fails open: non-payers get in. Revenue/security | **YES, with the fixtures we already have.** Device A reads `sandbox_only`, Device B reads `unknown`; both are genuinely unentitled and both are real production identities |
| **GRANT** — entitled identity served | fails closed: **a paying member is locked out.** The catastrophic one | **NO.** It needs a `membership` row with `environment = 'Production'`, and no such row has ever existed |

**A GENUINE PRODUCTION ENTITLEMENT CANNOT BE OBTAINED BEFORE PUBLIC RELEASE.**
TestFlight builds always transact against Sandbox StoreKit; subscription offer
codes require a live App Store listing; an Xcode StoreKit configuration is
synthetic and never reaches our server. **So the grant path is not
production-testable pre-release by any means, with or without a mechanism** — and
any option claiming otherwise is really proposing to fabricate the state, not to
obtain it.

**AND THE ASYMMETRY RESOLVES IT: the grant path becomes testable exactly when it
becomes consequential.** Before release there are no paying customers, so a
grant-path defect harms nobody and is verifiable locally against the real
policies. After release a real subscription exists, and it is verifiable in
production **with no mechanism at all.**

---

## 2. THE OPTIONS

### A — Entitling environment as configuration
`connected_member()` reads the entitling environment from `membership_control`
instead of the literal `'Production'`; QA sets it to `'Sandbox'`.

### B — A real Production subscription
Buy one and test with it.

### C — A scoped Production-environment row, honestly labelled
Insert a `membership` row with `environment = 'Production'` and a near-future
`renewal_date` for one known QA identity, carrying a **new
`binding_method = 'qa_fixture'`** so the provenance is *recorded as absent*
rather than invented. Self-expiring.

### D — Local reproduction covers the grant path
Drive every entitlement state — entitled, expired, grace, billing retry,
`sandbox_only`, `unknown` — against the **real policies** on the B-23 local
stack, over real HTTP with a real JWT, exactly as the existing acceptance suites
already do.

### E — A separate QA Supabase project
Replicate the stack and point a build at it.

### F — A policy-layer QA override table OR'd into the policies.

---

## 3. THE COMPARISON

| | **A** config env | **B** real sub | **C** labelled row | **D** local | **E** separate project | **F** override table |
|---|---|---|---|---|---|---|
| **Production safety** | **Poor.** One column governs who is entitled, project-wide | Perfect | Moderate: grants real entitlement to one identity, for hours | **Perfect — no production surface at all** | Neutral | **Worst.** Every policy gains a second way to say yes |
| **Bypass / oracle?** | **Yes — a global bypass.** Not an oracle | No | **No bypass, no oracle.** The predicate is untouched; only the data it reads changes | No | No | **Yes, a bypass in 23 policies** |
| **Can ship enabled?** | **Yes, and silently.** A wrong value entitles every Sandbox tester | n/a | **The capability ships; the effect does not.** Requires a row, and a release check asserts zero exist | **Cannot — nothing ships** | n/a | **Yes** |
| **Scoped to a known identity?** | **No — project-wide** | Yes | **Yes, one `user_id`** | Yes | Yes | Depends; typically no |
| **Enable / disable** | Update one row | Buy / cancel | Insert / delete a row, **and it self-expires on `renewal_date`** | Run the suite | Deploy a project | Update a table |
| **Evidence it produces** | Device A served on the real production path | **The real thing, end to end** | Device A served on the real production path | Every state × every policy, deterministic and re-runnable | Same as A, in a copy | Proves the override works, not the predicate |
| **Removal before release** | Must remove a **code branch** and redeploy | n/a | **Delete one row**; drop the enum value in the cleanup migration; release gate asserts zero | Nothing to remove | Delete the project | Must remove code from 23 policies |

### Why A and F are rejected outright

**A puts a branch inside the authority predicate whose safety rests on a
configuration value being right** — the exact shape D4 rejected, made worse by
being project-wide rather than per-identity. **F is the same defect moved one
layer out**, shipped into 23 policies, and it proves the override works rather
than that the predicate does.

### Why E is expensive and does not solve the problem

A separate project still computes `environment = 'Production'` against Sandbox
rows, so **it yields `sandbox_only` there too.** It would need A's change to help
— inheriting A's defect — and it costs a duplicated schema, duplicated Edge
Functions, duplicated Apple keys and a build repoint, while **App Store Connect
holds one Sandbox notification URL per app**, which the QA project would have to
take over from production. **High cost, and it does not answer the question.**

### Why B is right and unavailable

It is the only option with no mechanism and perfect fidelity. **It is simply not
obtainable before public release.** It is the post-release answer, not the
pre-release one.

---

## 4. RECOMMENDATION — the smallest mechanism is NO PRODUCTION MECHANISM

**Discharge Gate 6 with D plus the fixtures already in hand, and defer the grant
path to the first real subscriber.** Three parts:

1. **DENY path, in production, now.** Device A (`sandbox_only`) and Device B
   (`unknown`) are genuine production identities that are genuinely unentitled.
   After U6b binds, both must be refused on every observed surface. **This is the
   half that is testable today, and it is also the half the shadow window has
   already predicted in detail** — 7 observations, `would_deny = true`, zero
   exceptions.
2. **GRANT path, locally, against the real policies.** Extend the acceptance
   suite with Production-environment fixtures across entitled, expired, grace and
   billing-retry, asserting the policies serve and refuse correctly. The suites
   already build membership fixtures; this is more of what they do, not a new
   capability.
3. **GRANT path, in production, at first real subscription.** A named release
   step: the first genuine Production subscriber is verified end to end before
   any second one exists.

**This weakens nothing.** `connected_member()` is not touched, no exception exists
anywhere, nothing new is client-reachable, and there is no artefact to remove
before release **because none is created.**

### The residual, stated rather than glossed

**B-23 fidelity: the local stack is the same software, not the same
deployment.** That residual is real and it is the same one this project already
accepts for every backend claim U2 discharged — recorded as *verified against a
faithful local reproduction*, never as *verified in production*. The gate is GREEN
with one declared serialization exception, and the grant path is pure SQL
predicate logic, which is the kind of thing a reproduction reproduces well.

### If a production grant observation is judged necessary anyway

**Use C, and only C.** It is the sole option that leaves the predicate untouched.
Conditions it must carry:

- **`binding_method = 'qa_fixture'`** — a new value that *records provenance as
  absent*. This is the opposite of the U4 defect corrected on 2026-08-20, where a
  value was **inferred** and so invented provenance; here the value's whole
  meaning is "a human made this up for testing."
- **`renewal_date` at most a few hours out**, so it self-extinguishes without
  anyone remembering to remove it.
- **A release gate asserting `count(*) where binding_method = 'qa_fixture'` is
  zero**, and the cleanup migration drops the value from the CHECK constraint so
  the capability itself cannot survive to release.
- Inserted and deleted by the account holder in one guarded submission, like
  every other production mutation here.

**Its cost is honest and small: the capability ships even though the effect does
not.** That is strictly better than A or F, where the *branch* ships and only a
configuration value stands between it and a bypass.

---

## 5. ADJACENT, AND NOT PART OF GATE 6 — the U6b kill switch

**U6b will need a way to unbind quickly**, and that is a U6b design question, not
a Gate 6 one. Noted here only so it is not confused with the above: its failure
direction is **fail-open** (enforcement disabled → everyone served), which is the
safe direction for a rollback control and the unsafe one for an entitlement
exception. **Do not let it become the sandbox mechanism by the back door** — a
kill switch that can be scoped to an identity is an allowlist wearing a different
name, and D4 has already ruled on that.
