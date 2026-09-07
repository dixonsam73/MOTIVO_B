# P5-F / CP-3 — PREDICTION AND DISCRIMINATORS. 2026-09-07

**COMMITTED BEFORE MUTATION. No client file is changed at this commit.**
Design: `docs/phase-5-f-cp3-client-design.md`.

---

## 1. THE API, READ FROM THE SDK RATHER THAN THE DOCUMENTATION

`DeclaredAgeRange.framework` is present in **iPhoneSimulator26.5.sdk**. From its
`.swiftinterface` — the authoritative signatures:

```swift
@Environment(\.requestAgeRange) var requestAgeRange     // DeclaredAgeRangeAction
func callAsFunction(ageGates: Int, _: Int? = nil, _: Int? = nil) async throws -> AgeRangeService.Response

enum Response { case declinedSharing; case sharing(range: AgeRange) }
struct AgeRange { var lowerBound: Int?; var upperBound: Int?
                  var ageRangeDeclaration: AgeRangeDeclaration?
                  var activeParentalControls: ParentalControls }
enum Error: LocalizedError { case notAvailable; case invalidRequest }
```

**The SwiftUI environment action needs no `UIViewController`**, so the request
lives naturally in the Connected flow's own view.

**A free consequence of not persisting provenance:** `.confirmed` is
`@available(iOS 26.5)` and the granular cases are 26.2-and-deprecated. **Because
Études never inspects `ageRangeDeclaration`, none of that availability surface is
touched.** A design that stored provenance would have inherited an availability
problem at our 26.2 floor.

## 2. TIGHTENING 1 — NAMING

**Études does not ask an "age question".** Apple presents its own system sheet
and returns a range. Nothing in code, docs or UI may imply Études asked.

| forbidden | used instead |
|---|---|
| "age question", "ask the user's age", "age prompt" | **"request the declared age range"** / "Apple shares an age range" |

Identifiers: `DeclaredAgeRangeService`, `requestDeclaredAgeRange()`,
`DeclaredAgeRangeOutcome`, `AgeBand`. **No identifier contains `question`,
`ask`, `dob`, `birth` or `age(...)` as a scalar.**

UI copy is factual: Études asks **Apple** to share an age range; Apple decides
what to share; Études never receives a date of birth.

## 3. TIGHTENING 2 — THE EXPLICIT SETUP STATE MACHINE

```
.rangeNotRequested
    │ requestDeclaredAgeRange()
    ├── .ineligible  (lowerBound nil / < 13)      → Connected NOT offered.
    ├── .unavailable (declinedSharing / thrown)   → NOTHING written. No SIWA.
    └── .band(b) ──► SIWA ──► identity exists
                       │ account_privacy_upsert_v1(b)   ← FIRST authenticated call
                       ├── failure → .identityWithoutBand   ★ SETUP INCOMPLETE
                       │              • directory publish SUPPRESSED
                       │              • Connected not activated
                       │              • retried on next launch/foreground
                       └── success → .established → directory publish may proceed
```

**`.identityWithoutBand` is a real, reachable, named state** — SIWA has minted an
identity that outlives the failure, so it cannot be modelled as "nothing
happened".

**Retry safety, and why each property holds:**

| requirement | mechanism |
|---|---|
| reuses the existing identity | SIWA returns the same `sub`; no sign-out on failure, so `auth.users` cannot grow |
| no duplicate privacy state | `account_privacy_upsert_v1` is **insert-if-absent** (`on conflict … returning`) |
| timestamps preserved when nothing changed | deployed writer sets `band_updated_at = case when ap.age_band = excluded.age_band then ap.band_updated_at else now() end` |
| choices preserved | the writer touches **`age_band` only** — never `lookup_enabled`, `follow_requests_enabled`, `*_set_under_band` or `*_changed_at` |
| no prompt storm | Apple caches its response; a retry typically re-reads without presenting UI |

**The directory publish is suppressed rather than attempted-and-failed.** CP-1's
trigger would refuse it anyway, and that refusal is silently swallowed by the
existing `#if DEBUG`-only failure branch — so suppressing it is the difference
between a **known** incomplete state and an **invisible** one.

## 4. PREDICTED CHANGE SURFACE

**New:** `DeclaredAgeRangeService.swift` (Apple wrapper + **pure** derivation),
`AccountPrivacyService.swift` (the four RPCs + effective-state hydration).

**Modified:**

| file | change |
|---|---|
| `AccountDirectoryService.swift` | drop 2 payload keys; drop 2 **dead parameters** from 2 signatures |
| `AuthManager.swift` | band write before directory publish; suppress on failure; drop `lookupEnabled:`/`followRequestsEnabled:` args; hydrate effective state from `account_privacy_self_v1` |
| `ProfileView.swift` | request range before SIWA; discovery toggle → `account_privacy_set_lookup_v1`; drop args |
| `AppSetUpView.swift` | drop args |
| `AddEditSessionView.swift`, `PostRecordDetailsView.swift` | one shared Share derivation; `@State` initialisers `true → false` |
| `MOTIVO.entitlements` | add `com.apple.developer.declared-age-range` |

**Mechanical predictions:**

| measure | before | **after** |
|---|---|---|
| `"lookup_enabled"` / `"follow_requests_enabled"` payload keys | 2 | **0** |
| `lookupEnabled:` / `followRequestsEnabled:` arguments at call sites | 8 | **0** |
| `@State private var isPublic: Bool = true` | 2 | **0** |
| `fetchDefaultPostingIsPrivate()` direct callers | 2 | **0** (both via the shared rule) |
| entitlement keys | 1 | **2** |

## 5. DISCRIMINATORS

| # | assertion | fails today? |
|---|---|---|
| **C1** | derivation: `(nil,12)→ineligible`, `(13,15)→band_13_17`, `(16,17)→band_13_17`, `(18,nil)→band_18_plus` | n/a — new |
| **C2** | `.declinedSharing` and both `Error` cases → **`.unavailable`**, never a band | n/a — new |
| **C3** | no identifier in the new files matches `question|ask|dob|birth` | **yes** if named badly |
| **C4** | `upsertSelfRowOnce` source contains neither payload key | **YES** |
| **C5** | no call site passes `lookupEnabled:`/`followRequestsEnabled:` | **YES** |
| **C6** | both `isPublic` `@State` initialisers are `false` | **YES** |
| **C7** | Share rule: adult→`!defaultPrivacy`; teen/unknown/error→`false` | **YES** |
| **C8** | `AuthManager` calls the privacy writer **before** `publishLocalProfileSnapshotToDirectoryIfPossible` (source order + a test) | **YES** |
| **C9** | on band-write failure the directory publish is **not** called | **YES** |
| **C10** | retry with an unchanged band issues no preference write | n/a — new |
| **C11** | entitlement file contains the declared-age-range key | **YES** |

**C4, C5, C8 and C9 fail against the current client** — C8/C9 are the ordering
defect measured in the design, and they are the load-bearing pair.

**C3 is a source-text assertion and must target CODE, not comments** — the trap
hit four times in this session. It strips `//` lines before matching.

## 6. VERIFICATION AND SCOPE

Local only: Debug **and** Release build clean; `MOTIVOTests` **runs** (49 → 49 +
new). **No device or Sandbox run in this unit** — that is a separate step and is
where the entitlement is genuinely exercised.

**The entitlement is the one item not fully verifiable locally:** simulator
builds do not validate it against a provisioning profile, so a device install may
require the capability enabled for the App ID. **Flagged, not assumed away.**

**No Samuel/Steve privacy state in production. No server change.**

## 7. STATUS

**NOTHING IMPLEMENTED AT THIS COMMIT.**
