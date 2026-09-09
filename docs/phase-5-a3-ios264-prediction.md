# P5-A3 — iOS 26.4 PRODUCT BASELINE: PREDICTION

**Committed BEFORE any mutation, 2026-09-09.** A discrete pre-launch baseline
unit. **It is NOT part of P5-G**, and **no regulatory implementation is inferred
from it.**

## 1. Rationale, recorded permanently

**Pre-launch is the lowest-cost opportunity to establish the 26.4 floor, because
Études has no public installed base that can be stranded by the change. Raising
the floor later remains possible, but could exclude existing users or devices from
future versions.**

**The rationale for 26.4 is prospective simplification:** if a concrete future
obligation requires the 26.4 regulatory APIs, **all supported Études installations
can use them without introducing OS-availability branching into child-safety or
regulatory code.** **It changes no current legal conclusion and enables no new
behaviour today.**

**26.4 and not 26.5:** the only Declared Age Range symbol added at 26.5 is
`AgeRangeDeclaration.confirmed` — **assurance provenance, which Études has
deliberately decided never to read**. So 26.4 is the correct resting point.

## 2. WHAT THIS UNIT MUST NOT DO

- **No `isEligibleForAgeFeatures`, no `requiredRegulatoryFeatures`, no
  PermissionKit, no significant-change handling, no regulatory behaviour of any
  kind.**
- **No change to the unconditional age-establishment / teen-protection
  architecture.** Register §O2 continues to govern: Apple's regulatory signals
  must never gate the globally uniform protections.
- **No rewriting of dated historical or acceptance records.**
  `docs/phase-5-a2-baseline-acceptance.md` records the 18.5 → 26.2 change **as it
  was on 2026-09-07** and must stay as written; editing it would falsify the
  historical record.

## 3. PREDICTED CHANGES — exact

| file | change | count |
|---|---|---|
| `MOTIVO.xcodeproj/project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET = 26.2;` → `26.4;` | **4** (app Debug/Release, `MOTIVOTests` Debug/Release) |
| `CLAUDE.md` | Environment bullet: supported minimum 26.2 → 26.4 | 1 bullet |
| `docs/handover-p5g-cp4.md` | operative statement of the minimum | 1 line |
| `docs/phase-5-g-decision-register.md` | §O4 / §P: record the floor as raised | small |

**`MOTIVOUITests` is NOT edited — it inherits.**

**Predicted NOT to change:** any `.swift` file; the entitlements; the scheme;
`docs/phase-5-a2-baseline-acceptance.md`;
`docs/cp3-remaining-acceptance-matrix.md` (its "26.2+" states **Apple's Sandbox
requirement**, not our floor).

## 4. PREDICTED RESOLVED BUILD SETTINGS

All six read **26.4** afterwards:

| target | Debug | Release |
|---|---|---|
| `MOTIVO` (app) | 26.4 | 26.4 |
| `MOTIVOTests` | 26.4 | 26.4 |
| `MOTIVOUITests` | 26.4 (inherited) | 26.4 (inherited) |

## 5. PREDICTED VERIFICATION OUTCOMES

| measure | prediction |
|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET = 26.2;` | **0** |
| `IPHONEOS_DEPLOYMENT_TARGET = 26.4;` | **4** |
| `#available(iOS` / `@available(iOS` in app source | **0 / 0**, unchanged |
| Debug build | clean, 0 errors |
| Release build | clean, 0 errors |
| `MOTIVOTests` | **87 passed, 0 failed** |
| Device A (iPhone 16e, 26.6.1) | compatible |
| Device B (iPhone 17 Pro, 26.6.1) | compatible |

## 6. THE WARNING DELTA — the prediction most likely to be WRONG

**P5-A2 predicted "no new warnings" and was FALSIFIED**: 17 distinct warning kinds
became 24, all deprecations, every one *"deprecated in iOS 26.0"*. The mechanism
is that raising a deployment target brings newly-in-range deprecations into view.

**PREDICTION: 0 new warning kinds**, because the move is 26.2 → 26.4 — two minor
versions rather than a generational jump — and Apple deprecations in that window
are far fewer than at the 18.5 → 26.0 boundary.

**THIS PREDICTION IS EXPLICITLY LOW-CONFIDENCE.** The method, not the guess, is
what matters: build the **pre-change** tree and the **post-change** tree, each
with its **own derived-data path**, extract warnings, normalise away paths and
line numbers, and diff the distinct kinds.

**IF NEW WARNINGS APPEAR THEY MUST BE CLASSIFIED BEFORE THE UNIT IS ACCEPTED** —
each one identified as a deprecation, an API-availability consequence, or
something else. **"Probably harmless" is not a classification.**
