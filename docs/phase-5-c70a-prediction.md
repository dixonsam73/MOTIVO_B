# C-70(a) — INSPECTION AND PREDICTION, COMMITTED BEFORE MUTATION

**Unit:** P5 / C-70(a) — a generic directory-profile update failure falsely
identifies Account ID as the field that failed.
**Inspected at:** `3edf5fb`, 2026-09-09. **Scope:** `MOTIVO/ProfileView.swift`
and one new pure file. No backend, no migration, no production, no ASC, no
enforcement, no device or age-state mutation.

---

## 1. The defect, with its trigger set enumerated

`syncDirectoryFromCurrentState()` (`ProfileView:1471`) posts **one** row
carrying `display_name`, `account_id`, `location` and `instruments`. Its only
failure presentation is:

```swift
if isAccountIDCollision(error) {
    accountIDSyncMessage = "That account ID is already taken."
} else {
    accountIDSyncMessage = "Couldn’t update your Account ID. Please try again."   // :1524
}
```

**FIVE entry points reach that line, and only two involve the Account ID:**

| # | Trigger | Site | Account ID involved? |
|---|---|---|---|
| 1 | Account ID field **blur** | `:650` | yes |
| 2 | Account ID field **submit** (Return/Done) | `:656` | yes |
| 3 | **`name`** edited → debounced sync | `:2051` | **no** |
| 4 | **`locationText`** edited → debounced sync | `:2063` | **no** |
| 5 | **Instrument manager dismissed** → debounced sync | `:2105` | **no** |

So editing a display name, a location, or the instrument list and hitting any
non-collision failure produces a **red message under the Account ID field
blaming the Account ID** — a field the member did not touch. That is the defect,
now verified with its full trigger set rather than inferred from the one call
site the trace named.

**The message is rendered directly beneath the Account ID `TextField`**
(`:668`), which is why the misattribution is doubly legible on screen.

---

## 2. Is a more specific field-aware error cheaply available? PARTLY — reported, not adopted

`account_directory` carries **three** `account_id`-specific constraints:

| Constraint | Kind | Wire signature |
|---|---|---|
| `account_directory_account_id_key` | UNIQUE | 409 / `23505` — **already detected**, `isAccountIDCollision` (`:1634`) |
| `account_id_format` | CHECK (3–24 chars, `^[a-z0-9_]+$`) | 400 / `23514`, names the constraint |
| `account_id_lowercase` | CHECK | 400 / `23514`, names the constraint |

**So yes, two further Account-ID-attributable errors are cheaply detectable by
exactly the body-substring technique already in use. They are deliberately NOT
implemented, and the reason is the point of this unit.** The client normalises
input through `normalizeAccountID` and only sends `account_id` when
`acct.count >= 3`, so **neither CHECK is reachable through the shipping UI**.
Writing user-facing copy for an unreachable branch would be inventing handling
for a case nobody has observed — the opposite of what this unit is correcting.
**Recorded here so the next person knows the capability exists** rather than
rediscovering it.

**Everything else the backend returns is a whole-row failure it cannot attribute
to a field** — auth, network, RLS refusal, the CP-1 band trigger, the
`enforcement_gate`. For those the only truthful presentation is a generic one.

---

## 3. PREDICTION — committed before implementation

**P1.** Exactly **two** failure outcomes survive. A `23505` /
`account_directory_account_id_key` collision keeps its existing copy verbatim —
*"That account ID is already taken."* Every other failure produces a message
that **names no field**.

**P2.** The generic message becomes *"Couldn't update your profile. Please try
again."* It is truthful for all five triggers, and it invents no attribution the
backend cannot support.

**P3.** The classification moves out of the view into a **pure** type in its own
file, so it can be unit-tested directly — `PlaybackRate.swift`'s precedent. The
view keeps the presentation; it stops owning the decision. `isAccountIDCollision`
is not duplicated, it is **relocated**, so there is no second copy to drift.

**P4.** No behaviour changes other than the message text: the same triggers fire
the same sync, success still clears the message, editing the field still clears
it, and `accountIDSyncIsError` still drives the red colour.

**P5.** The state is renamed `directorySyncMessage` / `directorySyncIsError`.
**This is a rename, not a redesign** — the render site, the trigger set and the
lifecycle are untouched, and the compiler proves the rename complete. It is
included because **the variable name is itself the false attribution**, and the
name is what the next person implements from (the D14 lesson: correct a
finding's reasoning, not only its fix).

**P6.** Focused unit tests cover: collision → the collision copy; a non-collision
`httpError` → the generic copy; a non-`NetworkError` error → the generic copy; a
409 with an unrelated body → generic; and **that no message this unit can
produce contains the words "account id"** except the collision one. Debug and
Release clean. Full suite green, counted from the **structured** result via
`scripts/test-census.py`, never from console `passed` lines. Warning delta zero.

### What this unit does NOT do — stated so it is not read as done

**The message's PLACEMENT is unchanged and remains a residual.** A generic
failure still renders beneath the Account ID field, because that is the only
presentation site this state has. The text no longer *asserts* a false field,
but position still *hints* at one. Moving it needs a second presentation surface
in `ProfileView`, which is exactly the broad error-handling redesign this unit
is forbidden to attempt. **Named here, not silently absorbed.**

**C-3, C-5, C-62, C-63, C-65, C-66, C-68, C-69, C-71 and the C-20
re-verification stay out.** So does anything about C-70's dominant observation,
which is dispositioned and closed to further work until a legitimate Production
Connected path exists.
