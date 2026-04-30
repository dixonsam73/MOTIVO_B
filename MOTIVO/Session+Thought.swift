// CHANGE-ID: 20260430_ThoughtsSharedHelper
// SCOPE: Shared Thought detection and note parsing for metadata-free journal entries; no schema changes.
// SEARCH-TOKEN: 20260430_ThoughtsSharedHelper

import Foundation

extension Session {
    var isThought: Bool {
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return durationSeconds == 0
            && instrument == nil
            && trimmedTitle.isEmpty
            && (!trimmedNotes.isEmpty || hasThoughtAttachments)
    }

    var hasThoughtAttachments: Bool {
        if let set = attachments as? Set<Attachment> {
            return set.isEmpty == false
        }
        if let set = attachments as? NSSet {
            return set.count > 0
        }
        return false
    }

    var thoughtHeader: String? {
        ThoughtTextParts.parts(from: notes).header
    }

    var thoughtBodyPreview: String? {
        ThoughtTextParts.parts(from: notes).body
    }
}

extension BackendPost {
    var isThought: Bool {
        let trimmedTitle = (activityDetail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = (attachments ?? []).isEmpty == false
        let instrument = (instrumentLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (durationSeconds ?? 0) == 0
            && instrument.isEmpty
            && trimmedTitle.isEmpty
            && (!trimmedNotes.isEmpty || hasAttachments)
    }

    var thoughtHeader: String? {
        ThoughtTextParts.parts(from: notes).header
    }

    var thoughtBodyPreview: String? {
        ThoughtTextParts.parts(from: notes).body
    }
}

extension BackendSessionViewModel {
    var isThought: Bool {
        let trimmedTitle = (activityDetail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let instrument = (instrumentLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (durationSeconds ?? 0) == 0
            && instrument.isEmpty
            && trimmedTitle.isEmpty
            && (!trimmedNotes.isEmpty || attachmentRefs.isEmpty == false)
    }

    var thoughtHeader: String? {
        ThoughtTextParts.parts(from: notes).header
    }

    var thoughtBodyPreview: String? {
        ThoughtTextParts.parts(from: notes).body
    }
}

enum ThoughtTextParts {
    static func parts(from raw: String?) -> (header: String?, body: String?) {
        let lines = (raw ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let headerIndex = lines.firstIndex(where: { !$0.isEmpty }) else {
            return (nil, nil)
        }

        let header = lines[headerIndex]
        let body = lines[(headerIndex + 1)...]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (header, body.isEmpty ? nil : body)
    }
}
