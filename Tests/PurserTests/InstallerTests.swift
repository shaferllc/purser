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
