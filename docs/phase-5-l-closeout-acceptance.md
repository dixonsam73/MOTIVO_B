# P5-L CLOSE-OUT — ACCEPTANCE. 2026-09-11

Prediction and guards: `docs/phase-5-l-closeout-prediction.md`, committed at
`851267f` **before mutation**. C-80 and C-81 not touched. No production, ASC,
enforcement or age-state mutation.

## 1. Result

| | Prediction | Outcome |
|---|---|---|
| **Q1** | C-52 guard fails on the Debug scheme, passes on the restored one; StoreKit half passes in both | **MET** — with the scheme stashed to HEAD's Debug blob `9bb5409`, `testRunActionBuildsRelease` FAILED and `testRunActionPinsNoStoreKitConfiguration` passed; both pass on the restored blob `013cc35` |
| **Q2** | storefront guard fails pre-change | **MET** — "the store must observe Storefront.updates" |
| **Q3** | widened C-47 guard fails at 4, passes at 2 | **MET EXACTLY** — 4 pre-fix (`ContentView:2362`, `:2363` and the two pinned stem fallbacks); 2 after |
| **Q4** | 232 / 232; warnings unchanged | **MET** — **232 declared, 232 passed**, structured census; **Debug 177 / Release 165**, warning set identical |
| **Q5** | reload uses the existing observation shape; in-flight edge left | **MET** — `storefrontUpdatesTask` started from `start()`, the same shape as `transactionUpdatesTask` |
| **Q6** | no device acceptance for these | **Holds** |

Pre-change run structured: *11 reported, 8 Passed, 3 Failed* — exactly the three
predicted failures.

## 2. What changed

- **C-52** — the account holder's scheme restoration is committed; `SchemeConfigurationGuardTests` now enforces it. `CLAUDE.md`'s scheme bullet says so.
- **C-42** — closed narrowly, with a reopening condition. No code.
- **Storefront hardening** — `ConnectedMembershipStore.startStorefrontObservation()` reloads products on `Storefront.updates`. **Separate from C-42.** Known edge: a change landing during an in-flight load is not reloaded.
- **C-47 correction** — `ContentView.loadFeedPersistedTitles` is read-only and merging; the migrate-and-delete is gone. The guard is widened to catch any receiver and any removal.

## 3. Evidence inventory (C-52)

**No device evidence in the window is found questionable.** Device A holds only
`com.sdsongs.etudes` (measured with `devicectl`), so no Debug build from Xcode
reached it. Device B's window claims were deliberately Debug,
configuration-independent, or self-evidencing. **Both installs report `1.0
(131)`**, so the build number still cannot identify a build — a recorded gap,
not closed here.

## 4. Still open

- **C-47** — the Device B audio rename → close → reopen check.
- **C-69** — device check carried to the Production Connected fixture.
- **C-80, C-81** — open, untouched.
