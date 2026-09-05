# P4-U8 — D-1, D-2, C-32 AND APP STORE DISCLOSURES. COMPLETE 2026-09-05

**Prediction `57ab5fa`, committed before any edit.** Copy and disclosure
alignment only — **no architecture, no behaviour change, no production change.**

---

## 1. D-2 IS DISSOLVED. NOTHING WAS IMPLEMENTED FOR IT

D-2: *"Notes on unshared sessions uploaded unless separately marked private."*

**It cannot occur, on two INDEPENDENT grounds:**

1. **An unshared session produces no server row at all.** `op` is derived from
   `isPublic` so the contradictory state does not compile (U2c amendment);
   `uploadPost` is the only writer and sits behind an `.unshare` guard (U2b/U2c);
   and `posts_insert_owner` carries `AND (is_public = true)` (U2s). No row, so
   nothing for notes to attach to.
2. **Even on a SHARED session, private notes are never uploaded.**
   `patchPostMetadata` writes `meta["notes"] = NSNull()` when `areNotesPrivate` —
   it **force-clears** rather than omitting, so a stale server value is removed
   too.

**Ground 2 is the one easy to miss**, because D-2 as written concerns only
*unshared* sessions and the shared-only architecture answers exactly that. The
adjacent case was already correct, independently.

**Disposition: Resolved by dissolution, zero code.** Implementing anything here
would have been implementing a row rather than a defect.

---

## 2. WHAT THE COPY SAID, AND WHAT IT SAYS NOW

**Measured first** (`AddEditSessionView:1829`):
`isPublic = isThoughtMode ? false : !fetchDefaultPostingIsPrivate()`, and
`defaultPrivacy` defaults to `false` → **a session defaults to Share ON.**

| where | was | now |
|---|---|---|
| `AboutEtudesView` | *"Études is private by default. If you choose to enable Études Connected, sharing remains **entirely intentional**."* | *"…nothing leaves your device unless you enable Études Connected. In Connected, **sessions are shared with your followers by default**; you can turn sharing off for any session, or make private the default in **Profile → Default to Private Posts**."* |
| `AboutEtudesView` | (no mention of Thoughts) | *"**Thoughts start private**, though you can choose to share one."* |
| `ConnectedIntroductionView` | *"You decide what to share, and what remains private."* | …plus *"Sessions are shared with your followers by default — you can turn sharing off for any session, or make private the default in your profile."* |
| `ProfileView` — the toggle | **no explanatory text at all** | *"When on, new sessions start with sharing off. Thoughts always start private. You can change sharing for any individual session."* |

**Claims deliberately RETAINED because they are accurate**, each verified rather
than assumed:

| claim | evidence |
|---|---|
| "Études is private by default" (Études **proper**) | Solo uploads nothing |
| "Attachments are private by default" | `AttachmentPrivacy.isPrivate` returns `map[key] ?? true` |
| "Notes and attachments can remain personal even when a session is shared" | §1 ground 2 |

---

## 3. THE SENTENCE THAT WAS NEARLY WRITTEN AND IS FALSE

**"Thoughts are never shared" would have been wrong.** Brace analysis of
`AddEditSessionView` shows the "Share with followers" toggle at `:1123` is
enclosed only by the view and its content stack, guarded by
`appModeManager.canShareWithFollowers` and **not** by `!isThoughtMode`. In
Thought mode the toggle **is present**, merely initialised off.

**So Thoughts DEFAULT to private; they are not structurally unshareable.**
Writing the stronger sentence would have been the exact failure C-32 and D-1
exist to prevent — **copy claiming more privacy than the app delivers** — and it
is now pinned by `U8-A1`, which forbids the phrase in source.

**D-1's own wording, *"note that Thoughts default to private"*, was correct all
along.** The assumption that needed checking was mine.

---

## 4. APP STORE DISCLOSURES — CONTENT PRODUCED, NOT APPLIED

`docs/app-store-privacy-disclosures.md` maps every category to the code or
schema that produces it: identifiers, name, email, shared-session content,
explicitly-included attachments, comments, follows, purchase history, and the
`shadow_enforcement_stat` telemetry. It states what **never** leaves the device,
and answers tracking explicitly — **no third-party analytics, advertising,
attribution or crash SDKs exist in the source**, searched rather than assumed.

**The labels have NOT been entered in App Store Connect. I cannot do that, and
the document says so.** It remains a Phase 4 exit obligation.

---

## 5. GATES

| gate | result |
|---|---|
| `u8-acceptance.sh` | **24 passed, 0 failed** |
| Debug / Release | **BUILD SUCCEEDED** / **BUILD SUCCEEDED** |
| `MOTIVOTests` | **TEST SUCCEEDED**, **49 passed** |
| `u2a / u2a2 / u2b / u2c / u2s` | 16 / 22 / 16 / 20 / 12, **all 0 failed** |
| `u1-baseline` | 10 passed, 6 failed — the standing expected inversions |
| `u5-client-acceptance` | **28 passed, 2 failed — time-scoping, NOT regression. See below** |
| production | untouched; no SQL |

**Discriminator:** run against the pre-U8 copy the suite fails **8** — every
required statement absent and the two misleading ones present. `U8-A1` passes in
**both** worlds, correctly: a "must not say" assertion should never have flipped.

### The two u5-client failures are the suite-pinning policy, not a regression

`U5c-3` ("ProfileView, PracticeTimerView and AuthManager byte-untouched since
`dfba1d8`") and `U5c-10` ("no SQL/schema/migration change since `dfba1d8`") are
**time-scoped to U5's own baseline**. U8 legitimately edited `ProfileView`'s
copy, and U7 legitimately added migrations and moved the schema snapshot.

**Verified rather than argued: the suite returns 30 of 30 against its own commit
`7744027`** in a detached worktree. Neither assertion was weakened — this is the
same disposition already recorded for `u1-baseline`.

---

## 6. WHAT U8 DID NOT DO

- **No behaviour change.** Pinned by `U8-D1`–`D4`: only the three copy files
  changed under `MOTIVO/`, no line touches network, persistence or the sharing
  flag, no SQL, and no test was altered to accommodate the copy.
- **Did not close C-32**, whose cell is **4 / RC**. U8 owns *accuracy against
  shipped behaviour*; final customer-facing polish stays RC's.
- **Did not enter App Store Connect labels.**
