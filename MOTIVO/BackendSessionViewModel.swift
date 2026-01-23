// CHANGE-ID: 20260119_135600_Step12_ActivityReadFix
// SCOPE: Read activity_type from backend posts when activity_label is absent (backend preview parity)
// SEARCH-TOKEN: ACTIVITY-READ-PARITY-20260119

import Foundation

// A lightweight, read-only adapter that maps a BackendPost into a UI-friendly “session-like” shape.
// This type contains no Core Data, no SwiftUI, and no business logic.
public struct BackendSessionViewModel: Identifiable {

    // MARK: - Backend attachment ref (posts.attachments jsonb)

    public struct BackendAttachmentRef: Equatable, Hashable {
        public enum Kind: String {
            case image
            case video
            case audio
        }

        public let kind: Kind
        public let path: String
        public let bucket: String

        public init(kind: Kind, path: String, bucket: String = "attachments") {
            self.kind = kind
            self.path = path
            self.bucket = bucket
        }
    }

    // MARK: - Display-ready properties

    public let id: UUID

    // Timestamps (raw strings from backend; parsing/formatting can be layered later)
    public let sessionTimestampRaw: String?
    public let durationSeconds: Int?
    public let createdAtRaw: String?
    public let updatedAtRaw: String?

    // Metadata parity (Step 8F)
    public let activityLabel: String
    public let instrumentLabel: String?
    // Extra metadata (backend viewer only)
    public let activityDetail: String?
    public let effortDotIndex: Int?
    // Optional content
    public let notes: String?

    // Step 8G Phase 2: backend attachments (decoded from posts.attachments jsonb).
    public let attachmentRefs: [BackendAttachmentRef]

    // Ownership
    public let ownerUserID: String
    public let isMine: Bool

    public init(post: BackendPost, currentUserID: String?) {
        self.id = post.id

        self.sessionTimestampRaw = post.sessionTimestamp
        self.durationSeconds = post.durationSeconds
        self.createdAtRaw = post.createdAt
        self.updatedAtRaw = post.updatedAt

        // Step 8F: map backend labels (safe if absent)
        let activityLabelRaw = (post.activityLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let activityTypeRaw = (post.activityType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveActivity = !activityLabelRaw.isEmpty ? activityLabelRaw : activityTypeRaw
        self.activityLabel = effectiveActivity.isEmpty ? "—" : effectiveActivity

        let instrument = (post.instrumentLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.instrumentLabel = instrument.isEmpty ? nil : instrument
        let rawActivityDetail = (post.activityDetail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.activityDetail = rawActivityDetail.isEmpty ? nil : rawActivityDetail

        self.effortDotIndex = post.effort

        let rawNotes = (post.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = rawNotes.isEmpty ? nil : rawNotes

        // Step 8G Phase 2: extract attachments without hard-coupling to BackendPost's concrete schema.
        // This uses runtime reflection so this file can be green even if BackendPost evolves.
        self.attachmentRefs = BackendSessionViewModel.extractAttachmentRefs(from: post)

        self.ownerUserID = post.ownerUserID ?? ""
        self.isMine = (post.ownerUserID ?? "") == (currentUserID ?? "")
    }

    // MARK: - Attachments decoding helpers (reflection-based)

    private static func extractAttachmentRefs(from post: BackendPost) -> [BackendAttachmentRef] {
        // 1) Try to find a stored property named "attachments"
        let mirror = Mirror(reflecting: post)
        guard let raw = mirror.children.first(where: { $0.label == "attachments" })?.value else {
            return []
        }

        // Unwrap Optional<...>
        let unwrapped = unwrapOptional(raw)

        // 2) Already-typed case: [BackendAttachmentRef]
        if let typed = unwrapped as? [BackendAttachmentRef] {
            return typed
        }

        // 3) Dictionary-array case: [[String: Any]] or [[String: String]]
        if let arrAny = unwrapped as? [[String: Any]] {
            return parseAttachmentDictArray(arrAny)
        }
        if let arrStr = unwrapped as? [[String: String]] {
            let bridged: [[String: Any]] = arrStr.map { $0 }
            return parseAttachmentDictArray(bridged)
        }

        // 4) String JSON
        if let jsonString = unwrapped as? String,
           let data = jsonString.data(using: .utf8) {
            return parseAttachmentJSONData(data)
        }

        // 5) Data JSON
        if let data = unwrapped as? Data {
            return parseAttachmentJSONData(data)
        }

        return []
    }

    private static func unwrapOptional(_ value: Any) -> Any {
        let m = Mirror(reflecting: value)
        if m.displayStyle != .optional { return value }
        if let child = m.children.first {
            return child.value
        }
        // nil optional
        return value
    }

    private static func parseAttachmentJSONData(_ data: Data) -> [BackendAttachmentRef] {
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            if let arr = obj as? [[String: Any]] {
                return parseAttachmentDictArray(arr)
            }
        } catch {
            // swallow (read-only convenience)
        }
        return []
    }

    private static func parseAttachmentDictArray(_ arr: [[String: Any]]) -> [BackendAttachmentRef] {
        var out: [BackendAttachmentRef] = []
        out.reserveCapacity(arr.count)

        for item in arr {
            guard
                let kindRaw = (item["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                let kind = BackendAttachmentRef.Kind(rawValue: kindRaw),
                let path = (item["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty
            else { continue }

            let bucket = (item["bucket"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveBucket = (bucket?.isEmpty == false) ? bucket! : "attachments"

            out.append(BackendAttachmentRef(kind: kind, path: path, bucket: effectiveBucket))
        }

        return out
    }
}
