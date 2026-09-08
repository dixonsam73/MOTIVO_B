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
