// CHANGE-ID: 20260108_134900_Step8G_StorageHello_DebugViewer
// SCOPE: Step 8G seed — DEBUG-only Storage “Hello” (upload bundled image to attachments bucket + download via authenticated endpoint); additive-only.
// ADD-ON: Step 8A/8A.1 — Backend Feed debug fetch (Mine) + diagnostics.
// ADD-ON: Step 8B — Add Fetch All + allPosts + targetOwners diagnostics (debug-only). Additive-only.
// SEARCH-TOKEN: 20260108_134900_Step8G_StorageHello_DebugViewer

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
    @State private var deletePostIDText: String = ""
    @State private var deletePostStatusText: String? = nil


    // Step 8G (debug-only): Storage “Hello” pipeline (upload a bundled test image, then download via authenticated endpoint)
    @State private var storageHelloIsWorking: Bool = false
    @State private var storageHelloIsBusy: Bool = false
    @State private var storageHelloStatus: String = ""
    @State private var storageHelloObjectPath: String? = nil   // e.g. "debug/abc.png" (no bucket prefix)
    @State private var storageHelloImage: UIImage? = nil

    // Step 8A/8A.1/8B (debug-only): backend feed store
    @ObservedObject private var backendFeedStore: BackendFeedStore = .shared

    // Observe backend mode to trigger a mode-change tick
    @State private var observedBackendMode: BackendMode = BackendEnvironment.shared.mode
    private let backendModeTickKey = "BackendModeChangeTick_v1"

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



    // MARK: - Backend Storage “Hello” section (Step 8G seed)

    @ViewBuilder private var backendStorageHelloBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend • Step 8G Storage (DEBUG seed)").font(.headline)

            Text("Uploads a bundled debug image (Assets.xcassets → debug_upload_test) into Storage bucket “attachments” under folder “debug/”, then downloads it back using the authenticated Storage endpoint.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // Required RLS hint (dashboard-created bucket has owner unset; policies still required).
            VStack(alignment: .leading, spacing: 4) {
                Text("Supabase policies required (run in SQL Editor):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("""
create policy "debug uploads to attachments/debug"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'attachments' and
  (storage.foldername(name))[1] = 'debug'
);

create policy "debug reads from attachments/debug"
on storage.objects for select to authenticated
using (
  bucket_id = 'attachments' and
  (storage.foldername(name))[1] = 'debug'
);
""")
                .font(.caption2)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                Button(storageHelloIsBusy ? "Working…" : "Run Storage Hello") {
                    Task { await runStorageHello() }
                }
                .disabled(storageHelloIsBusy)

                if let objectPath = storageHelloObjectPath {
                    Button("Clear") {
                        storageHelloStatus = ""
                        storageHelloObjectPath = nil
                        storageHelloImage = nil
                        storageHelloIsWorking = false
                    }
                    .disabled(storageHelloIsBusy)

                    Text(objectPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if !storageHelloStatus.isEmpty {
                Text(storageHelloStatus)
                    .font(.footnote)
                    .foregroundStyle(storageHelloIsWorking ? .secondary : .primary)
            }

            if let uiImage = storageHelloImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, 8)
    }

    @MainActor private func runStorageHello() async {
        storageHelloIsBusy = true
        defer { storageHelloIsBusy = false }

        storageHelloStatus = "Preparing asset…"
        storageHelloIsWorking = false
        storageHelloImage = nil
        storageHelloObjectPath = nil

        #if canImport(UIKit)
        guard let img = UIImage(named: "debug_upload_test") else {
            storageHelloStatus = "❌ Asset not found: UIImage(named: \"debug_upload_test\") returned nil. Check Assets.xcassets name."
            return
        }
        guard let data = img.pngData() else {
            storageHelloStatus = "❌ Could not encode debug image as PNG."
            return
        }
        #else
        storageHelloStatus = "❌ UIKit not available; cannot load UIImage asset."
        return
        #endif

        let fileName = "debug_upload_test_\(Int(Date().timeIntervalSince1970)).png"
        let objectPath = "debug/\(fileName)"
        let uploadPath = "storage/v1/object/attachments/\(objectPath)"

        storageHelloStatus = "Uploading to Storage…"

        let uploadResult = await NetworkManager.shared.request(
            path: uploadPath,
            method: "POST",
            jsonBody: data,
            headers: [
                "Content-Type": "image/png",
                // Optional: allow overwriting if same path is reused; we use timestamp names so it should not collide.
                "x-upsert": "false"
            ]
        )

        switch uploadResult {
        case .failure(let error):
            storageHelloStatus = "❌ Upload failed. Likely missing Storage RLS policies. Error: \(error.localizedDescription)"
            return

        case .success(let responseData):
            // Expected: {"Key":"attachments/debug/filename.png"} (REST API)
            if let key = parseStorageKey(from: responseData) {
                // Convert "attachments/<path>" → "<path>"
                let cleaned = key.hasPrefix("attachments/") ? String(key.dropFirst("attachments/".count)) : key
                storageHelloObjectPath = cleaned
            } else {
                // If response format changes, still try the known objectPath we asked for.
                storageHelloObjectPath = objectPath
            }
        }

        guard let objectPathResolved = storageHelloObjectPath else {
            storageHelloStatus = "❌ Upload succeeded but could not resolve object path."
            return
        }

        storageHelloStatus = "Downloading via authenticated endpoint…"
        let downloadPath = "storage/v1/object/authenticated/attachments/\(objectPathResolved)"

        let downloadResult = await NetworkManager.shared.request(
            path: downloadPath,
            method: "GET"
        )

        switch downloadResult {
        case .failure(let error):
            storageHelloStatus = "❌ Download failed. Check SELECT policy. Error: \(error.localizedDescription)"
            return

        case .success(let bytes):
            #if canImport(UIKit)
            if let img = UIImage(data: bytes) {
                storageHelloImage = img
                storageHelloIsWorking = true
                storageHelloStatus = "✅ Storage Hello OK (uploaded + downloaded)."
            } else {
                storageHelloStatus = "❌ Downloaded bytes could not be decoded as an image."
            }
            #else
            storageHelloStatus = "✅ Download succeeded (\(bytes.count) bytes), but UIKit not available to render."
            storageHelloIsWorking = true
            #endif
        }
    }

    private func parseStorageKey(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = obj as? [String: Any]
        else { return nil }

        if let key = dict["Key"] as? String { return key }
        if let key = dict["key"] as? String { return key }
        return nil
    }

    // MARK: - Backend feed debug section (Step 8A/8B)

    @ViewBuilder private var backendFeedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend • Step 8A/8B Feed").font(.headline)

            HStack(spacing: 12) {
                Button(backendFeedStore.isFetching ? "Fetching…" : "Fetch Mine") {
                    Task { _ = await BackendEnvironment.shared.publish.fetchFeed(scope: "mine") }
                }
                .disabled(backendFeedStore.isFetching)

                Button(backendFeedStore.isFetching ? "Fetching…" : "Fetch All") {
                    Task { _ = await BackendEnvironment.shared.publish.fetchFeed(scope: "all") }
                }
                .disabled(backendFeedStore.isFetching)

                Spacer()

                Text("mine: \(backendFeedStore.minePosts.count) • all: \(backendFeedStore.allPosts.count)")
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Post UUID", text: $deletePostIDText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                    Button(backendFeedStore.isFetching ? "Deleting…" : "Delete Post") {
                        let trimmed = deletePostIDText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let uuid = UUID(uuidString: trimmed) else {
                            deletePostStatusText = "Invalid UUID"
                            return
                        }
                        deletePostStatusText = nil
                        Task {
                            let result = await BackendEnvironment.shared.publish.deletePost(uuid)
                            switch result {
                            case .success:
                                deletePostStatusText = "Deleted \(uuid.uuidString)"
                            case .failure(let error):
                                deletePostStatusText = "Delete failed: \(String(describing: error))"
                            }
                        }
                    }
                    .disabled(backendFeedStore.isFetching)
                }
                if let status = deletePostStatusText, !status.isEmpty {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(status.lowercased().contains("fail") ? .red : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("scope: \(backendFeedStore.lastScope ?? "nil")")
                    .font(.footnote)

                Text("rawPosts: \(backendFeedStore.lastRawCount) • minePosts: \(backendFeedStore.lastMineCount) • allPosts: \(backendFeedStore.lastAllCount)")
                    .font(.footnote)

                Text("targetOwners: \(backendFeedStore.lastTargetOwnerCount)")
                    .font(.footnote)

                if !backendFeedStore.lastTargetOwnerSamples.isEmpty {
                    Text("target owner samples:")
                        .font(.footnote)
                        .opacity(0.8)
                    ForEach(Array(backendFeedStore.lastTargetOwnerSamples.prefix(3).enumerated()), id: \.offset) { _, s in
                        Text("• \(s)")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }

                if let key = backendFeedStore.lastOwnerKey, !key.isEmpty {
                    Text("ownerKey: \(key)")
                        .font(.footnote)
                        .lineLimit(1)
                } else {
                    Text("ownerKey: nil")
                        .font(.footnote)
                        .opacity(0.7)
                }

                if !backendFeedStore.lastOwnerSamples.isEmpty {
                    Text("owner samples:")
                        .font(.footnote)
                        .opacity(0.8)
                    ForEach(Array(backendFeedStore.lastOwnerSamples.prefix(3).enumerated()), id: \.offset) { _, s in
                        Text("• \(s)")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }

                if !backendFeedStore.lastCreatedAtSamples.isEmpty {
                    Text("createdAt samples:")
                        .font(.footnote)
                        .opacity(0.8)
                    ForEach(Array(backendFeedStore.lastCreatedAtSamples.prefix(3).enumerated()), id: \.offset) { _, s in
                        Text("• \(s)")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 4)

            if let t = backendFeedStore.lastFetchAt {
                Text("lastFetchAt: \(t.formatted(date: .abbreviated, time: .standard))")
                    .font(.footnote)
            } else {
                Text("lastFetchAt: nil")
                    .font(.footnote)
                    .opacity(0.7)
            }

            if let err = backendFeedStore.lastError, !err.isEmpty {
                Text("error: \(err)")
                    .font(.footnote)
                    .foregroundColor(.red)
            } else {
                Text("error: nil")
                    .font(.footnote)
                    .opacity(0.7)
            }

            if !backendFeedStore.allPosts.isEmpty {
                Text("first posts:")
                    .font(.footnote)
                    .opacity(0.8)

                ForEach(Array(backendFeedStore.allPosts.prefix(3)), id: \.id) { p in
                    let suffix = p.createdAt.map { " — \($0)" } ?? ""
                    Text("• \(p.id.uuidString)\(suffix)")
                        .font(.footnote)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var jsonDumpBlock: some View {
        // JSON dump at the top
        Text(displayText)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.black.opacity(0.06))
            .cornerRadius(8)
            .padding(.horizontal)
    }

    @ViewBuilder private var backendControlsBlock: some View {
        // Backend + sync controls
        BackendModeSection()
        APIConfigView()
        SyncQueueSection()
    }

    @ViewBuilder private var backendStep6ABlock: some View {
        // Precompute mode line to ease type-checking
        let modeRaw: String = BackendEnvironment.shared.mode.rawValue
        let isBackendEnabled: Bool = (BackendEnvironment.shared.mode == .backendPreview)
        let enabledString: String = isBackendEnabled ? "true" : "false"
        let modeLine: String = "mode: \(modeRaw) • backend enabled: \(enabledString)"

        // Backend • Step 6A diagnostics
        VStack(alignment: .leading, spacing: 8) {
            Text("Backend • Step 6A").font(.headline)

            // 1) Mode
            Text(modeLine)
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
                    Text("• \(item.id.uuidString)")
                        .font(.footnote)
                }
            }

            // 5) Hint
            Text("Note: publish service selection is decided at app launch; relaunch after changing preview/config.")
                .font(.footnote)
                .opacity(0.7)
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var simulateFollowsBlock: some View {
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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                jsonDumpBlock

                backendControlsBlock

                backendStep6ABlock

                backendStorageHelloBlock

                backendFeedSection

                simulateFollowsBlock
            }
            .padding(.top, 8)
        }
        .onChange(of: BackendEnvironment.shared.mode) { _, newValue in
            // Keep a local copy updated
            observedBackendMode = newValue
            // Increment the mode change tick to force view refreshes listening to this key
            let k = backendModeTickKey
            let cur = UserDefaults.standard.integer(forKey: k)
            UserDefaults.standard.set(cur + 1, forKey: k)
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
            if let obj = session as AnyObject?, obj.responds(to: Selector(key)) {
                return obj.value(forKey: key)
            }
            for child in mirror.children {
                if child.label == key { return child.value }
            }
            return nil
        }

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
        struct SessionDumpWrapper: Encodable {
            let session: SessionSnapshot
            let attachments: [AttachmentSnapshot]
            let followContext: FollowContextDump?
        }

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

        let viewerIDResolved: String = {
            if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"),
               !override.isEmpty {
                return override
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



