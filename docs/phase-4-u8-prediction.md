# P4-U8 — D-1, D-2, C-32 AND APP STORE PRIVACY DISCLOSURES. PREDICTION

**Committed BEFORE any edit.** Accepted checkpoints: U7 `51ee7fa`,
device QA `3def222`.

**This is a copy/disclosure alignment unit. No architecture, no behaviour
change.** The behaviour was settled by U2–U7; U8 makes the words match it.

---

## 1. D-2 HAS DISSOLVED. NOTHING WILL BE IMPLEMENTED FOR IT

D-2: *"Notes on unshared sessions uploaded unless separately marked private."*

**It cannot occur, on two INDEPENDENT grounds, both verified in source:**

1. **An unshared session produces no server row at all.** `op` is derived from
   `isPublic` so `.publish + isPublic:false` does not compile (U2c amendment);
   `uploadPost` is the only writer and sits behind an `.unshare` guard; and
   `posts_insert_owner` carries `AND (is_public = true)` server-side (U2s). With
   no row, there is nothing for notes to be attached to.
2. **Even on a SHARED session, private notes are never uploaded.**
   `patchPostMetadata` writes `meta["notes"] = NSNull()` when
   `payload.areNotesPrivate` — it does not merely omit them, it **force-clears**,
   so stale server notes are removed too.

**Ground 2 is the stronger one and is easy to miss:** D-2 as written is about
*unshared* sessions, and the shared-only architecture answers exactly that. But
the adjacent question — private notes on a *shared* session — is answered
separately and was already correct.

**Predicted disposition: D-2 → Resolved, dissolved under shared-only uploads,
zero code.** Anything else would be implementing a row rather than a defect.

---

## 2. WHAT THE COPY GETS WRONG, MEASURED AGAINST SHIPPED BEHAVIOUR

**Verified behaviour** (`AddEditSessionView:1829`):
`isPublic = isThoughtMode ? false : !fetchDefaultPostingIsPrivate()`, and
`defaultPrivacy` defaults to **false** → **a session defaults to Share ON**.

| # | claim, and where | verdict |
|---|---|---|
| A | *"Études is private by default."* — `AboutEtudesView:21` | **accurate** for Études proper: Solo uploads nothing |
| B | *"...sharing remains entirely intentional."* — same sentence | **MISLEADING.** Share defaults **ON**, so a session shares unless the member turns it off. Reads as opt-in |
| C | *"You decide what to share, and what remains private."* — `ConnectedIntroductionView:113` | **incomplete** — true, but silent on the default |
| D | *"Attachments are private by default..."* — `AboutEtudesView:55` | **accurate** — `AttachmentPrivacy.isPrivate` returns `map[key] ?? true` |
| E | *"Notes and attachments can remain personal even when a session is shared."* | **accurate** — see §1 ground 2 |
| F | the sharing default follows a preference, and where to change it | **ABSENT everywhere** — D-1 requires it |
| G | Thoughts default to private | **ABSENT** — D-1 requires it |
| H | `ProfileView:692` "Default to Private Posts" | **no explanatory text at all** |

### THE ONE THING THE COPY MUST NOT SAY, AND WHY IT WAS NEARLY WRITTEN

**Thoughts DEFAULT to private; they are NOT structurally unshareable.** Brace
analysis of `AddEditSessionView` shows the "Share with followers" toggle at
`:1123` is enclosed only by the view and its content stack, guarded by
`appModeManager.canShareWithFollowers` and **not** by `!isThoughtMode` — so in
Thought mode the toggle is present, merely initialised off.

**"Thoughts are never shared" would therefore be FALSE**, and writing it would be
the exact failure C-32 and D-1 exist to prevent: **copy claiming more privacy
than the app delivers.** D-1's own wording — *"note that Thoughts default to
private"* — is correct, and is what will be written.

---

## 3. SCOPE — FOUR FILES, COPY ONLY

| file | change |
|---|---|
| `AboutEtudesView.swift` | correct B; add F and G |
| `ConnectedIntroductionView.swift` | complete C with the default and the preference |
| `ProfileView.swift` | a short explanatory footer under the toggle (H) |
| `docs/app-store-privacy-disclosures.md` | **new** — the disclosure content |

**App Store privacy labels live in App Store Connect, which I cannot change.**
U8 produces the content and the mapping to shipped behaviour; **applying it in
ASC is an account-holder action** and will be listed as an outstanding exit
obligation, not silently claimed.

---

## 4. PREDICTIONS

| # | prediction |
|---|---|
| **P1** | D-2 requires **zero** code and is dispositioned Resolved-by-dissolution |
| **P2** | **No behavioural change.** Every Swift edit is a string literal or a new `Text`; no control flow, no persistence, no network |
| **P3** | Debug + Release build; `MOTIVOTests` unchanged at **49 passed** |
| **P4** | Every claim in the revised copy maps to a behaviour verified in this unit — recorded as a claim → evidence table |
| **P5** | The copy does **not** say Thoughts are "never" shared, and does **not** describe Connected as private-by-default |
| **P6** | Standing suites unchanged: u6b 64/0, u7 26/0, u2* and u5-client all 0 failed |
| **P7** | No production change; no SQL |

---

## 5. WHAT U8 DOES NOT DO

- **No architecture.** The shared-only design is settled and is not reopened.
- **Does not close C-32.** Its cell is **4 / RC**: U8 owns making the copy
  *accurate* against shipped behaviour; final customer-facing polish stays RC.
- **Does not apply App Store Connect labels.**
