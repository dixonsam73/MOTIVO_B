# CP-3 — FRESH-IDENTITY 18+ DEVICE RUN. 2026-09-07

**CP-3 REMAINS OPEN.** Most of the 18+ matrix is established on hardware. **One
piece — directory publication ordering — is NOT, and is blocked.** Two findings
were made that were not predicted.

Device A, Release build `f27e715`, Sandbox Apple Account
`sdsongsltd+devicec@gmail.com`, Age Assurance fixture **18+ / age confirmed**.
New identity **`96a3cb7b`**, created 13:34:54.

---

## 1. ESTABLISHED ON HARDWARE

| # | claim | evidence |
|---|---|---|
| **1** | **Nothing exists while SIWA is pending** | **Interleaved measurement at a held pause**: `auth.users` 1, identities 1, `account_privacy` 0, directory 1, last session 2026-09-05. **Not reconstructed from final state** |
| **2** | **`requestAgeRange` completes and derives a band BEFORE SIWA** | **Structural**: every non-`.band` outcome shows a refusal alert and never calls `continueToConnectedJoin()`. **SIWA appearing at all proves the request returned a band first** |
| **3** | Apple's system UI is real and appears on Continue | the **10:46 run** — *"Age-Appropriate Experiences in Apps"* |
| **4** | **Bounds derivation → `band_18_plus`** on a genuinely new identity | `account_privacy` row for `96a3cb7b` |
| **5** | **Adult defaults** | `lookup_enabled` **true**, `lookup_set_under_band` `band_18_plus`, **`lookup_changed_at` NULL**; `follow_requests_enabled` **true**, **`changed_at` NULL**. **The NULLs prove these are initial defaults, not choices** |
| **6** | **A band-write failure SUPPRESSES directory publication** | **Observed TWICE on a genuine failure**: identity existed with **no band and no directory row**. **No orphan directory row was ever created** |
| **7** | Purchase is **bound at source** | `binding_method = 'purchase'`, `environment Sandbox`, `apple_status 1` — never the legacy-claim path |

**Claim 6 is the most valuable result of the run.** It is CP-3's central safety
invariant, and it held under a **real** failure rather than a contrived one.
Before CP-3 the same failure would have silently produced a directory row with no
band.

**Claims 2 and 3 are deliberately kept apart.** Apple **caches** its response and
re-prompts only on the declaration anniversary, so on this run the sheet did
**not** appear — the range was returned silently. *"Apple's UI precedes SIWA"* is
**unobservable once cached**; *"`requestAgeRange` precedes SIWA"* is what CP-3
requires and is what is established. **Merging them would have been a false
claim.**

## 2. NOT ESTABLISHED — DIRECTORY PUBLICATION ORDERING

**Blocked, not failed.** The new identity has **no `account_directory` row**.

**Measured cause, not inferred:** `scheduleDirectoryHydrationIfNeeded` opens with
`guard BackendEnvironment.shared.isConnected else { return }`. The client is in
**Solo**, so hydration never runs and the publish is never attempted. **That is
correct pre-existing behaviour** — Solo publishes nothing — and unrelated to CP-3.

**So the band → directory ordering cannot be observed until the client is in
Connected mode.** The structural guarantee still stands unexercised: CP-1's
trigger would refuse the INSERT without a band, and for a new identity there is
no skip clause to fall through.

**A prediction I withdrew mid-run:** I proposed a "second gap" when two relaunches
produced no directory row. **That was wrong** — there was nothing for them to do.

## 3. FINDING A — `identityWithoutBand` HAS NO AUTOMATIC RECOVERY

**My design and prediction both said this state is *"retried on next launch/
foreground"*. IT IS NOT. I never wired that trigger.**

Observed: SIWA created the identity, the band write did not happen, and **two
force-quit relaunches did not recover it**. `ensureAgeBandEstablished` is
reachable from only three call sites, all sign-in/hydration paths, and it needs
`pendingAgeBand` — which is **in-memory only** and gone after a relaunch. So it
correctly refuses to invent a band, and **nothing re-derives one from Apple**.

**Recovery required a manual act:** re-entering **Explore Connected → Continue**,
which re-derived the band (cached, no prompt) and wrote it — `account_privacy`
0 → 1 at 13:40:16, ~5½ minutes after the identity was created.

**The fix is known and small:** on finding an authenticated identity with no
band, re-request the range and write it — exactly the U5f attestation-coordinator
pattern the design cites and then failed to implement. **Not fixed in this run.**

## 4. FINDING B — CLIENT STAYS IN SOLO DESPITE A LIVE SANDBOX MEMBERSHIP

After a successful Sandbox purchase the app showed Connected **briefly**, then
returned to Solo, and **stayed there across two relaunches**.

**Server state says entitled:** `Sandbox`, `apple_status 1`, `auto_renew_status
1`, `renewal_date 14:13:57` against a server clock of 13:55:42,
`still_entitled_by_formula` **true**, no `entitlement_ended_at`, no
`pending_cleanup_at`. Apple delivered `SUBSCRIBED`/`RESUBSCRIBE`.

**NOT caused by CP-3, and this was checked rather than assumed:**
`connectedSetupIncomplete` is consumed by **nothing** outside `AuthManager`, and
the early return leaves `backendBootstrapState` at the same value the previous
code produced.

**Consistent with the documented C-1 / C-38 family** — a forced entitlement
refresh after a verified purchase publishing `notEntitled` — but **that is a
hypothesis, not a measurement**, and it does not explain persistence across two
relaunches. **This needs its own investigation and is recorded as an open
question, not diagnosed.**

## 5. PRODUCTION STATE AFTER THE RUN

`auth.users` **2** (Samuel + `96a3cb7b`) · `account_privacy` **1** ·
`account_directory` **1** (Samuel only) · `membership` **1** (Sandbox) ·
`membership_binding` **1** · `follows` **0** · `shadow_enforcement_stat` **34** ·
notifications **75**.

**Samuel untouched throughout.**

## 6. WHAT REMAINS FOR CP-3

1. **Directory publication ordering** — blocked on the client reaching Connected
   (Finding B).
2. **Finding A's recovery gap** — a real defect to fix.
3. Teen, under-13, decline/error and recovery discriminators — **not started**.

**CP-3 REMAINS OPEN.**
