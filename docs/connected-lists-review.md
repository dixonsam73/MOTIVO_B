# Lists and Connected sharing — local implementation review

17 September 2026. Client implemented locally on `feature/solo-connected`. Backend source was separately approved, reviewed with Claude, committed as `1f36ef1`, and deployed; the immediate production comparison matched the exact expected delta. No push performed. See `connected-lists-backend-deployment.md`. The sender’s local list is never changed by receipt deletion. Samuel confirmed the proposed lifecycle rules in this task.

## Behaviour

- The user-facing Tasks feature is now Lists. Existing defaults keys, saved data, template application, local editing and completion behaviour remain compatible.
- Open a saved list’s editor and tap the compact Send button at the top right. The existing Connected sharing flow offers Person and Ensemble, using its existing cards, recipient rows and navigation. Lists have no Outside Études/system-share route.
- Each explicit send produces an immutable snapshot. Only version, name, ordered line text and Header/item types travel. No completion, local IDs, scores or media links travel.
- Lists appear in People → Shared with you, with the same sender presentation and unread aggregation as attachments. Opening marks the delivery viewed. The list preview shows headers separately from unchecked items.
- Save to Lists creates a recipient-owned editable template with fresh list/line IDs. Saving the same delivery again returns the existing copy, including recipient edits. A separate send produces a separate copy. Removing that saved copy allows re-adoption while the inbox delivery still exists.
- Delete dismisses only the recipient’s delivery. Confirmation states that the sender’s original and any saved local copy survive. Failures are shown; the client requires an updated row before removing the item locally.
- Adoption is entirely local: no new saved/progress marker is sent to the backend, and Lists never go through the Scores library.

## Eligibility and lifecycle

These use the verified existing attachment policies, not new permissions. The recipient must be an approved follower of the sender; Ensembles intersect their local member IDs with that set. Sender entitlement is checked at delivery; recipient entitlement is checked at read/update/storage access. Recipient entitlement is not a send-time condition in the existing protocol.

B40 is unchanged. A teen may request to follow an adult who accepts requests and then receive after approval. New requests to follow the teen remain blocked. This feature introduces no new discovery/contact route.

A live reference is an inbox row whose `deleted_at` is null. Deleting one delivery withdraws that reference, not the shared object or another recipient’s reference. Existing expiry cleanup retains sent objects with live references; explicit sender-account deletion removes the sender’s backend objects/rows. Already-adopted recipient-local copies survive those sender lifecycle events. Existing cleanup workers are MIME-agnostic and are not changed or redeployed.

## Storage and compatibility

`SavedList.swift` unifies the three compatible saved-list record definitions and adds optional local `sourceSendID`. Manager and picker merging preserve provenance and do not collapse separate received copies by matching text. Timer saves exclude adopted copies from legacy context mirrors, preventing deleted copies from being resurrected. The picker’s legacy scan stays within the current owner namespace.

The transport is JSON v1 using `application/vnd.etudes.list+json` and `.etudeslist`, with 128 KiB encoded size, 500 lines, 200 name characters and 4,000 characters per line. Unknown versions and unknown/missing wire types are rejected; local legacy records still default missing type to item. Payload validation occurs before send and before caching/adoption. The invocation-owned export is removed on both successful and failed upload.

A list is uploaded once per explicit send and delivered through the existing bulk attachment insert. Network failure after server acceptance can leave delivery outcome uncertain, as with existing attachments; an explicit new attempt is a new send. No sender SELECT grant or new delivery RPC was added to introduce retry inspection.

Older app builds do not recognize this list MIME type or preserve new local provenance. Roll out receiver-capable builds before enabling list sending; mixed-version end-to-end behaviour has not been verified. Unknown future wire versions fail with an update-app message.

## Backend review and deployment plan

Prepared files:

- `supabase/migrations/20260917120000_connected_lists_mime.sql`
- `supabase/sql/2026-09-17-lists-apply-production.sql`
- `supabase/sql/2026-09-17-lists-rollback-production.sql`

Expected production delta: one MIME constraint modified; one list metadata constraint added; one private bucket MIME allowlist extended. No table/column, grant, RLS policy, function, worker or existing attachment MIME type changes. Only bucket configuration is updated; no member content is migrated or removed.

1. Review the complete client/backend diff. Obtain the separately required commit and live-deployment approvals; the current task authorizes neither action automatically.
2. Confirm receiver build availability and recheck the guarded production baseline. Keep the shared Run scheme Release and StoreKit Configuration None for genuine Connected device QA.
3. Submit the entire guarded apply artifact as one transaction. Inspect the response body, not just process exit status.
4. Capture and review the production schema immediately. Accept only the three expected changes above; verify all policies, grants, membership/teen predicates and workers remain unchanged.
5. Exercise Person and Ensemble delivery with genuinely entitled QA accounts: arrival indicator, Open, typed preview, Save to Lists, edit/reopen/re-save, separate sends, local deletion/re-adoption and inbox deletion. Confirm sender original, saved recipient copy and second recipient survive deletion. Do not use Samuel’s personal history as disposable fixtures.
6. Rollback is guarded: it refuses if list deliveries or stored list objects exist, or if the MIME/bucket baseline has changed. Once lists exist, retain receiver/backend support and disable new sending rather than stranding deliveries. No automatic cleanup or destructive rollback is supplied.

## Verification and limits

- Final Release iOS Simulator build (arm64) passed. Earlier generic Release simulator builds also passed for both simulator architectures.
- Thirteen focused format/adoption/upload/deletion-confirmation tests passed, zero failures, using a fresh isolated simulator and isolated UserDefaults suites. These cover legacy decoding, Header/item wire preservation, bounds/unknown versions, fresh IDs, reloading edited copies, duplicate adoption, separate deliveries, re-adoption, namespace isolation, corrupt-library refusal temporary-file cleanup and confirmed delivery updates.
- Local MIME migration and rollback rehearsals passed, with original schema/bucket/reference counts restored.
- Local authenticated-role SQL checks passed for approved-follower delivery, non-follower rejection, teen outbound follow/approval, blocked teen inbound requests, sender privacy, viewed state, recipient deletion, other-recipient/object survival and lapsed sender/recipient denial. B40/scope011 definitions were brought to the verified deployed shape only inside the test transaction because the local stack had older definitions. Everything, including fixtures, was rolled back and baseline fingerprints matched.
- These are local checks with explicit synthetic fixtures, not genuine Apple entitlement evidence or production/device QA. No physical device was touched. Backend deployment is now applied and structurally verified; Samuel has now confirmed core device send/receive/adoption and repeated-save idempotency (below); the compact Send label check remains pending.

Unrelated documentation changes from other ongoing work were preserved. `AGENTS.md` remains untracked and unstaged. The existing paused automation was not changed.

## Device QA follow-up — 17 September

Samuel reported an oversized one-item Send menu and a failed Release-to-Release send. The editor now uses a direct, intrinsically sized Send button in the trailing toolbar position. The device error explicitly reports `invalid_mime_type` for `application/vnd.etudes.list+json`, confirming the pending storage allowlist update blocks upload. This is not evidence of a membership failure. Samuel subsequently approved the scoped backend commits and live deployment; the update is now applied and structurally verified after Claude review.

The compact Send button follow-up passed its Release arm64 simulator build. **The compact Send label's appearance is ACCEPTED** — Samuel installed the new build on 17 September 2026 and confirmed it visually (*“Send button looks much nicer”*). **That is acceptance of the control's appearance only, and nothing more.**

## Device QA confirmed by Samuel — 17 September 2026

After deployment, Samuel confirmed a List successfully sent from Device B to Device A, was saved into A's Lists manager, and behaved like a List created on A. Repeated Save to Lists actions for the same delivery did not create duplicates. This provides real-device evidence for the core send/receive/adoption flow and same-delivery idempotency. The preceding device setup was latest Release builds on both devices in Connected mode.

**The compact Send label's appearance is ACCEPTED** — Samuel installed the new build on 17 September 2026 and confirmed it visually (*“Send button looks much nicer”*). **That is acceptance of the control's appearance only, and nothing more.** This confirmation does not independently establish Ensemble delivery, deletion isolation or re-adoption after local deletion; those retain their existing local-test evidence. No new commit, push or device action was performed to record this result.
