# Phase 6 — two independent audits, 17 September 2026

Archived report packet. **Every file here is a report or its evidence. No
application code, schema or configuration is part of this folder.**

**Baseline for both audits:** `feature/solo-connected` @
`2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`. Neither audit changed the
repository, and both recorded HEAD and the dirty-file hashes unchanged at
completion.

---

## READ THIS FIRST — the filenames do not indicate authorship

Samuel's brief specified `claude-phase-6-*` filenames for the deliverables.
**Codex reached those filenames first and wrote its reports under them**, and
discloses its own authorship inside each file. Claude (Opus 5) then wrote its
independent reports under `claude-opus5-phase-6-*` rather than overwrite them.

**The `claude-` prefix therefore means Codex. The `claude-opus5-` prefix means
Claude.** This is confusing and it is preserved deliberately: renaming the files
after the fact would break the cross-references inside both sets of reports and
inside the evidence manifest.

| File | Author |
|---|---|
| `claude-phase-6-scope.md` | **Codex** |
| `claude-phase-6-audit.md` | **Codex** |
| `claude-phase-6-comparison.md` | **Codex** |
| `claude-phase-6-evidence/` | **Codex** |
| `codex-phase-6-cross-review.md` | **Codex**, reviewing Claude |
| `claude-opus5-phase-6-scope.md` | **Claude (Opus 5)** |
| `claude-opus5-phase-6-audit.md` | **Claude (Opus 5)** |
| `claude-opus5-phase-6-comparison.md` | **Claude (Opus 5)** |
| `claude-opus5-phase-6-cross-review.md` | **Claude (Opus 5)**, reviewing Codex |
| `phase-6-reconciled-synopsis.md` | **Codex**, agreed summary of both |

---

## Reading order

1. **`phase-6-reconciled-synopsis.md`** — the agreed position. Start here.
2. The two **cross-reviews** — these carry the corrections.
3. The four **original** scope/audit/comparison files — these carry the
   evidence, and some of their conclusions are superseded (below).

---

## Which addenda supersede original conclusions

**The originals were deliberately not edited.** Where a cross-review corrects an
original, the correction is authoritative and the original text remains in place
so the overstatement stays findable. Nothing below was rebutted by either party.

### Corrections to Claude's original audit (`claude-opus5-phase-6-audit.md`)

Superseded by `claude-opus5-phase-6-cross-review.md` §5 and its amendment log:

| Original claim | Superseded by |
|---|---|
| **F-2 remedy** — send `Prefer: return=representation` and fail on zero rows | **Withdrawn.** It would have blocked a lapsed member from the deliberately ungated delete, breaking C-35. Replaced by design *constraints*, not an approved algorithm. Confirming absence via an RLS-filtered empty SELECT is also invalid — it reproduces the bug one level up |
| **F-2 consequence** — a post left `is_public = true` | **Qualified.** Not presently publicly readable: `posts_select_public_or_owner` also tests `owner_entitled_until`. Exposure is deferred to re-entitlement |
| **F-4** — the drone's audible gap was a route transition, not a stop | **Hypothesis withdrawn.** The deductive half stands (no in-app path can resume an invalidated drone; two user-only call sites). The device mechanism behind QA8's observation remains **unresolved** |
| **F-6 remedy** — delete the uploaded object on deliver failure | **Withdrawn as unsafe.** If the INSERT committed and only its response was lost, this deletes an object live rows reference. Definite rejection and uncertain outcome need different handling |
| **§3 invitations** — "not implemented, not approved, not legally cleared" | **Corrected.** Scope *is* approved. Correct statement: scope approved; implementation not authorised; legal and release gates separate; **B-40 unchanged** |
| **F-10** — "may be affecting the other auditor right now" | **Withdrawn.** Codex confirmed it read both `AGENTS.md` and current `CLAUDE.md` and the newer records. The drift finding itself stands for the next agent |
| **F-13** — "no device evidence exists either way" | **Withdrawn as too strong.** QA check 4 carries no audio/video label, so attribution is *unclear*. Does not reopen QA7 or QA8 |

Further corrections made to the cross-review itself, after Codex's second pass —
see its amendment log: the "shared root cause" framing (three distinct causes),
the "joint remedy" framing (constraints, not a design), and a findings count
that had silently downgraded F-10 from P2 to P3.

### Corrections to Codex's original audit (`claude-phase-6-audit.md`)

Refinements from `claude-opus5-phase-6-cross-review.md` §2. **All five findings
P6-I-01…05 were independently confirmed against source; none was weakened:**

- **P6-I-01** — the sibling editor is *worse* than the probed one:
  `AddEditSessionView+Attachments.swift:574` clears staged items unconditionally.
- **P6-I-02** — add that every client `posts` write is scoped by id alone, so the
  cross-account withdrawal is *reported as success*; and record the
  second-Apple-ID precondition so severity is not read as "every member".
- **P6-I-04** — broader than stated: a **wrong-type** value bypasses both decodes
  and is still overwritten.
- **P6-I-05** — forced-overlap is confined to `force: true` callers *within* the
  30-second cooldown; ordinary overlap can still arise afterwards while a newer
  attestation is pending.
- **C-17/C-54** — Codex recorded 68 test files as an inventory without running
  them. Claude ran the suite: **537 cases across 71 suites, 534 passed, 0 failed,
  3 deliberate self-reporting skips.**

---

## What neither audit establishes

**No device was operated, no live backend was read, no running UI was observed,
and no production data was touched by either pass.** Every conclusion in both
sets of reports is source-, probe- or catalog-derived.

**Neither audit found a P0 in its reviewed scope, and neither is a release
clearance.** Two independent audits agreeing is evidence about the source. It is
not whole-app safety, and it does not discharge the Phase 4 exit conditions, the
Phase 5 legal/DPIA/publication gates, C-99 residuals, or the accepted device-QA
obligations, all of which retain their own owners and statuses.

---

## Evidence

`claude-phase-6-evidence/` is Codex's, copied byte-for-byte, including its own
`README.md` (rerun instructions) and `SHA256.json` manifest. **The manifest was
re-verified against this copy: 20 files, 0 mismatches, nothing missing and
nothing unmanifested.** All probe fixtures are synthetic; no production, device
or personal data was used.

`release-build.log` (3.9 MB) is a raw `xcodebuild` transcript, retained because
the manifest covers it. It was scanned before archiving: no credentials, tokens,
private keys, signing identity or team identifier. It contains local absolute
paths under `/Users/samueldixon`, as do the reports themselves.

Claude ran its own Release build and unit-test run to an isolated scratch
directory outside the repository; those raw logs are **not** archived here. The
results are recorded in `claude-opus5-phase-6-audit.md` Appendices A and B, and
the exact commands are in `claude-opus5-phase-6-scope.md` §4, so both are
reproducible.

## Not included

The shared task brief and the two per-auditor prompts
(`phase-6-common-audit-brief.md`, `phase-6-claude-prompt.md`,
`phase-6-codex-handover.md`) remain in the working output directory at
`Documents/Codex/2026-09-17/pl/outputs/` and were not part of the requested
packet. The originals of every file archived here also remain there, untouched.
