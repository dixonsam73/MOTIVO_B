# Phase 6 — Lists checkpoint and stop

18 September 2026. Branch `feature/solo-connected`; parent implementation baseline
`a98d86033ce7a8bf5fbb9cd942838c9e620a1176`. This record accompanies the checkpoint
commit; it is not a Phase 6 closure or release approval.

## Boundary

Samuel instructed Claude and Codex to finish only the current Lists persistence
unit, review and verify it, commit without pushing, then stop. The recurring
eight-minute workflow is paused. No new Phase 6 unit or age-architecture work is
authorised by this checkpoint.

The new product direction is Solo unchanged, local and account-free, with
Connected available only to adults. Connected must fail closed unless adulthood
has been established through an Apple-provided assurance mechanism that
SD Songs Ltd determines adequate for the applicable requirement. Generic Apple
`.confirmed` has **not** been established as satisfying Ofcom HEAA. That remains
an evidential/legal gate. These are Samuel's instructions, not a legal finding or
a description of implemented behaviour. A separate read-only audit follows.

## Completed implementation at this boundary

- **Recording preservation** (`22e5af6`): failed attachment writes no longer become
  successful saves that discard staged originals.
- **Queued sharing ownership** (`cf8193e`, `9aa3338`): queued work belongs to its
  originating identity and requests use that identity or are refused.
- **Withdrawal reporting** (`fd6c22c`): report what the server response actually
  establishes. This does not solve late publication after withdrawal.
- **Test attribution** (`6c6471b`): correct the C-100 sentinel's false attribution
  to the app entry point.
- **Sharing-choice persistence** (`e6d2fc2`, `325a27f`): failed saves are visible;
  saved intent survives a restart on the same installation. Cross-device/server
  ordering is still open.
- **Presentation** (`10b6cbd`): About Études and Explore Connected refresh, with
  acceptance and limits in `phase-6-presentation-update-2026-09-18.md`.
- **Server storage-delete mitigation** (`a98d860`): bounded individual deletes;
  deployed as cleanup v8 and account deletion v11. This is not proof of removal
  of untracked uploaded bytes or provider retention behaviour.
- **Lists persistence (this commit; P6-I-04 / Claude F-1)**: one shared library
  path preserves unreadable data, migrates all of an owner's legacy contexts once,
  and stops legacy mirrors from resurrecting deleted Lists. Migration version and
  Lists share one encoded value. Writes merge against a fresh read so stale screens
  preserve unseen adoptions/newer unchanged entries and do not resurrect deletions.
  Manager, timer, picker and adoption use the shared contract. Unreadable data is
  reported, and refused saves do not proceed with successful-save follow-up actions.

## Verification and limits

Claude ran the final checks; Codex independently inspected the source changes,
the focused and full Xcode result bundles, and the Release build log:

- Focused persistence, adoption and format tests: **27 passed, 0 failed, 0 skipped**.
- Full unit regression: **727 total, 721 passed, 0 failed, 6 skipped**. The carried
  skips remain exclusions, not passes (C-87 repro cases and T-L5–T-L7 rehearsal-only
  checks).
- Release simulator build: **BUILD SUCCEEDED**, no compiler errors. Existing
  AVFoundation deprecations remain outside this unit.
- The full run logged simulator launch errors after its success summary; its
  Xcode result bundle reports Passed and zero failed tests. This is recorded,
  not presented as device evidence or a reason to change unrelated app code.
- Whitespace/diff checks passed. The six implementation/test file hashes matched
  Codex's reviewed snapshot after verification.

Local verification evidence is under
`/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/d9d4fc7d-cd76-4fdf-a378-c352abfe0694/scratchpad/`:
`lists-test3.log`, `lists-release.log`, `lists-full.log`, and
`dd-b2/Logs/Test/Test-MOTIVO-2026.09.18_22-17-15-+0100.xcresult` (focused) /
`Test-MOTIVO-2026.09.18_22-23-25-+0100.xcresult` (full, same directory).
These are temporary local evidence, not committed test bundles.

Physical-device acceptance of this Lists unit remains pending: check existing
Lists, save/delete/reopen across timer contexts, and received-List adoption.
Synthetic damaged-data cases must not be created in Samuel's real preferences.

The migrated value uses an envelope that older builds cannot read. Do not run
older destructive loaders against migrated preferences; they could overwrite it.
The single encoded value avoids a separate migration flag diverging from its
payload, but does not promise synchronous disk durability from UserDefaults.

## Intentionally unfinished

- Full sharing admission/ordering/deletion protocol: all six recorded blockers
  remain open. The proposed upload lease implementation was withdrawn after review
  found late-expiry and duplicate-admission counterexamples. The disposable U1-min
  model supports only its tested sequential transitions, not production readiness.
- Supabase support ticket SU-478356 has only been acknowledged. Hosted cleanup,
  retention and failure semantics remain unconfirmed. Observation of the first
  scheduled cleanup run after the deployment remains pending.
- Attestation completion ownership, score-viewer update warning, measured media
  performance, delivery reconciliation, simulated-service withdrawal behaviour,
  and remaining documentation follow-ups have not been completed by this unit.
- Private Invitations and the 18+ re-scope are not started here. Existing legal,
  age-assurance, release and device gates remain separate.

The Lists changes themselves are local persistence work and do not depend on teen
eligibility or age assurance. Prior Connected entry/presentation and membership
integration work may need reassessment under the new direction; no such audit or
adaptation has been performed in this checkpoint. Reliability fixes are not
evidence that the new 18+ access rule is implemented.

Pre-existing invitation-document changes and untracked `AGENTS.md` are left
untouched and outside the commit. The Phase 6 presentation record and its audit
README link are included as completed records-only work.
