# P5-J′ — PREDICTION, COMMITTED BEFORE MUTATION. C-6 · C-16 · C-20 · C-21.

**At `ecc0610`, 2026-09-10.** Each row was re-checked against HEAD and today's
clean build logs first. Dispositions were agreed with the account holder
beforehand. **Closure by evidence counts the same as a fix.** C-80, the P5-K′
remainder and C-81's implementation are out of scope.

---

## 1. Measured state at HEAD

| Row | Mechanism at HEAD | Evidence |
|---|---|---|
| **C-6** | `fatalError` on `loadPersistentStores` failure, `Persistence:43`, present since the initial commit | Source |
| **C-16** | `try!` on `url(for: .applicationSupportDirectory, create: true)`, **moved to `SessionSyncQueue:419`**; runs in `init`, reached at launch (`MOTIVOApp:391`) | Source; it is the **only** `try!` in app source |
| **C-20** | **REPRODUCES — the 2026-09-09 demotion looked at the wrong line.** `AuthManager:731`: `PersistenceController.shared` and `fetchUserInstruments` referenced inside `viewContext.performAndWait { … }` (`:724`) | Compiler, **both** configurations; `performBlockAndWait:` takes an `NS_SWIFT_SENDABLE` block (`NSManagedObjectContext.h:100`) |
| **C-21** | Three unused `status` bindings (`NetworkManager:260`, `:526`, `:577`); a fourth at `:859` **is** used | Compiler |

**C-20 runtime reading.** The enclosing function is a member of `@MainActor`
`AuthManager`, and `viewContext` is expected to be the main-queue context, so
`performAndWait` runs the block **inline on the main thread**. There is **no
off-main Core Data access**; the defect is a static isolation crossing that
Swift 6 would reject. **The main-queue premise is asserted by a test, not
assumed** — the SDK header does not state it.

**C-21 reading.** Each unused binding is followed immediately by the real check
on `http.statusCode`, so **no status check was dropped**. The only unhandled
case — a non-HTTP response treated as success — cannot arise from `URLSession`
over HTTPS.

**C-6 reading.** The only background mode is `audio`, which never launches the
app before first unlock, so a pre-unlock store-protection failure is not
reachable. **The realistic trigger is a non-inferable model migration:** 11
shipped versions, current **V9**, **no mapping models**, so every upgrade relies
on inferred lightweight migration. The trap is **fail-closed** — it never
touches the store file, so the local journal survives it.

## 2. Dispositions (agreed)

- **C-6 — CLOSE, NARROWLY:** accepted fail-closed behaviour under the current
  architecture, with migration compatibility moved to release-time verification
  by `StoreMigrationCompatibilityTests`. **Empty-store migration does NOT prove
  every populated-data case.** **If the test exposes an existing failure, STOP
  and reclassify C-6 — do not close it.**
- **C-16 — FIX:** the non-throwing `URL.applicationSupportDirectory`; identical
  path; `makeFileURL` becomes internal so the path can be tested.
- **C-20 — FIX by removing the redundant `performAndWait` wrapper**, not by
  `MainActor.assumeIsolated`, provided the main-queue premise holds.
- **C-21 — CLOSE AS REFUTED.** Deleting the three dead bindings is **incidental
  warning cleanup, not the fix**.
- **C-81 — FILED, NOT FIXED:** the `AgeBandRecoveryCoordinator:49` Swift 6
  warning.

## 3. PREDICTION

**J1 — the pre-change run of the new tests:**
- `CorrectnessHygieneTests.testNoForceTryInAppSource` **FAILS** (1 found).
- `testProfileSnapshotPublishHasNoIsolationCrossing` **FAILS** (`performAndWait`
  present).
- `testViewContextIsMainQueue` **PASSES** — the premise that makes C-20's removal
  behaviour-equivalent.
- `testAuthManagerIsMainActorIsolated` **PASSES**.
- `StoreMigrationCompatibilityTests` **PASSES for all 11 versions.** **This is
  the one prediction that can change what we know.** If any version fails, the
  unit stops there.

**J2 — after the change:** every new test passes; C-16's path test shows the
queue file URL is **byte-identical** to the old
`url(for: .applicationSupportDirectory, …)`-derived path.

**J3 — warnings, clean derived data:** **Debug 187 → 177, Release 175 → 165.**
C-20 accounts for −4 per configuration (two diagnostics, each logged twice) and
C-21 for −6 (three × two). **C-81's lines are unchanged**, and no new warning
appears anywhere.

**J4 — structured census: 213 declared, 213 passing** (208 + C-6 × 1 + C-16 × 2
+ C-20 × 2).

### CORRECTION AFTER THE PRE-CHANGE RUN — 2026-09-10. J1 IS KEPT AS WRITTEN

**J1's C-6 line was wrong about the inventory, not about migration.** The
pre-change run failed `testEveryShippedModelVersionMigratesToTheCurrentModel` on
**one assertion only**: *10 versions found, 11 expected*. **I miscounted:** the
compiled `MOTIVO.momd` holds **10** `.mom` files (V2, V3 (7.5), V4, V4 HARDENED,
V5–V9 and the original unversioned `MOTIVO`); `MOTIVO V9.omo` is Xcode's
optimised copy of V9, and I counted it. **No version failed to load or failed
the compatibility check**, so the stop condition as defined — a version failing
to migrate — was **not** met.

**Absence of failure was not accepted as evidence.** Before relying on it the
test was tightened: the expected count is **10**; the run must **positively
observe** every version migrate (collected and compared to the inventory); and
a **positive control** builds a store from the current model with one attribute's
type changed String→Int64 and requires production's configuration to **REFUSE**
it — so a harness that cannot fail cannot pass. **C-6 is closed only if all
three hold.** Count now **214** (J4's 213 + the control).

**J5 — no device acceptance for any row.** C-20 and C-21 are compile-time
properties with identical runtime behaviour. C-16's failure branch cannot be
produced on a device, and its success path is proven by the path test. C-6's
evidence is the migration test, which runs on the simulator.
