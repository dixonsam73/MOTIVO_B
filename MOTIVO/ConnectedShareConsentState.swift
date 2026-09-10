//
//  ConnectedShareConsentState.swift
//  MOTIVO
//
//  PHASE 5 · UNIT 1b — the member-facing decision, and nothing else.
//
//  **ONE PRESENTER, TWO SHAPES.** `AddEditSessionView`'s body is at the SwiftUI
//  type-checker's limit: during Unit 1a a fourth `.alert` — even extracted into
//  a `ViewModifier` — produced "unable to type-check this expression in
//  reasonable time". So the existing attachment alert is GENERALISED to carry
//  either a one-action notice or this two-action consent, adding zero modifiers
//  to that chain.
//
//  **THE COPY NAMES NO CAUSE, DELIBERATELY.** Today the only permanent
//  preflight case is size, but C-75's video work and C-73's remainder may add
//  others. A presentation that understood only "video too large" would have to
//  be rewritten for each; this one does not.
//
//  **IT DECIDES NOTHING.** The verdict comes from `ConnectedSharePreflight` and
//  the omission set is carried by the payload. This type only asks.
//

import Foundation

struct ConnectedShareConsentState {

    enum Mode: Equatable {
        /// A one-action notice, e.g. an unsupported import.
        case notice(String)
        /// Attachments that cannot be included; the member must choose.
        case consent(omissions: [UUID])
    }

    var mode: Mode?

    var isPresented: Bool { mode != nil }

    var title: String {
        switch mode {
        case .notice: return "Attachment"
        case .consent(let omissions): return ConnectedSharePreflight.consentTitle(count: omissions.count)
        case nil: return ""
        }
    }

    var message: String {
        switch mode {
        case .notice(let text): return text
        case .consent(let omissions): return ConnectedSharePreflight.consentMessage(count: omissions.count)
        case nil: return ""
        }
    }

    var requiresChoice: Bool {
        if case .consent = mode { return true }
        return false
    }

    /// The ids the member would authorise omitting, if they choose to proceed.
    var pendingOmissions: [UUID] {
        if case .consent(let omissions) = mode { return omissions }
        return []
    }

    mutating func present(notice text: String) { mode = .notice(text) }
    mutating func present(consentFor omissions: [UUID]) { mode = .consent(omissions: omissions) }
    mutating func dismiss() { mode = nil }
}
