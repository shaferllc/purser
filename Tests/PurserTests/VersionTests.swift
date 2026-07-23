@testable import Purser
import XCTest

final class VersionTests: XCTestCase {
    func testComparesComponentByComponent() {
        XCTAssertEqual(Version.compare("0.5", "0.5.1"), .orderedAscending)
        XCTAssertEqual(Version.compare("0.10", "0.9"), .orderedDescending)
        XCTAssertEqual(Version.compare("1.0.0", "1.0"), .orderedSame)
    }

    func testTrailingZerosDoNotCountAsAnUpdate() {
        XCTAssertFalse(Version.isNewer("1.0.0", than: "1.0"))
        XCTAssertFalse(Version.isNewer("1.0", than: "1.0.0"))
    }

    func testDoubleDigitComponentsSortNumericallyNotAlphabetically() {
        XCTAssertTrue(Version.isNewer("0.12.0", than: "0.9.9"))
        XCTAssertTrue(Version.isNewer("2.0", than: "1.99"))
    }

    /// A build like "1.2-beta" must not read as newer than "1.2".
    func testNonNumericSuffixesAreIgnoredRatherThanRankedHigh() {
        XCTAssertFalse(Version.isNewer("1.2-beta", than: "1.2"))
        XCTAssertTrue(Version.isNewer("1.3-beta", than: "1.2"))
    }

    func testGarbageNeverLooksNewer() {
        XCTAssertFalse(Version.isNewer("", than: "0.1"))
        XCTAssertFalse(Version.isNewer("unknown", than: "0.1"))
    }
}
