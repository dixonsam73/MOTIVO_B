# FIND PEOPLE / A↔B NON-DISCOVERY — CLASSIFICATION. NOT A DEFECT.

**Classification only, 2026-09-10, measured read-only against production at
`4793276`. Nothing was mutated:** no enforcement change, no membership, no age
band, no directory or privacy row, no StoreKit change, no test-only bypass.

**Conclusion up front: the A↔B non-discovery is FULLY EXPLAINED by the
deliberately incomplete Connected fixture. No Find People defect is
demonstrated, and the search would return zero for BOTH devices even if the
other side were perfectly configured — because the VIEWER gate fails first.**

---

## 1. What `Force Études Connected` changes

`AppModeManager.resolvedActivationMode` (`:56`–`:68`) — `#if DEBUG` only:
`.forceConnected` returns `AppMode.connected`, bypassing
`ProductionAppModeActivation.resolve`. `applyMode` then calls
`setBackendMode(.backendConnected)` and `BackendConfig.apply()`, and every
capability flag (`canViewFeed`, `canComment`, `canShareWithFollowers`, …) reads
`mode == .connected` and becomes true.

**So it changes CLIENT PRESENTATION AND ROUTING, and nothing else.**

## 2. What it does NOT create

It writes **no server state whatsoever**. It does not create a `membership` row,
does not make `connected_member()` or `connected_member_self()` true, does not
create `account_privacy` or an age band, does not create an `account_directory`
row, and does not change the identity in the JWT. **A device in Force Connected
presents Connected UI while the server still sees an unentitled identity** —
which is precisely the state both devices are in.

## 3. Server-side eligibility to APPEAR in Find People

`search_account_directory(q)`, deployed. A subject row survives only if **all**
of:

| # | Predicate | Source |
|---|---|---|
| S1 | an `account_directory` row **exists** | `from public.account_directory ad` |
| S2 | `not enforcement_active()` **OR** `ad.entitled_until > now()` | D-U6-1 — a lapsed member becomes undiscoverable |
| S3 | `account_privacy_discoverable(ad.user_id)` — a privacy row with `lookup_enabled`, and not the 13-17-set-as-adult case. **Absence resolves FALSE**, and it is deliberately NOT wrapped in `enforcement_active()`, because the kill switch may relax entitlement but must never relax child safety | CP-2 |
| S4 | `ad.user_id <> auth.uid()` — self-exclusion | |
| S5 | every query token matches account_id prefix, display_name substring, or an instrument | |

## 4. Requester-side predicate — AND THIS IS THE DECISIVE ONE

| # | Predicate | Source |
|---|---|---|
| R1 | `enforcement_gate('rpc.search_account_directory')` — when enforcement is active this is `connected_member_self()`, i.e. **a live PRODUCTION entitlement** | U6b |
| R2 | `auth.uid() is not null` | |
| R3 | `char_length(btrim(q)) >= 2` | |

The client adds **no** gate of its own: `PeopleView` calls the RPC through
`AccountDirectoryService:303` with no entitlement check, so **all eligibility is
server-side**.

## 5–6. Measured state — what each device lacks

**Production, read-only, today:**

```
enforcement_active        : true
account_directory rows    : 1        ← one identity has a directory row AT ALL
  with entitled_until>now : 0        ← NONE is entitled
account_privacy rows      : 2        ← both band_18_plus, both lookup_enabled = true
membership rows           : 1        ← Sandbox
Production membership rows: 0
```

| | Device A | Device B / `samueldixon` |
|---|---|---|
| directory row (S1) | **ABSENT** | present |
| `entitled_until > now()` (S2) | n/a — no row | **FAILS** — `entitled_until IS NULL` |
| privacy row + `lookup_enabled` (S3) | **satisfied** (`band_18_plus`, lookup on) | **satisfied** (`band_18_plus`, lookup on) |
| requester gate (R1) | **FAILS** — no Production membership | **FAILS** — no Production membership |

**Device A lacks:** a directory row (its INSERT is enforcement-gated — C-70's
measured cause), and Production entitlement.
**Device B lacks:** Production entitlement — which fails it **as a subject**
(`entitled_until` NULL → D-U6-1) *and* **as a requester** (`enforcement_gate`).

**The discovery preference being ON on both devices is real and irrelevant here:**
S3 is the only predicate it controls, and S3 is the one predicate both devices
already satisfy.

## 7. Is the non-discovery expected? YES, over-determined

**Neither device can search at all** (R1 fails for both), *and* neither is
findable (A fails S1, B fails S2). **Four independent failures**, so the zero is
over-determined and cannot be read as evidence about the search itself — the
same care recorded for the Phase-4 "Find People returns nothing" observation.

## 8. Any genuine defect? NONE DEMONSTRATED

Every element behaves as designed and as deployed. **`Membership options are
unavailable` is expected in this Debug build** — StoreKit product loading is
deliberately off in this configuration — and `Restore Purchases → "No membership
found"` merely establishes that the Sandbox account holds no active Connected
entitlement. **Neither is evidence of a defect, and neither was caused by Force
Connected**, which was applied only afterwards.

## 9. Ownership — NO NEW FINDING NEEDED

Already owned, three ways:
- **Q6/A** — Device B's legacy pre-CP directory row, still carrying
  `entitled_until IS NULL`;
- **C-70** — Device A's absent directory row, dispositioned as the deliberately
  unentitled pre-release state, to be confirmed opportunistically;
- **Phase 4 exit conditions 2, 6-ASC and 8** — all blocked on the same missing
  legitimate Connected path, with `docs/phase-4-exit-assessment.md` already
  recording that *all 17 identities are unentitled*.

**Cross-referenced rather than duplicated.**

## 10. Would ONE legitimate Connected path unlock several checks? YES — this is the leverage

A single genuine Production Connected entitlement on one device would make
`connected_member_self()` true and let the directory INSERT and `entitled_until`
follow. That one fixture would put in reach, at once:

- **Phase 4 condition 2**, **condition 4's production half**, **condition 8**;
- **C-34's avatar-replacement device verification**;
- **U2b / U2s share-unshare device verification**;
- **C-70's opportunistic Account-ID/directory establishment confirmation**;
- **the C-71 Feed/BSDV visual check**, unavailable in this pass;
- and, with a second entitled identity, **mutual discovery and follow** — which
  is what Find People actually needs.

**It is one fixture, not seven errands.** Getting it is a separate authorised
decision (a real subscription, or the Production ASSN configuration that is
already release-gating housekeeping) and is **not** something to manufacture.
