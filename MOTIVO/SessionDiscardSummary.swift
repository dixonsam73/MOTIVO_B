//
//  SessionDiscardSummary.swift
//  MOTIVO
//
//  C-84 — WHAT A CONFIRMED DISCARD PERMANENTLY DELETES, NAMED TRUTHFULLY.
//
//  The Reset card is the one place the whole draft can be discarded. When the
//  draft holds anything the member created — staged recordings, videos, photos,
//  or task content — Reset offers "keep the draft" and "discard the draft", and
//  the copy names exactly what the discard would lose. Without such content,
//  Reset clears the time and that is all.
//

import Foundation

struct SessionDiscardSummary: Equatable {
    var recordings: Int = 0
    var videos: Int = 0
    var photos: Int = 0
    var hasTasks: Bool = false

    static let title = "Reset the timer?"
    /// Time only; everything in the draft is kept.
    static let keepTitle = "Reset timer"
    /// Time and draft; permanent, so destructive.
    static let confirmTitle = "Reset and discard draft"

    var needsConfirmation: Bool { recordings + videos + photos > 0 || hasTasks }

    /// Reset opens its card only when attachments are staged (Samuel,
    /// 2026-10-11). Task content alone does not ask: reset keeps it anyway.
    var hasAttachments: Bool { recordings + videos + photos > 0 }

    var message: String? {
        guard needsConfirmation else { return nil }
        var parts: [String] = []
        func add(_ n: Int, _ one: String, _ many: String) {
            if n > 0 { parts.append("\(n) \(n == 1 ? one : many)") }
        }
        add(recordings, "recording", "recordings")
        add(videos, "video", "videos")
        add(photos, "photo", "photos")
        if hasTasks { parts.append("your tasks") }
        let list = parts.count == 1
            ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        let pronoun = (recordings + videos + photos > 1 || hasTasks || parts.count > 1) ? "them" : "it"
        return "Keep \(list) for your next attempt, or discard \(pronoun) with the timer. Discarding permanently deletes \(pronoun) and can’t be undone."
    }

    /// Task content counts only if the member made it: a line typed, or edited
    /// away from its preset text, or a task ticked. An untouched preset line or
    /// a blank line is not member content.
    static func memberTaskContent(_ lines: [TaskLine], autoTexts: [UUID: String]) -> Bool {
        lines.contains { line in
            if line.type == .task && line.isDone { return true }
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            guard let auto = autoTexts[line.id] else { return true }
            return text != auto.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
