# Invite someone to Études — proposed first-version scope

17 September 2026 · **For Samuel's review. No implementation authorised by this document.**

## 1. Recommendation

Use a private, expiring link to let its recipient **request to follow the sender**. The sender then reviews the specific Études account and approves or declines. Following back is a separate request, separately approved by the other person.

For example: Alice sends Ben a link; Ben chooses “Request to follow Alice”; Alice confirms that `@ben` is the person she intended and approves. Ben can now see what Alice shares with followers. Alice cannot see Ben's shared posts until she requests to follow him and he approves.

This extra confirmation protects against forwarding: **sending a link does not approve an unidentified future recipient**. A mutual-connection action would need two clearly explained grants and confirmation of both identities. Keep that out of version one. The trade-off is another step when both people want to follow each other.

Design the feature for all Connected members, including adults and undiscoverable members. The teen routes described below are a **proposed replacement policy**, contingent on legal review and Samuel's subsequent approval. B-40 remains in force until that replacement is ready. Neither this scope nor an adult implementation authorises weakening it.

Excluded: contacts access or upload, address-book matching, referral rewards, group invitation links, teacher privileges, shared Ensembles, an in-app messaging system, and automatic posting or sharing changes. Private journal sessions stay private. Approval exposes only content already shared under the existing visibility rules; the confirmation must explain that this can include previously shared posts.

## 2. Evidence and current working state

Inspected on `feature/solo-connected`, HEAD `c43b168`, with a dirty working tree. The legal changes listed in the handover are present but uncommitted; the concise legal brief is untracked. Other client, scheme, test and SQL work is changing concurrently. This scope adds only this file. No hosted state, account or device was inspected or changed; deployment statements below come from the repository's records, not a fresh production measurement.

| Existing evidence | Consequence for this feature |
| --- | --- |
| `PeopleView.swift`: conditional Shared with you, Responses and Requests sections, then **Find**, then **Your connections** | Put the primary action inside Find, immediately below the search controls and before results. |
| `ProfileView.swift`: Connected Account card has Manage Membership, About Études, Sign out and erase/delete; Solo has a separate Account card starting with Explore Connected | Add the secondary action after Manage Membership. Keep the Solo card's existing Explore Connected route. |
| `BackendShim.swift` and `FollowStore.swift`: requested/approved follows, acceptance, decline, unfollow and follower removal | Reuse directional relationships. Current delete implementations remove only the intended direction; an older comment in FollowStore still says both directions. The implementation, not that comment, is the evidence. |
| `supabase/schema/policies.json`: requester can insert `requested`; followed person approves; either party can delete | Preserve these authority boundaries. New invitation rules must also cover direct API writes, not just new screens. |
| B-40 migration and captured function definitions | Requests toward teens are closed. There is no approved-follow-back or invitation exception. Missing privacy state also resolves closed. |
| `AccountPrivacyService.swift` and CP-1 migration | Reuse age-band establishment and discovery defaults. No new age question, DOB field or contacts permission. |
| Source/schema search, entitlements and app entry point | No connection-invitation records, URL routing, Associated Domains entitlement, or blocking/reporting implementation found. The hidden legacy “Email invites” enum value is not a feature. |
| `NativeActivityView` in `ConnectedAttachmentShareUI.swift` | The native share-sheet wrapper exists; invitation generation and receipt are new. |
| `ConnectedIntroductionView.swift:179` | Existing copy already says someone can be invited. Align it with the actual shipped flow when this feature lands; it is not implementation evidence. |

The decision register §A2′/§A3′ and legal packet §0c still label the replacement pending legal review. No counsel answer is recorded in the inspected material. Preserve the historical B-40 record. The concurrently added `docs/connected-invitations-direction.md` was also read before completing this scope: invitations are a standalone feature, and the teen exception is a separate decision sharing its mechanism. Neither is assumed legally cleared by the other.

## 3. UI and journeys

**People → Find:** “Invite someone you know”. It opens a small sheet titled “Invite someone to Études”. **Profile → Account:** “Invite someone to Études” opens that same sheet, directly below Manage Membership and above About Études. No separate invitations destination or new tab.

The sheet explains: “Send a private link to one person. They can ask to follow you, and you choose whether to approve them. Connecting requires Études Connected for both of you.” Show expiry, a Share invitation button, and cancellation for the current unused link. Use the iOS share sheet; the member chooses Messages or another app. Dismissing the share sheet is not proof that a message was sent, so do not show “Invitation sent” merely because it closed.

Incoming requests reuse People → Requests, with a clear invitation label and a review action. For these requests, review shows the person's name and account ID plus “Is this the person you invited?” and explicit **Approve follower**, **Decline**, **Block** and **Report** actions. Do not permit the existing one-tap checkmark to bypass identity review for invitation requests. Pending requests are visible on refresh/opening People; push notifications are not required for version one.

There is one necessary access adjustment: Account currently switches to the Solo card when membership lapses. An authenticated former member must retain a **Manage invitations** entry into the same sheet, exposing their outstanding links/requests for cancellation or decline, with new invitations and approval unavailable. Safety controls and follower removal also need an identity-based Account route when People is unavailable. These are new navigation paths to protective actions, not an entitlement change. Someone who has never joined keeps the ordinary Solo card and the optional Explore Connected journey.

| Recipient's situation | Proposed journey |
| --- | --- |
| Signed in, Connected available | Open link → review inviter and your own account → Request to follow → wait for sender's approval. Closing the preview changes nothing. |
| Signed out | Open link → explain what it does and the membership requirement → existing sign-in flow → revalidate link → confirm the signed-in account → request. Never associate consent with an account merely because it signed in. |
| Solo, no Connected account | Show optional Explore Connected and “Not now”. Reuse the existing age-establishment/sign-in/purchase sequence. After setup, return to the invitation review; joining or paying does not submit the request. Solo remains usable without proceeding. |
| Existing identity, no current membership | Restore or manage/join Connected through existing routes, then return for explicit review. No claim, follow request or approval is granted by purchase completion. |
| No app | Generic web landing page explains Études, paid Connected and independent approval; offers the verified App Store listing. It tells the person to return to the original message and tap the link again after installation. |
| Wrong account, expired, cancelled or already used link | Explain the available next step without changing account automatically. Offer close, the existing account flow, or ask the sender for a new link. Never invite another purchase as the remedy for an invalid link. |

**Continuity:** retain one pending invitation reference locally through sign-in, foregrounding, termination and purchase, with an expiry and no journal content. Treat it as navigation intent, never consent or membership evidence. Revalidate on return and require the final tap. Clear on completion, dismissal, expiry, explicit sign-out or account deletion. An account change requires reopening/reconfirming; do not transfer a previously submitted request to the new account. If a second link arrives while one is pending, let the user choose which to review.

Do not promise transfer through App Store installation. The supported recovery is reopening the original message. Add an explicit **Paste invitation link** action in the shared invitation sheet and the Solo Explore Connected entry for browser-routing failures; read the clipboard only on that tap. No fingerprinting or deferred-link attribution service. Apple documents browser fallback and cases where Safari keeps navigation on the website, so test both the link and this manual recovery. [Apple: universal links](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content), [Apple: debugging universal links](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links).

## 4. Invitation, identity and lifecycle rules

These are recommended defaults for approval, not existing behaviour.

| Rule | Proposed first version |
| --- | --- |
| Sender identity | Authenticated Études identity, established age band, usable name/account ID, and current server-authorised Connected access. Never a user ID supplied as authority by the client. |
| Recipient identity | Bind only after an authenticated, eligible recipient explicitly requests to follow. Show “Continue as [name] · @accountID” before submission. The sender subsequently approves that exact immutable account identity. |
| Forwarding | Link possession permits a request, never access. Names and handles identify accounts, not verified real-world people. If uncertain, the sender checks the account ID through the original conversation before approving. No “verified friend” claim. |
| Expiry | Seven days from creation, measured by server time; displayed to both parties. The invitation-originated pending request has the same deadline. Once approved, the follow is an ordinary revocable follow and does not expire with the link. |
| Reuse | One authenticated claimant. Link previews, browser GETs and opening the app never consume it. Claim and pending-request creation are atomic. Retrying the same claim is safe; another account cannot take it over. |
| Simultaneous use | First eligible explicit claim wins; the sender still must approve. A forwarded recipient can occupy the link and force a replacement, but cannot gain access. This is an accepted inconvenience of this bounded design. |
| Outgoing volume | One unused link per sender at a time; once claimed, its request lives in Requests and the sender may create the next link. Start with ten new links per rolling 24 hours, enforced server-side. This intentionally favours individual invitations over class-wide distribution. |
| Cancellation | Sender may cancel an unused link or decline its pending request; recipient may withdraw a pending request. Replacing an unused link invalidates the old one. Cancellation remains available without paid access. |
| Rejection/repetition | A declined or cancelled claim cannot be replayed. One pending request per directed pair. Start with a seven-day pair cooldown after decline/removal, with an explicit fresh invitation from the protected person able to reopen that one opportunity; a block always wins. Apply this across ordinary and invitation requests. |
| Existing relationships | An approved follow shows “Already following”; never downgrade it. An existing pending request stays a single request. Any invitation provenance added to it must require the explicit claim and retain the invitation deadline for that exception. The reverse direction is unaffected. |
| Account deletion and cleanup | Invalidate outstanding links and claims involving that identity, with no journal changes. Specify deletion/retention for invitation, block and report records before schema approval; integrate with existing explicit-deletion and expiry lifecycles without enlarging the cleanup worker's authority. |

Use high-entropy, opaque tokens, with only a token hash stored server-side. Keep any raw link needed for local recovery in protected, expiring local storage, excluded from backup; redact tokens from logs, analytics, crash text and referrers. The server's invitation record contains identities, lifecycle timestamps and status, not phone numbers, email addresses or message contents. No public invitation listing or arbitrary profile lookup endpoint. Reject self-invitations, malformed tokens and unauthorised operations.

If the original raw link is unavailable on another device, offer **Replace invitation**, invalidating the old token; do not pretend a hash can reconstruct the link. A small current-link area in the existing sheet supplies cancellation without a separate management screen.

**Minimal disclosure:** public web pages and Messages link previews show generic Études copy only. After existing age eligibility/sign-in, a valid-link preview may show the inviter's display name and account ID, even if discovery is off, with a narrowly scoped preview permission for unpaid recipients before they decide to buy. No age, location, instruments, follower list, journal entries or activity history. Use initials, not remote avatars: existing avatar Storage access requires an approved follow. The sender sees the claimant's name/account ID only after explicit submission. Do not reuse ProfilePeek's broader fields as the invitation preview. This bounds the new flow's disclosure; it does not claim to tighten existing directory APIs globally.

## 5. Age and membership rules

| Case | Current protection and proposed change |
| --- | --- |
| Both adults | Core invitation flow can be designed and, after scope approval, built independently of teen exceptions. Discovery may remain off. An explicit invitation opens only its own request opportunity, not the general requests preference. |
| Teen sends invitation | **Legal gate:** permit its eligible claimant to request to follow that teen; teen still confirms the account and separately approves. No generic inbound opt-in. |
| Teen follows someone | **Legal gate:** only an existing **approved** teen→person follow permits that person to request the reverse direction. A pending outbound request is insufficient. Check that basis both when requesting and when approving; withdrawal removes the basis for an unapproved reverse request. |
| Adult sends invitation to teen | Under the proposed full model, teen may request to follow adult. This does not permit adult to follow teen automatically. Only after the teen's outbound follow is approved may the separately approved return path become available. |
| Two teens | Under the proposed full model, one initiates through their private invitation; approvals remain separate in both directions. |
| Other inbound request to teen | Refused, including direct API calls and a caller who merely knows the teen's account ID. Public discovery opt-in does not override this. |
| Missing/unknown age state | No invitation creation, claim or relationship approval until resolved through the existing flow. Never assume adulthood. |
| Under 13 | Existing Connected refusal before account establishment remains; opening a public landing page is not account creation. |

Recommend building the standalone adult core first, with the teen policy as a separately reviewed addition. **Release timing is Samuel's decision:** wait for all-member availability, or release adult-to-adult invitations once their own safety and applicable legal dependencies are met. In an adult release, enforce adult eligibility at creation, claim and approval, including incoming links opened by teens. Do not advertise classroom connections in that release. This preserves B-40; it does not redefine the long-term feature as adults-only or claim that adult invitations are automatically legally cleared.

Both parties need current server-authorised Connected access when a link is created/claimed as applicable, and again at approval. The new operations reuse membership authority, not cached app mode or possession of a StoreKit receipt. A valid signed-in preview is a deliberate, narrow read exception before purchase; it grants no social access.

If the sender lacks access, show “This invitation isn't available right now” before encouraging the recipient to subscribe; reveal no billing reason. If either loses access while a request is pending, approval is unavailable. It may resume, with a fresh explicit tap and all checks, if access returns before expiry. It must never silently approve on renewal. After an established follow, use the existing membership/content/cleanup rules. Decline, cancel, remove, block, report and account deletion must remain reachable without renewal.

## 6. Safeguards and legal gates

**Required in the release proposal:** server-enforced cancellation, expiry, deduplication, account and pair rate limits, final identity review, persistent blocking, and a working reporting/support route. The rate-limit numbers above are product defaults, not evidence that abuse is solved; final thresholds and record retention need review.

Follower removal already exists; **blocking does not**. A block must prevent new invitations, ordinary and reciprocal follow requests, and reapproval between the pair. Blocking should end both follow directions with clear confirmation, unlike directional Remove follower. It must also stop further comments and direct Connected sharing between the pair through their underlying APIs. Define treatment of existing shared content and reports in a bounded companion safety unit; neither a block nor follower removal can retract copies already downloaded into someone else's local storage. Unblocking must not restore follows or revive invitations automatically. Provide a small blocked-account management surface in Account so the decision is reversible.

Études can reject an invitation from a blocked account when it is opened, but cannot stop that person sending messages through another app. Do not claim otherwise; the recipient retains that app's own blocking controls. A copied invitation or a new account also cannot be treated as proof of a known person, which is why explicit account review remains required.

Reporting needs a real recipient, triage process, escalation route and response ownership, not merely a button. At minimum, report a suspicious invitation/account from the preview or request review and offer public support contact on the landing page. Avoid free-form invitation messages stored by Études in this version. Extending reporting/content controls across existing Connected UGC is a **release dependency owned by Samuel**, scoped separately rather than hidden inside link generation.

Apple's current Guideline 1.2 calls for content filtering, reporting with timely responses, blocking abusive users and published contact details for UGC/social services. Existing absence of these is therefore an App Review dependency for an adult launch too, not solely a teen question. An invitation-only report button would not by itself address the whole Connected service. [Apple App Review Guidelines §1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).

**Counsel gates, owned by Samuel to obtain and record:** review the proposed teen initiation/reciprocity model, minimal preapproval identity disclosure, forwarding risk, abuse controls, DPIA changes and outstanding legal-packet questions. Counsel must also resolve whether `communicationLimits` or another parental-control signal changes permitted behaviour, and any consent/update duties. Apple's API identifies communication restrictions for a minor; it does not establish Études' legal conclusion. A3′ remains open: neither “must implement” nor “unnecessary” is decided here. If required, scope signal acquisition, refusal/error handling, enforcement and refresh obligations before coding the teen replacement. [Apple: parental-control options](https://developer.apple.com/documentation/declaredagerange/agerangeservice/parentalcontrols).

Design adult link infrastructure, navigation recovery and tests independently after scope approval. Do not implement teen exceptions or change parental-control handling while these gates remain open. Preserve B-40 and its historical evidence; any replacement is a new forward migration with fresh review.

## 7. Genuinely new work and external prerequisites

Reuse the native share sheet, visual components, follow lists and directional follow actions, authentication, age establishment, StoreKit purchase/restore and membership attestation. Their presence does not establish the new end-to-end behaviour.

New work comprises the invitation state/authorisation layer; restricted identity previews; shared sending/review sheets; URL routing and pending-intent recovery; invitation-aware request UI; transactionally safe claim/approval/cancel operations; rate limits and suppression; web landing page; and lifecycle cleanup. Block/report capabilities are a companion release unit.

**Backend design condition:** the current target-only `follow_requests_open(target)` boolean cannot express “this particular caller is allowed because of this invitation/approved reverse follow”. Add an actor-aware request decision without making the teen's general effective preference true. Cover old direct INSERT/PATCH paths as well as new RPCs; an expired or cancelled invitation must not remain approvable through the old PATCH. Preserve restricted column grants, directional deletes and membership/child-safety boundaries. Do not make the membership kill switch disable child-safety or block checks. Local schema parity and B-23 remain deployment prerequisites.

**Web/app association:** choose and verify an owned HTTPS host, ideally on the existing proposed Études domain; ownership and hosting are not established by this scope. Host the landing page and `/.well-known/apple-app-site-association`; add Associated Domains and the correct app identifier/signing configuration. Restrict routing to invitation paths. Release currently uses `com.sdsongs.etudes`; Debug uses a different bundle ID. Confirm the actual application identifier prefix rather than guessing it. Apple requires the association file over HTTPS without redirects. [Apple: supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

The landing page needs a real public App Store destination, an Open in Études route, return-to-message instructions, support/privacy links, generic unavailable states, no account-bearing social previews and no third-party trackers. Configure hosting logs to avoid raw invitation tokens. Neither visiting it nor a messaging crawler may claim a link. Test the hosting/CDN and installed-app behaviour; the app entitlement alone is not proof.

**App Store/release:** a public listing and supported iPhone/iOS version, working Connected products and server attestation, revised privacy disclosures for invitation/safety records, assessed age-rating/DPIA impact, and review instructions that let App Review exercise both accounts' decisions. Current deployment target is iOS 26.4. Do not represent TestFlight installation as public App Store availability or use a permanent live invitation as the reviewer fixture.

## 8. Bounded stages and acceptance

1. **Review this scope.** Samuel decides direction, defaults and release split below. Record legal and safety dependencies with owners. No implementation starts before this review.
2. **Approve the protocol and safety unit.** Define states, privileges, actor-aware policy, retention and abuse controls; produce local predictions and meaningful negative tests. Adult core can progress separately; teen changes wait for counsel and product approval.
3. **Build and verify backend locally.** Invitations, lifecycle operations and restricted previews, with direct API bypass and concurrent claim/approval/cancel tests. Verify old follow behaviours and B-40 remain intact in the adult stage. Rehearse migration and rollback against the actual current baseline.
4. **Build app and web journeys.** Both entry points, share sheet, request review, cancellation, resume/paste recovery and landing page. Verify Debug and Release, accessibility and signed-out/Solo/member journeys. Integrate the existing purchase coordinator without changing purchase authority or journal storage.
5. **Release only after gates close.** Full teen behaviour requires approved replacement policy and tested safeguards; adult pilot requires its explicit decision and the same applicable safety prerequisites. Fresh B-23/prediction/review, separately authorised deployment, then independent verification and agreed physical-device/TestFlight QA. No personal-account deletion, subscription purchase or device change is implied by this scope.

Minimum behavioural acceptance:

- Share from either entry point opens the same flow; no Contacts permission or contact payload; cancelling share does not claim delivery.
- Opening, installing, signing in and purchasing each leave follows unchanged. Recipient request creates only recipient→sender `requested`; only sender approval grants that direction. Reverse follow needs its own request and approval.
- A forwarded link can at most create a reviewable request. Names do not bypass identity confirmation. Two simultaneous claims yield one claimant; retries cannot create extra requests. Preview crawlers cannot consume a token.
- Expiry, cancellation, decline, block and deletion defeat stale links and old direct API approval paths. Approval/cancel races resolve consistently. No auto-revival after removal, unblock, resubscription or token replacement.
- Hidden sender can be reached through their own invitation while remaining absent from search. Preview exposes only the specified fields and never opens avatar, journal, post or attachment access.
- In the adult-only stage, teen paths remain denied. In the reviewed replacement, test adult/teen, teen/adult and teen/teen in both directions; approved-follow-back versus pending-follow, withdrawn basis, unknown band, ordinary unsolicited request and direct API bypass. Turning off membership enforcement must not relax these protections.
- Sign-in cancellation, wrong account, declined age range, pending purchase, successful purchase with delayed attestation, offline return and process termination preserve a recoverable invitation without making a relationship decision. An expired invitation after purchase does not label the completed purchase a failure.
- Actual installation requires reopening the original link and succeeds that way; Safari fallback and explicit paste also work. No untested deferred-install promise.
- Lapse on either side prevents new approval; cancellation, removal, reporting and blocking remain usable. Existing journal history and privacy settings stay unchanged. Existing unrelated directional follows survive decline/removal.
- Safeguards are enforced through comments/sharing/request APIs, and a submitted report reaches the designated review process. Teen logic test coverage is not restated as real Apple teen-device verification; the existing fixture limitation needs explicit release disposition.

## 9. Decisions requested from Samuel

1. **One-direction invitation with sender confirmation**; following back remains separate. Recommended.
2. **Seven-day, one-claim links; one unused outgoing link at a time; ten new links/day; seven-day decline/removal cooldown**, with explicit fresh invitation as the narrow cooldown override and blocks always prevailing. These limits bound version one; adjust before implementation if too restrictive.
3. **Generic public preview; name and account ID only after eligibility/sign-in**, with no avatar or wider profile before approval. Reopen the original message after installation, with explicit paste as backup.
4. **Build the standalone adult core first; keep the teen replacement separately gated.** Decide whether to ship adult-to-adult invitations when their own dependencies are met or wait for all-member availability. No release split is assumed approved.
5. **Accept blocking/reporting and the broader Connected safety assessment as release dependencies**, with Samuel owning operational arrangements and counsel responses. They are new work, not capabilities already supplied by follower removal.

This is a source-reviewed proposal, not implementation, device verification, a legal determination or a production acceptance record. No build/test run was needed for this documentation-only deliverable.
