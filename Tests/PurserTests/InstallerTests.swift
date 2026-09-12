@testable import Purser
import XCTest

final class InstallerTests: XCTestCase {
    func testSupportPathsCoverTheUsualLeftovers() {
        let paths = Installer.supportPaths(for: "com.tomshafer.quay").map(\.path)

        XCTAssertTrue(paths.contains { $0.hasSuffix("Application Support/com.tomshafer.quay") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("Preferences/com.tomshafer.quay.plist") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("Caches/com.tomshafer.quay") })
    }

    func testSupportPathsStayInsideTheUsersLibrary() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        for url in Installer.supportPaths(for: "com.tomshafer.quay") {
            XCTAssertTrue(url.path.hasPrefix(home + "/Library/"), "\(url.path) escapes ~/Library")
        }
    }

    /// Regression: an app installed somewhere other than /Applications — the
    /// Desktop, say — was updated into /Applications instead, leaving a stale
    /// duplicate that LaunchServices would keep opening.
    func testAnUpdateReplacesTheCopyThatIsAlreadyThere() {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let installed = InstalledApp(
            bundleID: "com.spyglass.desktop",
            url: desktop.appendingPathComponent("Spyglass.app"),
            version: "0.1.0",
            build: "1",
            name: "Spyglass"
        )

        let destination = Installer.destination(
            updating: installed,
            fallback: URL(fileURLWithPath: "/Applications")
        )

        XCTAssertEqual(destination.standardizedFileURL, desktop.standardizedFileURL)
    }

    func testAFreshInstallUsesTheConfiguredLocation() {
        let fallback = URL(fileURLWithPath: "/Applications")

        XCTAssertEqual(Installer.destination(updating: nil, fallback: fallback), fallback)
    }

    func testAnUpdateFallsBackWhenTheCurrentLocationIsReadOnly() {
        let installed = InstalledApp(
            bundleID: "com.apple.Safari",
            url: URL(fileURLWithPath: "/System/Applications/Safari.app"),
            version: "1.0",
            build: "1",
            name: "Safari"
        )
        let fallback = Installer.userApplications()

        XCTAssertEqual(Installer.destination(updating: installed, fallback: fallback), fallback)
    }

    func testDefaultDestinationIsAnApplicationsFolder() {
        XCTAssertTrue(Installer.defaultDestination().lastPathComponent == "Applications")
    }

    func testUserApplicationsIsCreatedOnDemand() {
        let url = Installer.userApplications()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testShellReportsFailureWithoutThrowing() {
        let result = Shell.run("/usr/bin/false", [])

        XCTAssertFalse(result.succeeded)
    }

    func testShellCapturesOutput() {
        let result = Shell.run("/bin/echo", ["hello"])

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout, "hello")
    }
}
