@testable import Purser
import XCTest

final class InstalledAppsTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func makeBundle(version: String, build: String = "1") throws -> URL {
        let app = scratch.appendingPathComponent("Test Tile.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.tomshafer.purser-testtile",
            "CFBundleName": "Test Tile",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        return app
    }

    func testReadsVersionAndIdentifier() throws {
        let app = try makeBundle(version: "1.0.0")

        let installed = try XCTUnwrap(InstalledApps.read(at: app))

        XCTAssertEqual(installed.bundleID, "com.tomshafer.purser-testtile")
        XCTAssertEqual(installed.version, "1.0.0")
        XCTAssertEqual(installed.name, "Test Tile")
    }

    /// Regression: `Bundle(url:)` caches Info.plist for the life of the
    /// process, so after an update the app kept reporting the old version and
    /// the update badge never cleared.
    func testSeesANewVersionAfterTheBundleIsReplaced() throws {
        let app = try makeBundle(version: "1.0.0")
        XCTAssertEqual(InstalledApps.read(at: app)?.version, "1.0.0")

        _ = try makeBundle(version: "1.1.0", build: "2")

        XCTAssertEqual(InstalledApps.read(at: app)?.version, "1.1.0")
        XCTAssertEqual(InstalledApps.read(at: app)?.build, "2")
    }

    /// Regression: after Remove, LaunchServices still resolved the bundle ID to
    /// the copy in the Trash, so the app kept showing as installed.
    func testAppsInTheTrashDoNotCountAsInstalled() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        XCTAssertTrue(InstalledApps.isTrashed(home.appendingPathComponent(".Trash/Test Tile.app")))
        XCTAssertTrue(InstalledApps.isTrashed(URL(fileURLWithPath: "/Volumes/Data/.Trashes/501/Quay.app")))
        XCTAssertFalse(InstalledApps.isTrashed(URL(fileURLWithPath: "/Applications/Quay.app")))
        XCTAssertFalse(InstalledApps.isTrashed(home.appendingPathComponent("Applications/Quay.app")))
    }

    func testReturnsNilForSomethingThatIsNotAnApp() {
        XCTAssertNil(InstalledApps.read(at: scratch.appendingPathComponent("Nope.app")))
    }

    func testMissingVersionFallsBackRatherThanCrashing() throws {
        let app = scratch.appendingPathComponent("Bare.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.example.bare"],
            format: .xml,
            options: 0
        )
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let installed = try XCTUnwrap(InstalledApps.read(at: app))

        XCTAssertEqual(installed.version, "0")
        XCTAssertEqual(installed.name, "Bare")
    }
}
