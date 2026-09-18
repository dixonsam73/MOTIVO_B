//
//  SharingChoiceSaveAlert.swift
//  MOTIVO
//
//  P6-I-02 Unit 2d-1 — tell the member when a share or stop-sharing choice
//  could not be saved, and finish the editor exactly once.
//
//  THIS IS A FIRST SLICE, NOT DURABLE INTENT. A choice that is not saved is
//  kept in memory for this session and is not sent until it is saved; if Études
//  closes first it can be lost, and after a relaunch the older saved choice is
//  what runs (P6-I-03 stays open). The copy says exactly that and promises
//  nothing more.
//

import SwiftUI

/// The words the member sees. Kept here, and tested, so the promise stays honest.
enum SharingChoiceSaveCopy {
    static let title = "Sharing change not saved"
    static let tryAgain = "Try Again"
    static let ok = "OK"

    static func message(stoppingSharing: Bool) -> String {
        if stoppingSharing {
            return "Études couldn't save your choice to stop sharing this session. "
                + "Your session itself is saved, but followers may still see the post "
                + "until this change is saved and sent. It may be lost if Études closes."
        }
        return "Études couldn't save this sharing change on your iPhone. "
            + "Your session itself is saved. This change won't be sent until it's saved, "
            + "and it may be lost if Études closes."
    }
}

/// Holds an editor's already-saved state while the member decides, and runs the
/// editor's finalisation — its callback or dismissal — EXACTLY ONCE.
///
/// Try Again re-attempts the QUEUE'S save and nothing else. The session, its
/// attachments, the practice insight, staging clean-up and draft clearing
/// happened before the alert and are never repeated; the editor's CALLBACK and
/// DISMISSAL are the finish held here, run once when the member answers.
@MainActor
final class SharingChoiceSaveGate: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var stoppingSharing = false

    /// The finish of the ONE save awaiting the member's answer. Cleared before it
    /// runs, so each save finishes at most once; a later save gets its own.
    private var pendingFinalise: (() -> Void)?
    private let recover: @MainActor () -> Bool

    init(recover: @escaping @MainActor () -> Bool = SharingChoiceSaveGate.recoverAndFlush) {
        self.recover = recover
    }

    /// The real Try Again: save the queue, and — once it is saved, including when
    /// a foreground recovery already saved it — schedule the ordinary flush. The
    /// publish's own flush was refused while the store was latched, so without
    /// this the choice would wait for the next foreground. The flush keeps every
    /// existing guard: owner binding, identity-bound transport, single flight.
    static func recoverAndFlush() -> Bool {
        let saved = SessionSyncQueue.shared.recoverIfNeeded(reason: "try-again")
        if saved {
            // P6-I-03 / C1. Now the queue holds the choice durably, the marker the
            // editor wrote can be cleared (a ledger match), and any replay the
            // halted store blocked can run — all before the flush.
            SharingHandoffRecovery.run(reason: "try-again")
            Task { @MainActor in await SessionSyncQueue.shared.flushNow() }
        }
        return saved
    }

    /// True while the member has not yet answered the alert. Editors disable Save
    /// so a second tap cannot create a second session behind it.
    var isAwaitingDecision: Bool { pendingFinalise != nil }

    /// Called once, after the editor's save and the queueing of its choice.
    func handle(_ result: SharingChoiceSaveResult, stoppingSharing: Bool, finalise: @escaping () -> Void) {
        guard result == .notSaved else {
            finalise()
            return
        }
        self.stoppingSharing = stoppingSharing
        pendingFinalise = finalise
        isPresented = true
    }

    /// Re-reads the queue first — a foreground recovery may already have saved
    /// the choice — and otherwise makes one recovery attempt.
    func tryAgain() {
        guard pendingFinalise != nil else { return }
        if recover() {
            isPresented = false
            finishPending()
        } else {
            // SwiftUI clears the binding when a button is tapped; show it again.
            isPresented = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingFinalise != nil else { return }
                self.isPresented = true
            }
        }
    }

    /// The choice stays in memory for this session; the editor finishes now.
    func acknowledge() {
        isPresented = false
        finishPending()
    }

    private func finishPending() {
        guard let finalise = pendingFinalise else { return }
        pendingFinalise = nil
        finalise()
    }
}

/// The alert, as a modifier — editor bodies are close to the type-checker's
/// limit, as Batch 1 found.
struct SharingChoiceSaveAlertModifier: ViewModifier {
    @ObservedObject var gate: SharingChoiceSaveGate

    func body(content: Content) -> some View {
        content.alert(SharingChoiceSaveCopy.title, isPresented: $gate.isPresented) {
            Button(SharingChoiceSaveCopy.tryAgain) { gate.tryAgain() }
            Button(SharingChoiceSaveCopy.ok, role: .cancel) { gate.acknowledge() }
        } message: {
            Text(SharingChoiceSaveCopy.message(stoppingSharing: gate.stoppingSharing))
        }
    }
}
