//
//  ConnectedAgeGateTests.swift
//  MOTIVOTests
//
//  The adult-only gate: only an 18+ range that Apple reports as `.confirmed`
//  admits to Connected. Everything else is refused, with the reason the
//  anonymous refusal counter records.
//

import XCTest
@testable import Etudes

final class ConnectedAgeGateTests: XCTestCase {

    private typealias Gate = ConnectedAgeGate

    private static let allDeclarations: [Gate.Declaration?] =
        [nil, .confirmed, .selfDeclared, .guardianDeclared, .other]

    // MARK: - Admission

    func testOnlyAConfirmedAdultIsAdmitted() {
        XCTAssertEqual(Gate.evaluate(lowerBound: 18, upperBound: nil, declaration: .confirmed), .confirmedAdult)
        XCTAssertEqual(Gate.evaluate(lowerBound: 21, upperBound: 99, declaration: .confirmed), .confirmedAdult)
    }

    func testAnAdultThatIsNotConfirmedIsRefused() {
        for declaration in [nil, .selfDeclared, .guardianDeclared, .other] as [Gate.Declaration?] {
            XCTAssertEqual(Gate.evaluate(lowerBound: 18, upperBound: nil, declaration: declaration),
                           .refused(.unconfirmedAdult),
                           "18+ with declaration \(String(describing: declaration)) must be refused")
        }
    }

    // MARK: - Apple's sandbox ranges, against every declaration

    /// Apple's sandbox returns under-13, 13-15, 16-17 and 18+ as separate
    /// ranges. Every range below 18 is refused as under 18, whatever the
    /// declaration, including `.confirmed`.
    func testAppleSandboxRangesUnder18AreRefusedWhateverTheDeclaration() {
        let minorRanges: [(Int?, Int?)] = [(nil, 12), (13, 15), (16, 17)]
        for (lower, upper) in minorRanges {
            for declaration in Self.allDeclarations {
                XCTAssertEqual(Gate.evaluate(lowerBound: lower, upperBound: upper, declaration: declaration),
                               .refused(.under18),
                               "\(String(describing: lower))-\(String(describing: upper)) \(String(describing: declaration))")
            }
        }
    }

    func testBoundaries() {
        XCTAssertEqual(Gate.evaluate(lowerBound: 17, upperBound: 17, declaration: .confirmed), .refused(.under18))
        XCTAssertEqual(Gate.evaluate(lowerBound: 17, upperBound: nil, declaration: .confirmed), .refused(.under18))
        XCTAssertEqual(Gate.evaluate(lowerBound: 18, upperBound: 18, declaration: .confirmed), .confirmedAdult)
    }

    /// A nil lower bound is "below the lowest gate Apple used". It can never
    /// admit, whatever the upper bound or declaration says.
    func testNilLowerBoundNeverAdmits() {
        for upper in [5, 12, 17, 18, 99] as [Int?] {
            for declaration in Self.allDeclarations {
                XCTAssertEqual(Gate.evaluate(lowerBound: nil, upperBound: upper, declaration: declaration),
                               .refused(.under18))
            }
        }
    }

    /// No bounds at all is no answer, not an age.
    func testNoBoundsIsUnavailable() {
        for declaration in Self.allDeclarations {
            XCTAssertEqual(Gate.evaluate(lowerBound: nil, upperBound: nil, declaration: declaration),
                           .refused(.unavailable))
        }
    }

    /// Apple may raise the gate by region. A raised lower bound below 18 still
    /// refuses; only bounds decide, never the gate we asked for.
    func testRegionalGateOverrideStillDecidesByBounds() {
        XCTAssertEqual(Gate.evaluate(lowerBound: nil, upperBound: 20, declaration: .confirmed), .refused(.under18))
        XCTAssertEqual(Gate.evaluate(lowerBound: 21, upperBound: nil, declaration: .confirmed), .confirmedAdult)
    }

    // MARK: - Counter reasons and wording

    /// The raw values are the server counter's accepted reasons.
    func testRefusalReasonRawValuesMatchTheServerCounter() {
        XCTAssertEqual(Gate.RefusalReason.allCases.map(\.rawValue).sorted(),
                       ["declined", "ios_update_needed", "unavailable", "unconfirmed_adult", "under_18"])
    }

    func testRefusalWording() {
        XCTAssertTrue(Gate.refusalMessage(for: .iosUpdateNeeded).contains("Update iOS"))
        for reason in [.under18, .unconfirmedAdult, .declined, .unavailable] as [Gate.RefusalReason] {
            XCTAssertTrue(Gate.refusalMessage(for: reason).contains("Personal Information → Age Confirmation"),
                          "\(reason) must tell the person how to confirm")
        }
    }

    // MARK: - Apple mapping

    #if canImport(DeclaredAgeRange)
    func testAppleDeclarationsMapStrictly() throws {
        guard #available(iOS 26.5, *) else { throw XCTSkip("needs iOS 26.5") }
        XCTAssertEqual(Gate.declaration(for: .confirmed), .confirmed)
        XCTAssertEqual(Gate.declaration(for: .selfDeclared), .selfDeclared)
        XCTAssertEqual(Gate.declaration(for: .guardianDeclared), .guardianDeclared)
    }
    #endif
}
