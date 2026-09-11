# P5-L CLOSE-OUT — PREDICTION, COMMITTED BEFORE MUTATION. 2026-09-11

**At `2c3c3ed`.** Account-holder decisions 2026-09-11: close **C-42** narrowly;
implement the **storefront-change reload** as separate hardening; commit the
**C-52** scheme restoration with a non-vacuous guard and inventory affected
device evidence; record the `AddEditSessionView` legacy case as residue **only
if current code can no longer create it**. C-80 and C-81 out of scope.

---

## 1. A C-47 FINDING THAT CHANGES THE PICTURE — reported, and fixed here only because it enforces the decision already made

**`ContentView.loadFeedPersistedTitles` (`:2353-2368`) still MIGRATES AND
DELETES.** When the member has an identity and no per-identity store exists, it
copies the shared titles into the per-identity store and **removes the shared
store**; afterwards it returns the per-identity store **alone**, never merged.
It runs on **every Feed search with a non-empty query** (`:2111-2112`), so the
first search by a member with an identity:

- empties the shared store, so `AddEditSessionView` — which reads the shared
  store only — shows none of those titles;
- and hides from Feed search every title the C-47 writer later puts in the
  shared store.

**So current shipping code CAN still create the per-identity state**, and the
`AddEditSessionView` case is **not** merely legacy residue while this stands.

**My C-47 guard missed it — a fourth one-of-N miss.** It counted only
`UserDefaults.standard.set(` and this site writes through `defaults.set(` and
`defaults.removeObject(`. Widened: any `.set(` **or** `removeObject(forKey:` on a
title-store key outside the writer and factory reset. **Measured pre-fix count: 4**
(`ContentView:2362`, `:2363`, and the two pinned `PostRecordDetailsView` stem
fallbacks). **Allowed after: 2.**

**The fix is subtraction, not migration machinery:** the reader becomes
read-only and merges — shared, with per-identity over it — exactly as
`SessionDetailView` and `BackendShim` already do. Nothing is copied or deleted.
**Titles an earlier Feed search already moved are pre-launch beta residue:** they
remain readable through the two merging readers and reach the shared store again
the moment they are renamed.

## 2. C-52 — second recurrence

`3d49c4c` (2026-09-09 16:08) committed the Run action as **Debug**; the working
tree's restoration is blob `013cc35`, byte-identical to `67d64f0` and `e157b1c`.
**Only `buildConfiguration` regressed this time** — no StoreKit configuration is
pinned, at HEAD or in the tree.

**Inventory of possibly affected evidence — measured on the devices, read-only:**
`devicectl` shows **Device A holds ONLY `com.sdsongs.etudes`**. A Debug Run
installs `com.samueldixon.motivo.dev` alongside, and none exists, so no Debug
build from Xcode reached Device A: **every Device A claim in the window stands**
(C-50, P5-M, C-70's observation, P5-N Tier 1, CP-3, the Phase 4 device pass).
Strong, not absolute — an install later deleted would leave no trace. **Device B
holds both.** Its window claims were either deliberately Debug (Unit 1a/1b,
C-77, C-79, C-78, H-1 via Force Connected), configuration-independent (C-71's
visual check), or self-evidencing (C-42 probe run 1 `products=0` = Debug, run 2
`products=2` = Release). **No evidence is found to be questionable.** Both
installs report `1.0 (131)`, confirming the recorded gap that the build number
cannot identify a build.

## 3. PREDICTION

**Q1 — C-52 guard.** `SchemeConfigurationGuardTests` **FAILS** with the Run
action temporarily set back to Debug (HEAD's state) and **PASSES** on the
restored scheme; `testRunActionPinsNoStoreKitConfiguration` passes in both.

**Q2 — storefront guard.** `StorefrontReloadTests` **FAILS** pre-change.

**Q3 — C-47 widened guard.** `testEveryTitleWriteGoesThroughTheSharedWriter`
**FAILS** pre-fix with **4**; passes with **2** after.

**Q4 — after all changes:** every test passes. **Census 232 / 232** (229 + 2
scheme + 1 storefront; the C-47 guard is widened in place). **Warnings unchanged,
Debug 177 / Release 165.**

**Q5 — storefront reload design:** a `storefrontUpdatesTask` started from
`start()`, looping `for await _ in Storefront.updates` and calling
`loadProducts()` — the same shape as `transactionUpdatesTask`. **Known edge,
stated not engineered away:** `loadProducts()` returns early while a load is in
flight, so a storefront change landing during an in-flight load is not reloaded.
Handling it would need queued-reload state, which is the "meaningful lifecycle
architecture" the decision said to stop before.

**Q6 — no device acceptance** for the reload (a storefront change cannot be
produced on demand), the scheme guard, or the C-47 reader change beyond the
Device B check already outstanding.
