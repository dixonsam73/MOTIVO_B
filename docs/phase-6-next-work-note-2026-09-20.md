# Current position and next work — 20 September 2026

Concise alignment note written by Claude after the bounded clean-up was committed. **It records
where things stand and what is authorised next. It authorises nothing on its own, accepts no
deferral, and closes no phase.**

## Where we are

- **Bounded Phase 6 clean-up: COMPLETE, ACCEPTED, COMMITTED AND PUSHED** —
  `e5b3b08788e88324c942421ed64b640db122acf0` on `feature/solo-connected`. Four paths: the two
  source files, the C-12 audit row, and `docs/phase-6-cleanup-scope-2026-09-20.md`. Samuel
  reports it pushed and the locally recorded origin agrees at the same SHA; **no fetch was
  performed** to confirm that independently.
- **The Phase 6 CLEAN-UP CHECKPOINT is complete. PHASE 6 IS NOT CLOSED.** Formal closure and
  carryover acceptance have **not** been separately granted by Samuel.
- **Codex's disposition is a set of RECOMMENDATIONS**
  (`docs/phase-6-disposition-codex-2026-09-20.md`), as is my feedback on it
  (`docs/phase-6-disposition-claude-feedback-2026-09-20.md`). **Neither constitutes an accepted
  deferral of anything.**

## Standing freezes and protections — unchanged

- **Adult-assurance implementation is FROZEN**, pending the legal, Apple, HEAA and server-trust
  gates. **B-40 and the current band protections remain in force in production.**
- **Sharing-protocol implementation is FROZEN**, pending a sound reviewed design. The provider
  reply (SU-478356) is useful but **not the only design gate**, and **its absence is not a
  blanket block on independent work.**
- **No blanket down-tools and no indefinite wait on Supabase.**

## The C-70 remaining gaps — ADDRESSED AND COMMITTED at `8b54ba6`

**Both gaps are fixed in client code and committed.** They are stated below as the **pre-fix
problems this work addressed**, not as current defects.

1. **A naturally lapsed member in Solo could not sync maintenance of an existing Connected
   profile; the client returned before the directory write**, although the **D-U6-3
   owner-update carve-out is settled server-side** and `account_directory_update_owner` carries
   no gate. The blockers were mode-derived, not server-side. **This concerned the server-side
   sync of an existing profile — it never meant local profile editing was impossible.**
2. **Local display-name persistence ran only on `onDisappear`, and its Core Data error was
   swallowed.**

### Status — 20 September 2026

**Scoped, reviewed, approved, implemented, and COMMITTED at `8b54ba6`** on
`feature/solo-connected`, on Samuel's explicit instruction and after Codex's independent
**local implementation acceptance**.

**Local evidence at that commit:** full `MOTIVOTests` **972 passed, 0 failed, 6 skipped** —
the six being the standing opt-in set — and the **final Release build succeeded against the
committed bytes**. Measurements M1–M5 resolved the failure-handling design before it was
written.

**What is NOT established, and must not be read into the commit:**

- **Device QA is OUTSTANDING and is required before release.** The restored behaviour has
  **not** been observed on hardware, and there is no device or RLS end-to-end acceptance.
- **Codex's acceptance was explicitly LOCAL ONLY**, and carried no phase-closure or push
  authority.
- **Phase 6 remains OPEN.** This closes neither the phase nor its carried obligations.
- **Push status, corrected 20 September 2026.** An earlier revision of this note said "no push
  evidence exists for `8b54ba6`". **That overstated the absence and is withdrawn.** The
  **locally recorded** `origin/feature/solo-connected` is **`8b54ba6`**, and the local reflog
  records that ref moving to it by push. **No `git fetch` and no independent live-remote
  verification were performed**, so what is evidenced is the state of this clone's remote-
  tracking ref, not a confirmed observation of the remote itself. **Samuel retains pushing.**
  (The earlier clean-up commit `e5b3b08` is separately recorded as pushed per Samuel on the
  same basis; that dated report stands and is unaffected.)
- No production, device, credential or purchase action was taken.

Record: `docs/phase-6-c70-remaining-gaps-scope-2026-09-20.md`.

**Constraints the work preserved, carried forward from C-70's earlier accepted work:** gated
creation, identity and owner binding, stale-effect suppression, Solo remaining account-free,
and existing age and security policy. Creation stayed gated and stayed the server's decision,
and automatic handle generation stayed Connected-only.

**Explicitly excluded, and still excluded:** any change to general Connected mode; unlocking
the feed or access; C-34 avatar work; recorder work; and broader sharing or age changes.

**D-U6-3 is settled policy and is not to be re-asked.**
