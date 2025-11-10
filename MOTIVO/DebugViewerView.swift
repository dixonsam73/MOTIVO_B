// CHANGE-ID: v710G-DebugViewer-20251028-1630
// SCOPE: Debug Viewer Mode (DEBUG only), read-only inspector

#if DEBUG
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Foundation

struct FollowContextDump: Encodable {
    let viewerID: String
    let sessionOwnerID: String?
    let approvedIDs: [String]
    let pendingTargets: [String]
    let relationToOwner: String?   // "approved" | "pending" | "blocked" | "none"
}

extension DebugDump {

    @MainActor static func followContext(for viewerID: String, sessionOwnerID: String?) -> FollowContextDump {
        let store = FollowStore.shared
        let approved = store.followingIDs()
        let pending = Array(store.requests)

        var relation: String? = nil
        if let owner = sessionOwnerID {
            relation = store.state(for: owner).rawValue
        } else {
            relation = "none"
        }

        return FollowContextDump(
            viewerID: viewerID,
            sessionOwnerID: sessionOwnerID,
            approvedIDs: approved,
            pendingTargets: pending,
            relationToOwner: relation
        )
    }
}

public struct DebugViewerView: View {
    private let title: String
    @Binding private var jsonString: String
    @State private var isPretty: Bool = true

    public init(title: String, jsonString: Binding<String>) {
        self.title = title
        self._jsonString = jsonString
    }

    private var displayText: String {
        if isPretty, let pretty = Self.prettyPrinted(jsonString: jsonString) { return pretty }
        return jsonString
    }

    public var body: some View {
        ScrollView {
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Pretty/Raw toggle
                Button(isPretty ? "Raw" : "Pretty") {
                    togglePretty()
                }
                .accessibilityLabel(isPretty ? "Show raw JSON" : "Show pretty JSON")

                // Copy button
                Button("Copy") {
                    copyToClipboard(displayText)
                }
                .accessibilityLabel("Copy JSON")

                // Share button
                ShareButton(content: displayText)
            }
        }
    }

    private func togglePretty() {
        isPretty.toggle()
    }

    private static func prettyPrinted(jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
            return String(data: pretty, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Share Button helper

fileprivate struct ShareButton: View {
    let content: String
    var body: some View {
        #if canImport(UIKit)
        if #available(iOS 16.0, *) {
            ShareLink(item: content) {
                Image(systemName: "square.and.arrow.up")
            }
        } else {
            Button {
                presentActivityVC(text: content)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        #else
        Button("") { }
        #endif
    }

    #if canImport(UIKit)
    private func presentActivityVC(text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(activity, animated: true)
    }
    #endif
}

// MARK: - Debug dump utilities

public enum DebugDump {
    // Minimal, read-only snapshots safe for JSON encoding.
    struct SessionSnapshot: Encodable {
        let id: String?
        let title: String?
        let notes: String?
        let timestamp: Date?
        let durationSeconds: Int64
        let isPublic: Bool?
        let ownerUserID: String?
        let attachmentCount: Int
        let attachmentIDs: [String]
    }

    struct AttachmentSnapshot: Encodable {
        let id: String?
        let kind: String?
        let isThumbnail: Bool
        let createdAt: Date?
        let fileName: String?
        let fileURL: String?
    }

    @MainActor public static func dump(session: Any) -> String {
        // Best-effort reflection to avoid importing Core Data types here.
        // Expecting fields accessed via KVC-style lookups.
        // If anything fails, return an error stub.
        // Known field names from codebase: id (UUID), title (String?), notes (String?), timestamp (Date?), durationSeconds (Int64), isPublic (Bool?), ownerUserID (String?), attachments (Set<Attachment>)
        let mirror = Mirror(reflecting: session)
        var idString: String? = nil
        var title: String? = nil
        var notes: String? = nil
        var timestamp: Date? = nil
        var durationSeconds: Int64 = 0
        var isPublic: Bool? = nil
        var ownerUserID: String? = nil
        var attachmentIDs: [String] = []

        func valueForKey(_ key: String) -> Any? {
            // Try KVC via NSObject if available
            if let obj = session as AnyObject?, obj.responds(to: Selector(key)) {
                return obj.value(forKey: key)
            }
            // Fallback: mirror children
            for child in mirror.children {
                if child.label == key { return child.value }
            }
            return nil
        }

        // id
        if let uuid = valueForKey("id") as? UUID { idString = uuid.uuidString }
        else if let s = valueForKey("id") as? String { idString = s }

        title = valueForKey("title") as? String
        notes = valueForKey("notes") as? String
        timestamp = valueForKey("timestamp") as? Date
        if let d = valueForKey("durationSeconds") as? Int64 { durationSeconds = d }
        else if let d = valueForKey("durationSeconds") as? Int { durationSeconds = Int64(d) }
        isPublic = valueForKey("isPublic") as? Bool
        ownerUserID = valueForKey("ownerUserID") as? String

        var count = 0
        if let set = valueForKey("attachments") as? Set<AnyHashable> {
            count = set.count
            for any in set {
                if let anyObj = any as AnyObject?, let id = anyObj.value(forKey: "id") as? UUID {
                    attachmentIDs.append(id.uuidString)
                }
            }
        }

        let snap = SessionSnapshot(
            id: idString,
            title: title,
            notes: notes,
            timestamp: timestamp,
            durationSeconds: durationSeconds,
            isPublic: isPublic,
            ownerUserID: ownerUserID,
            attachmentCount: count,
            attachmentIDs: attachmentIDs.sorted()
        )

        #if DEBUG
        // Build a wrapper payload that includes followContext without altering existing fields
        struct SessionDumpWrapper: Encodable {
            let session: SessionSnapshot
            let attachments: [AttachmentSnapshot]
            let followContext: FollowContextDump?
        }

        // Attempt to collect attachments if present and encodable via our AttachmentSnapshot logic
        var attachSnaps: [AttachmentSnapshot] = []
        if let set = valueForKey("attachments") as? Set<AnyHashable> {
            for any in set {
                if let anyObj = any as AnyObject? {
                    let idString: String? = (anyObj.value(forKey: "id") as? UUID)?.uuidString
                    let kind = anyObj.value(forKey: "kind") as? String
                    let isThumb = (anyObj.value(forKey: "isThumbnail") as? Bool) ?? false
                    let createdAt = anyObj.value(forKey: "createdAt") as? Date
                    let fileURL = anyObj.value(forKey: "fileURL") as? String
                    let fileName = fileURL.flatMap { URL(fileURLWithPath: $0).lastPathComponent }
                    attachSnaps.append(AttachmentSnapshot(id: idString, kind: kind, isThumbnail: isThumb, createdAt: createdAt, fileName: fileName, fileURL: fileURL))
                }
            }
        }

        // Determine viewer ID using whatever is available in DEBUG; prefer auth if present, else persistence fallback
        var viewerIDResolved: String? = nil
        // Try an Auth-like singleton if present
        if let authClass = NSClassFromString("AuthManager") as? NSObject.Type,
           let auth = authClass.value(forKey: "shared") as? NSObject,
           let currentUserID = auth.value(forKey: "currentUserID") as? String {
            viewerIDResolved = currentUserID
        }
        if viewerIDResolved == nil,
           let pcClass = NSClassFromString("PersistenceController") as? NSObject.Type,
           let pcShared = pcClass.value(forKey: "shared") as? NSObject,
           let currentUserID = pcShared.value(forKey: "currentUserID") as? String {
            viewerIDResolved = currentUserID
        }

        let followCtx = viewerIDResolved.map { DebugDump.followContext(for: $0, sessionOwnerID: ownerUserID) }

        let payload = SessionDumpWrapper(
            session: snap,
            attachments: attachSnaps,
            followContext: followCtx
        )
        return encodeJSON(payload)
        #endif

        return encodeJSON(snap)
    }

    public static func dump(attachments: [Any]) -> String {
        var snaps: [AttachmentSnapshot] = []
        for a in attachments {
            let obj = a as AnyObject
            let idString: String? = (obj.value(forKey: "id") as? UUID)?.uuidString
            let kind = obj.value(forKey: "kind") as? String
            let isThumb = (obj.value(forKey: "isThumbnail") as? Bool) ?? false
            let createdAt = obj.value(forKey: "createdAt") as? Date
            let fileURL = obj.value(forKey: "fileURL") as? String
            let fileName = fileURL.flatMap { URL(fileURLWithPath: $0).lastPathComponent }
            snaps.append(AttachmentSnapshot(id: idString, kind: kind, isThumbnail: isThumb, createdAt: createdAt, fileName: fileName, fileURL: fileURL))
        }
        return encodeJSON(snaps)
    }

    public static func dump(post: Any) -> String {
        // For symmetry; try common fields: id, ownerUserID, createdAt, text, sessionID
        let obj = post as AnyObject
        var dict: [String: Any?] = [:]
        dict["id"] = (obj.value(forKey: "id") as? UUID)?.uuidString ?? (obj.value(forKey: "id") as? String)
        dict["ownerUserID"] = obj.value(forKey: "ownerUserID") as? String
        dict["createdAt"] = obj.value(forKey: "createdAt") as? Date
        dict["text"] = obj.value(forKey: "text") as? String
        dict["sessionID"] = (obj.value(forKey: "sessionID") as? UUID)?.uuidString
        return encodeJSON(dict)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        do {
            let data = try enc.encode(value)
            return String(data: data, encoding: .utf8) ?? "{\"error\":\"encoding-failed\"}"
        } catch {
            return "{\"error\":\"encoding-failed\",\"message\":\"\(error.localizedDescription)\"}"
        }
    }

    private static func encodeJSON(_ dict: [String: Any?]) -> String {
        var cleaned: [String: Any] = [:]
        for (k, v) in dict { if let v = v { cleaned[k] = v } }
        do {
            let data = try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .withoutEscapingSlashes])
            return String(data: data, encoding: .utf8) ?? "{\"error\":\"encoding-failed\"}"
        } catch {
            return "{\"error\":\"encoding-failed\"}"
        }
    }
}

#endif

