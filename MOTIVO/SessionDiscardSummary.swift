//
//  SessionDiscardSummary.swift
//  MOTIVO
//
//  C-84 — PRE-CHANGE STAND-IN, NO CALLER. Reports that nothing needs
//  confirmation, which is what Reset does today. It exists only so
//  `C84SessionPreservationTests` compile and fail for the right reason; the
//  implementation commit replaces this body.
//

import Foundation

struct SessionDiscardSummary: Equatable {
    var recordings: Int = 0
    var videos: Int = 0
    var photos: Int = 0
    var hasTasks: Bool = false

    static let title = "Reset session?"
    static let confirmTitle = "Delete and Reset"

    var needsConfirmation: Bool { false }
    var message: String? { nil }

    static func memberTaskContent(_ lines: [TaskLine], autoTexts: [UUID: String]) -> Bool { false }
}
