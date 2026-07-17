// CHANGE-ID: 20260717_ConnectedAttachmentUserFacingName
// SCOPE: Preserve storage filename identity while carrying optional user-facing attachment_name metadata through Connected upload, delivery and receipt. Backwards-compatible fallback remains filename.
// SEARCH-TOKEN: 20260717_ConnectedAttachmentUserFacingName
//
// CHANGE-ID: 20260716_M8C_ConnectedSessionAttachmentSharing
// SCOPE: Generalise the existing Connected attachment upload boundary and recipient local-file persistence for PDF, photo, audio and video payloads. Preserve schema, delivery, upload-once/reference-many, notifications and recipient lifecycle.
// SEARCH-TOKEN: 20260716_M8C_ConnectedSessionAttachmentSharing
//
// CHANGE-ID: 20260715_ConnectedAttachmentNotifications_Phase1
// SCOPE: Add recipient viewed state, unread derivation, and idempotent mark-viewed support
// for the existing relational notification pipeline. No transport, storage, save, delete,
// page export, sharing ownership, or presentation changes.
//
// CHANGE-ID: 20260714_ConnectedAttachmentSharing_Phase1
// SCOPE: Connected-only immutable PDF attachment delivery, persistent local recipient copies,
// one-upload/many-recipient rows, and recipient-only lifecycle metadata. No post/feed/messaging integration.

import Foundation
import Combine

public struct ConnectedAttachment: Codable, Hashable, Identifiable {
    public let id: UUID
    public let assetID: UUID
    public let senderUserID: String
    public let recipientUserID: String
    public let storageBucket: String
    public let storagePath: String
    public let filename: String
    public let attachmentName: String?
    public let mimeType: String
    public let byteCount: Int64
    public let pageCount: Int
    public let createdAt: Date
    public let savedToScoresAt: Date?
    public let deletedAt: Date?
    public let viewedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case assetID = "asset_id"
        case senderUserID = "sender_user_id"
        case recipientUserID = "recipient_user_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case filename
        case attachmentName = "attachment_name"
        case mimeType = "mime_type"
        case byteCount = "byte_count"
        case pageCount = "page_count"
        case createdAt = "created_at"
        case savedToScoresAt = "saved_to_scores_at"
        case deletedAt = "deleted_at"
        case viewedAt = "viewed_at"
    }
}


public struct ConnectedAttachmentUploadPayload: Hashable {
    public let localURL: URL
    public let filename: String
    public let attachmentName: String?
    public let mimeType: String
    public let pageCount: Int

    public init(localURL: URL, filename: String, attachmentName: String? = nil, mimeType: String, pageCount: Int = 0) {
        self.localURL = localURL
        self.filename = filename
        self.attachmentName = attachmentName
        self.mimeType = mimeType
        self.pageCount = pageCount
    }
}

public struct ConnectedAttachmentUploadReference: Hashable {
    public let assetID: UUID
    public let storageBucket: String
    public let storagePath: String
    public let filename: String
    public let attachmentName: String?
    public let mimeType: String
    public let byteCount: Int64
    public let pageCount: Int
}

public enum AttachmentShareDestination: Hashable {
    case person
    case ensemble
    case iOS
}

public enum AttachmentSharePageScope: Hashable {
    case entireDocument
    case currentPage(Int)
    case selectedPages([Int])
}

public protocol BackendConnectedAttachmentService {
    func upload(_ payload: ConnectedAttachmentUploadPayload) async -> Result<ConnectedAttachmentUploadReference, Error>
    func deliver(_ reference: ConnectedAttachmentUploadReference, to recipientUserIDs: [String]) async -> Result<Void, Error>
    func fetchReceived() async -> Result<[ConnectedAttachment], Error>
    func markViewed(id: UUID) async -> Result<Void, Error>
    func markSavedToScores(id: UUID) async -> Result<Void, Error>
    func softDelete(id: UUID) async -> Result<Void, Error>
    func download(_ attachment: ConnectedAttachment) async -> Result<Data, Error>
}

public extension BackendConnectedAttachmentService {
    func uploadPDF(
        localURL: URL,
        filename: String,
        attachmentName: String? = nil,
        pageCount: Int
    ) async -> Result<ConnectedAttachmentUploadReference, Error> {
        await upload(
            ConnectedAttachmentUploadPayload(
                localURL: localURL,
                filename: filename,
                attachmentName: attachmentName,
                mimeType: "application/pdf",
                pageCount: pageCount
            )
        )
    }
}

public struct SimulatedConnectedAttachmentService: BackendConnectedAttachmentService {
    public init() {}
    public func upload(_ payload: ConnectedAttachmentUploadPayload) async -> Result<ConnectedAttachmentUploadReference, Error> {
        let size = ((try? FileManager.default.attributesOfItem(atPath: payload.localURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let assetID = UUID()
        let ext = HTTPBackendConnectedAttachmentService.safePathExtension(for: payload)
        return .success(.init(
            assetID: assetID,
            storageBucket: "attachments",
            storagePath: "shared/simulated/\(assetID.uuidString.lowercased()).\(ext)",
            filename: HTTPBackendConnectedAttachmentService.safeFilename(payload.filename, pathExtension: ext),
            attachmentName: payload.attachmentName,
            mimeType: payload.mimeType,
            byteCount: size,
            pageCount: payload.pageCount
        ))
    }
    public func deliver(_ reference: ConnectedAttachmentUploadReference, to recipientUserIDs: [String]) async -> Result<Void, Error> { .success(()) }
    public func fetchReceived() async -> Result<[ConnectedAttachment], Error> { .success([]) }
    public func markViewed(id: UUID) async -> Result<Void, Error> { .success(()) }
    public func markSavedToScores(id: UUID) async -> Result<Void, Error> { .success(()) }
    public func softDelete(id: UUID) async -> Result<Void, Error> { .success(()) }
    public func download(_ attachment: ConnectedAttachment) async -> Result<Data, Error> { .failure(ConnectedAttachmentError.downloadUnavailable) }
}

public enum ConnectedAttachmentError: LocalizedError {
    case missingUserID
    case emptyRecipients
    case invalidAttachment
    case fileTooLarge
    case downloadUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingUserID: return "Missing Connected user identity."
        case .emptyRecipients: return "There are no valid recipients."
        case .invalidAttachment: return "The attachment could not be prepared."
        case .fileTooLarge: return "This attachment is too large to share."
        case .downloadUnavailable: return "The attachment could not be downloaded."
        }
    }
}

public final class HTTPBackendConnectedAttachmentService: BackendConnectedAttachmentService {
    public init() {}

    private let maxUploadBytes: Int64 = 50 * 1024 * 1024

    private func currentBackendUserID() -> String? {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let override = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override.lowercased()
        }
        #endif
        if let value = UserDefaults.standard.string(forKey: "supabaseUserID_v1")?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value.lowercased()
        }
        if let value = UserDefaults.standard.string(forKey: "backendUserID_v1")?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value.lowercased()
        }
        return nil
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func upload(_ payload: ConnectedAttachmentUploadPayload) async -> Result<ConnectedAttachmentUploadReference, Error> {
        guard let senderID = currentBackendUserID() else { return .failure(ConnectedAttachmentError.missingUserID) }
        guard payload.localURL.isFileURL, FileManager.default.fileExists(atPath: payload.localURL.path) else {
            return .failure(ConnectedAttachmentError.invalidAttachment)
        }

        let values = try? payload.localURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values?.fileSize ?? 0)
        guard byteCount <= maxUploadBytes else { return .failure(ConnectedAttachmentError.fileTooLarge) }

        let data: Data
        do { data = try Data(contentsOf: payload.localURL) }
        catch { return .failure(error) }

        let assetID = UUID()
        let ext = Self.safePathExtension(for: payload)
        let path = "users/\(senderID.lowercased())/connected/\(assetID.uuidString.lowercased()).\(ext)"
        let result = await NetworkManager.shared.request(
            path: "storage/v1/object/attachments/\(path)",
            method: "POST",
            query: nil,
            jsonBody: data,
            headers: ["Content-Type": payload.mimeType, "x-upsert": "false"]
        )

        switch result {
        case .success:
            return .success(.init(
                assetID: assetID,
                storageBucket: "attachments",
                storagePath: path,
                filename: Self.safeFilename(payload.filename, pathExtension: ext),
                attachmentName: payload.attachmentName,
                mimeType: payload.mimeType,
                byteCount: byteCount,
                pageCount: payload.pageCount
            ))
        case .failure(let error):
            return .failure(error)
        }
    }

    public func deliver(_ reference: ConnectedAttachmentUploadReference, to recipientUserIDs: [String]) async -> Result<Void, Error> {
        guard let senderID = currentBackendUserID() else { return .failure(ConnectedAttachmentError.missingUserID) }
        let recipients = Array(Set(recipientUserIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }))
            .filter { !$0.isEmpty && $0 != senderID }
        guard !recipients.isEmpty else { return .failure(ConnectedAttachmentError.emptyRecipients) }

        let rows: [[String: Any]] = recipients.map { recipientID in
            var row: [String: Any] = [
                "asset_id": reference.assetID.uuidString.lowercased(),
                "sender_user_id": senderID,
                "recipient_user_id": recipientID,
                "storage_bucket": reference.storageBucket,
                "storage_path": reference.storagePath,
                "filename": reference.filename,
                "mime_type": reference.mimeType,
                "byte_count": reference.byteCount,
                "page_count": reference.pageCount
            ]
            if let attachmentName = reference.attachmentName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !attachmentName.isEmpty {
                row["attachment_name"] = attachmentName
            }
            return row
        }

        do {
            let body = try JSONSerialization.data(withJSONObject: rows)
            let result = await NetworkManager.shared.request(
                path: "/rest/v1/connected_attachments",
                method: "POST",
                query: nil,
                jsonBody: body,
                headers: ["Prefer": "return=minimal"]
            )
            return result.map { _ in () }
        } catch {
            return .failure(error)
        }
    }

    public func fetchReceived() async -> Result<[ConnectedAttachment], Error> {
        guard let userID = currentBackendUserID() else { return .success([]) }
        let result = await NetworkManager.shared.request(
            path: "/rest/v1/connected_attachments",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "recipient_user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            jsonBody: nil
        )
        switch result {
        case .success(let data):
            do { return .success(try decoder().decode([ConnectedAttachment].self, from: data)) }
            catch { return .failure(error) }
        case .failure(let error): return .failure(error)
        }
    }

    public func markViewed(id: UUID) async -> Result<Void, Error> {
        await patch(
            id: id,
            values: ["viewed_at": ISO8601DateFormatter().string(from: Date())],
            additionalQueryItems: [
                URLQueryItem(name: "viewed_at", value: "is.null")
            ]
        )
    }

    public func markSavedToScores(id: UUID) async -> Result<Void, Error> {
        await patch(id: id, values: ["saved_to_scores_at": ISO8601DateFormatter().string(from: Date())])
    }

    public func softDelete(id: UUID) async -> Result<Void, Error> {
        await patch(id: id, values: ["deleted_at": ISO8601DateFormatter().string(from: Date())])
    }

    private func patch(
        id: UUID,
        values: [String: Any],
        additionalQueryItems: [URLQueryItem] = []
    ) async -> Result<Void, Error> {
        do {
            let data = try JSONSerialization.data(withJSONObject: values)
            let result = await NetworkManager.shared.request(
                path: "/rest/v1/connected_attachments",
                method: "PATCH",
                query: [
                    URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")
                ] + additionalQueryItems,
                jsonBody: data,
                headers: ["Prefer": "return=minimal"]
            )
            return result.map { _ in () }
        } catch { return .failure(error) }
    }

    public func download(_ attachment: ConnectedAttachment) async -> Result<Data, Error> {
        await NetworkManager.shared.downloadAuthenticatedStorageObject(bucket: attachment.storageBucket, path: attachment.storagePath)
    }

    static func safePathExtension(for payload: ConnectedAttachmentUploadPayload) -> String {
        let source = payload.localURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !source.isEmpty { return source }

        switch payload.mimeType.lowercased() {
        case "application/pdf": return "pdf"
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic", "image/heif": return "heic"
        case "audio/mpeg": return "mp3"
        case "audio/mp4", "audio/x-m4a": return "m4a"
        case "audio/wav", "audio/x-wav": return "wav"
        case "video/quicktime": return "mov"
        case "video/mp4": return "mp4"
        default: return "bin"
        }
    }

    static func safeFilename(_ raw: String, pathExtension: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = base.isEmpty ? "Shared Attachment" : base
        let invalid = CharacterSet(charactersIn: "/\\:\0")
        let sanitized = fallback.components(separatedBy: invalid).joined(separator: "-")
        if sanitized.lowercased().hasSuffix(".\(pathExtension.lowercased())") { return sanitized }
        return sanitized + "." + pathExtension
    }
}

public extension BackendEnvironment {
    var connectedAttachments: BackendConnectedAttachmentService {
        let hasHTTPConfig = BackendConfig.isConfigured && NetworkManager.shared.baseURL != nil
        if isConnected && hasHTTPConfig { return HTTPBackendConnectedAttachmentService() }
        return SimulatedConnectedAttachmentService()
    }
}

@MainActor
public final class ReceivedConnectedAttachmentStore: ObservableObject {
    public static let shared = ReceivedConnectedAttachmentStore()

    @Published public private(set) var items: [ConnectedAttachment] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?

    private let fileManager = FileManager.default
    private init() {}

    public var unreadItems: [ConnectedAttachment] {
        items.filter { $0.viewedAt == nil }
    }

    public var unreadCount: Int {
        unreadItems.count
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        switch await BackendEnvironment.shared.connectedAttachments.fetchReceived() {
        case .success(let received):
            items = received
            errorMessage = nil
        case .failure:
            errorMessage = "Couldn’t refresh shared attachments."
        }
    }

    public func localURL(for item: ConnectedAttachment) async throws -> URL {
        let destination = try localDestination(for: item)
        if fileManager.fileExists(atPath: destination.path) { return destination }

        switch await BackendEnvironment.shared.connectedAttachments.download(item) {
        case .success(let data):
            try data.write(to: destination, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = destination
            try? mutable.setResourceValues(values)
            return destination
        case .failure(let error): throw error
        }
    }

    public func markViewed(_ item: ConnectedAttachment) async {
        guard item.viewedAt == nil else { return }

        if case .success = await BackendEnvironment.shared.connectedAttachments.markViewed(id: item.id) {
            await refresh()
        }
    }

    public func markSavedToScores(_ item: ConnectedAttachment) async {
        if case .success = await BackendEnvironment.shared.connectedAttachments.markSavedToScores(id: item.id) {
            await refresh()
        }
    }

    public func delete(_ item: ConnectedAttachment) async {
        if case .success = await BackendEnvironment.shared.connectedAttachments.softDelete(id: item.id) {
            if let url = try? await localURLIfPresent(for: item) { try? fileManager.removeItem(at: url) }
            items.removeAll { $0.id == item.id }
        }
    }

    private func localURLIfPresent(for item: ConnectedAttachment) async throws -> URL? {
        let destination = try localDestination(for: item)
        return fileManager.fileExists(atPath: destination.path) ? destination : nil
    }

    private func localDestination(for item: ConnectedAttachment) throws -> URL {
        let filenameExtension = URL(fileURLWithPath: item.filename).pathExtension
        let storageExtension = URL(fileURLWithPath: item.storagePath).pathExtension
        let ext = !filenameExtension.isEmpty ? filenameExtension : (!storageExtension.isEmpty ? storageExtension : "bin")
        return try receivedDirectory()
            .appendingPathComponent(item.id.uuidString.lowercased())
            .appendingPathExtension(ext)
    }

    private func receivedDirectory() throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("ReceivedConnectedAttachments", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
