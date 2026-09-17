import Foundation

struct ConnectedListShareRequest: Identifiable {
    let id = UUID()
    let payload: ConnectedListPayload
}

extension ConnectedAttachment {
    var isList: Bool { mimeType.lowercased() == ConnectedListPayload.mimeType }
}

/// Only the invocation-owned export is temporary. The saved sender list is never modified.
@MainActor
enum ConnectedListUpload {
    static func upload(_ list: ConnectedListPayload, using service: BackendConnectedAttachmentService,
                       temporaryDirectory: URL = FileManager.default.temporaryDirectory) async throws -> ConnectedAttachmentUploadReference {
        let data = try list.encoded()
        let url = temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("etudeslist")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)
        return try await service.upload(ConnectedAttachmentUploadPayload(
            localURL: url, filename: list.name + ".etudeslist", attachmentName: list.name,
            mimeType: ConnectedListPayload.mimeType, pageCount: 0
        )).get()
    }
}
