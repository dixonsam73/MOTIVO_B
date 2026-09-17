# Études Phase 6 — independent audit scope

17 September 2026. Requested Claude-named deliverables; this report was executed by the current Codex agent as an independent pass. No other new Phase 6 audit was consulted, and no identity as a different model is claimed.

Baseline: `feature/solo-connected`, `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`. Dirty: `docs/connected-invitations-direction.md`, `docs/private-connection-invitations-scope-2026-09-17.md`; untracked: `AGENTS.md`. SHA-256:

- `AGENTS.md`: `f948387812c8e6b8a002e4baf84cce472430c954677bed8577e5d9b2f1cbaaaa`
- `CLAUDE.md`: `d1c96997a14ba7d2a298150e87c4307c9d74c778b69e9c2db0487b2bdcfb573f`
- `docs/connected-invitations-direction.md`: `90f60494f42ec2500254b6a7aa6384ee670ffa49fd5b678fb26191eeb27885c0`
- `docs/private-connection-invitations-scope-2026-09-17.md`: `c470d4a18c79cff102b01b472f7d06ddb4079fdbcffc998f11e260882236223d`

Scope fixed before conclusions

1. Trace journal/staging save and deletion, Lists migration/adoption, queue persistence and owner transitions, backup policy and restore boundaries.
2. Trace client requests through committed RLS/storage/grants, directional follows, B-40 teen enforcement, received-content ownership and deletion versus expiry.
3. Check StoreKit/attestation separation, refresh/reset lifetime, cancellation and the cleanup worker's Apple-authority ordering.
4. Review recording failure paths and audio engine/UI lifetime. Preserve QA1–8 as user-reported acceptance; no physical-device operations or request to repeat passes.
5. Check sharing/adoption retry and malformed-data paths, offline/relaunch behavior and source-level accessibility. No visual acceptance inferred from source.
6. Inventory actionable Phase 6 leftovers and build provenance. Run a Release simulator compile with isolated outputs and disposable source-based probes only where they settle a concrete issue.

Evidence boundaries

Read-only repository and backend investigation; report/probe files outside the repository only. No fixes, fixtures in the repo, commits, pushes, branch changes, upgrades, deploys, live writes, account changes or personal data access. No automation changes. No local backend reset. Live schema access is optional, not a dependency for completing this audit; committed schema is explicitly dated evidence, not current live verification.

Current invitation edits are approved scope/proposals, not shipped behavior and not this audit's implementation authority. Legal/publication approval remains separate. B-40 remains the current implementation. Lists core delivery/adoption, duplicate-save prevention and compact Send acceptance remain intact. Ensemble delivery, deletion isolation and re-adoption have local evidence only.

Priority is consequential data/privacy failure paths, then bounded cleanup. No broad architecture redesign or deprecation-only rewrite. Findings receive temporary independent IDs P6-I-n; existing C-/B- IDs remain intact. Report and comparison table will distinguish measured synthetic results, source proofs, hypotheses, historical acceptance and untested cases.
