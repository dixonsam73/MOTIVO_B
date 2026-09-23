import XCTest
@testable import Etudes

/// Guideline 1.2 pieces: the shared-text filter, the report email and the
/// device-local block list.
final class ModerationTests: XCTestCase {

    // MARK: - Content filter

    func testOrdinaryTextIsAllowed() {
        XCTAssertTrue(SharedTextFilter.isAllowed("Scales in F#, slow bowing, felt good"))
        XCTAssertTrue(SharedTextFilter.isAllowed(""))
    }

    func testWordsThatMerelyContainABlockedWordAreAllowed() {
        // Whole-word matching: no Scunthorpe problem.
        XCTAssertTrue(SharedTextFilter.isAllowed("Scunthorpe gig, then cocktails"))
        XCTAssertTrue(SharedTextFilter.isAllowed("A niggling intonation issue in bar 12"))
        XCTAssertTrue(SharedTextFilter.isAllowed("Spicy tempo; the fagotto part (bassoon)"))
    }

    func testBlockedWordsAreRefused() {
        XCTAssertFalse(SharedTextFilter.isAllowed("what a cunt"))
        XCTAssertFalse(SharedTextFilter.isAllowed("Total WHORE"))
    }

    func testRootsCatchVariants() {
        XCTAssertFalse(SharedTextFilter.isAllowed("fucking hard passage"))
        XCTAssertFalse(SharedTextFilter.isAllowed("Motherfucker"))
    }

    func testCaseAccentsAndLeetspeakAreFolded() {
        XCTAssertFalse(SharedTextFilter.isAllowed("FÜCK"))
        XCTAssertFalse(SharedTextFilter.isAllowed("c0cksucker"))
        XCTAssertFalse(SharedTextFilter.isAllowed("wh0re"))
    }

    func testAreAllowedIgnoresNilAndChecksEveryText() {
        XCTAssertTrue(SharedTextFilter.areAllowed(["Etudes", nil]))
        XCTAssertFalse(SharedTextFilter.areAllowed(["Etudes", "fuck this"]))
    }

    // MARK: - Report email

    func testReportEmailIsAddressedToSupportAndCarriesIdentifiers() throws {
        let post = UUID()
        let comment = UUID()
        let report = ModerationReport(
            kind: .comment,
            reportedUserID: "  ABC-123 ",
            reportedDisplayName: "Some One",
            reporterUserID: "ME-1",
            postID: post,
            commentID: comment,
            excerpt: "offending text")

        let url = try XCTUnwrap(report.mailtoURL)
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, Moderation.supportEmail)

        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["subject"], "Report: Comment")
        let body = try XCTUnwrap(items["body"])
        XCTAssertTrue(body.contains("abc-123"))
        XCTAssertTrue(body.contains("Some One"))
        XCTAssertTrue(body.contains(post.uuidString.lowercased()))
        XCTAssertTrue(body.contains(comment.uuidString.lowercased()))
        XCTAssertTrue(body.contains("offending text"))
        XCTAssertTrue(body.contains("Reported by: me-1"))
    }

    // MARK: - C-105: the filter only applies to text that will be shared

    func testC105_SoloSaveIsNeverFiltered_EvenIfTheSessionWasShared() {
        XCTAssertFalse(SharedTextFilter.refusesSave(sharingAvailable: false, isShared: true,
                                                    texts: ["fucking hard passage"]))
    }

    func testC105_ConnectedSharedSaveIsFiltered() {
        XCTAssertTrue(SharedTextFilter.refusesSave(sharingAvailable: true, isShared: true,
                                                   texts: ["fucking hard passage"]))
        XCTAssertFalse(SharedTextFilter.refusesSave(sharingAvailable: true, isShared: true,
                                                    texts: ["slow scales"]))
    }

    func testC105_ConnectedPrivateSaveIsNotFiltered() {
        XCTAssertFalse(SharedTextFilter.refusesSave(sharingAvailable: true, isShared: false,
                                                    texts: ["fucking hard passage"]))
    }

    // MARK: - Block list

    /// Stand-in for the server's answer to "are both follow rows gone?".
    @MainActor
    private final class SeverSpy {
        var succeeds: Bool
        var calls: [String] = []
        init(succeeds: Bool) { self.succeeds = succeeds }
        func sever(_ id: String) async -> Bool { calls.append(id); return succeeds }
    }

    @MainActor
    func testBlockListPersistsNormalisedIDsAndUnblocks() async throws {
        let suite = "ModerationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SeverSpy(succeeds: true)

        let list = BlockList(defaults: defaults, sever: spy.sever)
        XCTAssertFalse(list.isBlocked("ABC"))

        let ok = await list.block(" ABC ", displayName: "  ")
        XCTAssertTrue(ok)
        XCTAssertEqual(spy.calls, ["abc"])
        XCTAssertTrue(list.isBlocked("abc"))
        XCTAssertFalse(list.isUnconfirmed("abc"))
        XCTAssertEqual(list.blocked["abc"], "Blocked account")

        // A fresh instance reads the same storage, as after a relaunch.
        XCTAssertTrue(BlockList(defaults: defaults, sever: spy.sever).isBlocked("ABC"))

        list.unblock("abc")
        XCTAssertFalse(list.isBlocked("abc"))
        XCTAssertFalse(BlockList(defaults: defaults, sever: spy.sever).isBlocked("abc"))
    }

    /// C-104: a block whose follow removal the server did not confirm must say
    /// so, survive a relaunch as unfinished, and clear once a retry succeeds.
    @MainActor
    func testC104_UnconfirmedRemovalIsReportedPersistedAndRetried() async throws {
        let suite = "ModerationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SeverSpy(succeeds: false)

        let list = BlockList(defaults: defaults, sever: spy.sever)
        let ok = await list.block("follower-1", displayName: "F")
        XCTAssertFalse(ok, "a failed removal is not reported as success")
        XCTAssertTrue(list.isBlocked("follower-1"), "still hidden locally")
        XCTAssertTrue(list.isUnconfirmed("follower-1"))

        let relaunched = BlockList(defaults: defaults, sever: spy.sever)
        XCTAssertTrue(relaunched.isUnconfirmed("follower-1"), "unfinished state survives a relaunch")

        spy.succeeds = true
        await relaunched.retryUnconfirmed()
        XCTAssertFalse(relaunched.isUnconfirmed("follower-1"))
        XCTAssertFalse(BlockList(defaults: defaults, sever: spy.sever).isUnconfirmed("follower-1"))
        XCTAssertEqual(spy.calls, ["follower-1", "follower-1"])
    }

    @MainActor
    func testC104_UnblockClearsUnfinishedState() async throws {
        let suite = "ModerationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SeverSpy(succeeds: false)

        let list = BlockList(defaults: defaults, sever: spy.sever)
        await list.block("x", displayName: nil)
        list.unblock("x")
        XCTAssertFalse(list.isUnconfirmed("x"))
        await list.retryUnconfirmed()
        XCTAssertEqual(spy.calls, ["x"], "nothing retried after unblock")
    }

    @MainActor
    func testReloadAfterStorageWipeClearsTheList() async throws {
        let suite = "ModerationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = SeverSpy(succeeds: false)

        let list = BlockList(defaults: defaults, sever: spy.sever)
        await list.block("xyz", displayName: "X")
        defaults.removePersistentDomain(forName: suite)   // what Erase All does
        list.reloadFromDefaults()
        XCTAssertFalse(list.isBlocked("xyz"))
        XCTAssertFalse(list.isUnconfirmed("xyz"))
    }

    // MARK: - C-104: both follow rows are removed, and failure is reported

    private final class FakeFollowService: BackendFollowService {
        var unfollowResult: Result<Void, Error> = .success(())
        var removeFollowerResult: Result<Void, Error> = .success(())
        var calls: [String] = []

        func fetchFollowingApproved() async -> Result<[String], Error> { .success([]) }
        func fetchFollowersApproved() async -> Result<[String], Error> { .success([]) }
        func fetchIncomingRequests() async -> Result<[String], Error> { .success([]) }
        func fetchOutgoingRequests() async -> Result<[String], Error> { .success([]) }
        func requestFollow(to targetUserID: String) async -> Result<Void, Error> { .success(()) }
        func approveFollow(from requesterUserID: String) async -> Result<Void, Error> { .success(()) }
        func declineFollow(from requesterUserID: String) async -> Result<Void, Error> {
            calls.append("decline:\(requesterUserID)"); return .success(())
        }
        func unfollow(_ targetUserID: String) async -> Result<Void, Error> {
            calls.append("unfollow:\(targetUserID)"); return unfollowResult
        }
        func removeFollower(_ followerUserID: String) async -> Result<Void, Error> {
            calls.append("removeFollower:\(followerUserID)"); return removeFollowerResult
        }
    }

    @MainActor
    func testC104_SeverRemovesBothDirections_AlreadyGoneCountsAsRemoved() async {
        let service = FakeFollowService()
        service.unfollowResult = .failure(FollowRelationshipError.notFound)
        let ok = await FollowStore.severRelationships(with: "abc", using: service)
        XCTAssertTrue(ok)
        XCTAssertEqual(service.calls, ["unfollow:abc", "removeFollower:abc"])
    }

    @MainActor
    func testC104_SeverReportsFailureWhenTheFollowerRowIsNotRemoved() async {
        let service = FakeFollowService()
        service.removeFollowerResult = .failure(URLError(.notConnectedToInternet))
        let ok = await FollowStore.severRelationships(with: "abc", using: service)
        XCTAssertFalse(ok)
    }

    @MainActor
    func testC104_SeverStillRemovesTheFollowerWhenUnfollowFails() async {
        let service = FakeFollowService()
        service.unfollowResult = .failure(URLError(.timedOut))
        let ok = await FollowStore.severRelationships(with: "abc", using: service)
        XCTAssertFalse(ok)
        XCTAssertEqual(service.calls, ["unfollow:abc", "removeFollower:abc"],
                       "the follower row is still attempted")
    }
}
