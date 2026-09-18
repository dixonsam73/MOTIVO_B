//
//  C100SentinelAttributionTests.swift
//  MOTIVOTests
//
//  C-100 — the activation-write sentinel must still catch what it was built to
//  catch, and must stop blaming the host app for writes it did not make.
//
//  POSITIVE CONTROL: the frames the sentinel caught on 2026-09-14, copied
//  VERBATIM from that negative control's recorded failure
//  (claude-evidence/c100/p4-negative-control/failures.txt, frames 23–25; the
//  recorder truncated frame 24's symbol, which is kept as recorded). No launch,
//  no activation and no network: the real path is represented by its recorded
//  frames, not re-triggered, so `UnitTestHost` is never bypassed.
//
//  NEGATIVE CONTROLS: a stack whose only `MOTIVOApp` frame is the `@main` entry
//  point — in the recorded form (the 2026-09-18 probe) and LIVE, captured on the
//  main run loop during this async test, the shape of the unexplained failure.
//

import XCTest
@testable import Etudes

final class C100SentinelAttributionTests: XCTestCase {

    /// Recorded 2026-09-14 — what the sentinel originally caught.
    private let originallyCaught = [
        "23  Etudes.debug.dylib                  0x000000010a8c561c $s6Etudes14AppModeManagerC15applyActivation4auth10isEntitledyAA04AuthD0C_SbtF + 96",
        "24  Etudes.debug.dylib                  0x000000010b069e4c $s6Etudes9MOTIVOAppV21handleMembershipState33_D67A57795BB9BB6F265616E36A26D899LLyyAA09Conne",
        "25  Etudes.debug.dylib                  0x000000010b069a08 $s6Etudes9MOTIVOAppV4bodyQrvg7SwiftUI4ViewPAEE20preferredColorSchemeyQrAE0hI0OSgFQOyAgEE9on",
    ]

    /// Recorded 2026-09-18 — the entry frame, as the probe captured it.
    private let entryFrame =
        "64  Etudes.debug.dylib                  0x0000000107985738 $s6Etudes9MOTIVOAppV5$mainyyFZ + 40"

    private let harmlessFrames = [
        "16  CoreFoundation                      0x000000018041c904 _CFRunLoopRunSpecificWithOptions + 496",
        "17  XCTestCore                          0x00000001017f5e38 +[XCTWaiter _synchronouslyWaitForTimeInterval:] + 108",
        "58  UIKitCore                           0x0000000185a3f8c0 UIApplicationMain + 120",
    ]

    // MARK: - Positive control: the original catch still attributes

    func testOriginallyCaughtActivationPathStillAttributesEvenWithTheEntryFrameBelowIt() {
        let stack = harmlessFrames + originallyCaught + [entryFrame]
        let attributing = HostActivationAttribution.attributingFrames(stack)
        XCTAssertEqual(attributing.count, 2, "handleMembershipState and the MOTIVOApp.body closure: \(attributing)")
        XCTAssertTrue(attributing.contains { $0.contains("MOTIVOAppV21handleMembershipState") })
        XCTAssertTrue(attributing.contains { $0.contains("MOTIVOAppV4body") })
        XCTAssertFalse(attributing.contains(entryFrame), "the entry frame itself never attributes")
    }

    // MARK: - Negative controls: the entry frame alone does not

    func testRecordedEntryFrameOnlyStackIsNotAttributed() {
        let stack = harmlessFrames + [entryFrame]
        XCTAssertTrue(HostActivationAttribution.attributingFrames(stack).isEmpty)
    }

    /// The shape of the unexplained 2c failure, LIVE: a block the main run loop
    /// executes while XCTest waits on this async (non-MainActor) test. Reported
    /// with XCTAssert only — no XCTContext activity off the main thread.
    func testLiveMainRunLoopStackCarriesOnlyTheEntryFrameAndIsNotAttributed() async {
        let stack: [String] = await withCheckedContinuation { continuation in
            RunLoop.main.perform { continuation.resume(returning: Thread.callStackSymbols) }
        }
        XCTAssertTrue(stack.contains { HostActivationAttribution.symbol(of: $0) == HostActivationAttribution.entryPointSymbol },
                      "fixture: the live stack must carry the real entry symbol, or this test proves nothing")
        XCTAssertTrue(stack.contains { $0.contains("XCTWaiter") }, "fixture: delivered while XCTest waits, as in the failure")
        XCTAssertTrue(HostActivationAttribution.attributingFrames(stack).isEmpty,
                      "no MOTIVOApp CODE frame is on this stack, so nothing attributes")
    }

    // MARK: - The exclusion is exact, and fails towards reporting

    func testOnlyTheExactEntrySymbolIsExcluded() {
        let lookalike = "64  Etudes.debug.dylib  0x0000000107985738 $s6Etudes9MOTIVOAppV5$mainyyFZTf4d_n + 40"
        let otherMain = "12  Etudes.debug.dylib  0x0000000107985738 $s6Etudes9MOTIVOAppV8someMainyyF + 12"
        XCTAssertEqual(HostActivationAttribution.attributingFrames([lookalike, otherMain]).count, 2,
                       "a specialised or differently named MOTIVOApp frame is still app code")
    }

    func testAnUnparseableLineNamingMOTIVOAppStillAttributes() {
        XCTAssertEqual(HostActivationAttribution.attributingFrames(["MOTIVOApp"]).count, 1)
    }
}
