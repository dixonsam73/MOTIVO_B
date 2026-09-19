# Lists: one-to-two instrument transition investigation

19 September 2026 — Codex investigation; no app changes, commit, push or deployment.

Samuel reports all previously requested Lists and PDF device checks green, with a new suspected Lists disappearance after adding a second saved instrument. Console excerpt contains no SwiftUI publishing-during-view-update warning and no evidence establishing List deletion. Existing device results remain accepted; this new scenario is open.

## Confirmed source mechanism

`TasksManagerView.swift:229–236` enables the instrument selector only for multiple instruments and makes the preference key suffix depend on that visibility. With one instrument, default selection is stored under the activity-only key. On reopening with two instruments, `:837–844` selects the first instrument and reloads.

`loadAll` at `:1069` reads only the new instrument-specific default key, without falling back to the activity-only default. Missing selection becomes nil. `syncAutofillCompatibilityFlag` at `:1062` then writes false for that instrument/activity, merely as a consequence of reading the screen.

The timer at `PracticeTimerView.swift:741–749` treats this explicit false as a hard stop before its activity-only fallback. Thus opening the manager after adding a second instrument can disable the previously working default List for that instrument, despite the old default still being stored.

The manager initially selects the first fetched instrument, which need not be the original instrument. Any eventual fix must distinguish existing assignments, explicit no-default choices, and an absent assignment; do not silently assign the original default to every new instrument.

## What is not established

Actual deletion of named Lists is NOT reproduced. `SavedListLibrary.key` is owner-wide and independent of instrument count. The manager displays all loaded saved Lists without an instrument filter. The instrument-add path writes Core Data instrument records, not the Lists library. If the named rows disappear entirely, further device reproduction is required; the confirmed default-selection defect alone does not explain that symptom.

## Isolated verification

Compiled current `SavedList.swift` verbatim with a disposable Foundation probe using an isolated, random UserDefaults suite. The probe mirrors the manager key/selection/write sequence and the timer early-return condition; it does not run SwiftUI or constitute device UI reproduction.

Results: real SavedListLibrary retained the named List and byte-identical canonical storage; the instrument-specific default lookup returned no selection; the subsequent false flag suppressed fallback; the original default remained stored. All assertions passed. The isolated suite was removed; no personal preferences or media accessed.

Probe source: `/tmp/EtudesInstrumentTransitionProbe.swift` (temporary evidence).

## Disposition

Confirmed default-selection/fallback bug; possible full library disappearance remains unconfirmed. Asked Samuel whether named rows vanished or only default selection/autofill was lost. Claude informed of green QA and instructed not to implement or investigate concurrently. No fix authorised by this investigation report; agree a narrow preservation rule before implementation. Adult/server freezes and paused overnight automation remain unchanged.

## Resolution note (added 19 September 2026, later the same day; the record above is preserved as written)

- **Samuel approved the product rule:** a default List is explicit per (instrument, activity),
  whatever the number of instruments. Nothing is inherited, assigned or transferred when opening
  the manager, switching, or adding or removing instruments.
- **Implemented through `ListsDefaultContext`**, shared by the Lists manager and the practice
  timer:
  - no fall-through to the activity-only context for instrument sessions;
  - manager reads write nothing;
  - the manager shows the primary instrument, then the first.
- **Legacy activity-only settings are kept raw** and are not applied to instruments. Bass's
  earlier default needed one explicit reselection.
- **The interim inherited-display workaround was superseded and never committed.**
- **Code review accepted; device QA reported all green by Samuel.**
- **Actual deletion of named Lists was never reproduced.** The apparent loss was consistent with
  the default-selection behaviour described above, and is not recorded as confirmed data loss.
