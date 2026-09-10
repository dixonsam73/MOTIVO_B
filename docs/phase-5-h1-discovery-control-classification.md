# H-1 — WHY `Let other members find you` IS ABSENT UNDER FORCE CONNECTED

**Classification only, 2026-09-10, at `60d7873`. No code changed, no gate
weakened, no membership/band/directory state manufactured, no production
mutation.**

**Conclusion: correct behaviour under a synthetic fixture. NOT an H-1
regression, and NOT a visibility-rule inconsistency.** The device observation
matches what the source predicts, precisely — including *which* control appears
and which does not.

---

## 1. The exact inner predicate

`if auth.accountPrivacyState != nil` (`ProfileView:845`), nested inside
`if appModeManager.canShowConnectedAccountManagement`.

`accountPrivacyState` is `@Published private(set)` on `AuthManager:151` and has
**five** writers, all reached only through `AccountPrivacyService.fetchSelf` or
`upsertBand`. Both go through `preflight` (`AccountPrivacyService:116`):

```
guard auth.hasConnectedIdentity                     // isSignedIn ∧ hasSupabaseAccessToken ∧ non-empty backendUserID
guard BackendConfig.isConfigured
guard await auth.ensureValidBackendSession(...)     // a LIVE Supabase session
```

…and then the server must actually return a band from
`account_privacy_self_v1`, i.e. **an `account_privacy` row must exist for that
identity**. Failure sets it to `nil` (`AuthManager:678`).

**So the control's real predicate is:** a genuine Connected identity **∧** a live
backend session **∧** a server-held age band.

## 2. Which part Device B fails

**The first one.** Force Connected sets `AppMode.connected` and
`setBackendMode(.backendConnected)` and **nothing else** — it creates no Sign in
with Apple identity, no Supabase session, and no `account_privacy` row. So
`hasConnectedIdentity` is false (or the session is absent), `preflight` refuses
before any request is made, and `accountPrivacyState` stays `nil`.

### The asymmetry is the proof, not a puzzle

The two controls have **different gates**, and each behaved exactly as its gate
requires:

| Control | Gate | Force Connected satisfies it? | Observed |
|---|---|---|---|
| Default to Private Posts | `canShowConnectedAccountManagement` → `mode == .connected` (`AppModeManager:109`) | **YES** — it is derived from AppMode | **shown** ✓ |
| Let other members find you | `accountPrivacyState != nil` → identity + session + server band | **NO** — none of those is client state | **hidden** ✓ |

**Seeing exactly one of the two is the outcome the source predicts.** Had both
appeared, *that* would have been the defect.

## 3. Did H-1 preserve the predicate? YES — byte-for-byte

Machine-compared, `c2c4719` (pre-H-1) against HEAD: the discovery block
including its `if auth.accountPrivacyState != nil` line is **byte-identical**.
The only two lines H-1 removed anywhere in that move were the outer
`if appModeManager.canShowConnectedAccountManagement {` and its closing brace,
which became the new section's own gate.

## 4. Would it have been absent before H-1 too? YES

The gate is unchanged and its inputs are untouched by Force Connected, so the
control was equally invisible in the previous layout under this fixture. **H-1
did not remove it; it was never displayable in this state.** The reason it was
not noticed before is that nobody had a reason to look for it in a
Force-Connected Debug container.

## 5–6. The gate is deliberately backend-dependent

The source says so in its own words (`ProfileView`, comment above the gate):
*"Shown only once the server holds an age band — without one the member is
undiscoverable anyway and the writer would refuse, so offering a control here
would be offering one that cannot work."*

**Required before the control should appear:** a Connected identity
(`isSignedIn` ∧ `hasSupabaseAccessToken` ∧ a backend user id), a live Supabase
session, and an `account_privacy` row carrying a band.

## 7. Correct behaviour, not an inconsistent rule

Showing it in this state would present a control whose only writer,
`AccountPrivacyService.setLookupEnabled`, would refuse — and CP-3 chose that
deliberately, because the alternative is a toggle that appears to work and
silently does not. **The intended product model is unaffected:** a legitimate
Connected member with a band sees Connected as *Default to Private Posts +
helper, Let other members find you + helper*, which is exactly what H-1
arranges.

**Corroborating measurement from the Find People classification:** production
holds **2 `account_privacy` rows, both `band_18_plus` with `lookup_enabled =
true`**. So the server state this control needs *does exist* for those
identities — what is missing on Device B Debug is the client's authenticated
session to reach it, not the row.

---

## 8. Disposition

All three of the account holder's conditions are met — H-1 preserved the gate,
Force Connected never satisfied it, and a legitimate Connected state will expose
the control as intended. **Recorded as a fixture limitation, not a defect.**

**H-1 closes as:**
- presentation **visually accepted** (section organisation good);
- **Default to Private Posts device-verified** in the Connected section;
- **discovery-control relocation structurally verified** — byte-identical move,
  gate intact, order asserted — **but not device-visible under the synthetic
  Force-Connected fixture**;
- **legitimate Connected device verification carried** to the existing future
  Production Connected fixture, alongside the seven obligations that fixture
  already unlocks.
