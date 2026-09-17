# Études Phase 6 — independent comparison worksheet

17 September 2026 · `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`

This is one independent report's merge-ready table. No other new audit was read. “Other report” deliberately remains pending; agreement or disagreement must not be invented. The Claude-prefixed filenames were requested; the current Codex agent performed this pass, as disclosed in the report.

| Area | Stable ID | This report's conclusion | Evidence | Severity / confidence | Required next check | Other report |
|---|---|---|---|---|---|---|
| Local save | P6-I-01 | Attachment failure swallowed; success cleanup can delete original recording | Exact timer commit + actual StagingStore cleanup, synthetic failure; source caller trace | P1 / high | Both editors; first/nth write and Core Data save faults; retry keeps originals | Pending |
| Account ownership | P6-I-02 | Queue lacks originating account; old work dispatched under current account | Real queue + stub probe; current-owner HTTP body, bearer and RLS trace | P1 / high mechanism; HTTP reproduction outstanding | Disposable A→B→A publish/unshare; legacy migration decision | Pending |
| Privacy durability | P6-I-03 | Failed Unshare persistence leaves old Publish on disk | Actual filesystem denial; old file unchanged; current decoder returns Publish | P1 / high | Failed write + process restart + network failure; recovery convergence | Pending |
| Lists | P6-I-04 | Screen loader overwrites unreadable v2 library | Exact loader probe: damaged bytes → `[]`; valid control; adoption reader refuses | P2 / high | Exercise screen loader with adopted/legacy/corrupt/wrong-type data | Pending |
| Membership concurrency | P6-I-05 | Late completion clobbers coordinator reset/new flight | Exact coordinator with forced continuation overlap | P2 / high state bug; frequency unknown | Reset→B and late cancellation result; no stale publication/slot clear | Pending |
| Video | C-97 | Fault recovery gap remains; audio-session interruption handler does exist | VideoRecorderView:1616; QA7 bounded acceptance | P3 carried gap / high source | Capture runtime error/interruption, reset, missing audio | Pending |
| Drone | C-96 | QA8 stands; automatic recovery mechanism unresolved | Engine invalidation + only explicit source start sites; user report | Evidence gap / mechanism unknown | Exact binary and route/config trace if revisited; no automatic QA rerun | Pending |
| Staging concurrency | C-99 | Index fixes stand; R-a…R-f not closed | Lock/file phase source and accepted historical local record | P2 residual / bounded | Same-ID and allocation races; real-interaction frequency | Pending |
| Lists retry | P6-R-send | Lost send response may yield duplicate distinct deliveries | Fresh asset UUID per upload; delivery uniqueness per asset | Hypothesis / medium; unassigned | Drop response after committed deliver; retry through actual UI | Pending |
| Sharing | C-61/C-87 | Accepted normal unshare and revision guard stand | Device record; queue source | Accepted within scope | Queued/offline convergence distinct from I-03 disk faults | Pending |
| Backend privacy | B-40 | Current effective teen gate stands; invitations not built | Helper + two mirrors in committed snapshot/migration | Deployed record / high source | No weakening; replacement policy/legal approval separately | Pending |
| Membership refund | B-39 | Status-5 fix present; not a new open defect | Current predicate/writer/derive and deployment record | Deployed record / high source | No fresh production/Apple rerun claimed | Pending |
| Backend fidelity/tests | B-41/B-42/C-100/C-101 | Existing fixes stand; no new parity claim | Current repair records; complete-array snapshot inventory | Resolved historical / not rerun | Run required suites when an authorised change needs them | Pending |
| Cleanup | C-12/C-15/C-22/C-4 helper | Bounded dead code, metadata and naming; 77 unique deprecation diagnostics | Source reachability; Release log | P3 / source/build | Small subtraction/API units; do not turn warnings into risk counts | Pending |
| Release provenance | C-52/C-53 | Release/None intact; simulator bundle exclusions intact | Scheme + built app inspection | Current local check | Device archive/TestFlight provenance remains separate | Pending |
| Legal/launch | P5-G, C-31, ASSN config | Open gates remain; questions are not legal approval | Current packet/decision register, code Sandbox default | Release gate / current external state not measured | Counsel disposition, publication, authorised config verification | Pending |
| Carried operations | G7/B-34/B-11 Gate 6 | Not discharged here | Existing obligation records | Owned evidence obligations | Natural cleanup/real subscription; shadow silence not proof | Pending |

Comparison procedure: match mechanisms and triggers, not titles. Keep measured/source/hypothesis grades separate. For disagreements, state the exact falsifier and smallest isolated check. Preserve C-/B- IDs; allocate new permanent IDs only after merging. Suggested batches are A local-save atomicity, B queue ownership/durability, C Lists read safety, D attestation ownership, E bounded cleanup, F remaining release/QA gates. No implementation has started.
