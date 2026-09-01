# U6b — BINDING ENFORCEMENT. IMPLEMENTATION AND ACCEPTANCE PLAN, 2026-09-01

**NOTHING IS IMPLEMENTED OR DEPLOYED. U6b HAS NOT BEGUN.** No schema, no policy,
no function, no flag, no production mutation. This is the plan and its committed
predictions-to-be.

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

1. **Record telemetry** — the existing body, write wrapped in
   `exception when others then null`. Telemetry that can fail a request is not
   telemetry, and that reasoning is unchanged.
2. **If enforcement is globally disabled, return `true`.**
3. **Otherwise return `connected_member_self()`.**

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

## 5. THE G10 COLD-CACHE DIRECTORY TEST — DESIGNED, NOT INCIDENTAL

`get_account_directory_by_user_ids` is **cache-gated** at
`AccountDirectoryService.swift:258`, so ordinary use never reaches it. It must be
forced.

| Half | Where | Assertion |
|---|---|---|
| **Unentitled viewer refused** | **Production**, Device A, **cold cache via reinstall** | the RPC refuses |
| **Entitled viewer still resolves a LAPSED subject** | **Local**, Production fixtures | attribution survives — **gating on the subject would break every retained comment** |

**Reinstall, do not erase.** `Erase All` on Device B is forbidden by the rig
rules; a reinstall clears the client cache without a destructive backend path.

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
written from the control flag at decision time.** The 56 observations already
collected stay readable as what they are, forever.

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
