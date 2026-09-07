# P5-F / CP-3 — UI COMPLETION. LOCALLY VERIFIED. CP-3 REMAINS OPEN. 2026-09-07

**CP-3 IS NOT RESOLVED.** Device/Sandbox acceptance, where the entitlement and
Apple's API are genuinely exercised, has not run.

---

## 1. THE FOLLOW-REQUEST QUESTION, ANSWERED BEFORE BUILDING ANYTHING

**User-configurable follow-request opt-in was NEVER settled as a product
requirement, so no control was built.**

The settled text is discovery only — *"Under-18 **directory discoverability**
default OFF, independently opt-in"*
(`childrens-privacy-workstream-scope.md:149`). `follow_requests_enabled` entered
the design in two places, **both server-side safety**: the protective downgrade
set (r3 §7.3′) and CP-2-R1's fail-closed fix. **Neither is a user control.**

### But a consequence needs YOUR decision, and it is live

The deployed writer derives **both** initial defaults from the band:

```
values (…, (p_age_band='band_18_plus'),  …, (p_age_band='band_18_plus'), …)
         └ lookup_enabled                    └ follow_requests_enabled
```

**So a 13–17 member has follow requests CLOSED, permanently, with no opt-in** —
because I am not inventing the control. **That symmetry was my design choice in
r3, not a settled requirement**, and it deserves an explicit decision:

| option | effect |
|---|---|
| **(a) accept** | teens are not requestable by strangers at all. Coherent, and mitigated: they are undiscoverable by default, so a stranger cannot find them to ask anyway. A teen can still *initiate* follows |
| **(b) opt-in** | give teens the same independent control as discovery — **needs a settled product requirement first** |
| **(c) decouple** | default teens' follow-requests to `true` and protect discovery only |

**Not decided here.** (a) is the current deployed behaviour by default.

## 2. THE DISCOVERABILITY CONTROL

Added to Profile → Settings, beside *Default to Private Posts*:

- **written through `account_privacy_set_lookup_v1`** — the only client writer;
- **hydrated from the server's EFFECTIVE value**, so the child-safety override is
  never recomputed client-side, where drift would fail permissive;
- **shown only when the server holds a band.** Without one the member is
  undiscoverable anyway and the writer would refuse — offering a control that
  cannot work is worse than offering none;
- **failure returns the control to the server's last known state**, so the UI
  never claims a preference the server did not accept;
- **unknown hydrates to OFF**, the protective direction.

**Copy is neutral and states both positions and what does not change either
way:** *"When this is on, other members can find you by searching your name,
Account ID or instrument. When it is off, they cannot search for you. Either way,
people you already share with still see your name on anything you have shared."*
No recommendation, no nudge.

## 3. ACCEPTANCE — TEEN OFF → EXPLICIT ON → REPUBLISH STAYS ON

Run against **production**, impersonating an identity, inside a transaction that
**raises and rolls back**:

| assertion | result |
|---|---|
| teen initial `lookup_enabled` | **false** ✅ |
| teen initial `lookup_changed_at` is NULL *(initial default, not a choice)* | **true** ✅ |
| teen initial effective discoverability | **false** ✅ |
| after explicit opt-in — stored | **true** ✅ |
| after explicit opt-in — **effective** | **true** ✅ |
| `lookup_changed_at` now set *(now a choice)* | **true** ✅ |
| **after an ordinary profile republish — stored** | **true** ✅ |
| **after an ordinary profile republish — effective** | **true** ✅ |
| adult initial `lookup_enabled` | **true** ✅ |
| adult initial effective | **true** ✅ |

**10/10.** The republish sent exactly what the CP-3 client now sends — display
name and location, **no privacy columns** — and the preference survived it.

**Nothing persisted:** `account_privacy` 0 rows, directory 2, `auth.users` 2,
enforcement true, `shadow_enforcement_stat` 75. **No Samuel/Steve privacy state.**

## 4. THE SHARE ASSERTION, MADE EXPLICIT

`testShareDefaultMatrixIsExplicit` states all three cases as one table:

| band | `defaultPrivacy` | Share default |
|---|---|---|
| `band_13_17` | either | **OFF** |
| unresolved / error / not fetched | either | **OFF** |
| `band_18_plus` | false | **ON** |
| `band_18_plus` | true | **OFF** |

**And `testAdultProductIsNotConvertedToPrivateByDefault` guards the regression
this unit must not cause**: it asserts the adult outcome equals the pre-CP-3
expression `!defaultPrivacy` for both inputs. **The `@State = false` initialisers
are transient only**; if they ever became the adult outcome, Études would have
been quietly converted to private-by-default, and D-1 explicitly settled the
opposite.

## 5. LOCAL VERIFICATION

**Debug and Release build clean. `MOTIVOTests`: 59 passed, 0 failed**, including
**11 CP-3 tests**.

**One observation worth recording, and it is NOT a CP-3 regression.**
`PublishServiceConnectedDeleteTests.testFailedUnshareLeavesRowPrivateNotPublic_C61Fixed`
was **skipped** in the full run while passing both before and when run in
isolation. Cause: the whole class calls `skipUnlessLocalStack()`, which
`XCTSkip`s when the local Supabase stack is unreachable. **So the suite's total
is not a stable measure** — it moves between 58, 59 and 60 with local-stack
reachability, and a future reader comparing raw totals could chase a phantom
regression.

## 6. WHAT REMAINS BEFORE CP-3 CAN CLOSE

- **Device/Sandbox acceptance**, including the real entitlement and the
  `DeclaredAgeRange` API. **Simulator builds do not validate the entitlement
  against a provisioning profile**, so this is where it is genuinely exercised.
- **The §1 follow-request decision.**

**CP-3 REMAINS OPEN.**
