# U6b — BINDING ENFORCEMENT. IMPLEMENTATION AND ACCEPTANCE PLAN, 2026-09-01

**NOTHING IS IMPLEMENTED OR DEPLOYED. U6b HAS NOT BEGUN.** No schema, no policy,
no function, no flag, no production mutation. This is the plan and its committed
predictions-to-be.

**FIVE DECISIONS TAKEN 2026-09-01 ARE FOLDED IN BELOW.** (1) **Fail CLOSED** on
an error in the entitlement path; no fail-open fallback. (2) **D-U6-1 is IN
SCOPE** — lapsed members become undiscoverable in `search_account_directory`,
while `get_account_directory_by_user_ids` keeps resolving retained authors.
(3) **`shadow_enforcement_stat` keeps its name**, with the transition documented.
(4) **The Device A reinstall is WITHDRAWN — it was never necessary. See §5.1.**
(5) **Production deny-path tests run BEFORE the grandfather cleanup**, which
becomes a separate no-op-against-verified-state unit.

**Gate 6 is settled and this plan assumes its answer:** no production Sandbox
grant mechanism, no entitlement override, no allowlist, no Sandbox exception. The
`qa_fixture` row is **rejected**. See `README-gate6-enforcement-qa.md`.

---

## 1. THE BINDING MECHANISM — one function, and a flag that ships OFF

### 1.1 `shadow_observe(text)` is REPLACED by `enforcement_gate(text)`

```
public.enforcement_gate(p_surface text) returns boolean
  volatile security definer, granted to `authenticated` only
```

**ORDER MATTERS AND IT IS INVERTED FROM `shadow_observe`.** The decision is taken
**first and unwrapped**; telemetry is written **second and wrapped**.

1. **Decide, NOT wrapped.** Read `enforcement_active()`; if disabled return
   `true`, else return `connected_member_self()`. **An error here propagates and
   the request fails — FAIL CLOSED, decided 2026-09-01.** There is no fail-open
   entitlement fallback anywhere.
2. **Record, wrapped** in `exception when others then null`, using the
   already-computed decision. Telemetry that can fail a request is not telemetry —
   and now that the decision precedes it, **a failed write cannot change an
   outcome**, which the old ordering could not guarantee.

**The null-uid early return is DELETED from the decision path.** It is kept only
as "skip the telemetry write, there is nothing to attribute". An unauthenticated
caller now flows into `connected_member_self()` → `connected_member(null)` →
**false**, asserted by U3's A10. **Fail-closed by construction rather than by a
special case.**

**Fail-closed is a deliberate trade and the reasoning is recorded so it can be
re-argued on evidence rather than taste:** a wrongly-denied paying member
complains within minutes and the kill switch is one row; a wrongly-granted
non-member is silent, indefinite, and undetectable by users. **A silent grant on
error is exactly how B-11 came to exist.**

**The rename is not cosmetic and the cost is accepted.** A function called
`shadow_observe` that denies requests is precisely the C-25 defect — a name that
describes a caller's motive rather than what the thing does — and F6 was filed for
exactly that shape. Keeping the name would make the 23-policy migration
unnecessary and the B-23 policy delta zero, **and it would be a lie in the one
place this project has been burned by names repeatedly.** We take the migration.

### 1.2 THE ENTITLEMENT PREDICATE IS NOT TOUCHED

`connected_member(uuid)` answers *"is this identity entitled"* and never lies.
`enforcement_gate` answers *"should this request proceed right now"*. **The kill
switch lives in the enforcement layer, never in the entitlement layer.** D4's
rejection stands untouched: there is no exception, per-identity or otherwise,
inside the authority predicate.

### 1.3 THE KILL SWITCH, AND WHY IT CANNOT BECOME AN ALLOWLIST

```sql
alter table public.membership_control
  add column enforcement_enabled boolean not null default false;
```

**It ships OFF.** Deploying U6b therefore changes no request's outcome — the gate
returns `true` exactly as `shadow_observe` did, and telemetry continues. **Binding
is a separate one-row flip, exactly as the grandfather retirement separated
"stop granting" from "start denying".** That pattern is now proven twice.

**Four structural protections, asserted rather than promised:**

| # | Protection |
|---|---|
| **K1** | `enforcement_gate` takes **one `text` parameter and no `uuid`**. There is nothing to aim. Same reasoning as B-33's zero-argument wrapper |
| **K2** | `membership_control` is a **singleton** (`id boolean` primary key). There is no per-identity row to add — the shape of the table forbids it |
| **K3** | Acceptance asserts the gate's body references **only** `membership_control`, `shadow_enforcement_stat` and `connected_member_self()` — no other table, no other predicate |
| **K4** | Acceptance asserts `connected_member(uuid)` and `membership_state(uuid)` remain **ungranted to every client role**, so no uuid-addressable oracle exists |

**A kill switch that can be scoped to an identity is an allowlist wearing a
different name.** K1 and K2 make that structurally impossible rather than
discouraged.

---

## 2. HOW THE 23 POLICIES AND 9 RPCs CHANGE

### Policies — a textual substitution, nothing more

```
-  (select public.shadow_observe('posts.select'))
+  (select public.enforcement_gate('posts.select'))
```

**Every reference stays `(select …)`, never bare.** G4-S3's cliff — 278ms against
3.9ms at 5000 rows, both forms functionally correct so review cannot catch it — is
re-asserted in U6b's suite, per policy, exactly as U6a asserted it.

**The own-material rule is unchanged and still load-bearing.** A branch reducing
to `= auth.uid()` on an ownership column stays **open**; only branches reaching
another member's content are gated. So a lapsed member keeps reading their own
retained material (D-U6-4), keeps their own profile (D-U6-3), and **all six DELETE
policies stay untouched (D-U6-2) — withdrawal is never gated.** Q1 stands: in
`post_comments_select_visible` only the owner and recipient branches are gated and
the author branch stays open.

### RPCs — an explicit check, because SECURITY DEFINER bypasses RLS

```
-  perform public.enforcement_gate('rpc.add_post_comment');
+  if not public.enforcement_gate('rpc.add_post_comment') then
+    raise exception 'not permitted';
+  end if;
```

`post_comments` has no INSERT/UPDATE policy at all, so **every comment write is
invisible to policy work** — omitting the RPCs would enforce two-thirds of the
surface and report it as the whole.

**THE DIRECTORY ASYMMETRY IS THE DELICATE ONE AND K1 PROTECTS IT.**
`get_account_directory_by_user_ids` gates on the **viewer** and **must never gate
on the subject**, or retained-comment attribution breaks for every surviving
comment (G10). Because `enforcement_gate` takes no `uuid`, **it cannot gate on a
subject even by mistake** — the type system forecloses the defect.

---

## 3. ACCEPTANCE — DENY PATH, IN PRODUCTION

Both fixtures are genuine production identities and both are genuinely
unentitled. **This is the half that is testable today.**

| Fixture | State | Expected after binding |
|---|---|---|
| **Device A** | `sandbox_only` | denied on every gated surface |
| **Device B** | `unknown` | denied on every gated surface |

**Predicted observable shape, and it differs by verb — this must be predicted, not
discovered:** an RLS-denied `SELECT` returns **zero rows, not an error**; a denied
`INSERT`/`UPDATE` returns an **error**; a denied RPC raises `not permitted`. So:

| Action | Expected |
|---|---|
| Open the feed | **empty**, no crash |
| Open a known post directly | **not found** |
| Post a session | **refused** |
| Comment | **refused**, `not permitted` |
| Read another member's attachment | **refused** |
| **Own retained material** | **STILL READABLE** — D-U6-4 |
| **Own profile edit** | **STILL WORKS** — D-U6-3 |
| **Delete own account** | **STILL WORKS** — D-U6-2, and membership never gates deletion (C-35) |

**A UX consequence to expect rather than be surprised by:** the client resolves
`AppMode` from local StoreKit, so **Device A will present the full Connected UI
over an empty feed.** That is a client-side disagreement with the server, it is
narrow post-release, and it is **not** a U6b defect — but it must be recorded when
observed rather than treated as one.

## 4. THE STORAGE-WRITE DENIAL TEST — REQUIRED BY B-34

**The shadow window can never observe storage writes** — the predicate is
evaluated and its side effects are discarded. So this must be a **direct
observation, and the absence of telemetry proves nothing.**

- **Production:** Device A or B attempts to attach media to a post. The upload
  must be **refused** with `new row violates row-level security policy`.
- **Local:** the same HTTP upload against an unentitled fixture, plus the
  `WITH CHECK` control that proved RLS genuinely gates that path.

**Both halves are needed.** Local proves the predicate; production proves the
deployed storage-api path still routes through it.

## 4b. D-U6-1 — LAPSED MEMBERS BECOME UNDISCOVERABLE (decision 2, in scope)

**The two directory RPCs diverge, and the divergence is the entire point.**

| RPC | Gates on the VIEWER | Gates on the SUBJECT |
|---|---|---|
| `search_account_directory` | **yes** — `enforcement_gate` | **YES, new** — rows filtered to `connected_member(ad.user_id)` |
| `get_account_directory_by_user_ids` | **yes** — `enforcement_gate` | **NEVER** |

```sql
-- search only:
and (not public.enforcement_active() or public.connected_member(ad.user_id))
```

**The subject filter respects the kill switch too**, or flipping enforcement off
would not fully restore prior behaviour — a rollback that only half-rolls-back is
not a rollback.

**Calling `connected_member(uuid)` here creates no oracle.**
`search_account_directory` is `SECURITY DEFINER`, so the call runs as the owner
and needs no grant; `connected_member(uuid)` stays ungranted to every client role
(K4). The caller sees search results, never an arbitrary uuid probe. **The residual
disclosure — "search a name, and absence implies unentitled" — IS the product
behaviour being asked for**, bounded to names the searcher already knows and 20
rows, and it is disclosure by design rather than leakage.

**G10 IS PROTECTED BY A SOURCE-TEXT ASSERTION, AND IT MUST STRIP COMMENTS.**
Acceptance asserts `get_account_directory_by_user_ids`'s body contains **zero**
occurrences of `connected_member`. Gating it on the subject would break
attribution for every retained comment on every surviving post. **Comments are
stripped before matching** — U5c-34 and three U5d assertions were each defeated by
a well-commented file explaining the very rule being checked.

**Scale caveat, recorded rather than discovered later:** the subject filter is a
`STABLE` per-row function call evaluated before `limit 20`. Trivial at 17
identities; it is a filtered-set cost that will want an index or a materialised
entitlement column long before it is a real corpus.

## 5. THE G10 COLD-CACHE DIRECTORY TEST — DESIGNED, NOT INCIDENTAL

`get_account_directory_by_user_ids` is **cache-gated** at
`AccountDirectoryService.swift:258`, so ordinary use never reaches it. It must be
forced.

### 5.1 THE REINSTALL IS WITHDRAWN — IT WAS NEVER NECESSARY

**Corrected 2026-09-01, and only because the reinstall's cost was challenged
before it was authorised.** I proposed a Device A reinstall to force a cold
directory cache. **I had not read the cache.** It is
`private actor DirectoryAccountCache` holding a plain in-memory dictionary, and
the source says so in its own comment:

> *batch directory lookup cache (viewer-local, in-memory only). Note: This cache
> is intentionally ephemeral (clears on cold start).*

**A force-quit and relaunch clears it completely. Nothing is lost, because
nothing needed clearing beyond process memory.**

**What a reinstall WOULD have destroyed, stated because it was nearly spent for
nothing:** the entire app container — local journal, sessions, Scores and their
index, media, attachments, `AttachmentPrivacy.json`, `CommentsStore.json`, the
received-attachment cache and all settings. **CLAUDE.md records Device A's local
journal as "not surveyed — do not assume empty or populated"**, so the cost was
not merely large, it was *unknown*, which is worse. The Keychain items
(`supabaseAccessToken_v1`, `appleUserID`) survive app deletion on iOS while the
UserDefaults identity keys do not, so a reinstall would also have left a split
auth state nobody had designed for.

**The lesson is the cheap one: I proposed a destructive step from an assumption
about code I had not opened, and the question "state exactly what is lost"
is what caught it.**

| Half | Where | Assertion |
|---|---|---|
| **Unentitled viewer refused** | **Production**, Device A, **cold cache via force-quit + relaunch** | the RPC refuses |
| **Entitled viewer still resolves a LAPSED subject** | **Local**, Production fixtures | attribution survives — **gating on the subject would break every retained comment** |

**Never run `Erase All` on Device B**, and no reinstall is required on either.

## 6. THE LOCAL GRANT-PATH MATRIX — Production fixtures, real policies

Driven over real HTTP with a real JWT against the deployed policy definitions, as
the existing suites already do.

| # | Fixture state | `connected_member` | `membership_state` | Expect |
|---|---|---|---|---|
| 1 | Production, `renewal_date` future | true | `entitled` | **GRANT** |
| 2 | Production, cancelled, still paid-through | true | `entitled` | **GRANT** |
| 3 | Production, billing retry **+ grace unexpired** | true | `entitled` | **GRANT** |
| 4 | Production, billing retry, **grace expired** | false | `expired` | **DENY** |
| 5 | Production, expired | false | `expired` | **DENY** |
| 6 | Production, refunded / revoked | false | `expired` | **DENY** |
| 7 | **Sandbox row only** | false | `sandbox_only` | **DENY** |
| 8 | No row, not in cutover | false | `unknown` | **DENY** |
| 9 | No row, in cutover, grandfather off | false | `unknown` | **DENY** |

Each state × every policy family × the 9 RPCs, **plus the own-material,
own-profile and deletion carve-outs asserted OPEN in every row of the matrix.**
Row 3 is the one most likely to be got wrong: Apple's formula requires
`isInBillingRetryPeriod` **combined with** an unexpired grace period, and retry
alone does **not** entitle.

## 7. ROLLBACK

**One row.** `update public.membership_control set enforcement_enabled = false;`
The flag is read live inside the gate on every call, so there is no
partially-applied window and no cache.

**Roll back on any of:**
- any identity that **should** be entitled being denied — the fail-closed
  direction, and the only genuinely catastrophic one;
- any own-material, own-profile or account-deletion path being refused —
  D-U6-2/3/4 violated;
- errors on `SELECT` paths where empty results were predicted;
- any request failing for a reason the matrix did not predict;
- attribution breaking for retained comments — G10.

**Not a rollback condition:** unentitled fixtures being denied. That is the unit
working.

## 8. SHADOW TELEMETRY AFTER BINDING

**Recording continues, but `would_deny` changes meaning** — from *would have* to
*did*. Left alone, the pre- and post-binding rows become indistinguishable and
the whole shadow-window evidence base becomes uninterpretable.

**So `shadow_enforcement_stat` gains `enforced boolean not null default false`,
written from the control flag at decision time — AND IT GOES INTO THE PRIMARY
KEY.** The 56 observations already collected stay readable as what they are,
forever.

**`enforced` is in the key for the reason GF-5 proved:** `decided_clause` being in
the key is what preserved 11 `grandfathered` rows intact beside the new `unknown`
ones, so the before and after of that experiment sit in one table. The same
property is wanted here — **an hour that straddles the binding flip must produce
two rows, not one mutated row**, or the moment enforcement began becomes
unreconstructable.

**The table keeps its name, deliberately (decision 3).** Renaming would break
continuity with every committed reference to the shadow evidence. The name is
historical from the moment `enforced` is true, and it is documented as such here
rather than fixed by a rename that would cost more than it buys.

The bounded-aggregate shape is unchanged — one row per identity × surface × clause
× hour — so volume stays bounded under real traffic, which is what B-29 was filed
for.

## 9. CLEANUP OF THE DISABLED GRANDFATHER MECHANISM

**A separate migration, after binding is stable. Not folded into U6b.**

- drop the middle `coalesce` arm of `connected_member()`;
- drop `'grandfathered'` from `membership_state()` — five values become four;
- drop `public.membership_cutover`;
- drop `membership_control.grandfather_enabled` and `grandfather_expires_at`.

**KEEP `cutover_at`, `cutover_identity_count`, `cutover_verified_at` and
`u6b_bound_at`.** They are the historical record of a boundary this project's
documents refer to throughout, they are inert once the mechanism is gone, and
`cutover_at` is stated in CLAUDE.md as something that must never be altered.

## 10. RELEASE GATE — the first real Production subscription

**Explicit, named, and not dischargeable by anything above.**

> **Before a second paying subscriber exists**, the first genuine App Store
> subscription is verified end to end in production: a `membership` row with
> `environment = 'Production'` and `binding_method = 'purchase'`, `connected_member()`
> true, and the full Connected surface served on the real device.

This is the only evidence that closes the grant path in production, it is
unobtainable before release, and **it must not be quietly marked satisfied by the
local matrix.**

---

# 11. IMPLEMENTATION AND DEPLOYMENT SEQUENCE — four units, and only one denies

**Nothing below has been built. Each unit's numbers are MEASURED and COMMITTED as
predictions before it deploys** — no figure in this section is estimated.

| Unit | What | Denies anything? |
|---|---|---|
| **U6b-1** | The migration. Gate, flag, telemetry column, 23 policies, 9 RPCs, D-U6-1 | **NO — ships with `enforcement_enabled = false`** |
| **U6b-2** | The binding flip. One row | **YES** |
| **U6b-3** | Device QA, production + local | — |
| **U6b-4** | Grandfather cleanup | **NO — no-op against verified state** |

### U6b-1 contents

```
add   membership_control.enforcement_enabled   boolean not null default false
add   shadow_enforcement_stat.enforced         boolean not null default false  (INTO THE PK)
new   public.enforcement_active()              -- zero-arg, internal, no client grant
new   public.enforcement_gate(text)            -- granted to `authenticated` only
alter 23 policies    shadow_observe -> enforcement_gate, every reference `(select …)`
alter 9  RPCs        perform -> `if not … then raise exception 'not permitted'`
alter search_account_directory  + the D-U6-1 subject filter
drop  public.shadow_observe(text)
```

### Prediction-first gates, in order

| # | Step | Gate |
|---|---|---|
| **P0** | Build U6b-1 locally, `db reset`, run every suite | **All green.** U3 97 · U4 73/98/43 · U5 68/53/57/62 · U6a's successor. Any red stops the unit |
| **P1** | Capture the local post-U6b-1 structural delta against live production | **Committed as a prediction before deploy**, like U6a's 10-of-10 |
| **P2** | Re-generate the rollback baseline **from production**, verify it as a no-op | Not the local file. B-23 fidelity is measured, never assumed |
| **P3** | Apply U6b-1 — **one submission, guard inside, ending in a SELECT that returns a row** | Guard asserts 23 policies carry `enforcement_gate`, **zero bare calls**, `shadow_observe` gone, `enforcement_enabled` **false** |
| **P4** | `capture-schema.sh` + `verify-baseline.sh` | **GATE MET**, only `account_id_format` |
| **P5** | **Prove U6b-1 is inert**: exercise Device A and Device B | **Nothing changes.** This is the whole point of shipping the flag off |
| **P6** | Commit predictions for the flip | Before P7, never after |
| **P7** | **U6b-2 — the flip.** One row, guarded, returns a row | Guard asserts `u6b_bound_at` is set in the same transaction |
| **P8** | **U6b-3 device QA** — §11.1 order | Any unpredicted refusal → rollback |
| **P9** | Score, commit, refresh the snapshot | |
| **P10** | **U6b-4 cleanup**, separately, after P8 is accepted | |

## 11.1 DEVICE QA ORDER — deny path first, own-material carve-outs last

**Device A before Device B**, because Device A is the spent-fixture and Device B
is the control that must survive.

1. **Device A — force-quit and relaunch.** Cold directory cache. Expect the feed
   **empty, not erroring**, and `rpc.get_account_directory_by_user_ids`
   **refused** (G10 viewer half).
2. **Device A — open a known post directly.** Expect **not found**.
3. **Device A — attempt to publish a session with an attachment.** Expect the
   post **refused**, and — **the B-34 direct test** — the storage upload refused
   with `new row violates row-level security policy`. **The telemetry will show
   nothing for the storage surface, and that proves nothing either way.**
4. **Device A — attempt a comment.** Expect `not permitted`.
5. **Device A — THE CARVE-OUTS, which must all still WORK:** read own retained
   material (D-U6-4), edit own profile (D-U6-3), and confirm the account-deletion
   route is reachable (D-U6-2, C-35) — **reachable, do NOT run it.**
6. **Device B — repeat 1-5.** **Never `Erase All`, never delete the account.**
7. **Telemetry check:** new rows carry `enforced = true` and sit *beside* the
   historical `enforced = false` rows, not merged into them.

## 12. ROLLBACK — one row, and what triggers it

```sql
update public.membership_control set enforcement_enabled = false where id;
```

Read live inside the gate on every call: no partially-applied window, no cache.

**Roll back on:** any identity that should be entitled being denied; **any
carve-out failing** — own material, own profile, or account deletion; an error
where an empty result was predicted; any refusal the matrix did not predict;
attribution breaking for retained comments.

**Not a trigger:** unentitled fixtures being denied. That is the unit working.

## 13. A SCOPE GAP I AM NOT SILENTLY CLOSING

**"Undiscoverable" is not "invisible", and the product rule asks for the second.**

D-U6-1 removes a lapsed member from `search_account_directory`. But every gate in
this plan is **viewer-side**: `posts_select_public_or_owner` checks whether *the
reader* is entitled, never whether the *author* is. **So after U6b a lapsed
member's posts remain visible to entitled readers**, while CLAUDE.md's quarantine
rule says *"the Connected presence becomes invisible to other members
immediately."*

**That is a genuine gap between this plan and the settled product rule.** It is
not in the decisions taken, so I have not folded it in — but it must not be
discovered after binding. **It needs a decision: extend U6b to author-side
gating on `posts`/`post_shares`, or record it as a named follow-on unit.**

## 14. RELEASE GATE — unchanged and undischargeable

> **Before a second paying subscriber exists**, the first genuine App Store
> subscription is verified end to end in production: `environment = 'Production'`,
> `binding_method = 'purchase'`, `connected_member()` true, full Connected surface
> served on a real device.

**Nothing in §11 or §6 can mark this satisfied.**

---

# 15. IMPLEMENTATION RESULT AND THE PRODUCTION PLAN — 2026-09-01. NOT DEPLOYED

**Built and green locally. Nothing is deployed and `enforcement_enabled` has not
been flipped anywhere.**

## 15.1 The one measurement, run before implementing

**Claim tested:** a `SECURITY DEFINER` trigger function fires for an
`authenticated` caller **without** that role holding EXECUTE.

| | |
|---|---|
| SECURITY DEFINER trigger fn, granted to nobody | **FIRED** |
| **CONTROL** — invoker-rights twin, same grants | **`permission denied for function`** |

**The control is what makes it evidence.** B-33's first experiment failed because
a defensive clause destroyed the only thing being measured; here the probe was
shown capable of detecting a permission failure before its success was believed.
**`membership_entitled_until` stays granted to nobody. No extra grant was needed.**

## 15.2 Local result — all green on fresh resets

```
u3/acceptance      97      u5/acceptance      57      u6a/acceptance (superseded)  3
u4/acceptance      98      u5/e2e             62      u6b/acceptance              54
u4/e2e             43      u5/client-struct   53      inventory-complete    COMPLETE
```

**U4's and U5's TypeScript module suites were not re-run and are not claimed:**
U6b touches no Edge Function and no shared module, only SQL.

**Structural, verified in the built database:** 23 policies carry the gate,
**zero bare calls**, 4 policies carry the subject check, 9 RPCs gated,
`shadow_observe` gone, `membership_entitled_until` executable by no client role,
4 columns, 5 triggers, `enforced` in the primary key.

## 15.3 Blast radius — 3 assertions moved, and one suite was superseded

| | |
|---|---|
| **U3 `A15c`** | exception list widened **by name** from 1 to 6. No namespace, no pattern — any *other* function acquiring a membership dependency still fails it |
| **U3 `A16b`** | trigger count 5 → **10**, still an exact count |
| **U4 `A57c`** | trigger count 1 → **6**, still an exact count |
| **U6a's suite** | **superseded** — its subject, `shadow_observe`, no longer exists |

**The U6a suite was not edited until it passed, and it is not a stub that always
passes** — that is the "check that cannot fire" defect this repository names. Its
twelve assertions with unique value are **carried into U6b group K unchanged in
substance**, and what remains is an executable guard on the supersession that
**can fail**: it asserts `shadow_observe` is genuinely absent, that the successor
exists, and that all twelve carried assertions are present in it.

**A blanket rename also rewrote four HISTORICAL comments** describing U6a's
`shadow_observe` — which would have made the record read as though the function
were always called something else. **Restored.** Historical material may be marked
superseded; it must never be rewritten to look as though it was always right.

**The inventory gate caught a real gap:** both trigger functions inherited
`PUBLIC` EXECUTE by default. Postgres refuses a direct call to a trigger function
so it is hygiene rather than a hole, but a `SECURITY DEFINER` function reading
`membership` should not carry a default grant. **Both are now explicitly revoked**
and all five new functions are documented in `docs/u6-enforcement-inventory.md`.

## 15.4 PREDICTED PRODUCTION DELTA — measured against live production, not estimated

| Surface | Prod | After U6b-1 | Delta |
|---|---|---|---|
| `columns` | 130 | **136** | **+6** |
| `functions` | 24 | **28** | **+5 new, −1 dropped, 9 MODIFIED** |
| `function_grants` | 72 | **84** | **+15 new, −3 dropped** |
| `column_grants` | 523 | **554** | **+31** |
| `triggers` | 5 | **10** | **+5** |
| `policies` | 33 | **33** | **0 added, 23 MODIFIED** |
| `constraints` | 67 | **67** | **0 added, 1 MODIFIED** — the stat PK gains `enforced` |
| `rls_enabled` · `table_grants` · `storage_buckets` | | | **IDENTICAL** |

**B-23 will report GATE NOT MET with exactly 99 problems**, and the arithmetic
closes with every one a U6b object:

```
31 column_grants + 23 policies + 18 function_grants + 15 functions
 + 6 columns + 5 triggers + 1 constraints  =  99
```

## 15.5 PRODUCTION SEQUENCE — stop points are absolute

| # | Step | Denies? |
|---|---|---|
| **P0** | Re-run the live pre-flight; confirm `enforcement_enabled` absent and `u6b_bound_at` null | no |
| **P1** | **Regenerate the rollback baseline FROM PRODUCTION** and verify it as a no-op | no |
| **P2** | Apply U6b-1 — one submission, guard inside, ending in a `SELECT` that returns a row | **no — ships with the flag false** |
| **P3** | `capture-schema.sh` + `verify-baseline.sh` → **GATE MET** | no |
| **P4** | **Prove inertness on Device A and Device B.** Nothing changes | no |
| **P5** | Commit predictions for the flip | no |
| **P6** | **THE FLIP** — one row, guarded, `u6b_bound_at` set in the same transaction | **YES** |
| **P7** | Device QA per §11.1 | — |
| **P8** | Score, commit, refresh the snapshot | — |
| **P9** | U6b-4 grandfather cleanup, separately | no |

**P2 and P6 are separate deployments and must not be combined.** Everything
between them is the evidence that P6 is safe to take.

**Expected at P4, and it is the whole point of shipping the flag off:** both
devices behave exactly as they do today.

**Expected at P7:** every gated surface refused; every carve-out — own material,
own profile, account deletion reachable — still working; **and the entire
Connected corpus invisible, because backfill resolves every `entitled_until` to
NULL when no Production membership row has ever existed.**
