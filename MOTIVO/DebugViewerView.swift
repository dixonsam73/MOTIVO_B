// CHANGE-ID: v7.13A-DebugViewer-OverrideViewerID-20251201_1830
// SCOPE: Social hardening — use Debug.currentUserIDOverride in followContext viewerID + ensure JSON block is visible in scroll view.

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
    @State private var targetID: String = "user_B"
    @State private var acceptFromID: String = "local-device"
    @StateObject private var followStore = FollowStore.shared

    private var activeViewerID: String {
        if let o = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"), !o.isEmpty {
            return o
        }
        if let current = PersistenceController.shared.currentUserID {
            return current
        }
        return "local-device"
    }

    public init(title: String, jsonString: Binding<String>) {
        self.title = title
        self._jsonString = jsonString
    }

    private var displayText: String {
        if isPretty, let pretty = Self.prettyPrinted(jsonString: jsonString), !pretty.isEmpty {
            return pretty
        }
        if !jsonString.isEmpty {
            return jsonString
        }
        // Fallback so we *see* something if the buffer is never populated
        return "(debugJSONBuffer is empty – no debug payload received)"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // JSON dump at the top
                Text(displayText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black.opacity(0.06))
                    .cornerRadius(8)
                    .padding(.horizontal)

                // Backend + sync controls
                BackendModeSection()
                APIConfigView()
                SyncQueueSection()

                // Backend • Step 6A diagnostics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend • Step 6A").font(.headline)

                    // 1) Mode
                    Text("mode: \(BackendEnvironment.shared.mode.rawValue) • backend enabled: \(BackendEnvironment.shared.mode == .backendPreview ? "true" : "false")"
                    )
                    .font(.subheadline)

                    // 2) Network config
                    Group {
                        if let url = NetworkManager.shared.baseURL {
                            Text("baseURL: \(url.absoluteString)")
                                .font(.footnote)
                        } else {
                            Text("baseURL: nil")
                                .font(.footnote)
                        }
                    }

                    // 3) Publish service type
                    Text("publish service: \(String(describing: type(of: BackendEnvironment.shared.publish)))")
                        .font(.subheadline)

                    // 4) Queue
                    VStack(alignment: .leading, spacing: 4) {
                        Text("queue: \(SessionSyncQueue.shared.items.count)")
                            .font(.subheadline)
                        ForEach(Array(SessionSyncQueue.shared.items.prefix(5)), id: \.id) { item in
                            Text("• \(item.id.uuidString)\(item.lastError != nil ? " — " + (item.lastError ?? "") : "")")
                                .font(.footnote)
                        }
                    }

                    // 5) Hint
                    Text("Note: publish service selection is decided at app launch; relaunch after changing preview/config.")
                        .font(.footnote)
                        .opacity(0.7)
                }
                .padding(.horizontal)

                // Simulate Follows panel
                VStack(alignment: .leading, spacing: 12) {
                    Text("Simulate Follows").font(.headline)

                    HStack {
                        Text("Viewer: \(activeViewerID)")
                            .font(.subheadline)
                        Spacer()
                    }

                    HStack {
                        TextField("Counterparty ID", text: $targetID)
                            .textFieldStyle(.roundedBorder)
                        Button("Request") {
                            FollowStore.shared.simulateRequestFollow(to: targetID)
                            FollowStore.shared.debugReload()
                        }
                        Button("Unfollow") {
                            FollowStore.shared.simulateUnfollow(targetID)
                            FollowStore.shared.debugReload()
                        }
                    }

                    HStack {
                        TextField("Accept From ID", text: $acceptFromID)
                            .textFieldStyle(.roundedBorder)
                        Button("Accept From") {
                            FollowStore.shared.simulateAcceptFollow(from: acceptFromID)
                            FollowStore.shared.debugReload()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top, 8)
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

                // Identity menu
                Menu("Identity") {
                    Button("local-device") {
                        UserDefaults.standard.set("local-device", forKey: "Debug.currentUserIDOverride")
                        PublishService.shared.setOwnerKey("local-device")
                        FollowStore.shared.debugReload()
                    }
                    Button("user_B") {
                        UserDefaults.standard.set("user_B", forKey: "Debug.currentUserIDOverride")
                        PublishService.shared.setOwnerKey("user_B")
                        FollowStore.shared.debugReload()
                    }
                    Button("user_C") {
                        UserDefaults.standard.set("user_C", forKey: "Debug.currentUserIDOverride")
                        PublishService.shared.setOwnerKey("user_C")
                        FollowStore.shared.debugReload()
                    }
                    Divider()
                    Button("Clear Override") {
                        UserDefaults.standard.removeObject(forKey: "Debug.currentUserIDOverride")
                        PublishService.shared.setOwnerKey(PersistenceController.shared.currentUserID ?? "local-device")
                        FollowStore.shared.debugReload()
                    }
                }
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

        // Determine viewer ID using whatever is available in DEBUG; prefer override, then auth, then persistence fallback
        let viewerIDResolved: String = {
            if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"),
               !override.isEmpty {
                return override
            }

            if let authClass = NSClassFromString("AuthManager") as? NSObject.Type,
               let auth = authClass.value(forKey: "shared") as? NSObject,
               let currentUserID = auth.value(forKey: "currentUserID") as? String,
               !currentUserID.isEmpty {
                return currentUserID
            }

            if let pcClass = NSClassFromString("PersistenceController") as? NSObject.Type,
               let pcShared = pcClass.value(forKey: "shared") as? NSObject,
               let currentUserID = pcShared.value(forKey: "currentUserID") as? String,
               !currentUserID.isEmpty {
                return currentUserID
            }

            return "local-device"
        }()

        let followCtx = DebugDump.followContext(for: viewerIDResolved, sessionOwnerID: ownerUserID)

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
        dict["text"] = (obj.value(forKey: "text") as? String)
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

