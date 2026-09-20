//
//  B37SearchThrottleTransportTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_130000_B37_SearchBudgetRefusal
//  SCOPE: B-37 — a throttle refusal travelling through the REAL NetworkManager
//  path. The pure mapping tests cannot establish this: what is being asserted
//  here is that a 429 provokes NO session refresh and NO retry, which is a
//  property of the transport, not of the mapper.
//  SEARCH-TOKEN: 20260920_130000_B37_SearchBudgetRefusal
//

import XCTest
@testable import Etudes

/// Answers every intercepted request with the server's own 429 refusal and
/// counts how many it saw.
final class B37ThrottleStub: URLProtocol {
    static let lock = NSLock()
    static var requestCount = 0
    static var lastPath: String? = nil

    static func reset() {
        lock.lock(); requestCount = 0; lastPath = nil; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.contains("search_account_directory") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        Self.lastPath = request.url?.path
        Self.lock.unlock()

        let body = #"{"code":"PT429","details":"{\"retry_after_seconds\":42}","hint":null,"message":"search_rate_limited"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 429,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class B37SearchThrottleTransportTests: XCTestCase {

    private var savedBaseURL: URL?
    private var savedAuthToken: String?
    private var savedChallenge: (() async -> Bool)?

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(B37ThrottleStub.self)
        B37ThrottleStub.reset()

        savedBaseURL = NetworkManager.shared.baseURL
        savedAuthToken = NetworkManager.shared.authToken
        savedChallenge = NetworkManager.shared.onAuthChallenge

        // Deliberately NO setBearerToken here. The stub answers regardless of
        // credentials, and `configure` does not clear the bearer -- so setting
        // one would leak a fake token into every test that ran afterwards.
        NetworkManager.shared.configure(baseURL: URL(string: "https://b37.invalid")!,
                                        authToken: "b37-anon-key")
    }

    override func tearDown() {
        NetworkManager.shared.onAuthChallenge = savedChallenge
        NetworkManager.shared.configure(baseURL: savedBaseURL, authToken: savedAuthToken)
        URLProtocol.unregisterClass(B37ThrottleStub.self)
        super.tearDown()
    }

    func testA429ThrottleNeitherRefreshesTheSessionNorRetries() async {
        let challenges = Counter()
        NetworkManager.shared.onAuthChallenge = {
            await challenges.increment()
            return true
        }

        let result = await AccountDirectoryService.shared.search(query: "alpha")

        B37ThrottleStub.lock.lock()
        let requests = B37ThrottleStub.requestCount
        B37ThrottleStub.lock.unlock()

        XCTAssertEqual(requests, 1, "a throttle must be sent exactly once — no retry")
        let seen = await challenges.value
        XCTAssertEqual(seen, 0, "a throttle must never provoke a session refresh")

        switch result {
        case .success:
            XCTFail("a 429 must not surface as success")
        case .failure(let error):
            XCTAssertEqual(error as? DirectorySearchError, .rateLimited(retryAfterSeconds: 42),
                           "and it must arrive typed, with the server's own duration")
        }
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
