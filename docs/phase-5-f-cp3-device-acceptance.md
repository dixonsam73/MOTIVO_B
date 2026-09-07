# P5-F / CP-3 — DEVICE ACCEPTANCE: STARTED, BLOCKED, NOT COMPLETE. 2026-09-07

**CP-3 IS NOT COMPLETE.** The on-device Declared Age Range run has **not** been
performed. One gate passed, the rest are blocked on a locked device.

---

## 1. WHAT IS ESTABLISHED — THE ENTITLEMENT IS REAL

**This is the one device-class question that could be answered without the device
being unlocked, and it is the one most likely to have failed.**

A **device-signed Release build** (`-destination 'generic/platform=iOS'`,
`-allowProvisioningUpdates`) **succeeded**, and the result was inspected rather
than assumed:

| check | result |
|---|---|
| entitlement in the **signed binary** | **`com.apple.developer.declared-age-range` = true** |
| entitlement **granted by the embedded provisioning profile** | **TRUE** |
| profile | *iOS Team Provisioning Profile: com.sdsongs.etudes* |
| profile expiry | **2027-09-07** |
| `com.apple.developer.applesignin` still present | yes |

**Both halves matter.** A `.entitlements` file can carry a key the profile does
not grant; codesign accepts it and the OS refuses the app at install. **Here the
profile itself grants it**, which means the capability is enabled on the App ID —
so the prediction's flagged risk ("may require the capability enabled for the App
ID") **is measured as satisfied**, not merely hoped.

## 2. WHAT IS BLOCKED, AND WHY

```
xcrun devicectl device install app --device <Device A> Etudes.app
ERROR: The operation failed because the device was still locked.
       The device has not been unlocked recently
```

**Device A (SD beta burner, iPhone 16e, iOS 26.6.1) is paired and reachable over
the network but LOCKED.** Installation needs it unlocked and trusted at the time
of install. **That is a physical action I cannot perform.**

**Device B was deliberately NOT used.** It is the untouched established/lapsed
Phase 4 control fixture, and installing a new Release build over its existing one
would spend it. The standing rule is not to spend it casually.

## 3. WHAT REMAINS UNVERIFIED — STATED, NOT ESTIMATED

**None of the following has been observed. No result below may be inferred from
§1.**

- Declared Age Range requested **before** SIWA on real hardware;
- eligibility derived from **returned bounds** against a real Apple response;
- **18+** establishing adult privacy state, with the existing adult Share default
  retained;
- a **13–17** result producing Share OFF and discovery OFF, where Apple's sandbox
  machinery permits one;
- **declined / unavailable / error** failing to establish eligibility **and**
  failing to publish a directory row;
- **first authenticated privacy establishment preceding directory publication** —
  the ordering defect this unit exists to fix, and the single most important
  device observation;
- **`identityWithoutBand` / `connectedSetupIncomplete` recovery and safe retry**.

## 4. LIMITATIONS OF APPLE'S SANDBOX MACHINERY, RECORDED IN ADVANCE

Relevant to planning the run, from Apple's documentation read on 2026-09-06:

- **Sandbox age-assurance testing requires iOS/iPadOS 26.2+** and a **Sandbox
  Apple Account** with **Developer Mode** enabled. Device A is on **26.6.1**, so
  this precondition is **met**.
- The cases are selected from **Settings → Developer → Sandbox Apple Account →
  Manage → Age Assurance**, and there are **six fixed fixtures** — under-13
  `(nil,12)`, `(13,15)`, `(16,17)`, and three `(18,nil)` variants.
- **There is no 13–17 fixture.** The two teen cases are **13–15** and **16–17**,
  which is exactly why derivation is bounds arithmetic. A 13–17 observation will
  come from one of those, not from a range matching our gates.
- **`declinedSharing` cannot be produced in a regulated region** — Apple's
  documentation states the system supplies the range and the person cannot
  decline. The decline path is exercised via *Age Range for Apps → **Never
  Share***, and **if the test account's region is treated as regulated, that
  case may be unobtainable**. That is a limitation of Apple's machinery, not of
  the implementation, and it should be recorded as such if it occurs.
- **Apple caches its response**, revealing new information only on the
  **anniversary** of the original declaration. Switching fixtures may therefore
  need *Share Age Range again* to take effect promptly.

## 5. TO RESUME

1. **Unlock Device A** and keep it unlocked/trusted.
2. Re-run:
   `xcrun devicectl device install app --device BA5D3570-… <Etudes.app>`
   (the signed build is already produced and verified — §1).
3. Sign in to a **Sandbox Apple Account** and select the Age Assurance fixture.
4. Execute §3 in order, recording measured results only.

**Preserved throughout: Samuel, Steve, their mutual approved follow, and the
Phase 4 fixture. No production mutation. No unrelated cleanup.**

## 6. STATUS

**CP-3 REMAINS OPEN.** The entitlement/provisioning gate has passed on real
signing; **the Declared Age Range API has not yet run on device.**
