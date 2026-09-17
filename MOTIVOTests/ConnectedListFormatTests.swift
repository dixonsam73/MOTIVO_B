import XCTest
@testable import Etudes

@MainActor
final class ConnectedListFormatTests: XCTestCase {
    func testLegacySavedListsKeepIDsAndDefaultMissingTypeToItem() throws {
        let id = UUID()
        let data = Data("[{\"id\":\"\(id)\",\"name\":\"Weekly work\",\"items\":[{\"text\":\"Warm-up\",\"type\":\"context\"},{\"text\":\"Scales\"}]}]".utf8)
        let decoded = try JSONDecoder().decode([SavedList].self, from: data)
        XCTAssertEqual(decoded[0].id, id)
        XCTAssertNil(decoded[0].sourceSendID)
        XCTAssertEqual(decoded[0].items.map(\.type), [.context, .task])
    }

    func testWirePreservesNameOrderAndTypesWithoutLocalFields() throws {
        let list = SavedList(id: UUID(), name: "Friday set", items: [
            SavedListLine(text: "First half", type: .context),
            SavedListLine(text: "Prelude"),
            SavedListLine(text: "Second half", type: .context),
            SavedListLine(text: "Finale")
        ], sourceSendID: UUID())
        let payload = ConnectedListPayload(list: list)
        let data = try payload.encoded()
        XCTAssertEqual(try ConnectedListPayload.decode(data), payload)
        XCTAssertEqual(payload.name, list.name)
        XCTAssertEqual(payload.items.map(\.text), list.items.map(\.text))
        XCTAssertEqual(payload.items.map(\.type), [.header, .item, .header, .item])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["version", "name", "items"]))
        let lines = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertTrue(lines.allSatisfy { Set($0.keys) == Set(["text", "type"]) })
    }

    func testProvenanceSurvivesSavedListEncoding() throws {
        let list = SavedList(id: UUID(), name: "Edited copy", items: [SavedListLine(text: "Practice")], sourceSendID: UUID())
        XCTAssertEqual(try JSONDecoder().decode(SavedList.self, from: JSONEncoder().encode(list)), list)
    }

    func testUnknownVersionOrTypesAndMissingTypesAreRejected() {
        let invalid = [
            "{\"version\":2,\"name\":\"A\",\"items\":[{\"text\":\"a\",\"type\":\"item\"}]}",
            "{\"version\":1,\"name\":\"A\",\"items\":[{\"text\":\"a\",\"type\":\"unknown\"}]}",
            "{\"version\":1,\"name\":\"A\",\"items\":[{\"text\":\"a\"}]}",
            "{\"version\":1,\"name\":\"A\",\"items\":[]}"
        ]
        for raw in invalid {
            XCTAssertThrowsError(try ConnectedListPayload.decode(Data(raw.utf8)))
        }
    }

    func testPayloadBounds() {
        XCTAssertThrowsError(try ConnectedListPayload.decode(Data(repeating: 0x20, count: ConnectedListPayload.maxBytes + 1)))
        let tooMany = SavedList(id: UUID(), name: "A", items: (0...ConnectedListPayload.maxItems).map { SavedListLine(text: String($0)) })
        XCTAssertThrowsError(try ConnectedListPayload(list: tooMany).encoded())
        let longLine = SavedList(id: UUID(), name: "A", items: [SavedListLine(text: String(repeating: "x", count: 4001))])
        XCTAssertThrowsError(try ConnectedListPayload(list: longLine).encoded())
    }
}
