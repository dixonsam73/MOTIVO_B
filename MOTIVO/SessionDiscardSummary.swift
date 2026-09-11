//
//  SessionDiscardSummary.swift
//  MOTIVO
//
//  C-84 — WHAT A CONFIRMED RESET PERMANENTLY DELETES, NAMED TRUTHFULLY.
//
//  Reset is the one explicit whole-session discard. It asks before destroying
//  anything the member created — staged recordings, videos, photos, or task
//  content — and the copy names exactly what will be lost. The timer's value
//  alone never asks: Reset already means that.
//

import Foundation

struct SessionDiscardSummary: Equatable {
    var recordings: Int = 0
    var videos: Int = 0
    var photos: Int = 0
    var hasTasks: Bool = false

    static let title = "Reset session?"
    static let confirmTitle = "Delete and Reset"

    var needsConfirmation: Bool { recordings + videos + photos > 0 || hasTasks }

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
        return "This resets the timer and permanently deletes \(list). This can’t be undone."
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
