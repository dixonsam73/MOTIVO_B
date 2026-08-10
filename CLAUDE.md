# Études — Working Context

iPhone app: a local-first journal for musicians, with an optional paid
"Études Connected" social layer (Supabase + StoreKit 2 + Sign in with Apple).

Working branch: `feature/solo-connected`. Audit baseline commit: `ec2f52f`.

"MOTIVO" is the legacy working title. The project file, scheme and source
directory are all named MOTIVO; the product is `Etudes.app`, display name
"Études". Renaming is not release work.

Baseline verified at migration: Debug and Release both compile clean
(0 errors). See `docs/audit-findings.md` for what the Release build surfaced.

**Current position: Phase 1 in progress.** Landed and device-verified: C-13
(purchase-path hang), C-24 (reconnect after reinstall), C-1 client half (client
expiry-deletion authority removed), C-2 (Scores survived Erase All).
Verification batch cleared: C-7, C-8, C-19. Filed along the way: C-23, C-25,
C-26, C-27, C-28. Next: C-28 (needs a product decision first), safe
`delete_account_v1`, directory and follow-policy hardening, zero-dependency
cleanup, C-3 measurement, B-6 two-account test. Update this line as work lands.

**Temporary instrumentation: removed.** `MembershipTrace.swift` and its
thirteen call sites were deleted once QA B2 passed on real StoreKit, as the
standing condition here required. It earned its keep — it diagnosed C-24,
produced C-1's only device evidence, and framed C-13's verification. One
lesson worth keeping: it was labelled "Release-capable by design" but only ever
read through Xcode, and on TestFlight every line arrived as `<private>`,
because `NSLog` with `%@` arguments is redacted when read from a device. If
release-readable logging is ever needed again, use `os.Logger` with
`privacy: .public`.

---

## Architectural invariants — FIXED. Do not revisit.

1. **The local journal is never deleted by any Connected or membership action.**
2. **If nobody else can see it, it does not belong on Supabase.**
3. **Reversible decisions may rely on client-side evidence. Irreversible
   decisions require authoritative server-side evidence.**
4. **Personal durability is independent of Connected membership and follows
   Apple's normal backup model.**

Settled after a four-phase client audit and a Supabase backend audit. Only
genuine new evidence contradicting one of them is grounds to reopen — not a
preference for a different design.

`docs/architecture.md` — the four data domains, plus designed-but-parked work.
`docs/audit-findings.md` — finding register (IDs C-n client, B-n backend).
`docs/qa-plan.md` — manual QA, used at each phase gate and for the RC.

---

## Product principles

These are interaction principles rather than architectural invariants.

- **Reduce ceremony between the musical impulse and the musical record.**
- **Assistance should never override explicit user intent.**
- **Live state is useful; historical state should never become guilt or performance pressure.**
- **Reflection over measurement. Continuity over productivity.**

---

## Settled decisions

- Only sessions the user explicitly shares are uploaded. Solo mode uploads
  nothing. Unsharing deletes the backend post and any storage objects no longer
  required by surviving recipient references.
- Notes and each attachment keep independent privacy controls within a shared
  session. Only explicitly included components upload.
- "Share with followers" defaults ON. This is intentional, chosen from
  TestFlight evidence that the opposite default produced empty feeds. Users
  have a persistent "Default to Private Posts" preference. Copy must describe
  this accurately rather than claiming "private by default" of Connected.
- Client StoreKit governs Études vs Connected (access only). Apple's App Store
  Server Notifications are the sole authority for membership-expiry deletion.
  Explicit user-triggered **Erase All Études Data** remains a valid
  client-initiated destructive action.
- Expiry removes Connected, not the musician. Local journal, Scores, media,
  profile name, avatar, location, instruments, activities, settings and
  preferences all survive untouched.
- Comments a departing member wrote on others' surviving posts are RETAINED.
- Attachments a departing member sent survive for existing recipients. The
  departing member's own received-attachment references are removed. The asset
  itself is removed only when no live recipient reference remains.
- M13 (iPad) and M14 (personal iCloud sync) are deliberately deferred. Their
  absence is not a defect.

---

## Implementation phases

One phase at a time. Tight scope, green build, explicit verification, reviewed
before moving on. Six bounded, separately reviewable phases — not one rewrite.

1. **Safety** — C-13 first (purchase-path hang); safe `delete_account_v1`;
   directory + follow-policy hardening; remove client expiry-deletion
   authority; Scores erase defect; zero-dependency cleanup; cheap verification
   tests (staged-video measurement, B-6 two-account test).
2. **Durability** — restore Apple backup participation for permanent user
   data, including the reconciliation pass for already-excluded media. Keep
   excluding staging and timer scratch.
3. **Membership authority** — server-side entitlement state; App Store Server
   Notifications; Billing Grace; replay protection; idempotent processing.
4. **Shared-only architecture** — shared-only uploads; remove the accidental
   analytics mirror; purge historic unshared rows; align onboarding, settings
   and App Store privacy disclosures.
5. **Remaining client fixes** — duplicate Score adoption; staged-video work if
   measurement justifies it; playback rate (AttachmentViewerView only, local
   and remote audio/video, discrete 50/75/100%, pitch preserved, no looping,
   no PracticeTimerView changes, no MediaTrimView carry-over, TestFlight soak);
   accessibility and polish.
6. **Cleanup** — obsolete backend code, AVFoundation deprecation sweep,
   architectural leftovers.

Verification gate after each phase. RC QA confirms an already-tested system.

---

## Per-phase working rules

- Restate the agreed scope before proposing any implementation.
- Keep changes strictly within that scope.
- Preserve existing architecture. Prefer subtraction over new abstractions.
- Surface assumptions before making changes; never fill gaps with invented
  behaviour.
- Finish with clear verification steps.
- Verify before asserting. Several audit findings were wrong because behaviour
  was inferred from names and structure rather than checked.

---

## Environment

- iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), deployment target iOS 18.5.
- Flat source layout via `fileSystemSynchronizedGroups` — everything in
  `MOTIVO/` is auto-included in the app target.
- Debug and Release use different bundle IDs. The shared scheme's Run action is
  Release and pins a `StoreKitConfigurationFileReference` to `Etudes.storekit`.
  A pinned StoreKit configuration applies **regardless of build configuration**,
  so running from Xcode always gets synthetic StoreKit — Release included.
  **Real StoreKit behaviour requires TestFlight**, or clearing the StoreKit
  configuration in Run → Options. This bit us mid-audit: a Release QA pass was
  mistaken for real-StoreKit evidence. See C-9.
- 193 `#if DEBUG` blocks. Always verify Release as well as Debug.
- Unit test suite is an empty template. "Green build" means compile-clean, not
  test-verified.
- Build: `xcodebuild -project MOTIVO.xcodeproj -scheme MOTIVO -configuration
  {Debug|Release} -destination 'generic/platform=iOS Simulator' build`
