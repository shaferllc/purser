@testable import Purser
import XCTest

/// These build real bundles on disk and run the real `codesign`, because the
/// whole point of the check is what that tool says.
final class SignatureTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurserSig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A minimal but real .app: Info.plist, an executable, and a resource.
    @discardableResult
    private func makeBundle(named name: String = "Sig Test") throws -> URL {
        let app = scratch.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        let resources = app.appendingPathComponent("Contents/Resources")

        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let executable = macOS.appendingPathComponent("SigTest")
        try "#!/bin/bash\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try "resource".write(to: resources.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.tomshafer.purser-sigtest",
            "CFBundleName": name,
            "CFBundleExecutable": "SigTest",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        return app
    }

    func testAProperlySignedBundleVerifies() throws {
        let app = try makeBundle()
        XCTAssertTrue(Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path]).succeeded)

        XCTAssertEqual(Installer.signatureState(of: app), .valid)
    }

    func testABundleWithNoSignatureAtAllReadsAsUnsigned() throws {
        let app = try makeBundle()

        XCTAssertEqual(Installer.signatureState(of: app), .unsigned)
    }

    /// The Spyglass 0.1.2 case: the executable carries a signature but the
    /// bundle was never sealed, because the build's `codesign` step failed and
    /// its error was swallowed. codesign says "code has no resources but
    /// signature indicates they must be present". That's a packaging mistake,
    /// not tampering, and must be reported as such.
    func testABundleWhoseExecutableIsSignedButHasNoSealedResourcesReadsAsUnsigned() throws {
        let app = try makeBundle()
        let executable = app.appendingPathComponent("Contents/MacOS/SigTest")

        // A system binary stands in for a linker-signed Swift executable: both
        // carry a valid signature of their own inside an unsealed bundle.
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: executable)

        XCTAssertEqual(Installer.signatureState(of: app), .unsigned)
    }

    /// Signed, then altered: the seal no longer matches the contents.
    func testEditingASignedBundleBreaksTheSeal() throws {
        let app = try makeBundle()
        XCTAssertTrue(Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path]).succeeded)

        try "tampered".write(
            to: app.appendingPathComponent("Contents/Resources/data.txt"),
            atomically: true,
            encoding: .utf8
        )

        guard case .broken = Installer.signatureState(of: app) else {
            return XCTFail("a modified signed bundle must read as broken, not unsigned")
        }
    }

    func testAddingAFileToASignedBundleBreaksTheSeal() throws {
        let app = try makeBundle()
        XCTAssertTrue(Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path]).succeeded)

        try "extra".write(
            to: app.appendingPathComponent("Contents/Resources/smuggled.txt"),
            atomically: true,
            encoding: .utf8
        )

        guard case .broken = Installer.signatureState(of: app) else {
            return XCTFail("an added file must read as broken, not unsigned")
        }
    }
}
