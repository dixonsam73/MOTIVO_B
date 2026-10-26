//
//  ProfileNameCommitPolicy.swift
//  MOTIVO
//
//  C-137. The profile name is mandatory: set-up cannot finish without one,
//  and the home screen's set-up gate (`PracticeTimerView.requiresAppSetUpNow`)
//  reads the committed Profile row. Profile commits that row on every typing
//  pause (C-70), so a field emptied before retyping used to commit "" and send
//  an established person back to onboarding, and, with private sync, the
//  other device too. The rule: an empty draft never commits over an existing
//  name; the field shows the kept name again when the edit finishes.
//

import Foundation

enum ProfileNameCommitPolicy {
    /// What the Profile row (and the directory) should hold for this draft.
    static func committedName(draft: String, stored: String?) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let kept = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return kept
    }

    /// When an edit finishes with an empty field over an existing name, the
    /// text the field should show again; nil when nothing needs restoring.
    static func restoredDraft(draft: String, stored: String?) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return nil }
        let kept = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? nil : kept
    }
}
