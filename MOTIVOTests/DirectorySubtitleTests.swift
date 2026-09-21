// CHANGE-ID: 20260920_HandleRemoval_DirectorySubtitle
// SCOPE: The people-row second line that replaced `@handle`. Pure formatter,
// tested without a view.
// SEARCH-TOKEN: 20260920_HandleRemoval_DirectorySubtitle

import XCTest
@testable import Etudes

/// `DirectorySubtitle` composes the second line of a people row from what the
/// directory ALREADY returned for that account.
///
/// **These are value tests, not rendering tests.** They establish what the
/// formatter produces; they do not establish that SwiftUI drew it.
final class DirectorySubtitleTests: XCTestCase {

    // MARK: - The four presence cases

    func testBothInstrumentsAndLocation() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Cello"], location: "London"),
                       "Cello · London")
    }

    func testInstrumentsOnly() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Cello"], location: nil), "Cello")
    }

    func testLocationOnly() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: nil, location: "London"), "London")
    }

    /// **Empty is truthful and is the point.** A row with neither renders no
    /// second line, which is exactly what the directory rows carrying no handle
    /// already did before this existed — so this is a generalised existing
    /// state, not a new one.
    func testNeitherIsEmptyRatherThanInvented() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: nil, location: nil), "")
        XCTAssertEqual(DirectorySubtitle.text(instruments: [], location: nil), "")
    }

    // MARK: - Whitespace is not content

    func testWhitespaceOnlyValuesAreDroppedNotRendered() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["   "], location: "  \n "), "")
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["  ", "Cello", "\t"], location: "   "),
                       "Cello",
                       "a blank instrument must not consume one of the two named slots")
    }

    func testValuesAreTrimmedBeforeJoining() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["  Cello  "], location: "  London  "),
                       "Cello · London")
    }

    // MARK: - The bound

    func testTwoInstrumentsAreBothNamed() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Cello", "Piano"], location: nil),
                       "Cello, Piano")
    }

    /// The third becomes `+1` rather than being silently dropped: a row that
    /// ends "+1" is honest about what it is not showing.
    func testTheThirdInstrumentBecomesACount() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Cello", "Piano", "Violin"], location: nil),
                       "Cello, Piano +1")
    }

    func testManyInstrumentsCountTheRemainderExactly() {
        let many = ["Cello", "Piano", "Violin", "Viola", "Double Bass", "Harp"]
        XCTAssertEqual(DirectorySubtitle.text(instruments: many, location: "Leeds"),
                       "Cello, Piano +4 · Leeds")
    }

    func testTheBoundCountsOnlyNonEmptyInstruments() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Cello", "  ", "Piano", "", "Violin"],
                                              location: nil),
                       "Cello, Piano +1",
                       "blanks must not inflate the +N")
    }

    // MARK: - Non-Latin text passes through unchanged

    /// The handle generator folded and filtered to `[a-z0-9_]`, which is why a
    /// non-Latin name produced no handle at all. This formatter does no folding,
    /// no filtering and no transliteration.
    func testNonLatinInstrumentsAndLocationsAreNotFoldedOrFiltered() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["ヴァイオリン"], location: "東京"),
                       "ヴァイオリン · 東京")
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Виолончель", "Фортепиано"], location: "Москва"),
                       "Виолончель, Фортепиано · Москва")
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["عود"], location: "القاهرة"), "عود · القاهرة")
    }

    func testDiacriticsSurviveIntact() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Saxofón"], location: "Málaga"),
                       "Saxofón · Málaga")
    }

    // MARK: - Long values are not truncated

    /// The bound is on the NUMBER of instruments, not on their length. A
    /// mid-word truncation would misname the instrument, which is worse than a
    /// long line the layout can wrap.
    func testALongInstrumentNameIsNotTruncated() {
        let long = String(repeating: "a", count: 200)
        XCTAssertTrue(DirectorySubtitle.text(instruments: [long], location: nil).contains(long))
    }

    // MARK: - Order is the caller's, not the formatter's

    func testOrderIsPreservedExactlyAsReturned() {
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Piano", "Cello"], location: nil),
                       "Piano, Cello")
        XCTAssertEqual(DirectorySubtitle.text(instruments: ["Cello", "Piano"], location: nil),
                       "Cello, Piano")
    }

    // MARK: - The account convenience

    /// `nil` rather than `""` when there is nothing to say, so a call site
    /// passing this to `overrideSubtitle` expresses "no override" rather than
    /// "override with a blank".
    func testTheAccountFormOfNothingIsNilNotEmpty() {
        XCTAssertNil(DirectorySubtitle.text(for: nil))
        XCTAssertNil(DirectorySubtitle.text(for: account(instruments: nil, location: nil)))
        XCTAssertNil(DirectorySubtitle.text(for: account(instruments: ["  "], location: " ")))
    }

    func testTheAccountFormUsesThatAccountsOwnValues() {
        XCTAssertEqual(DirectorySubtitle.text(for: account(instruments: ["Cello"], location: "York")),
                       "Cello · York")
    }

    private func account(instruments: [String]?, location: String?) -> DirectoryAccount {
        DirectoryAccount(userID: "11111111-1111-1111-1111-111111111111",
                         accountID: "a_handle_nobody_can_see",
                         displayName: "Ada",
                         location: location,
                         avatarKey: nil,
                         instruments: instruments,
                         avatarVersion: nil)
    }

    /// The formatter has no access to `accountID` at all, so a row that still
    /// carries one in the database cannot leak it into the subtitle.
    func testAServerReturnedHandleNeverReachesTheSubtitle() {
        let a = account(instruments: ["Cello"], location: "York")
        let subtitle = DirectorySubtitle.text(for: a) ?? ""
        XCTAssertFalse(subtitle.contains(a.accountID ?? ""))
        XCTAssertFalse(subtitle.contains("@"))
    }
}
