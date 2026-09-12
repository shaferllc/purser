@testable import Purser
import XCTest

final class LicenceHandoffTests: XCTestCase {
    private var prefs: [String: String] = [:]
    private var defaults: UserDefaults!

    private var store: LicenceHandoff.Store {
        LicenceHandoff.Store(
            read: { [unowned self] key, bundleID in prefs["\(bundleID)/\(key)"] },
            write: { [unowned self] key, value, bundleID in prefs["\(bundleID)/\(key)"] = value }
        )
    }

    private let capstan = ["capstan": "com.tomshafer.capstan"]
    private let slot = "com.tomshafer.capstan/capstan.licenseKey"

    override func setUp() {
        prefs = [:]
        defaults = UserDefaults(suiteName: "LicenceHandoffTests")
        defaults.removePersistentDomain(forName: "LicenceHandoffTests")
    }

    private func licence(_ key: String, expires: String? = "2026-10-12T00:00:00+00:00") -> IssuedLicense {
        IssuedLicense(product: "capstan", key: key, source: expires == nil ? "purchase" : "membership", expiresAt: expires)
    }

    func testWritesTheKeyIntoAnEmptySlot() {
        let unlocked = LicenceHandoff.apply([licence("m1")], bundleIDs: capstan, store: store, defaults: defaults)

        XCTAssertEqual(prefs[slot], "m1")
        XCTAssertEqual(unlocked, ["capstan"])
    }

    func testReplacesAKeyItWroteItself() {
        LicenceHandoff.apply([licence("m1")], bundleIDs: capstan, store: store, defaults: defaults)
        LicenceHandoff.apply([licence("m2")], bundleIDs: capstan, store: store, defaults: defaults)

        XCTAssertEqual(prefs[slot], "m2")
    }

    func testNeverOverwritesAKeyPastedByHand() {
        prefs[slot] = "bought-it"

        let unlocked = LicenceHandoff.apply([licence("m1")], bundleIDs: capstan, store: store, defaults: defaults)

        XCTAssertEqual(prefs[slot], "bought-it")
        XCTAssertTrue(unlocked.isEmpty)
    }

    func testPerpetualBeatsExpiringAndLaterBeatsEarlier() {
        let best = LicenceHandoff.best([
            licence("early", expires: "2026-09-20T00:00:00+00:00"),
            licence("late", expires: "2026-11-01T00:00:00+00:00"),
        ])
        XCTAssertEqual(best["capstan"]?.key, "late")

        let withPurchase = LicenceHandoff.best([licence("late"), licence("forever", expires: nil)])
        XCTAssertEqual(withPurchase["capstan"]?.key, "forever")
    }

    func testSkipsAppsThatAreNotInstalled() {
        LicenceHandoff.apply([licence("m1")], bundleIDs: [:], store: store, defaults: defaults)

        XCTAssertTrue(prefs.isEmpty)
    }

    func testRevokeRemovesOnlyItsOwnKeys() {
        LicenceHandoff.apply([licence("m1")], bundleIDs: capstan, store: store, defaults: defaults)
        LicenceHandoff.revoke(bundleIDs: capstan, store: store, defaults: defaults)
        XCTAssertNil(prefs[slot])

        prefs[slot] = "bought-it"
        LicenceHandoff.revoke(bundleIDs: capstan, store: store, defaults: defaults)
        XCTAssertEqual(prefs[slot], "bought-it")
    }
}
