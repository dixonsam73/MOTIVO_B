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
        if let set = attachments {
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
        let text = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.isEmpty == false else {
            return (nil, nil)
        }

        let characters = Array(text)

        var splitIndex: Int?

        for index in characters.indices {
            let character = characters[index]

            guard character == "." || character == "!" || character == "?" else {
                continue
            }

            let nextIndex = characters.index(after: index)

            if nextIndex == characters.endIndex ||
                characters[nextIndex].isWhitespace {
                splitIndex = index
                break
            }
        }

        guard let splitIndex else {
            return (text, nil)
        }

        let header = String(characters[...splitIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let bodyStart = characters.index(after: splitIndex)

        let body = bodyStart < characters.endIndex
            ? String(characters[bodyStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return (header.isEmpty ? nil : header,
                body.isEmpty ? nil : body)
    }
    }
