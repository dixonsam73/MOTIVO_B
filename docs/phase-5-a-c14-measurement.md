# P5-A / C-14 — MEASUREMENT BEFORE SCOPING. 2026-09-06

**Measured at `5cfcd58`. NOTHING IS IMPLEMENTED. No code changed.**

C-14 reads *"Backend user IDs and handles logged via NSLog in release"* — P3,
**Confirmed defect**. This unit's first obligation was to **measure the exposure
before scoping the fix**, because CLAUDE.md already records that `NSLog` with
`%@` arguments arrives as `<private>` when read from a device. The measurement
changed the unit's shape substantially, so it is recorded before any edit.

---

## 1. THE HANDOVER PREMISE IS WRONG ABOUT WHERE THE EXPOSURE IS

The working premise entering this unit was *"concentrated in `AuthManager`
(~10 sites logging `user=%@` with the Supabase user id), plus `FollowStore:201`;
105 `NSLog` sites overall"*.

**`AuthManager` contributes ZERO shipping sites.** All **38** of its `NSLog`
calls sit inside `#if DEBUG`. Verified twice by independent methods: a
preprocessor-nesting parse, and then — because a parser's own success is not
evidence — by listing every `#if`/`#endif` pair and every `NSLog` line number in
the file and confirming each of the 38 falls strictly inside a `DEBUG` pair.

**The count of 105 is right and nearly all of it is irrelevant to C-14.**

---

## 2. THE MEASURED POPULATION

| measure | count |
|---|---|
| `NSLog` occurrences in `MOTIVO/` | **105** |
| of those, comments not call sites | 2 |
| real call sites | **103** |
| inside `#if DEBUG` — **do not ship** | **43** |
| **ship in Release** | **60** |
| shipping sites logging a **backend user ID** | **8** — all in `FollowStore` |
| shipping sites logging a **handle / display name / email** | **0** |

**The "and handles" half of C-14 has no shipping instance at all.** No Release
`NSLog` emits a display name, handle or email address.

### The 8 identifying sites, and why none is plainly reachable

- **`FollowStore` 201, 224, 256, 290, 316** — `request`, `approve`, `decline`,
  `removeFollower`, `unfollow`. Each sits on the **local-simulation branch**,
  after an early `return` taken when `isBackendHTTPActive`. They are called from
  real UI (`PeopleView:456/474`, `ProfilePeekView:306/385`,
  `FollowersListView:142`), so they are **not dead code** — but reaching them
  needs the Connected follow UI under a **non-Connected backend mode**.
- **`FollowStore` 368, 382, 393** — `simulate*`. Their **only** callers are
  `DebugViewerView:1004/1009/1019`, and that file is `#if DEBUG` from line 13 to
  its `#endif` at line 1389, the last line. **Unreachable in Release.**

### `PublishService`'s `owner=%@` is not a user ID in Release

`PublishService:32` and `:398` log `ownerKey`. Its **only** writer is
`setOwnerKey`, whose only callers are `DebugViewerView:1087/1093/1099/1106`.
In a Release build nothing ever writes `UserDefaults` key
`PublishService.ownerKey`, so `ownerKey` resolves to its literal fallback
**`"local-device"`**. `:398` is unreachable; `:32` logs a constant.

**The declared intent and the shipped reality differ**, which is the part worth
keeping: the property is documented *"Provided by app layer"* and its example is
*"user UUID"*. It is a user UUID **only in Debug**. Anyone auditing this by
reading the declaration would record a Release exposure that does not exist.

### Backend mode in Release is two-valued

`setBackendMode` has four app-target callers: `MOTIVOApp:95`
(`.localSimulation`, at launch before `AuthManager` initialises),
`AppModeManager:49/51` (`.localSimulation` for Solo, `.backendConnected` for
Connected), and `BackendModeSection:26` — whose only instantiation is
`DebugViewerView:892`, so **the manual mode picker is not reachable in Release**.

---

## 3. REDACTION — WHICH SITES ARE ACTUALLY READABLE

Swift interpolation and format arguments behave **differently**, and the
difference decides the exposure:

- `NSLog("… %@", value)` — a real format argument. Per **this project's own
  recorded TestFlight measurement** (CLAUDE.md, the `MembershipTrace` lesson),
  these arrive as **`<private>`** when read from a device.
- `NSLog("… \(value)")` — Swift interpolates **before** `NSLog` sees it, so the
  value is baked into the format string and **no redaction applies**.

| shipping sites | count |
|---|---|
| use `%@` / `%d` format args — redacted on device | **52** |
| use Swift interpolation — **not** redacted | **8** |

**All 8 identifying sites use `%@`.** All 8 interpolated sites carry no
identifier — a filename (`AttachmentPrivacy:243`), a factory-reset reason
(`LocalFactoryReset:30/37/40`), a container path (`PracticeTimerStore:151`,
`StagingStore:530`) and error descriptions (`LocalFactoryReset:131`,
`ProfileStore:300`).

**So the two sets do not overlap: nothing that carries an identifier is readable
on device, and nothing readable on device carries an identifier.**

**NOT RE-VERIFIED TODAY.** The redaction behaviour is taken from the project's
existing measurement, not re-measured on hardware for this unit. It is recorded
as inherited evidence, not as a fresh observation.

---

## 4. WHAT THIS DOES AND DOES NOT CHANGE

**C-14 is not withdrawn and its P3 severity stands.** The app does write backend
user IDs into the unified logging system on a reachable-in-principle path, and
redaction is a **default**, not a guarantee — it can be disabled system-wide by
a logging configuration profile. Writing an identifier and relying on the OS not
to show it is a weaker position than not writing it.

**What changes is the size and the location of the fix.** It is **8 lines in one
file**, not a sweep of 105 sites, and `AuthManager` — where the effort was
expected to go — needs no change at all.

## 5. ONE FINDING OUTSIDE C-14 AS FILED

`PublishService:294` logs, in Release, a session **`title`** together with
`mood`, `effort`, `duration` and `activityType`. That is **user content, not
identity**, so it is outside C-14's stated scope and is **not** fixed under it.

It is recorded here rather than acted on because the same line shows deliberate
care in the opposite direction — it logs `notes=present/nil`, never the note
text. Someone drew the line at notes and left titles. **Whether a session title
belongs in the log deserves its own decision**, taken deliberately, not folded
silently into C-14.
