# Account ID behaviour audit — 20 September 2026

Audited source at `05ad6a8`. Read-only code/schema review; no app implementation, production queries, device actions, new test runs, or commits performed. HEAD and locally recorded origin both pointed to that commit; no live remote check was made. SQL findings describe the checked-in implementation, not a fresh production measurement. Recommendations below are not implementation approval or Phase 6 closure.

## Overall recommendation

Keep the handle independent of subsequent display-name changes. Allow deliberate handle changes rather than locking a name-derived handle permanently. Present it as **Username** or **Connected handle**, since the actual stable account identity is a UUID. Improve creation completion, editing clarity and search before expanding its role into invitations or public links.

## What it does today

- Generation uses the existing server directory row's display name. `Samuel Dixon` becomes `samueldixon`; `@` is presentation only. Diacritics and full-width characters are folded, then everything except ASCII a–z, digits and underscore is removed; the result is capped at 24 characters and must have at least three.
- If occupied, generation tries the base followed by suffixes 2 through 10, shortening the base to fit. There are ten candidates total, not an unlimited allocator.
- Generation refuses to overwrite either a nonempty local handle or an existing server handle. The write itself requires `account_id IS NULL`, protecting against an intervening server change.
- Changing an established member's display name does **not** regenerate the existing handle. The directory update sends the existing local handle alongside the new name. Example: Samuel Dixon → Sam Dixon leaves `@samueldixon`.
- The Profile field is editable. Valid new handles are submitted on Return or leaving the field. There is no handle-specific rename interval, lifetime lock, old-name reservation or alias history in the inspected implementation. The database enforces uniqueness, lowercase and the 3–24 character format.
- Posts, follows and sharing use UUIDs, rather than the handle, for identity. A handle rename therefore does not itself change ownership or the follow graph. Existing cached labels can take time to refresh; directory cache TTL is 20 minutes.
- Account-free Solo has no handle field. **The newly accepted C-70 code also shows the field to an existing Connected identity while lapsed into Solo**, provided the backend is configured. Owner maintenance and automatic generation have different gates; generation stays Connected-only.
- Handles appear on other people's profile previews and attribution/connection surfaces. People search supports a handle prefix as well as name/instrument matching, but its placeholder only advertises name or instrument. Privacy and membership controls still determine discoverability; knowing a handle does not bypass them.

## Findings

### 1. The displayed @handle does not match the search input contract

`PeopleView.performLookup` and `AccountDirectoryService.search` trim whitespace only. The latest B-37 SQL lowercases/splits/escapes tokens but does not strip `@`. Its handle branch compares against the stored value without `@`.

Consequently `samueldixon` can match the handle while `@samueldixon` cannot match that branch. Other fields could coincidentally match the latter text; the finding is not that every such query necessarily returns zero rows.

**Recommendation:** accept a leading `@` for handle lookup, advertise username search, and preserve literal wildcard handling, budgets and privacy gates. Do not weaken the B-37 protections while fixing input semantics.

Evidence: `PeopleView.swift:607`, `AccountDirectoryService.swift:419`, `20260920130000_b37_literal_search_and_budget.sql:189,287`.

### 2. The editor conflates an unconfirmed draft with the current handle

Every edit is written immediately to `ProfileStore`, before server acceptance. Blank or one/two-character handles are omitted from the remote payload, preserving the previous server handle. A successful update can therefore clear error feedback while the field remains blank/too short and the server still holds the old handle. Generation will not repair this by replacing an existing server value.

A taken valid handle receives explicit collision feedback, which is good, but the rejected value stays in the local store. Because later name/location/instrument updates include that same draft handle in the whole-row update, its collision can also prevent those changes reaching Connected. Local name persistence is separate and can still succeed.

**Recommendation:** distinguish confirmed handle from editable draft. Use explicit Save/Cancel for this identity-facing field, show format errors before submission, and explain collision/failure without presenting the draft as confirmed. Do not allow an invalid handle draft to silently block unrelated profile changes. Preserve the draft for correction rather than discarding it without explanation.

Evidence: `ProfileView.swift:774–813,1784–1808,1937–1957`; `ProfileStore.swift:150–167`; `AccountDirectoryService.swift:677–685`.

### 3. Joining does not guarantee assignment

The generator explicitly returns an optional result. Names reducing to fewer than three allowed characters (for example `Li`, or entirely non-Latin names), ten occupied candidates, missing rows and network errors can all return nil. `AppSetUpView` proceeds to `onComplete()` even when generation returns nil, after its session checks. Background backfill and ProfileView each have attempt suppression; these are best-effort recovery paths, not a completion guarantee.

**Recommendation:** preserve automatic name-based assignment for the common case, but provide an explicit fallback/choice and recoverable status when no handle is assigned. A member should not have to discover the omission later. International names need a supported fallback rather than a silent failure.

Evidence: `AccountDirectoryService.swift:178–198,776–860`; `AppSetUpView.swift:375–400`; `AuthManager.swift:639–681`; `ProfileView.swift:1962–2019`.

### 4. Another device can republish an older handle

The already-hydrated AuthManager path republishes its local snapshot without first re-reading the directory. That snapshot includes the local handle; the owner update has no expected-old-handle or version condition. Thus device B retaining the old value can overwrite a rename made on device A when B later republishes. This is a code-path risk, **not a device-reproduced result**. Per-device write ordering does not establish cross-device ordering.

**Recommendation:** publish a handle change only as explicit handle intent, with server-side conflict handling for concurrent changes. Routine name/location/profile publication should not reassert a cached handle.

Evidence: `AuthManager.swift:615–625,779–846`; `AccountDirectoryService.swift:665–705`.

### 5. Rename continuity needs a product decision

The inspected schema has a unique current `account_id`, not a historical handle registry. Renaming releases the old value for another eligible account to claim. Combined with unrestricted rename frequency, this can confuse people searching by a previously shared handle. It does not transfer followers or posts, because those use UUIDs.

**Recommendation:** keep handles editable for corrections, stage names and privacy needs, while making a change deliberate. Before promoting handles for durable invitations/links, decide old-handle reuse/reservation and any modest rename limit. Those controls would need server enforcement; a UI restriction alone is insufficient. Do not invent public links or expand the invitation scope as part of this audit.

## Suggested order

1. Fix @ search and make confirmed versus draft handle state truthful.
2. Prevent unrelated profile updates and other devices from overwriting/retrying a handle without explicit rename intent.
3. Make initial assignment/fallback reliable and understandable.
4. Set rename/reuse policy before making handles a stronger external discovery or invitation mechanism.

The current stable UUID underneath an editable public handle is the right foundation. The main deficiencies are the handle's creation/editing lifecycle and discoverability, not the decision to keep it independent of the display name.
