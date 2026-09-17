//
//  AttemptScopedUndo.swift
//  MOTIVO
//
//  PHASE 6 · BATCH 1 · P6-I-01 — ATTEMPT-LOCAL CORE DATA RECOVERY.
//
//  A failed save must undo exactly what this save attempt changed, and nothing
//  else. `viewContext.rollback()` cannot express that: it discards every pending
//  change on the shared main-queue context, including edits that have nothing to
//  do with this editor. `objectID.isTemporaryID` cannot express it either — it is
//  not provenance, since a pre-existing inserted object can carry a temporary id
//  and a newly inserted one can obtain a permanent id.
//
//  This wraps the attempt in its OWN undo group on its OWN undo manager, so the
//  undo is scoped by WHEN a change was registered rather than by a guess about
//  what the object looks like.
//
//  THE CONSTRAINTS ARE NOT DECORATIVE — each one is a way this goes wrong, and
//  TWO OF THEM WERE MEASURED WRONG ON THE FIRST ATTEMPT:
//
//    * pre-existing pending changes are PROCESSED before the group opens, so they
//      are never inside it and can never be undone by it;
//    * the group is explicit and `groupsByEvent = false`, so the run loop cannot
//      open or close groups underneath us;
//    * `processPendingChanges()` runs while the group is still open, because Core
//      Data registers undo operations at processing time, not at mutation time —
//      without it the group closes empty and undoes nothing;
//    * **`undo()`, NOT `undoNestedGroup()`, once the group is closed.** Measured:
//      `undoNestedGroup` on a closed top-level group is a no-op and the whole
//      attempt survived;
//    * **only ONE configuration is supported: a context with no undo manager.**
//      Reuse of a caller's manager was implemented and measured, and it did not
//      preserve their groups or history, so it is refused rather than shipped
//      half-working. `Persistence.swift` sets `viewContext.undoManager = nil`, so
//      the app is always in the supported configuration.
//
//  None of this is asserted by this comment. `P6I01AttemptScopedUndoTests` proves
//  each property against an in-memory store — restored scalars, restored
//  relationships, restored deleted rows, untouched pre-existing inserted/dirty/
//  deleted objects, and untouched caller history.
//
import Foundation
import CoreData

/// P6-I-01 — the context is in a state this helper cannot make attempt-local.
/// Raised BEFORE anything is mutated, so a save that hits it changes nothing.
struct AttemptScopedUndoUnavailable: LocalizedError {
    var errorDescription: String? {
        "This session could not be saved right now. Nothing has been changed — please try again."
    }
}

@MainActor
enum AttemptScopedUndo {

    /// One opened attempt: the manager carrying its group, and how to put the
    /// context back exactly as it was found.
    struct Ticket {
        fileprivate let manager: UndoManager
        fileprivate let installedByUs: Bool
        fileprivate let previousGroupsByEvent: Bool
        fileprivate weak var context: NSManagedObjectContext?
        fileprivate let alreadyUndone = Flag()
        fileprivate let closed = Flag()

        final class Flag { var value = false }

        /// Closes the attempt's group. Idempotent; `undo()` calls it first,
        /// because `undo()` on an OPEN group does not undo it.
        @MainActor
        fileprivate func close() {
            guard let context, !closed.value else { return }
            closed.value = true
            // Core Data registers undo operations when changes are PROCESSED, not
            // when they are made, so this must happen while the group is open.
            context.processPendingChanges()
            manager.endUndoGrouping()
        }

        /// Undoes the attempt's changes, once. Safe to call more than once.
        @MainActor
        func undo() {
            guard let context, !alreadyUndone.value else { return }
            close()
            alreadyUndone.value = true
            let restore = context.undoManager
            context.undoManager = manager
            context.processPendingChanges()
            // The group was CLOSED by `begin`, so this is `undo()`, not
            // `undoNestedGroup()` — measured: `undoNestedGroup` on a closed
            // top-level group does nothing at all and the attempt survived.
            manager.undo()
            context.processPendingChanges()
            context.undoManager = restore
        }

        /// Closes the attempt's group if it is still open, then puts the context's
        /// undo configuration back. Always called, on both paths.
        ///
        /// CLOSING IS NOT OPTIONAL. An earlier revision restored the configuration
        /// without closing, so the SUCCESS path of the non-closure API
        /// (`open` → mutate → save → `release`) left the group open. With an
        /// installed manager that leaked only until it was detached; with a
        /// caller's own manager it would have left THEIR group open, and the next
        /// save would then be refused by `open`'s precondition.
        @MainActor
        fileprivate func release() {
            guard let context else { return }
            close()
            manager.groupsByEvent = previousGroupsByEvent
            if installedByUs {
                context.undoManager = nil
            }
        }
    }

    /// Opens an attempt-scoped group and returns its ticket. **Call this BEFORE
    /// the first mutation the attempt makes** — a group opened later cannot undo
    /// what came earlier.
    ///
    /// The caller must finish with exactly one of `undoAndRelease` (failure) or
    /// `release` (success); both close the group and put the context back.
    ///
    /// SUPPORTED CONFIGURATION: a context with NO undo manager. Anything else is
    /// refused with `AttemptScopedUndoUnavailable`, before anything is processed
    /// or mutated, so the caller can abort with the member's data untouched.
    /// Reuse of a caller's manager was implemented and measured and did not
    /// preserve their groups or history, so it is not shipped.
    /// `Persistence.swift` sets `viewContext.undoManager = nil` at both
    /// construction sites, so the app is always in the supported configuration.
    static func open(in context: NSManagedObjectContext) throws -> Ticket {
        // THE GUARD COMES FIRST, BEFORE `processPendingChanges()`.
        //
        // Processing pending changes while a caller's undo manager is attached
        // registers undo actions ON THAT MANAGER — so checking afterwards would
        // already have altered the state we are about to refuse to touch.
        guard context.undoManager == nil else { throw AttemptScopedUndoUnavailable() }

        // Anything already pending belongs to somebody else. Register it now, so
        // it falls OUTSIDE our group and our undo can never reach it. Safe here:
        // there is no manager attached yet, so this registers nothing anywhere.
        context.processPendingChanges()

        let manager = UndoManager()
        context.undoManager = manager

        let previousGroupsByEvent = manager.groupsByEvent
        manager.groupsByEvent = false
        manager.beginUndoGrouping()

        return Ticket(manager: manager,
                      installedByUs: true,
                      previousGroupsByEvent: previousGroupsByEvent,
                      context: context)
    }

    static func begin<T>(in context: NSManagedObjectContext, _ body: () throws -> T) throws -> (T, Ticket) {
        let ticket = try open(in: context)
        do {
            let value = try body()
            ticket.close()
            return (value, ticket)
        } catch {
            ticket.undo()
            ticket.release()
            throw error
        }
    }

    /// `begin` plus an immediate release — for callers with nothing to do after
    /// the body.
    static func run<T>(in context: NSManagedObjectContext, _ body: () throws -> T) throws -> T {
        let (value, ticket) = try begin(in: context, body)
        ticket.release()
        return value
    }

    /// Undo the attempt and put the context's undo configuration back.
    static func undoAndRelease(_ ticket: Ticket) {
        ticket.undo()
        ticket.release()
    }

    /// Keep the attempt and put the context's undo configuration back.
    static func release(_ ticket: Ticket) {
        ticket.release()
    }
}
