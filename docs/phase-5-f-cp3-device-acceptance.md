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

## 1b. RUNTIME GATES NOW PASSED ON DEVICE A — 2026-09-07

Device A unlocked; the **already-verified signed Release build** was installed and
launched. **These are runtime facts, not inferences from §1's signing check.**

| gate | result | why it is not implied by signing |
|---|---|---|
| **install accepted by iOS** | **PASS** — installed to `…/E4BF8F0D-…/Etudes.app` | iOS validates entitlements **against the profile at install** and refuses an app carrying one the profile does not grant. Signing alone never proves this |
| **app launches and stays up** | **PASS** — PID 7201 alive, **no crash report** | `DeclaredAgeRange.framework` is linked and therefore **loaded by dyld at launch**. A missing or incompatible framework aborts the process. So the framework **links and loads on real hardware** |
| **launch alone changes no server state** | **PASS** — `account_privacy` 0, `shadow_enforcement_stat` 75 unchanged, latest `auth.sessions.updated_at` still 2026-09-05 | confirms the flow is not triggered by launch and that nothing was written unattended |

**WHAT THIS DOES NOT ESTABLISH, AND MUST NOT BE READ AS ESTABLISHING:** that
`requestAgeRange` was ever *called*, that Apple returned anything, or that any
ordering or recovery invariant holds. **No age-range API call has been observed.**

## 1d. THE DECLARED AGE RANGE API RAN ON HARDWARE — 2026-09-07, 10:46 UTC

**Valid CP-3 evidence. Device A, Release build `f27e715`, Sandbox Apple Account
`sdsongsltd+devicec@gmail.com`, fixture *18+, age confirmed, significant change
not applicable*.**

| observation | result |
|---|---|
| **`requestAgeRange` invoked on real hardware** | **YES** |
| Apple's system UI appeared **immediately on Continue** | **YES** — *"Age-Appropriate Experiences in Apps"*, offering **Continue** / **Update Birthday** and a close control |
| the 18+ fixture returned a **shareable range** | **YES** |
| **bounds derivation produced `band_18_plus`** | **YES** |
| first authenticated privacy establishment wrote **adult defaults** | **YES** — `lookup_enabled = true`, `lookup_set_under_band = band_18_plus`, **`lookup_changed_at = NULL`**, `follow_requests_enabled = true` |

**`lookup_changed_at = NULL` is the sharp part:** it proves the value is an
**initial default derived from the band**, not a user choice, which is the
distinction the whole three-layer model rests on.

**Apple's sheet text is its own, and it is worth recording verbatim in
substance:** *"Share that you're an adult so you're not limited to child and teen
content in apps"*, and *"Your device uses your Apple Account information,
including your date of birth, to determine the age range that can be shared with
apps."* **Études is not the asker.** It also states a parent or guardian must
enable the feature for children and teens in a family group.

### WHAT THIS RUN DID NOT ESTABLISH, AND CANNOT

**It did not establish pre-SIWA ordering, and it did not establish
band-before-directory-publication.** **No SIWA sheet appeared at all**, and the
membership selection screen followed the age sheet directly.

**The cause is measured, not guessed: Device A retained STEVE's Connected
identity while being in SOLO.** Solo mode and Connected identity are independent
— a lapse withdraws *access* and **retains the identity** (C-1/C-26). So
`hasConnectedIdentity` was **true**, the code took the already-authenticated
branch, and there was no sign-in to order against and no directory row to create.

**MY PREDICTION THAT SIWA WOULD APPEAR WAS FALSIFIED, AND MY REASONING FOR IT WAS
WRONG.** I wrote *"Device A in Solo resolves the risk cleanly:
`hasConnectedIdentity` is false"*. **This project's own record says the
opposite**, and I had read it. Both ordering discriminators still require a
**genuinely new identity**.

### The row it created, and its removal

The run wrote a real `account_privacy` row for **Steve** — correct product
behaviour, wrong subject, caused by the inference above. **Deleted the same day
by explicit id under guards** (exactly one row, md5 `64ffb132`, `account_id`
`steveckeabuo`, created today), and the full baseline re-verified:
`account_privacy` **0**, `auth.users` **2**, directory **2**, approved follows
**2**, posts **7**, comments **5**, shadow **75**, membership **1**, with Samuel's
avatar and the mutual approved follow intact in both directions.

## 1e. CLEARING STEVE FROM DEVICE A — ANALYSED, NOT PERFORMED

**The obvious route is safe but INSUFFICIENT, and that is the finding.**

**`AuthManager.signOut()` is purely local** — it deletes the Keychain items
(`appleUserID`, `displayName`, both Supabase tokens), removes the backend
UserDefaults keys and clears the bearer token. **It makes no server call and
deletes no backend identity.** It is reachable from Profile → **Sign out**. So it
is safe for the fixture.

**But it will NOT produce a new identity.** This project measured on **2026-08-25**
that **Sign in with Apple returns the SAME `sub`** even after the credential had
been manually revoked, re-authenticating the existing identity, with `auth.users`
**not growing**. So after signing out, SIWA on Device A with the same Apple
Account **re-authenticates Steve** and returns the device to exactly today's
state.

**Three routes to a genuinely new Études identity:**

| | route | cost |
|---|---|---|
| **(a) RECOMMENDED** | sign Device A into a **different Apple Account** — the primary Apple Account is what SIWA uses, and is **separate from the Sandbox Apple Account** driving the age fixture | reconfiguring a burner's Apple Account. **Touches no server state and no fixture** |
| (b) | delete Steve server-side, so the same `sub` maps to a new `auth.users` row | **FORBIDDEN** while he is half the Phase 4 fixture |
| (c) | discharge Phase 4's outstanding device verification first, releasing Steve, then (b) | reorders the work |

**A question only the account holder can answer before (a) is actionable:**
**which Apple Account is Device A's primary account, and is it the one that
created Steve?** If they differ, a sign-out may already be enough. **I cannot see
that from here and will not assume it.**

## 1c. THE REMAINING MATRIX NEEDS PHYSICAL INTERACTION I CANNOT PERFORM

**Stated as a capability limit, not a scheduling excuse.** The simulator control
tool is **simulator-only by contract** and cannot drive a physical iPhone. Every
remaining discriminator begins with a tap:

- Profile → **Explore Connected → Continue** is what calls `requestAgeRange`;
- **Apple's own system sheet** must then be answered;
- the fixture is chosen in **Settings → Developer → Sandbox Apple Account →
  Manage → Age Assurance**.

**None of that is reachable from this machine.** What I can do, and will, is
**verify the server side after each step** — `account_privacy` contents,
`band_updated_at`, `lookup_changed_at`, directory-row presence and ordering — which
is where every invariant in §3 is actually decided.

**A note on which identity to use, because it is a real choice and not mine to
make silently.** Device A last held **Steve** (`64ffb132`), who is half the Phase 4
fixture. Running the flow signed in as Steve **would create a real
`account_privacy` row for him** — genuine product behaviour, not manufactured
state, but it **does** change fixture state and, once CP-2's clause applies, his
discoverability. **A fresh Sandbox tester identity avoids touching the fixture at
all** and is the recommended route.

## 2. WHAT IS BLOCKED, AND WHY

```
xcrun devicectl device install app --device <Device A> Etudes.app
ERROR: The operation failed because the device was still locked.
       The device has not been unlocked recently
```

**RESOLVED 2026-09-07: Device A was unlocked and the install succeeded — see
§1b.** The blocker below is retained as the record of why the first attempt
stopped. **What replaces it is a different limit: the remaining matrix needs UI
interaction on physical hardware (§1c), which is a capability limit rather than a
device-state one.**

**Original:** Device A (SD beta burner, iPhone 16e, iOS 26.6.1) is paired and
reachable over the network but LOCKED. Installation needs it unlocked and trusted
at the time of install. That is a physical action I cannot perform.

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

## 5. THE RUN SCRIPT — ORDERED, WITH WHAT I VERIFY AFTER EACH STEP

**Recommended: sign in with a FRESH Sandbox tester**, so the Phase 4 fixture is
not touched at all.

| # | on the device | I then verify server-side |
|---|---|---|
| **1** | Settings → Developer → Sandbox Apple Account → **Manage → Age Assurance** → choose **18+, age confirmed** | — |
| **2** | Études → Profile → **Explore Connected → Continue** | Apple's sheet should appear **before** any sign-in UI. **This is the pre-SIWA ordering discriminator** |
| **3** | Share the age range, complete **Sign in with Apple** | `account_privacy` gains **exactly one row**, `age_band = band_18_plus`, `lookup_enabled = true`, `lookup_changed_at` **NULL**. **And `account_directory` for that identity must exist — created only AFTER the band**, which is the ordering fix |
| **4** | Open a new session in the journal | Share toggle **ON** (adult default retained) |
| **5** | Profile → **Let other members find you** → off, then on | `lookup_enabled` follows; `lookup_changed_at` becomes non-NULL |
| **6** | Switch fixture to **13–15** (or 16–17), then *Share Age Range again*, relaunch | band moves to `band_13_17`; **preferences and `lookup_changed_at` unchanged**; **effective** discovery false if the preference was adult-set |
| **7** | Age Assurance → **under 13**, fresh identity | **refused: no `auth.users`, no `account_privacy`, no directory row** |
| **8** | *Age Range for Apps* → **Never Share**, fresh identity | **refused, nothing written.** If the region is treated as regulated this may be **unobtainable** — report as an Apple limitation |
| **9** | Airplane mode immediately after SIWA | `identityWithoutBand` recovery: identity exists, **no privacy row, NO directory row**; restore network and foreground → band written, directory row appears |

**Step 9 is the recovery discriminator and step 3 is the ordering one.** Those two
are the reason this unit exists.

## 6. TO RESUME

1. **Unlock Device A** and keep it unlocked/trusted.
2. Re-run:
   `xcrun devicectl device install app --device BA5D3570-… <Etudes.app>`
   (the signed build is already produced and verified — §1).
3. Sign in to a **Sandbox Apple Account** and select the Age Assurance fixture.
4. Execute §3 in order, recording measured results only.

**Preserved throughout: Samuel, Steve, their mutual approved follow, and the
Phase 4 fixture. No production mutation. No unrelated cleanup.**

## 7. STATUS

**CP-3 REMAINS OPEN.** The entitlement/provisioning gate has passed on real
signing; **the Declared Age Range API has not yet run on device.**
