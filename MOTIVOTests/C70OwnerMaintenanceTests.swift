//
//  C70OwnerMaintenanceTests.swift
//  MOTIVOTests
//
//  C-70 remaining gaps — BEHAVIOURAL acceptance, 20 September 2026.
//
//  These exercise the REAL production types the shipped code calls, not
//  re-implementations of them: `ProfileMaintenancePolicy` and
//  `ProfileNameDraftState` are the exact values `ProfileView` consults, and
//  `NetworkManager.boundRequest` / `AuthManager.ensureValidBackendSession` are
//  the exact APIs the maintenance path uses.
//
//  WHAT THESE CANNOT DO, stated rather than implied. They drive the REAL policy
//  types production calls, with counted effects — but they **do not mount
//  `ProfileView` and do not execute its storage modifiers**. They are therefore
//  NOT end-to-end view-storage tests, and must never be described as such: they
//  establish that the mechanisms decide correctly, not that every call site
//  consults them. That second half comes from the two pins in
//  `C70WiringPinTests` and from independent wiring review.
//

import XCTest
@testable import Etudes

final class C70OwnerMaintenanceTests: XCTestCase {

    // MARK: - Policy: identity and configuration, never AppMode

    /// The lapsed-owner case this whole unit exists for.
    func testRemoteMaintenanceIsAllowedForAnIdentityWithoutConnectedMode() {
        XCTAssertTrue(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: true, isBackendConfigured: true,
            hasAccessToken: true, backendUserID: "abc"))
    }

    func testRemoteMaintenanceRefusesWithoutIdentity() {
        XCTAssertFalse(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: false, isBackendConfigured: true,
            hasAccessToken: true, backendUserID: "abc"),
            "Solo without an identity must do no backend work at all")
    }

    func testRemoteMaintenanceRefusesWithoutConfigurationOrTokenOrOwner() {
        XCTAssertFalse(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: true, isBackendConfigured: false,
            hasAccessToken: true, backendUserID: "abc"))
        XCTAssertFalse(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: true, isBackendConfigured: true,
            hasAccessToken: false, backendUserID: "abc"))
        XCTAssertFalse(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: true, isBackendConfigured: true,
            hasAccessToken: true, backendUserID: "   "),
            "a blank owner is not an owner")
        XCTAssertFalse(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: true, isBackendConfigured: true,
            hasAccessToken: true, backendUserID: nil))
    }

    /// The editor must not vanish mid-edit, so visibility cannot depend on the
    /// handle text — see the scope's §2.7.
    func testMaintenanceSurfaceVisibilityIgnoresHandleContentAndMode() {
        XCTAssertTrue(ProfileMaintenancePolicy.mayShowMaintenanceSurface(
            hasConnectedIdentity: true, isBackendConfigured: true))
        XCTAssertFalse(ProfileMaintenancePolicy.mayShowMaintenanceSurface(
            hasConnectedIdentity: false, isBackendConfigured: true))
        XCTAssertFalse(ProfileMaintenancePolicy.mayShowMaintenanceSurface(
            hasConnectedIdentity: true, isBackendConfigured: false))
    }

    // MARK: - The local-first gate, driven with COUNTED effects

    /// **A failed local commit publishes NOTHING.** Counted, not asserted about a
    /// boolean: the remote step is only reached on `.remotePermitted`.
    func testAFailedLocalCommitPermitsNoRemoteWork() {
        var commits = 0, remoteChecks = 0, published = 0
        let decision = ProfileMaintenanceGate.decide(
            commitLocally: { commits += 1
                             return .failure(NSError(domain: "t", code: 1)) },
            mayAttemptRemote: { remoteChecks += 1; return true })
        if decision == .remotePermitted { published += 1 }

        XCTAssertEqual(decision, .blockedByLocalFailure)
        XCTAssertEqual(commits, 1, "the local commit is still attempted")
        XCTAssertEqual(remoteChecks, 0, "eligibility is not even consulted after a local failure")
        XCTAssertEqual(published, 0, "nothing may be published that was not recorded")
    }

    /// **Solo with no identity still persists locally.** This is the members for
    /// whom the local record is the only record, and the regression this ordering
    /// exists to prevent.
    func testNoIdentityStillCommitsLocallyAndPublishesNothing() {
        var commits = 0, published = 0
        let decision = ProfileMaintenanceGate.decide(
            commitLocally: { commits += 1; return .success(()) },
            mayAttemptRemote: {
                ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
                    hasConnectedIdentity: false, isBackendConfigured: true,
                    hasAccessToken: true, backendUserID: "abc")
            })
        if decision == .remotePermitted { published += 1 }

        XCTAssertEqual(decision, .localOnly)
        XCTAssertEqual(commits, 1, "local persistence must NOT sit behind the remote preconditions")
        XCTAssertEqual(published, 0)
    }

    /// The lapsed-owner case: identity present, Connected mode absent.
    func testALapsedOwnerCommitsLocallyAndIsPermittedToPublish() {
        var commits = 0
        let decision = ProfileMaintenanceGate.decide(
            commitLocally: { commits += 1; return .success(()) },
            mayAttemptRemote: {
                ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
                    hasConnectedIdentity: true, isBackendConfigured: true,
                    hasAccessToken: true, backendUserID: "abc")
            })
        XCTAssertEqual(decision, .remotePermitted)
        XCTAssertEqual(commits, 1)
    }

    /// The local commit must run BEFORE eligibility is consulted, not after.
    func testTheLocalCommitRunsBeforeEligibilityIsConsulted() {
        var order: [String] = []
        _ = ProfileMaintenanceGate.decide(
            commitLocally: { order.append("commit"); return .success(()) },
            mayAttemptRemote: { order.append("eligibility"); return true })
        XCTAssertEqual(order, ["commit", "eligibility"])
    }

    // MARK: - Reset: no writes after the GLOBAL flag has cleared

    /// The window that a single boolean hides: the reset's own `defer` has
    /// already cleared `isInProgress`, and a late `.onDisappear` arrives.
    func testAnInvalidatedViewRefusesStorageEvenAfterTheGlobalFlagClears() {
        XCTAssertFalse(ProfileLocalStorageGate.isUsable(viewInvalidatedByReset: true,
                                                        resetInProgress: false),
                       "this is the .onDisappear-after-reset path that re-created erased text")
        XCTAssertFalse(ProfileLocalStorageGate.isUsable(viewInvalidatedByReset: true,
                                                        resetInProgress: true))
        XCTAssertFalse(ProfileLocalStorageGate.isUsable(viewInvalidatedByReset: false,
                                                        resetInProgress: true))
        XCTAssertTrue(ProfileLocalStorageGate.isUsable(viewInvalidatedByReset: false,
                                                       resetInProgress: false))
    }

    /// An invalidated view performs ZERO local writes through the gate, counted.
    func testAnInvalidatedViewPerformsZeroLocalWrites() {
        var coreDataWrites = 0, defaultsWrites = 0
        func persistIfPermitted(invalidated: Bool, inProgress: Bool) {
            guard ProfileLocalStorageGate.isUsable(viewInvalidatedByReset: invalidated,
                                                   resetInProgress: inProgress) else { return }
            coreDataWrites += 1
            defaultsWrites += 1
        }
        persistIfPermitted(invalidated: true, inProgress: false)   // late onDisappear
        persistIfPermitted(invalidated: true, inProgress: true)    // during the reset
        XCTAssertEqual(coreDataWrites, 0)
        XCTAssertEqual(defaultsWrites, 0)

        persistIfPermitted(invalidated: false, inProgress: false)  // ordinary save
        XCTAssertEqual(coreDataWrites, 1, "an ordinary save must still work")
    }

    // MARK: - Pre-submit staleness, including A→B→A

    func testADelayedTaskDoesNotSubmitAfterAnOwnerChange() {
        var submits = 0
        let token = ProfilePreSubmitToken(owner: "A", generation: 1)
        if token.isStillCurrent(owner: "B", generation: 1) { submits += 1 }
        XCTAssertEqual(submits, 0, "an edit composed under A must never be sent as B")
    }

    /// **A→B→A.** The owner reads as A again, so an owner check alone would pass;
    /// the generation is what makes the stale intent stale.
    func testAnABATransitionIsStaleEvenThoughTheOwnerMatchesAgain() {
        var submits = 0
        let token = ProfilePreSubmitToken(owner: "A", generation: 1)
        if token.isStillCurrent(owner: "A", generation: 2) { submits += 1 }
        XCTAssertEqual(submits, 0, "the session was torn down and rehydrated between capture and use")
    }

    func testAnUnchangedIdentityStillSubmits() {
        let token = ProfilePreSubmitToken(owner: "A", generation: 1)
        XCTAssertTrue(token.isStillCurrent(owner: "A", generation: 1))
    }

    // MARK: - Draft state: EVERY edit reopens the window

    func testHydrationIsBlockedWhileTheNewestEditIsUnsaved() {
        var d = ProfileNameDraftState()
        XCTAssertTrue(d.mayHydrate)
        d.edited()
        XCTAssertFalse(d.mayHydrate)
        d.evidencedSaved()
        XCTAssertTrue(d.mayHydrate)
    }

    /// The correction Codex required: the guard is not "has a save ever run".
    func testEachNewEditReopensTheWindowAfterAnEvidencedSave() {
        var d = ProfileNameDraftState()
        d.edited(); d.evidencedSaved()
        d.edited()
        XCTAssertFalse(d.mayHydrate, "a NEW edit after a save must block hydration again")
    }

    /// **Hydration preserves the newer text**, counted as the assignment a real
    /// `load()` would make.
    func testHydrationPreservesTheDraftAndOverwritesOnlyWhenClean() {
        var d = ProfileNameDraftState()
        var displayed = "STORED"
        func hydrate(from stored: String) { if d.mayHydrate { displayed = stored } }

        d.edited(); displayed = "TYPING"
        hydrate(from: "STORED")
        XCTAssertEqual(displayed, "TYPING", "an unrelated save must not replace a live draft")

        d.evidencedSaved()
        hydrate(from: "TYPING")
        XCTAssertEqual(displayed, "TYPING")
    }

    /// In-flight: neither cleared nor hydratable.
    func testAnInFlightAttemptNeitherClearsTheFlagNorPermitsHydration() {
        var d = ProfileNameDraftState()
        d.edited()
        XCTAssertFalse(d.mayHydrate)
        XCTAssertTrue(d.isDirty)
    }

    /// **Reset drops the draft AND the storage gate refuses**, which together are
    /// the no-resurrection boundary. Neither half is sufficient alone.
    func testFactoryResetDropsTheDraftAndTheGateRefusesAnyWriteBack() {
        var d = ProfileNameDraftState()
        d.edited()
        d.invalidateForFactoryReset()
        XCTAssertFalse(d.isDirty)

        var writes = 0
        if ProfileLocalStorageGate.isUsable(viewInvalidatedByReset: true, resetInProgress: false) {
            writes += 1
        }
        XCTAssertEqual(writes, 0, "a cleared draft must not be written back after the reset")
    }

    // MARK: - The forced refresh is opt-in

    /// **NARROW CLAIM, named honestly.** This establishes only that the `force`
    /// parameter EXISTS with a default of `false` — the call compiles without it
    /// — and that the no-identity guard refuses before any refresh, forced or
    /// not. It does **not** exercise forced-vs-coalesced behaviour or real 401
    /// recovery; the 401 route is covered end to end against the transport in
    /// `C70DirectoryWriteTransportTests`, and C-98's refresh lifecycle by
    /// `C98AuthRefreshLifecycleTests`.
    @MainActor
    func testForceParameterExistsAndTheNoIdentityGuardRefusesEitherWay() async {
        let auth = AuthManager()
        let implicit = await auth.ensureValidBackendSession(reason: "test-implicit")
        let explicit = await auth.ensureValidBackendSession(reason: "test-explicit", force: false)
        let forced = await auth.ensureValidBackendSession(reason: "test-forced", force: true)
        XCTAssertFalse(implicit)
        XCTAssertFalse(explicit)
        XCTAssertFalse(forced, "no currentUserID means no refresh, forced or not")
    }
}
