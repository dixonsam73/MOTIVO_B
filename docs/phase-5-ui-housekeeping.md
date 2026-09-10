# PHASE 5 — UI HOUSEKEEPING BACKLOG

Small presentation items logged during other work. **None is to be implemented
while CP-3 acceptance is in flight.**

---

## H-1 · ProfileView: group the Connected privacy controls into their own section

**Logged 2026-09-08 from on-device observation in Connected mode. NOT
IMPLEMENTED. Do not implement during CP-3 acceptance.**

**Observed:** the two Connected privacy controls sit inside the ordinary Études
Settings list and interrupt it —

- `Default to Private Posts`
- `Let other members find you`

**Proposed organisation:**

```
Settings
  Instruments
  Activities
  Journal Tint
  Tasks
  existing Show… controls

Connected            (shown only when applicable)
  Default to Private Posts
    helper text
  Let other members find you
    helper text

Account
  Manage Membership
  Sign out
  Delete Account & All Études Data
```

**Section naming, decided rather than left open:**

- **"Connected", not "Privacy".** These are preferences governing *participation
  in Études Connected*, and the name gives future Connected-specific preferences
  an appropriate home. "Privacy" would both overclaim and crowd out that space.
- **"Account" stays as it is.** It already describes membership, authentication
  and account-management actions cleanly; "Connected Account" adds nothing.

**SCOPE — PRESENTATION AND ORGANISATION ONLY.** The move must not change:

- the controls' behaviour;
- privacy semantics;
- hydration or the writers behind either control — `Let other members find you`
  must keep going through `AccountPrivacyService.setLookupEnabled`, the **only**
  client writer of the discovery preference;
- visibility rules — `Default to Private Posts` stays behind
  `appModeManager.canShowConnectedAccountManagement`, and the discovery toggle
  stays behind `auth.accountPrivacyState != nil`, which exists because without a
  server band the writer would refuse and the control could not work;
- the copy, which was revised on 2026-09-08 and is pinned by `U8-B5`/`U8-B6`.

**A pure move should leave `u8-acceptance` at its current score.** If it does
not, the change was not a pure move.


---

## H-2 — the directory-sync failure message sits under the Account ID field

**Logged 2026-09-09 from C-70(a). LOGGED ONLY — NOT A REOPENING OF C-70(a),
which is resolved.**

`ProfileView` has exactly one presentation site for a directory-write failure,
and it renders **beneath the Account ID `TextField`** (`:668`). C-70(a) fixed the
*text* — a generic failure no longer names a field — but a `name`, `location` or
instrument-list failure still appears in that position, so the **placement**
continues to hint at a field the member did not touch.

**Deliberately not fixed there.** Moving it needs a second presentation surface
in `ProfileView`, which is a broad error-handling redesign; C-70(a) was scoped
to forbid exactly that.

**Size:** small. **Risk if left:** cosmetic mis-suggestion only — the words are
truthful. **Owner:** unassigned; a candidate for any future `ProfileView` pass,
alongside H-1.


---

## H-1 — COMPLETE 2026-09-10. AUTHORITATIVE DISPOSITION.

Profile is now **Settings · Connected · Account**.

1. **Presentation visually accepted.**
2. **`Default to Private Posts` device-verified** in the Connected section.
3. **`Let other members find you` relocation structurally verified, with its
   visibility gate preserved BYTE-FOR-BYTE** — machine-compared against
   `c2c4719`.
4. **The discovery control was NOT device-visible under synthetic Force
   Connected**, because that fixture lacks the legitimate backend
   identity/session/band state `accountPrivacyState` requires. **Correct
   behaviour, not a defect.**
5. **Legitimate Connected device verification is CARRIED** to the future
   Production Connected fixture.

**THE GATE MUST NOT BE WEAKENED OR ALTERED.** Full analysis:
`docs/phase-5-h1-discovery-control-classification.md`.

The move itself is provably verbatim — every removed line reappears
byte-identical except the wrapper `if` that became the section's own gate —
bindings and the sole discovery writer are unchanged, and Solo renders no empty
"Connected" header.
