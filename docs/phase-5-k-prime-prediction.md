# P5-K′ REMAINDER — PREDICTION, COMMITTED BEFORE MUTATION. C-66 · C-68 · C-69.

**At `25ff020`, 2026-09-10.** Each row was re-checked against HEAD first. The
dispositions were agreed with the account holder beforehand. **C-80, C-81 and
unrelated cleanup are out of scope.** C-65, the first P5-K′ row, was resolved
2026-09-09.

---

## 1. Measured state at HEAD, and what each row claimed

| Row | Mechanism at HEAD | Claimed consequence, re-measured |
|---|---|---|
| **C-66** | `unfollow`'s failure branch (`FollowStore:321-322`) only logs; `declineFollow` (`:259`) and `removeFollower` (`:296`) refresh | **Narrower than filed.** `unfollow` does not mutate `following` optimistically, so a transport or auth failure leaves the display **correct**. The stale case is **`.notFound`** — the row is already gone, and "Following" stays until another of the **nine** refresh sites fires. No error is shown; the sole caller (`ProfilePeekView:306`) discards the result. **A stuck label, never data loss** |
| **C-68** | `VideoRecorderController.onDisappear()` (`:513-519`) stops capture and deletes the recording file, and never pauses or releases `player` | **Probably never observable.** The controller is a `@StateObject`, every closure in it is `[weak self]`, observers are selector-based or `[weak self]`, so by **inspection** nothing retains it past dismissal and the player dies with it. The recorder presents nothing over itself, so `onDisappear` is terminal. **Inspection, not measured deallocation** |
| **C-69** | `remoteController.rate` is set only by `.onChange(of: playbackRate)` (`:2907`), which does not fire for a page appearing after the rate was chosen | **Accurate and unreachable.** Remote means `http(s)` (`:2730`); the only source is `BackendSessionDetailView`'s signed post URLs (`:719`), gated by `posts` SELECT with no entitled identity. Received direct sends are downloaded first (`ConnectedAttachmentShareUI:686`) and use the local path, which is correct |

**Inventory for C-69:** exactly **one** `toggle(url:)` declaration (`:2598`) and
**one** caller (`:2846`).

## 2. Dispositions (agreed)

- **C-66 — (a):** refresh on failure, matching the siblings. **`.notFound`
  semantics unchanged; no shared failure architecture; no error presentation.**
- **C-68 — (a):** pause and release the review player in `onDisappear`.
  **Narrow lifecycle hardening.** It does **not** explain C-50, and no
  user-visible failure was reproduced. **C-50 stays closed under its existing
  reopening condition.**
- **C-69 — (a):** `toggle(url:rate:)` — the rate becomes a **required** input, so
  starting remote playback cannot omit it. **Not closed:** recorded as
  implementation-complete / structurally accepted, with **real-device acceptance
  carried to the legitimate Production Connected fixture.**

## 3. PREDICTION

**K1 — the pre-change run of `ReliabilityRemainderTests` FAILS all three:**
- `testEveryFollowMutationRefreshesOnFailure` — `unfollow` carries **one**
  refresh, not two;
- `testRecorderTeardownReleasesTheReviewPlayer` — `onDisappear` neither pauses
  nor releases;
- `testRemotePlaybackRequiresTheSessionRate` — `toggle(url:)` takes no rate.

**K2 — after the change:** all three pass, plus a behavioural
`testRemoteToggleAdoptsTheGivenRate`.

**K3 — warnings unchanged: Debug 177 / Release 165.** The warning set is
identical **modulo line numbers** in `VideoRecorderView.swift`, whose many
deprecation warnings sit below the edit and shift down; nothing added, nothing
removed.

**K4 — structured census: 219 declared, 219 passing** (215 + 4).

**K5 — device acceptance.** **C-66:** not needed for a deterministic refresh,
and blocked anyway (it needs two Connected identities with an approved follow).
**C-68:** not needed and not discriminating — the pre-change build almost
certainly already stops playback on deallocation. **C-69:** genuinely the only
proof of the view wiring, and **unreachable**, so it is **carried** to the
Production Connected fixture and the row stays open.
