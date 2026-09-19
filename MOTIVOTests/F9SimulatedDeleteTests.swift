import XCTest
@testable import Etudes

/// F-9. The simulated publish service performs no network deletion, and says so.
///
/// Uses the existing held `QueueStubServer` / `QueueStubFixture` (a URLProtocol stub
/// at 127.0.0.1:9): a configured backend and a retained synthetic token, with NO real
/// network, account or personal data. The HTTP path's direct delete is covered by the
/// retained `P6I02BoundTransportTests.testB19_AmbientDeletePostIsUnbound`.
@MainActor
final class F9SimulatedDeleteTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()                              // configured backend + synthetic bearer
        NetworkManager.shared.setBearerToken("stub-bearer")     // a retained token, as in Solo after lapse
        setBackendMode(.localSimulation)                        // local mode: the simulated service
    }

    override func tearDown() async throws {
        QueueStubFixture.disconnect()                           // restores mode, bearer and identity key
        try await super.tearDown()
    }

    func testF9_SimulatedDeleteSendsNothingAndReportsThatNothingWasDeleted() async throws {
        let service = BackendEnvironment.shared.publish
        XCTAssertTrue(service is SimulatedPublishService, "local mode selects the simulated service")

        let result = await service.deletePost(UUID())

        guard case .failure(let error) = result else {
            return XCTFail("a simulated delete must not report success: \(result)")
        }
        XCTAssertEqual(error as? SimulatedPublishError, .deletionNotPerformed)
        // The exact rendering the Debug viewer uses: "Delete failed: \(String(describing: error))".
        XCTAssertEqual(String(describing: error),
                       "Not deleted: the simulated backend performs no network deletion.")
        XCTAssertEqual(error.localizedDescription,
                       "Not deleted: the simulated backend performs no network deletion.")
        XCTAssertTrue(QueueStubServer.allURLs.isEmpty,
                      "no request of any kind: \(QueueStubServer.allURLs.map(\.key))")
    }
}
