# P5-F / CP-3 — CLIENT DESIGN. 2026-09-07

**DESIGN ONLY. NO CODE CHANGED.** Server architecture is settled (CP-1 `9a1f604`,
CP-2 `531d64b`); CP-3 connects the client to it.

---

## 1. THE MEASURED FLOW, AND THE ORDERING FINDING THAT DRIVES THE DESIGN

```
ProfileView
 └─ ConnectedIntroductionView
      onContinue → hasConnectedIdentity ? MembershipSelectionView : SIWA sheet(.join)
 └─ SIWA completes → AuthManager.handle(result)
      └─ directory hydration (AuthManager:505–551)
           row == nil → backendBootstrapState = .newAccount
                      → publishLocalProfileSnapshotToDirectoryIfPossible   ← ★ FIRST DIRECTORY INSERT
           row exists → setDiscoveryModeRaw(row.lookupEnabled) ; hydrate local
                      → publishLocalProfileSnapshotToDirectoryIfPossible
 └─ MembershipSelectionView
      .task loadBindingToken → ensure_membership_binding()                 ← BINDING
      purchase(appAccountToken:) → attestIfNeeded                          ← ESTABLISHMENT
 └─ PracticeTimerView → AppSetUpView (incomplete setup) → upsertSelfRow
```

**★ THE FIRST `account_directory` INSERT HAPPENS INSIDE SIGN-IN HYDRATION — BEFORE
BINDING, BEFORE PURCHASE, BEFORE `AppSetUpView`.** Not where the r3 design
assumed (`AppSetUpView`), and this is measured from `AuthManager:520`, not
inferred.

**Consequently CP-1's trigger is ALREADY LIVE against that path.** A new
Connected identity with no `account_privacy` row will have its directory INSERT
**refused** — and `publishLocalProfileSnapshotToDirectoryIfPossible` guards on a
non-empty display name and logs failure only under `#if DEBUG`, **so the refusal
is silently swallowed**. The member would end up Connected with **no directory
row**: undiscoverable, unattributable, and no error anywhere.

**This is latent today** (pre-release, two identities, no new joins) **but it is
live.** It sets CP-3's hardest constraint:

> **The band must be written between SIWA returning an identity and the directory
> publish — inside `AuthManager`'s post-sign-in path, not merely "before
> purchase".**

## 2. A SECOND MEASURED CORRECTION — AND THIS SECTION IS ITSELF CORRECTED

**AMENDED 2026-09-07 during implementation.** This section said a wired toggle
"never persisted the member's choice". **Closer measurement showed something
slightly different and worth stating exactly:** `ProfileView` carries the comment
*"Connected discovery is no longer user-configurable"* and **hard-forces
`DiscoveryMode.search` at two sites**. So the control was **withdrawn from the
UI**, and the local state was pinned ON — while the writer separately discarded
its argument. **Same net effect (no user control, permanent discoverability),
different mechanism**, and the mechanism is what the next person implements from.

### The original text follows

C-41 recorded `lookup_enabled` as *vestigial client plumbing*. **It is not.**

- `DiscoveryMode` is a real user-facing control (`ProfileView:150`, toggled at
  `:1032/:1046/:1931`), persisted per-user in `ProfileStore.discoveryModeRaw`.
- It is **hydrated from the server** at `AuthManager:528` —
  `setDiscoveryModeRaw(row.lookupEnabled ? 1 : 0)`.
- It is **read back** at `AuthManager:469` and passed to `upsertSelfRow(lookupEnabled:)`.

**And `upsertSelfRow` discards it** (`AccountDirectoryService:328`), then
`upsertSelfRowOnce` hard-codes `"lookup_enabled": true` in the payload (`:433`).

**So a shipped, wired, server-hydrated privacy toggle has never once persisted the
member's choice.** CP-3 does not *build* a discoverability control — it **repairs
one that already exists**, which is a smaller change and a worse latent defect
than the record described.

## 3. THE CHANGES

**Age assurance — no availability fallback.** iOS 26.2+ everywhere, so
`AgeRangeService.shared.requestAgeRange(ageGates: 13, 18, in:)` is called
unconditionally. Entitlement `com.apple.developer.declared-age-range` added.

**Derivation is bounds arithmetic, fail-closed** (r3 §5) — never gate-shape
matching, because Apple's own sandbox returns 13–15 and 16–17:

```
.sharing(r), r.lowerBound >= 18  → band_18_plus
.sharing(r), r.lowerBound >= 13  → band_13_17
everything else                  → BLOCK (incl. lowerBound == nil,
                                   .declinedSharing, thrown errors)
```

**Sequencing.** Question asked in `ConnectedIntroductionView.onContinue`, **before
the SIWA sheet**, held in memory only. Under-13/declined/error → Connected not
offered, **no SIWA, no identity minted, nothing written**. Otherwise SIWA runs,
and on success `AuthManager` calls **`account_privacy_upsert_v1(band)` as the
first authenticated call, before the directory publish** (§1). A failed band
write **suppresses the directory publish** and leaves Connected unestablished;
the coordinator re-asks on the next foreground.

**Writers repointed:**

| preference | from | to |
|---|---|---|
| discoverability | `upsertSelfRow(lookupEnabled:)` (discarded) | **`account_privacy_set_lookup_v1`** |
| follow requests | `upsertSelfRow(followRequestsEnabled:)` (discarded) | **`account_privacy_set_follow_requests_v1`** |
| hydration | `row.lookupEnabled` | **`account_privacy_self_v1`** — the **effective** value, computed server-side so the override rule is never reimplemented client-side |

**Dead plumbing removed:** the two payload keys in `upsertSelfRowOnce`, the two
**dead parameters** in both signatures, and the three call sites
(`AuthManager:618`, `AppSetUpView:325/337`, `ProfileView:1396/1409`). **Ordinary
profile publishing then cannot touch a privacy preference — structurally, because
it no longer sends those columns.**

**Share posture.** One shared derivation replaces two `@State … = true`
initialisers (`AddEditSessionView:222`, `PostRecordDetailsView:235`) and two
derivation sites (`:1829`, `:309`):

```
shareDefaultOn = (confirmed band == band_18_plus) && !fetchDefaultPostingIsPrivate()
```

**Unknown, unfetched, failed and `band_13_17` all default OFF.** The per-session
Share toggle stays offered — this changes the default, not the capability.

**Initial defaults vs later choices** are already separated server-side
(`*_set_under_band`, `*_changed_at`). The client **never** writes an initial
default; it only calls the two setters on an explicit user action.

**Attribution untouched.** No change to `get_account_directory_by_user_ids` or any
caller.

**Copy** is neutral and factual — what is collected, why, and that it can be
changed later. No nudging, no default-steering language.

## 4. PRE → POST AND DISCRIMINATORS

| # | scenario | PRE | **POST** | discriminator |
|---|---|---|---|---|
| 1 | **under 13** | no age request; join proceeds | **Connected not offered; no SIWA; no `auth.users`; no privacy row** | `auth.users` count unchanged; no network call to SIWA |
| 2 | **13–17** | — | band written **before** directory publish; discovery **off**; requests **closed**; Share default **OFF** | `account_privacy` row = `band_13_17`, `lookup_changed_at` **NULL**; `isPublic == false` on a new session |
| 3 | **18+** | — | band `band_18_plus`; discovery **on**; Share default = existing adult default | row present; `isPublic == !defaultPrivacy` |
| 4 | **declined / unavailable / error** | — | **no eligibility, no identity, no row**; Solo unaffected | forced `.declinedSharing` and a thrown error both leave `account_privacy` empty |
| 5 | **repeat / retry** | — | `upsert_v1` is insert-if-absent → **same row, no duplicate, band not overwritten** | run onboarding twice: one row, `band_updated_at` unchanged on the second |
| 6 | **profile republish after a privacy choice** | **rewrites `lookup_enabled = true`** | **preference unchanged** | set discovery OFF, then edit the profile and save → `account_privacy_self_v1` still reports off. **Fails against today's client** |
| 7 | **adult → teen reconciliation** | — | stored preference **preserved**; **effective** discovery/requests false | server `lookup_enabled` still true, `lookup_set_under_band='band_18_plus'`, effective **false** |
| 8 | **teen → adult** | — | band updated; **no preference touched**; adult-set values apply again | `lookup_changed_at` unchanged across the transition |
| 9 | **first directory INSERT for a new identity** | INSERT attempted with no band → **silently refused** (§1) | band written first → **INSERT succeeds** | new-identity join produces an `account_directory` row. **Fails against today's client** |

**Discriminators 6 and 9 are the load-bearing ones** — both fail against the
current client, and 9 fails against it **in production as it stands today**.
**5 and 8 are the ones a naive implementation passes by accident**, so they need
the stated field-level assertions rather than a pass/fail on the row existing.

## 5. TESTING

Unit tests cover the pure pieces: bounds derivation (all four shapes plus Apple's
six sandbox fixtures), the Share-default rule, and the absence of the removed
parameters. Device/Sandbox work uses the settled ephemeral flows and Apple's
sandbox age-assurance cases; **both devices are on 26.6.1, above the 26.2 floor.**

**No Samuel/Steve privacy state is created in production.** Any band needed for a
device run is created through the real onboarding path on a designated test
identity, or transactionally as CP-2's suite did.

## 6. STATUS

**NOTHING IMPLEMENTED. Awaiting review.**
