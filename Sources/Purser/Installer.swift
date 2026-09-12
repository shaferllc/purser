import AppKit
import CryptoKit
import Foundation

enum InstallStage: Sendable, Equatable {
    case waiting
    case downloading(Double)
    case verifying
    case expanding
    case installing

    var label: String {
        switch self {
        case .waiting: "Waiting…"
        case .downloading: "Downloading…"
        case .verifying: "Verifying…"
        case .expanding: "Unpacking…"
        case .installing: "Installing…"
        }
    }

    var fraction: Double? {
        if case let .downloading(value) = self { return value }

        return nil
    }
}

/// What `codesign` makes of a downloaded bundle.
enum SignatureState: Equatable {
    /// Signed, and the seal is intact.
    case valid
    /// Never properly signed — the executable carries the linker's ad-hoc
    /// signature but the bundle has no sealed resources. A build that skipped
    /// `codesign`, not a bundle anyone tampered with.
    case unsigned
    /// Signed, but the seal is broken. Somebody or something changed the
    /// bundle after it was signed.
    case broken(String)
}

enum InstallError: LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case unpackFailed(String)
    case noAppBundle
    case wrongBundleID(expected: String, found: String)
    case signatureInvalid(String)
    case unsignedAndUnverified(String)
    case destinationNotWritable(URL)
    case moveFailed(String)

    var errorDescription: String? {
        switch self {
        case let .checksumMismatch(expected, actual):
            "The download didn't match its checksum (expected \(expected.prefix(12))…, got \(actual.prefix(12))…). It was discarded."
        case let .unpackFailed(detail):
            "Couldn't unpack the download. \(detail)"
        case .noAppBundle:
            "The download didn't contain an app."
        case let .wrongBundleID(expected, found):
            "The download identifies itself as \(found), not \(expected). It was discarded."
        case let .signatureInvalid(detail):
            "The app's code signature is broken, which means the bundle was changed after it was signed. It was discarded.\n\n\(detail)"
        case let .unsignedAndUnverified(name):
            "\(name) isn't code signed, and its release publishes no checksum — there's nothing to check it against, so it wasn't installed."
        case let .destinationNotWritable(url):
            "Can't write to \(url.path)."
        case let .moveFailed(detail):
            "Couldn't move the app into place. \(detail)"
        }
    }
}

/// The result of an install: what landed, and anything the user should know
/// about it that wasn't bad enough to stop.
struct InstallOutcome: Sendable {
    var app: InstalledApp
    var warning: String?
}

/// Downloads an app, checks it is what the catalog said it was, and swaps it
/// into the applications folder.
enum Installer {
    /// LaunchServices' registration tool — the only supported way to tell macOS
    /// an app has appeared or gone away without waiting for it to notice.
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/"
        + "Frameworks/LaunchServices.framework/Support/lsregister"

    // MARK: - Install

    static func install(
        _ app: CatalogApp,
        from url: URL,
        into destinationDirectory: URL,
        progress: @escaping @Sendable (InstallStage) -> Void
    ) async throws -> InstallOutcome {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        progress(.downloading(0))
        let archive = try await download(url, into: scratch, progress: progress)

        var checksumVerified = false

        if let expected = app.latestRelease?.sha256, !expected.isEmpty {
            progress(.verifying)
            let actual = try sha256(of: archive)

            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                throw InstallError.checksumMismatch(expected: expected, actual: actual)
            }

            checksumVerified = true
        }

        progress(.expanding)
        let unpacked = try unpack(archive, into: scratch)

        guard let bundle = findAppBundle(in: unpacked) else { throw InstallError.noAppBundle }

        if let expected = app.bundleID {
            let found = Bundle(url: bundle)?.bundleIdentifier ?? "an unsigned bundle"

            guard found == expected else {
                throw InstallError.wrongBundleID(expected: expected, found: found)
            }
        }

        // A broken seal means the bundle changed after signing, and that's
        // always fatal. A bundle that was never signed is a packaging mistake
        // rather than an attack — install it only when the checksum already
        // proved it is byte-for-byte what the catalog published, and say so.
        var warning: String?

        switch signatureState(of: bundle) {
        case .valid:
            break
        case let .broken(detail):
            throw InstallError.signatureInvalid(detail)
        case .unsigned:
            guard checksumVerified else { throw InstallError.unsignedAndUnverified(app.name) }

            warning = "\(app.name) isn't code signed — its build skipped that step. "
                + "The download matched the checksum the catalog published, so it is the right file, "
                + "but macOS can't vouch for it."
        }

        progress(.installing)

        let installed = try place(bundle, named: app.name, into: destinationDirectory, bundleID: app.bundleID)

        // A release whose bundle carries a different version than the catalog
        // advertises would otherwise show up as an update that never completes:
        // we install it, rescan, still read the old version, and offer it again.
        if let expected = app.latestRelease?.version,
           Version.compare(installed.version, expected) != .orderedSame
        {
            warning = [
                warning,
                "\(app.name) installed, but the bundle reports version \(installed.version) while the "
                    + "catalog offers \(expected). The release is mis-stamped, so it will keep appearing "
                    + "under Updates until it's rebuilt with the right version.",
            ]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        }

        return InstallOutcome(app: installed, warning: warning)
    }

    // MARK: - Uninstall

    /// Moves the app to the Trash rather than deleting it — an install manager
    /// should never be the last word on someone's files.
    static func uninstall(_ installed: InstalledApp, alsoRemoveData: Bool) throws {
        quitIfRunning(bundleID: installed.bundleID)

        var trashed: NSURL?
        try FileManager.default.trashItem(at: installed.url, resultingItemURL: &trashed)

        // Without this LaunchServices keeps resolving the bundle ID to the copy
        // now sitting in the Trash, and the app still looks installed.
        Shell.run(lsregister, ["-u", installed.url.path])

        if let trashedURL = trashed as URL? {
            Shell.run(lsregister, ["-u", trashedURL.path])
        }

        guard alsoRemoveData else { return }

        for url in supportPaths(for: installed.bundleID) where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// Everything a well-behaved sandbox-free Mac app leaves behind.
    static func supportPaths(for bundleID: String) -> [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")

        return [
            library.appendingPathComponent("Application Support/\(bundleID)"),
            library.appendingPathComponent("Preferences/\(bundleID).plist"),
            library.appendingPathComponent("Caches/\(bundleID)"),
            library.appendingPathComponent("Containers/\(bundleID)"),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            library.appendingPathComponent("HTTPStorages/\(bundleID)"),
        ]
    }

    // MARK: - Destinations

    /// /Applications when we can write there, otherwise the user's own
    /// ~/Applications — no privilege escalation, no admin prompt.
    static func defaultDestination() -> URL {
        let system = URL(fileURLWithPath: "/Applications")

        if FileManager.default.isWritableFile(atPath: system.path) { return system }

        return userApplications()
    }

    /// Where an update should land. An app already on this Mac gets replaced
    /// where it actually lives — installing an update into /Applications while
    /// the old copy sits on the Desktop would leave two of them, and the older
    /// one is what LaunchServices would keep opening.
    static func destination(updating installed: InstalledApp?, fallback: URL) -> URL {
        guard let installed else { return fallback }

        let current = installed.url.deletingLastPathComponent()

        guard FileManager.default.isWritableFile(atPath: current.path) else { return fallback }

        return current
    }

    static func userApplications() -> URL {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        return url
    }

    // MARK: - Steps

    private static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Purser-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        return url
    }

    private static func download(
        _ url: URL,
        into directory: URL,
        progress: @escaping @Sendable (InstallStage) -> Void
    ) async throws -> URL {
        let reporter = ProgressReporter { progress(.downloading($0)) }
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: reporter)

        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw ClientError.http(http.statusCode, nil)
        }

        // Keep the server's filename so we can tell a .zip from a .dmg.
        let name = response.suggestedFilename ?? url.lastPathComponent
        let destination = directory.appendingPathComponent(name.isEmpty ? "download.zip" : name)

        try FileManager.default.moveItem(at: temporary, to: destination)

        return destination
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()

        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func unpack(_ archive: URL, into directory: URL) throws -> URL {
        let target = directory.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        switch archive.pathExtension.lowercased() {
        case "dmg":
            return try attachDiskImage(archive, copyingInto: target)
        default:
            // ditto -x -k is what unpacks a .app without losing symlinks or
            // extended attributes; Archive Utility uses the same code path.
            let result = Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, target.path])

            guard result.succeeded else { throw InstallError.unpackFailed(result.output) }

            return target
        }
    }

    private static func attachDiskImage(_ image: URL, copyingInto target: URL) throws -> URL {
        let mount = target.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        let attach = Shell.run("/usr/bin/hdiutil", [
            "attach", image.path, "-nobrowse", "-readonly", "-noverify",
            "-mountpoint", mount.path,
        ])

        guard attach.succeeded else { throw InstallError.unpackFailed(attach.output) }

        defer { Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }

        guard let bundle = findAppBundle(in: mount) else { throw InstallError.noAppBundle }

        let copy = target.appendingPathComponent(bundle.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: bundle, to: copy)

        return target
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        if let app = contents.first(where: { $0.pathExtension == "app" }) { return app }

        // Some archives wrap the app in a folder; look one level down.
        for child in contents where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if let nested = (try? FileManager.default.contentsOfDirectory(
                at: child,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.first(where: { $0.pathExtension == "app" }) {
                return nested
            }
        }

        return nil
    }

    /// These apps are ad-hoc or self-signed rather than Developer ID signed, so
    /// this asks whether the signature is intact — not whether Apple vouches
    /// for it.
    static func signatureState(of bundle: URL) -> SignatureState {
        let verify = Shell.run("/usr/bin/codesign", ["--verify", "--strict", bundle.path])

        if verify.succeeded { return .valid }

        // Nothing was signed at all.
        if verify.output.contains("not signed at all") { return .unsigned }

        // Or the executable carries a signature but the bundle has no sealed
        // resources — what you get when a build's `codesign` step failed and
        // the error was swallowed. There was never a seal here to break.
        let display = Shell.run("/usr/bin/codesign", ["-dv", bundle.path])

        if display.output.contains("Sealed Resources=none") { return .unsigned }

        return .broken(verify.output)
    }

    private static func place(
        _ bundle: URL,
        named name: String,
        into directory: URL,
        bundleID: String?
    ) throws -> InstalledApp {
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw InstallError.destinationNotWritable(directory)
        }

        let destination = directory.appendingPathComponent(bundle.lastPathComponent)

        if let bundleID { quitIfRunning(bundleID: bundleID) }

        // Quarantine comes from the download; strip it so the app opens
        // without a Gatekeeper prompt for something we just verified.
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", bundle.path])

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: bundle)
            } else {
                try FileManager.default.moveItem(at: bundle, to: destination)
            }
        } catch {
            throw InstallError.moveFailed(error.localizedDescription)
        }

        // Let LaunchServices notice it straight away, so the Installed list and
        // Spotlight agree with each other.
        Shell.run(lsregister, ["-f", destination.path])

        guard let installed = InstalledApps.read(at: destination) else {
            throw InstallError.noAppBundle
        }

        return installed
    }

    private static func quitIfRunning(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)

        guard !running.isEmpty else { return }

        for application in running { application.terminate() }

        // Give them a beat to go quietly before we replace the bundle.
        let deadline = Date().addingTimeInterval(3)

        while Date() < deadline,
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        {
            Thread.sleep(forTimeInterval: 0.1)
        }

        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            application.forceTerminate()
        }
    }
}

/// Bridges URLSession's download progress callbacks to a plain closure.
private final class ProgressReporter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }

        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo _: URL) {
        // The async download(from:delegate:) form takes care of the file.
    }
}
