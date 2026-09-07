# P5-F / CP-3 — IMPLEMENTED AND LOCALLY VERIFIED. 2026-09-07

**Client connected to the CP-1/CP-2 server architecture. No server change. No
production mutation. No device or Sandbox run — that is a separate step.**

---

## 1. RESULT

| discriminator | result |
|---|---|
| **C1** Apple's six sandbox fixtures derive correctly | ✅ unit-tested |
| **C2** decline / errors / unknown shapes → never a band | ✅ |
| **C3** no forbidden identifier in the new files | ✅ **NONE** |
| **C4** `upsertSelfRowOnce` sends neither privacy key | ✅ **0** |
| **C5** privacy args at call sites | ✅ **0** (was 8) |
| **C6** `@State isPublic` initialisers | ✅ **0 true / 2 false** |
| **C7** Share rule: adult→own default; teen/unknown→OFF | ✅ unit-tested |
| **C8** band write precedes the directory publish | ✅ source order |
| **C9** band-write failure suppresses the publish | ✅ `guard … return` |
| **C11** entitlement key present | ✅ |

**Debug and Release both build clean, 0 errors. `MOTIVOTests` RUNS: 58 tests,
0 failures** (49 before, 9 new).

## 2. WHAT SHIPPED

**`DeclaredAgeRangeService`** — Apple's range requested via the SwiftUI
`@Environment(\.requestAgeRange)` action; **pure** `derive(lowerBound:upperBound:)`
and **pure** `shareDefaultOn(band:defaultPostingIsPrivate:)`. Bounds arithmetic,
fail-closed: a nil `lowerBound` is `ineligible`, never a guess.

**`AccountPrivacyService`** — the four RPCs. Reads the server's **effective**
values rather than recomputing the override, because drift here fails permissive.
Strict decoding: an unrecognised shape is refused, since every default would be a
guess about a child's privacy.

**Ordering (the load-bearing change).** `AuthManager` now calls
`ensureAgeBandEstablished` **before** `publishLocalProfileSnapshotToDirectoryIfPossible`,
and on failure sets `connectedSetupIncomplete` and **returns without publishing**.
`.identityWithoutBand` is a real state: SIWA mints an identity that outlives the
failure.

**Retry** is safe by construction — `fetchSelf` short-circuits an existing row,
`.noBandEstablished` is distinguished from transport failure so a network problem
is never read as "no band", and the deployed writer preserves `band_updated_at`
and every preference when the band is unchanged.

**Dead plumbing gone.** Two payload keys, two dead parameters across two
signatures, eight call-site arguments. **Profile publishing now cannot touch a
privacy preference — structurally, because the columns are no longer sent.**

**Share default centralised.** Both `@State` initialisers `true → false`, both
derivation sites through the one rule. The per-session toggle is unchanged.

## 3. TWO CORRECTIONS TO MY OWN RECORD

**The design doc was wrong about the discovery control**, and it is amended in
place. I wrote that a wired toggle "never persisted the member's choice".
Measured: `ProfileView` **hard-forces `DiscoveryMode.search`** at two sites under
the comment *"no longer user-configurable"* — the control was **withdrawn from
the UI** and the local state pinned ON, while the writer separately discarded its
argument. **Same net effect, different mechanism, and the mechanism is what the
next person implements from.** **C-41 is corrected accordingly.**

**A guard of mine was mis-scoped again.** C4 first read **2**, because I grepped
the whole file: the two hits are `CodingKeys` on the **decoded** row, not the
write payload. Scoped to `upsertSelfRowOnce` as the prediction actually stated,
it is **0**. **The code was right and my check was wrong** — the third mis-scoped
assertion in this project's recent history, after CP-1's grant filter and CP-2's
comment matching.

**And a design improvement fell out of a compile failure:** the pure decoders
inherited `@MainActor` from the enum and could not be called from a synchronous
test. Marking them `nonisolated` **makes the purity real rather than claimed**.

## 4. WHAT IS NOT DONE — THE OUTSTANDING HALF

**There is no user-facing discoverability or follow-request control.**
`account_privacy_set_lookup_v1` and `account_privacy_set_follow_requests_v1` are
wired and callable, and hydration reads the effective values — **but no UI
reaches the writers**, because §3 established that the control had already been
removed from the product. **So a 13–17 member cannot yet opt in**, and the
"explicit opt-in" scenario is unreachable from the UI even though the server and
client plumbing both support it.

**This is scope, not an oversight**: building that settings surface is a
product/copy decision (neutral explanation, no nudging) and deserves its own
small unit rather than being appended here.

**Also outstanding:** device/Sandbox acceptance, where the **entitlement is
genuinely exercised** — simulator builds do not validate it against a
provisioning profile, so a device install may require the capability enabled for
the App ID.

## 5. UNTOUCHED

No server object. No production data. **No Samuel/Steve privacy state.** CP-0,
CP-1 and CP-2 architecture unchanged.

## 6. STATUS

**CP-3 client plumbing complete and locally verified. Device/Sandbox acceptance
NOT started.**
