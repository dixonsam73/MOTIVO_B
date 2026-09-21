# Lapsed-member profile maintenance — device QA

21 September 2026. Samuel reported the subscription expired, the app remained in Solo, and the existing profile name remained Ben Craft. Before any erase/rejoin, he changed location to `London QA`, saw no error, closed/reopened the app and confirmed the location persisted.

Codex independently performed a read-only linked Supabase query at **08:29:29 UTC**. Exactly one matching directory row was returned:

- User: `6fd0a833-9e12-4dbb-a8e4-b4b01f706ea2`
- Display name: `Ben Craft`
- Location: `London QA`
- `entitled_until`: **08:17:28 UTC**, 21 September 2026
- `entitled_until > now()`: **false**

**PASS for this scenario:** existing-owner location maintenance in Solo after natural subscription expiry, local persistence after app reopening (Samuel's observation), and matching server directory state while server entitlement was expired (independent read).

Limits: no request-level trace or before-write server snapshot captured; no forced expired-token/401 recovery demonstrated; no name edit exercised; no fresh onboarding/join exercised. This is not blanket device coverage or Phase 6 closure. No database mutation performed by Codex. Samuel separately reported other handle-removal device QA green, with fresh onboarding/join still outstanding at this checkpoint.

## Fresh join follow-up — not yet passed

Samuel erased the previous account data, onboarded as Clara (requested test details Clara Reed / Bristol / Cello), and reported inactive subscription before joining. Read-only pre-join checks found no former Ben Craft directory row and no Clara row; copied device preferences showed Bristol and `backendMode_v1 = localSimulation`.

After joining, Samuel reported SIWA first, needing to enter Explore Connected again, then returning to Profile with the new details and the red message “We couldn’t confirm your profile changes were saved to Connected.” He had not refreshed the feed or otherwise interacted after the warning.

Read-only server inspection found a new identity `ab4b1b0e-fb1a-4a57-9e78-9e8fd4cabc3d`, created `2026-09-21 08:44:09.757503+00`, `connected_member = true`, provenance `sandbox_only`, and no directory row. The directory contained only the other existing test profile at inspection. Deployed account-ID CHECK constraints explicitly permit NULL; directory INSERT is membership-gated, whereas owner UPDATE is not. These observations do not establish the failed request's cause or membership state at request time. A timing issue remains a hypothesis, not a finding. No backend mutation performed. Fresh join must not be scored green on this evidence.

### Recovery after reopening Profile

Samuel closed and reopened Profile without editing, then reported the red warning gone and details intact. A subsequent read-only server query confirmed the new identity remained `connected_member = true` and now had a directory row: **Clara Reed / Bristol / [Cello]**. This demonstrates recovery following reopening, not merely disappearance of the view's error message. It does not establish the initial failure's cause, nor prove reopening was the only possible recovery trigger. Initial fresh-join warning and repeated Explore Connected step remain unresolved; fresh-join UX is not scored clean.

### Investigation started with Claude

Samuel authorised joint investigation. Codex sent the complete successful/failed QA report to the existing Claude “Account ID/handle removal discussion” task; Claude acknowledged and began tracing both issues, with scope review required before implementation.

Independent source findings: `signedOutGateView.onAppear` unconditionally sets `signedOutGateWasVisible`; the sign-in completion handler tests that flag and returns before its `.join` continuation branch. The shared view is also presented for join SIWA. This is a concrete control-flow conflict consistent with the observed interruption, pending lifecycle reproduction. Separately, Profile name/location hydration can schedule owner maintenance once authenticated, before membership establishment; missing-row creation is membership-gated. The join completion callback unwinds navigation without explicitly reconciling the directory. An early refused creation followed by no post-attestation resubmission is a hypothesis to reproduce, not an observed request trace. Codex shared both findings and required preserving lapsed-owner PATCH, real failure reporting, identity/freshness guards, and avoiding arbitrary delay-based fixes.

## F1/F2 updated-build fresh join — Daniel Brown, 2026-09-21

Samuel reported subscription inactive, onboarding completed, then Connected join: SIWA led directly to subscription choices, monthly selected, returned to Profile with no warning. F1 navigation observation PASS; absence of warning alone does not score directory publication.

Codex read-only server check after that report found no Daniel Brown directory row. Direct recent-identity check found new identity `ee32dfe0-7fc0-4f3c-be5a-746f0e2b54c0`, created `2026-09-21 10:46:17.943582+00`, `connected_member = true`, `has_directory_row = false`. Display/location/instruments null in this LEFT JOIN mean directory row absent, not user-entered fields cleared. Thus F2 fresh-join publication is NOT passed despite clean UI. Samuel has not yet been asked to reopen or edit Profile; preserve current device state for investigation. No server mutation performed.

### Daniel: controlled close/reopen recovery

While Samuel remained on Profile without interaction, a second server check at `2026-09-21 10:49:39.055831+00` still showed active membership and no directory row. Samuel then closed Profile to the timer, waited a few seconds, and reopened Profile, tapping nothing else. Read-only check at `2026-09-21 10:53:17.045119+00` found the directory row **Daniel Brown / Manchester / [Guitar]**, membership active. Recovery follows this controlled navigation; no feed refresh or edit was needed. This strongly supports a missing initial publication trigger, but does not independently identify which request created the row. F1 navigation passed; F2 initial publication remains failed despite eventual recovery and no warning. The approved F2 policy currently requires an outstanding foreground failure; a fresh join with no foreground write/failure is not covered by that condition. Further bounded investigation/fix remains required before final sign-off.

## Steve Jerkz — F3 device run

Samuel erased Device A, cancelled Sandbox subscription and explicitly confirmed inactive before onboarding Steve Jerkz / Guitar / Prague and joining on the latest build. He reported all green except first monthly purchase attempt displayed approximately “we are unable to process your membership”. He returned to Profile and tried again; second purchase worked, and he made no further interaction afterwards. Console is available for investigation.

Read-only server check at `2026-09-21 12:52:47.785215+00`: new identity `f0ba3610-ee14-4e78-b3cc-3eb7e320ccc6`, created `12:51:17.514238+00`, connected_member=true, directory row present **Steve Jerkz / Prague / [Guitar]**. Thus profile publication was evidenced without navigation/edit/feed refresh AFTER the successful purchase. This run included navigation and a second purchase attempt before success: do not label the whole join first-attempt clean, or claim the exact request/trigger that created the row was captured. First purchase failure remains unexplained pending console; no assumption it was Sandbox/vendor rather than app. No server mutation by Codex.

### Steve console review

Codex read all98 lines in user attachment `1bf61924-1eab-461d-8b70-350940038c5f/pasted-text.txt`. Contains keyboard/LaunchServices/XPC/media messages and app recovery/queue logs; no identifiable purchase outcome, StoreKit error domain/code, or attestation response for the failed attempt. Cannot attribute the purchase error to those adjacent system messages, or establish a Sandbox fault. Source review: MembershipSelectionView renders `.failed(error)` as “Purchase unavailable” plus `error.localizedDescription`; ConnectedMembershipStore catches product.purchase errors without a structured purchase-error log. Thus excerpt cannot settle the first-attempt cause. Successful membership and profile server evidence remains as recorded; clean first-attempt join remains unproven by this retry-containing run. No implementation or device action taken in this console review.
