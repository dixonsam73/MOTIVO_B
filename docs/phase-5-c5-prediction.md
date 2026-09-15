# C-5 — prediction, before any edit (2026-09-15)

**Governing documents:** `claude-scope-010.md`, as approved with execution clarifications by `codex-scope-review-010.md`.

## Mechanism

- **The caller:** `ConnectedAttachmentShareUI.saveToScores` calls `ScoreLibraryStore.importPDF(from:displayName:)` on every "Add to Scores". The server's `saved_to_scores_at` is one-shot, and a second write fails silently.
- **The store:** `importPDF` always copies to a new `Documents/Scores/<UUID>.pdf` and appends a new `ScoreLibraryItem`.
- **The model:** it carries no source identity.

## Fix

- **Model:** `ScoreLibraryItem` gains `var sourceAttachmentID: UUID?` (default `nil`, synthesized Codable).
- **Store:** `importPDF(from:displayName:sourceAttachmentID: UUID? = nil)`. When the id is non-nil, it looks for an item whose `sourceAttachmentID == id` **and** whose file exists at `url(for:)`.
  - **Match found:** it returns that item **untouched**, with no copy and no persist.
  - **No match:** it imports as today and stamps the id. An older item with the same id whose file is missing is left as it is.
- **Caller:** only `ConnectedAttachmentShareUI.saveToScores` passes `sourceAttachmentID: attachment.id`.
- **Unchanged:** manual import (`ScoresLibraryView:119`), scanning (`:438`), factory reset, backup, and the server.

**Legacy limitation.** An item adopted before this change has no `sourceAttachmentID`, so it cannot be matched. The first adoption afterwards can make one new tracked copy, and later taps deduplicate. No backfill and no content matching.

## Tests — `MOTIVOTests/C5ScoreAdoptionIdentityTests.swift`, five cases

**Setup and teardown:**
- **Baseline:** `ScoreLibraryStore.shared` is initialised first. The test then snapshots the full `items`, `activeScoreID`, the raw `scoreLibrary_v2` and `scoreLibrary_activeScore_v2` values, and the file names in `Documents/Scores`.
- **Teardown:** it deletes only test-created items (through `delete(_:)`) and any leftover test-created files. It restores both defaults values exactly, then asserts the in-memory items, active selection and file set equal the baseline.
- **Scope:** the disposable hosted test process only.

**"Before"** means the test-local shim `adopt(_:_:)` calls today's `importPDF(from:displayName:)`, ignoring the id. **"After"** means it passes `sourceAttachmentID`.

| # | Case | Before | After |
|---|---|---|---|
| 1 | Adopt X, rename it and mark it favourite, adopt X again → one item; returned item keeps title and favourite; one new file | **FAIL** | PASS |
| 2 | Adopt X, delete it, adopt X again → a new item exists (re-adoption) | PASS | PASS |
| 3 | Manual import of the same file twice → two items | PASS | PASS |
| 4 | A legacy saved-library JSON fixture (no `sourceAttachmentID`) decodes, and re-encodes without that key | PASS | PASS |
| 5 | Adopt X, remove its file, adopt X (new usable copy, 2 items), adopt X again → still 2 items; returns the usable copy | **FAIL** (3 items) | PASS |

**Predicted:** 2 failed / 3 passed before, 5 / 5 after. Then one Release build. No full suite.

## Limits

- **What is tested:** the store identity rule only. The UI argument is reviewed by reading it, not driven.
- **Not tested:** device acceptance.
- **Not changed:** separate shares of the same asset still make separate Scores (a product choice), and there is no new "Already in Scores" copy.

**If a valid run contradicts a prediction, stop and report it.**
