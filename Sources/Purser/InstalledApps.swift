import AppKit
import Foundation

struct InstalledApp: Sendable, Hashable {
    var bundleID: String
    var url: URL
    var version: String
    var build: String?
    var name: String

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// Finds the catalog's apps on this Mac. LaunchServices is the source of truth
/// — it knows about apps wherever they were dropped, not just /Applications.
enum InstalledApps {
    static func scan(bundleIDs: [String]) -> [String: InstalledApp] {
        var found: [String: InstalledApp] = [:]

        for bundleID in bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }

            // LaunchServices keeps pointing at an app after it's been moved to
            // the Trash; something in the bin is not installed.
            guard !isTrashed(url), let app = read(at: url) else { continue }

            found[bundleID] = app
        }

        return found
    }

    /// True for anything sitting in a Trash folder — the user's, another
    /// volume's, or a per-user one on a shared disk.
    static func isTrashed(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash") || url.pathComponents.contains(".Trashes")
    }

    /// Reads Info.plist straight off disk rather than through `Bundle`, which
    /// caches for the life of the process — after an update that cache would
    /// keep reporting the version we just replaced.
    static func read(at url: URL) -> InstalledApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")

        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String
        else { return nil }

        return InstalledApp(
            bundleID: bundleID,
            url: url,
            version: info["CFBundleShortVersionString"] as? String ?? "0",
            build: info["CFBundleVersion"] as? String,
            name: info["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        )
    }

    /// The icon macOS itself would show for an installed app.
    static func icon(for app: InstalledApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.url.path)
    }

    static func launch(_ app: InstalledApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func revealInFinder(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }
}
