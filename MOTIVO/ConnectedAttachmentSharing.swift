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
    public let mimeType: String
    public let byteCount: Int64
    public let pageCount: Int
    public let createdAt: Date
    public let savedToScoresAt: Date?
    public let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case assetID = "asset_id"
        case senderUserID = "sender_user_id"
        case recipientUserID = "recipient_user_id"
        case storageBucket = "storage_bucket"
        case storagePath = "storage_path"
        case filename
        case mimeType = "mime_type"
        case byteCount = "byte_count"
        case pageCount = "page_count"
        case createdAt = "created_at"
        case savedToScoresAt = "saved_to_scores_at"
        case deletedAt = "deleted_at"
    }
}

public struct ConnectedAttachmentUploadReference: Hashable {
    public let assetID: UUID
    public let storageBucket: String
    public let storagePath: String
    public let filename: String
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
    func uploadPDF(localURL: URL, filename: String, pageCount: Int) async -> Result<ConnectedAttachmentUploadReference, Error>
    func deliver(_ reference: ConnectedAttachmentUploadReference, to recipientUserIDs: [String]) async -> Result<Void, Error>
    func fetchReceived() async -> Result<[ConnectedAttachment], Error>
    func markSavedToScores(id: UUID) async -> Result<Void, Error>
    func softDelete(id: UUID) async -> Result<Void, Error>
    func download(_ attachment: ConnectedAttachment) async -> Result<Data, Error>
}

public struct SimulatedConnectedAttachmentService: BackendConnectedAttachmentService {
    public init() {}
    public func uploadPDF(localURL: URL, filename: String, pageCount: Int) async -> Result<ConnectedAttachmentUploadReference, Error> {
        let size = ((try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let assetID = UUID()
        return .success(.init(assetID: assetID, storageBucket: "attachments", storagePath: "shared/simulated/\(assetID.uuidString.lowercased()).pdf", filename: filename, mimeType: "application/pdf", byteCount: size, pageCount: pageCount))
    }
    public func deliver(_ reference: ConnectedAttachmentUploadReference, to recipientUserIDs: [String]) async -> Result<Void, Error> { .success(()) }
    public func fetchReceived() async -> Result<[ConnectedAttachment], Error> { .success([]) }
    public func markSavedToScores(id: UUID) async -> Result<Void, Error> { .success(()) }
    public func softDelete(id: UUID) async -> Result<Void, Error> { .success(()) }
    public func download(_ attachment: ConnectedAttachment) async -> Result<Data, Error> { .failure(ConnectedAttachmentError.downloadUnavailable) }
}

public enum ConnectedAttachmentError: LocalizedError {
    case missingUserID
    case emptyRecipients
    case invalidPDF
    case fileTooLarge
    case downloadUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingUserID: return "Missing Connected user identity."
        case .emptyRecipients: return "There are no valid recipients."
        case .invalidPDF: return "The PDF could not be prepared."
        case .fileTooLarge: return "This PDF is too large to share."
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

    public func uploadPDF(localURL: URL, filename: String, pageCount: Int) async -> Result<ConnectedAttachmentUploadReference, Error> {
        guard let senderID = currentBackendUserID() else { return .failure(ConnectedAttachmentError.missingUserID) }
        guard localURL.pathExtension.lowercased() == "pdf" else { return .failure(ConnectedAttachmentError.invalidPDF) }

        let values = try? localURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values?.fileSize ?? 0)
        guard byteCount <= maxUploadBytes else { return .failure(ConnectedAttachmentError.fileTooLarge) }

        let data: Data
        do { data = try Data(contentsOf: localURL) }
        catch { return .failure(error) }

        let assetID = UUID()
        let path = "users/\(senderID.lowercased())/connected/\(assetID.uuidString.lowercased()).pdf"
        let result = await NetworkManager.shared.request(
            path: "storage/v1/object/attachments/\(path)",
            method: "POST",
            query: nil,
            jsonBody: data,
            headers: ["Content-Type": "application/pdf", "x-upsert": "false"]
        )

        switch result {
        case .success:
            return .success(.init(
                assetID: assetID,
                storageBucket: "attachments",
                storagePath: path,
                filename: Self.safeFilename(filename),
                mimeType: "application/pdf",
                byteCount: byteCount,
                pageCount: max(pageCount, 1)
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
            [
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

    public func markSavedToScores(id: UUID) async -> Result<Void, Error> {
        await patch(id: id, values: ["saved_to_scores_at": ISO8601DateFormatter().string(from: Date())])
    }

    public func softDelete(id: UUID) async -> Result<Void, Error> {
        await patch(id: id, values: ["deleted_at": ISO8601DateFormatter().string(from: Date())])
    }

    private func patch(id: UUID, values: [String: Any]) async -> Result<Void, Error> {
        do {
            let data = try JSONSerialization.data(withJSONObject: values)
            let result = await NetworkManager.shared.request(
                path: "/rest/v1/connected_attachments",
                method: "PATCH",
                query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                jsonBody: data,
                headers: ["Prefer": "return=minimal"]
            )
            return result.map { _ in () }
        } catch { return .failure(error) }
    }

    public func download(_ attachment: ConnectedAttachment) async -> Result<Data, Error> {
        await NetworkManager.shared.downloadAuthenticatedStorageObject(bucket: attachment.storageBucket, path: attachment.storagePath)
    }

    private static func safeFilename(_ raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = base.isEmpty ? "Shared Score.pdf" : base
        let withExtension = fallback.lowercased().hasSuffix(".pdf") ? fallback : fallback + ".pdf"
        let invalid = CharacterSet(charactersIn: "/\\:\0")
        return withExtension.components(separatedBy: invalid).joined(separator: "-")
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
        let directory = try receivedDirectory()
        let destination = directory.appendingPathComponent(item.id.uuidString.lowercased()).appendingPathExtension("pdf")
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
        let destination = try receivedDirectory().appendingPathComponent(item.id.uuidString.lowercased()).appendingPathExtension("pdf")
        return fileManager.fileExists(atPath: destination.path) ? destination : nil
    }

    private func receivedDirectory() throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("ReceivedConnectedAttachments", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
