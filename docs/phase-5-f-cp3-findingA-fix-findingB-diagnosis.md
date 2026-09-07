# CP-3 — FINDING A FIXED · FINDING B DIAGNOSED. 2026-09-07

**CP-3 REMAINS OPEN.** Finding A is fixed and locally verified. **Finding B is
diagnosed and NOT fixed**, as instructed.

---

## PART 1 — FINDING A: RECOVERY IMPLEMENTED

`AgeBandRecoveryCoordinator`, wired at **launch** and **every foreground**.

### It re-asks Apple rather than persisting the band, deliberately

**Persisting the derived band locally would make recovery trivial and would be
wrong.** After process death the client would be asserting an age it can no
longer justify — from storage rather than from Apple. **No band may be invented
after process death**, so recovery **re-acquires the range**. That is cheap:
Apple caches its answer and re-prompts only on the declaration anniversary, so
the ordinary case presents **no UI at all**.

**No provenance is persisted either.** `ageRangeDeclaration` is still never read.

### Safety properties, each with its mechanism

| property | how it holds |
|---|---|
| no band invented after process death | the band comes **only** from a live `requestAgeRange`; nothing is read from storage |
| unresolved / declined / error stays non-eligible | `bandToEstablish` returns nil for `.ineligible` and `.unavailable`; **only `.band` proceeds** |
| directory publication stays suppressed until establishment | unchanged — and CP-1's trigger enforces it **independently of the client** |
| retries are idempotent | an existing band **short-circuits before Apple is called**; the server writer is insert-if-absent, so a repeat cannot create a second row or move `band_updated_at` |
| no foreground prompt loop | **single-flight + a 60s in-memory cooldown** |

**A transport or session failure is not read as "no band".** Only an explicit
`.noBandEstablished` proceeds — otherwise an outage would re-ask Apple on every
foreground.

**The cooldown is in memory, not persisted** — copied from U5f, where persisting
it would make a previous failure permanent authority.

**Not gated on Connected mode**, for U5f's stated reason: the member this rescues
is precisely the one whose Connected state is incomplete.

### Verification

**Debug and Release build clean. `MOTIVOTests`: 65 passed, 0 failed**, including
**5 new recovery tests** — identity/config gating, fresh-identity attempt,
single-flight suppression, the **cooldown prompt-loop guard**, and **only a
derived band is establishable** (both refusal outcomes asserted nil).

**No destructive device run was performed for Finding A**, as instructed.

---

## PART 2 — FINDING B: DIAGNOSED, NOT FIXED

### The authoritative path, traced end to end

```
Transaction.currentEntitlements                     ← StoreKit, on device
  └─ ConnectedMembershipStore.refreshEntitlement()
       └─ membershipState  (.entitled only if a VERIFIED transaction
                            whose productID ∈ ProductID.all is yielded)
            └─ isEntitled  ( == .entitled )
                 └─ MOTIVOApp .onReceive($membershipState) → handleMembershipState
                      └─ AppModeManager.applyActivation(auth:isEntitled:)
                           └─ ProductionAppModeActivation.resolve
                                guard BackendConfig.isConfigured
                                guard isEntitled          ← FAILS HERE
                                guard auth.hasConnectedIdentity
                                → .connected
                                     └─ setBackendMode(.backendConnected) → isConnected
```

### The first point where live entitlement becomes Solo

**`ConnectedMembershipStore.refreshEntitlement()`'s iteration over
`Transaction.currentEntitlements` yields no matching verified transaction**, so
`resolvedState` keeps its default `.notEntitled`, and `resolve()` returns
`.solo` at `guard isEntitled`.

### Server and client are NOT in disagreement about authority

**`resolve()` never consults the server.** Its only inputs are
`BackendConfig.isConfigured`, local StoreKit entitlement, and
`hasConnectedIdentity`. **The server membership row is not an input to client
mode at all** — by the settled split in which the client governs UI reversibly
and the server governs the API. So "server says entitled, client says Solo" is
**not** a contradiction; it is the client's **local** read being false.

### What was ruled OUT, by measurement rather than assumption

| candidate | verdict |
|---|---|
| **product-ID mismatch** | **RULED OUT.** Purchased `com.sdsongs.etudes.connected.monthly`; `ProductID.all` contains exactly that |
| **no re-activation after refresh** | **RULED OUT.** `.onReceive($membershipState)` → `handleMembershipState` → `applyActivation(isEntitled: true)` on `.entitled`. The chain is sound; it is never reached |
| **stale local cache overriding the server** | **RULED OUT as a mechanism** — there is no cached entitlement to be stale. `membershipState` is recomputed from StoreKit each refresh |
| **activation hydration failing** | **RULED OUT.** Directory hydration is downstream of mode and cannot affect it |
| **CP-3's changes** | **RULED OUT.** `connectedSetupIncomplete` is consumed by nothing outside `AuthManager`, and the early return leaves `backendBootstrapState` at the value the previous code produced |

### NOT assigned to the C-1 / C-38 family

**The symptom resembles it and the evidence does not support it.** C-1 recorded a
**transient** `notEntitled` immediately after a verified purchase, with the
**second** refresh publishing `entitled`.

**Here it is persistent** — across two force-quit relaunches and roughly ten
minutes, with `refreshEntitlement()` running on every foreground. **A transient
race does not survive that.** Assigning it to C-1/C-38 would explain the shape
while contradicting the duration.

### What remains unestablished, and what would settle it

**Why `Transaction.currentEntitlements` is empty while the server holds a live
Sandbox membership** (`apple_status 1`, `renewal_date 14:13:57` against a
13:55:42 clock, no `entitlement_ended_at`).

**It cannot be settled from this machine** — `currentEntitlements` is device- and
Apple-Account-scoped. **The evidence needed is on-device:**

1. **Settings → Developer → Sandbox Apple Account** — is it still
   `sdsongsltd+devicec@gmail.com`, and does **Manage → Subscriptions** show the
   monthly subscription as active?
2. Whether **Restore Purchases** in Études resolves entitlement — that calls
   `AppStore.sync()` and would distinguish "StoreKit has it but the app has not
   seen it" from "this Apple Account has no entitlement".
3. Device-attached console output during a foreground, to see what
   `refreshEntitlement` observes.

**A relevant precedent, not a conclusion:** CLAUDE.md records two Apple surfaces
disagreeing before — a subscription live in Manage Membership while
Settings → Sandbox Apple Account → Subscriptions read *"You do not have any
subscriptions"* — with the note that **where the retained entitlement state lives
is unknown**. That is the same *class* of Apple-side inconsistency, and it is
offered as context, **not as an assignment of ownership**.

**Ownership is therefore not yet established, and no fix is proposed.**

---

## STATE PRESERVED

Fresh identity `96a3cb7b` and its genuine `band_18_plus` state are **untouched**.
**Samuel is untouched.** No production mutation in this unit.

## STATUS

Finding A fixed and locally verified. **Finding B diagnosed to its first
divergence point, ownership unestablished.** Directory-publication ordering
**remains blocked, not failed**. Teen / under-13 / decline **not started**.
**CP-3 REMAINS OPEN.**
