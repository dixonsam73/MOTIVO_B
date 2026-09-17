import XCTest
@testable import Etudes

@MainActor
final class ConnectedListAdoptionTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suite = "ConnectedListTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, suite)
    }

    private var original: SavedList {
        SavedList(id: UUID(), name: "Friday set", items: [
            SavedListLine(text: "Opening", type: .context),
            SavedListLine(text: "Prelude"),
            SavedListLine(text: "Encore", type: .context),
            SavedListLine(text: "Finale")
        ])
    }

    func testAdoptionKeepsFormattingAndAllocatesRecipientIDs() throws {
        try withDefaults { defaults, _ in
            let sender = original
            let snapshot = sender
            let delivery = UUID()
            let copy = try SavedListLibrary.adopt(ConnectedListPayload(list: sender), sourceSendID: delivery,
                                                 ownerScope: "recipient", defaults: defaults)
            XCTAssertEqual(copy.name, sender.name)
            XCTAssertEqual(copy.items.map(\.text), sender.items.map(\.text))
            XCTAssertEqual(copy.items.map(\.type), sender.items.map(\.type))
            XCTAssertNotEqual(copy.id, sender.id)
            XCTAssertTrue(Set(copy.items.map(\.id)).isDisjoint(with: sender.items.map(\.id)))
            XCTAssertEqual(copy.sourceSendID, delivery)
            XCTAssertEqual(sender, snapshot)
        }
    }

    func testRepeatedAdoptionAfterReloadPreservesRecipientEdits() throws {
        try withDefaults { defaults, suite in
            let payload = ConnectedListPayload(list: original)
            let delivery = UUID()
            var copy = try SavedListLibrary.adopt(payload, sourceSendID: delivery, ownerScope: "owner", defaults: defaults)
            copy.name = "My edited set"
            copy.items.reverse()
            copy.items[0].text = "My own instructions"
            defaults.set(try JSONEncoder().encode([copy]), forKey: SavedListLibrary.key(ownerScope: "owner"))
            let reloaded = try XCTUnwrap(UserDefaults(suiteName: suite))
            let repeated = try SavedListLibrary.adopt(payload, sourceSendID: delivery, ownerScope: "owner", defaults: reloaded)
            XCTAssertEqual(repeated, copy)
            XCTAssertEqual(try SavedListLibrary.read(ownerScope: "owner", defaults: reloaded).count, 1)
        }
    }

    func testLocalDeletionAllowsReadoptionWithoutLegacyResurrection() throws {
        try withDefaults { defaults, _ in
            let payload = ConnectedListPayload(list: original)
            let delivery = UUID()
            let first = try SavedListLibrary.adopt(payload, sourceSendID: delivery, ownerScope: "owner", defaults: defaults)
            let local = original
            let mirror = SavedListLibrary.legacyMirror([first, local])
            XCTAssertEqual(mirror, [local])
            defaults.set(try JSONEncoder().encode([SavedList]()), forKey: SavedListLibrary.key(ownerScope: "owner"))
            let again = try SavedListLibrary.adopt(payload, sourceSendID: delivery, ownerScope: "owner", defaults: defaults)
            XCTAssertNotEqual(first.id, again.id)
            XCTAssertEqual(again.items.map(\.type), first.items.map(\.type))
        }
    }

    func testSeparateDeliveriesSurviveContentDeduplication() throws {
        try withDefaults { defaults, _ in
            let local = original
            let payload = ConnectedListPayload(list: local)
            let a = try SavedListLibrary.adopt(payload, sourceSendID: UUID(), ownerScope: "owner", defaults: defaults)
            let b = try SavedListLibrary.adopt(payload, sourceSendID: UUID(), ownerScope: "owner", defaults: defaults)
            XCTAssertNotEqual(a.id, b.id)
            var merge = SavedListMergeIdentity()
            XCTAssertTrue(merge.include(local, contentSignature: "same"))
            XCTAssertTrue(merge.include(a, contentSignature: "same"))
            XCTAssertTrue(merge.include(b, contentSignature: "same"))
            XCTAssertFalse(merge.include(a, contentSignature: "same"))
            XCTAssertEqual(try SavedListLibrary.read(ownerScope: "owner", defaults: defaults).count, 2)
        }
    }

    func testLegacyLibrarySurvivesAdoptionAndOwnersRemainIsolated() throws {
        try withDefaults { defaults, _ in
            let old = LegacySavedList(id: UUID(), name: "Old list", items: ["Scales", "Study"])
            defaults.set(try JSONEncoder().encode([old]), forKey: SavedListLibrary.key(ownerScope: "A"))
            let payload = ConnectedListPayload(list: original)
            let delivery = UUID()
            let a = try SavedListLibrary.adopt(payload, sourceSendID: delivery, ownerScope: "A", defaults: defaults)
            let b = try SavedListLibrary.adopt(payload, sourceSendID: delivery, ownerScope: "B", defaults: defaults)
            XCTAssertNotEqual(a.id, b.id)
            let libraryA = try SavedListLibrary.read(ownerScope: "A", defaults: defaults)
            XCTAssertEqual(libraryA.count, 2)
            XCTAssertEqual(libraryA[0].id, old.id)
            XCTAssertEqual(libraryA[0].items.map(\.text), old.items)
            XCTAssertEqual(libraryA[0].items.map(\.type), [.task, .task])
            XCTAssertEqual(try SavedListLibrary.read(ownerScope: "B", defaults: defaults), [b])
        }
    }

    func testUnreadableLibraryIsNeverOverwritten() throws {
        try withDefaults { defaults, _ in
            let key = SavedListLibrary.key(ownerScope: "owner")
            let invalidValues: [Any] = [Data("broken".utf8), "wrong storage type"]
            for bad in invalidValues {
                defaults.set(bad, forKey: key)
                XCTAssertThrowsError(try SavedListLibrary.adopt(ConnectedListPayload(list: original), sourceSendID: UUID(), ownerScope: "owner", defaults: defaults))
                if let data = bad as? Data { XCTAssertEqual(defaults.data(forKey: key), data) }
                else { XCTAssertEqual(defaults.string(forKey: key), bad as? String) }
            }
        }
    }

    func testDeleteNeedsConfirmationOfThisDelivery() throws {
        let id = UUID()
        let confirmed = try JSONEncoder().encode([["id": id.uuidString]])
        let another = try JSONEncoder().encode([["id": UUID().uuidString]])
        XCTAssertTrue(HTTPBackendConnectedAttachmentService.confirmsUpdatedDelivery(confirmed, id: id))
        XCTAssertFalse(HTTPBackendConnectedAttachmentService.confirmsUpdatedDelivery(Data("[]".utf8), id: id))
        XCTAssertFalse(HTTPBackendConnectedAttachmentService.confirmsUpdatedDelivery(another, id: id))
        XCTAssertFalse(HTTPBackendConnectedAttachmentService.confirmsUpdatedDelivery(Data(), id: id))
        XCTAssertFalse(HTTPBackendConnectedAttachmentService.confirmsUpdatedDelivery(
            try JSONEncoder().encode([["id": id.uuidString], ["id": id.uuidString]]), id: id))
    }

    func testUploadCleansOnlyItsExportOnSuccessAndFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("keep.etudeslist")
        let originalData = Data("unrelated original".utf8)
        try originalData.write(to: existing)
        let payload = ConnectedListPayload(list: original)
        for fail in [false, true] {
            let service = ListUploadProbe(fail: fail)
            do {
                _ = try await ConnectedListUpload.upload(payload, using: service, temporaryDirectory: directory)
                XCTAssertFalse(fail)
            } catch { XCTAssertTrue(fail) }
            XCTAssertEqual(service.uploadCount, 1)
            XCTAssertEqual(try ConnectedListPayload.decode(XCTUnwrap(service.bytes)), payload)
            XCTAssertEqual(service.mimeType, ConnectedListPayload.mimeType)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [existing.lastPathComponent])
            XCTAssertEqual(try Data(contentsOf: existing), originalData)
        }
    }
}

private final class ListUploadProbe: BackendConnectedAttachmentService {
    let fail: Bool
    var uploadCount = 0
    var bytes: Data?
    var mimeType: String?
    init(fail: Bool) { self.fail = fail }
    func upload(_ payload: ConnectedAttachmentUploadPayload) async -> Result<ConnectedAttachmentUploadReference, Error> {
        uploadCount += 1
        bytes = try? Data(contentsOf: payload.localURL)
        mimeType = payload.mimeType
        if fail { return .failure(ConnectedAttachmentError.invalidAttachment) }
        return .success(.init(assetID: UUID(), storageBucket: "attachments", storagePath: "test.etudeslist",
                              filename: payload.filename, attachmentName: payload.attachmentName,
                              mimeType: payload.mimeType, byteCount: Int64(bytes?.count ?? 0), pageCount: 0))
    }
    func deliver(_ reference: ConnectedAttachmentUploadReference, to recipientUserIDs: [String]) async -> Result<Void, Error> { .success(()) }
    func fetchReceived() async -> Result<[ConnectedAttachment], Error> { .success([]) }
    func markViewed(id: UUID) async -> Result<Void, Error> { .success(()) }
    func markSavedToScores(id: UUID) async -> Result<Void, Error> { .success(()) }
    func softDelete(id: UUID) async -> Result<Void, Error> { .success(()) }
    func download(_ attachment: ConnectedAttachment) async -> Result<Data, Error> { .failure(ConnectedAttachmentError.downloadUnavailable) }
}
