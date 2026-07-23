import AppKit
import Foundation
import Observation

/// Everything the UI reads: the catalog, what's installed, what's downloading,
/// and who's signed in.
@MainActor
@Observable
final class Library {
    var catalog: Catalog = .empty
    var installed: [String: InstalledApp] = [:]
    var account: Account?
    var stages: [String: InstallStage] = [:]
    var lastSyncedAt: Date?
    var isSyncing = false
    var syncError: String?
    var alert: AlertMessage?

    struct AlertMessage: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    private let preferences = Preferences.shared
    private var token: String? { Keychain.get("deviceToken") }

    private var client: CatalogClient {
        CatalogClient(baseURL: preferences.serverURL, token: token)
    }

    init() {
        catalog = CatalogCache.load() ?? .empty
        rescanInstalled()
    }

    // MARK: - Derived state

    var isSignedIn: Bool { token != nil }

    var hasMembership: Bool { account?.membershipActive ?? false }

    var apps: [CatalogApp] { catalog.apps }

    var installedApps: [CatalogApp] {
        catalog.apps.filter { app in
            guard let bundleID = app.bundleID else { return false }

            return installed[bundleID] != nil
        }
    }

    /// Catalog apps whose latest release is newer than what's on disk.
    var updatableApps: [CatalogApp] {
        catalog.apps.filter { app in
            guard let bundleID = app.bundleID,
                  let current = installed[bundleID],
                  let release = app.latestRelease
            else { return false }

            return Version.isNewer(release.version, than: current.version)
        }
    }

    func installedVersion(of app: CatalogApp) -> InstalledApp? {
        guard let bundleID = app.bundleID else { return nil }

        return installed[bundleID]
    }

    func hasUpdate(_ app: CatalogApp) -> Bool {
        guard let current = installedVersion(of: app), let release = app.latestRelease else { return false }

        return Version.isNewer(release.version, than: current.version)
    }

    func stage(for app: CatalogApp) -> InstallStage? { stages[app.slug] }

    func apps(inCategory slug: String) -> [CatalogApp] {
        catalog.apps.filter { $0.categories.contains(slug) }
    }

    // MARK: - Syncing

    func refresh() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let fetched = try await client.catalog()
            catalog = fetched
            lastSyncedAt = Date()
            syncError = nil
            CatalogCache.save(fetched)
        } catch {
            syncError = error.localizedDescription
        }

        if isSignedIn {
            account = try? await client.account()
        }

        rescanInstalled()
    }

    func rescanInstalled() {
        installed = InstalledApps.scan(bundleIDs: catalog.apps.compactMap(\.bundleID))
    }

    // MARK: - Account

    func signIn(email: String, password: String) async -> String? {
        do {
            let deviceName = Host.current().localizedName ?? "Mac"
            let result = try await CatalogClient(baseURL: preferences.serverURL, token: nil)
                .signIn(email: email, password: password, deviceName: deviceName)

            Keychain.set(result.token, for: "deviceToken")
            account = result.account

            await refresh()

            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func signOut() async {
        try? await client.signOut()
        Keychain.remove("deviceToken")
        account = nil
    }

    // MARK: - Installing

    func install(_ app: CatalogApp) {
        guard stages[app.slug] == nil else { return }

        stages[app.slug] = .waiting

        Task {
            await performInstall(app)
        }
    }

    func updateAll() {
        for app in updatableApps { install(app) }
    }

    private func performInstall(_ app: CatalogApp) async {
        let slug = app.slug
        let destination = preferences.installLocation.url
        let client = client

        do {
            let url = try await client.resolveDownload(for: app)

            let installedApp = try await Installer.install(
                app,
                from: url,
                into: destination,
                progress: { [weak self] stage in
                    Task { @MainActor in self?.stages[slug] = stage }
                }
            )

            installed[installedApp.bundleID] = installedApp
        } catch {
            alert = AlertMessage(
                title: "Couldn't install \(app.name)",
                message: error.localizedDescription
            )
        }

        stages[slug] = nil
        rescanInstalled()
    }

    // MARK: - Removing

    func uninstall(_ app: CatalogApp) {
        guard let installedApp = installedVersion(of: app) else { return }

        do {
            try Installer.uninstall(installedApp, alsoRemoveData: preferences.removeDataOnUninstall)
            installed[installedApp.bundleID] = nil
        } catch {
            alert = AlertMessage(
                title: "Couldn't remove \(app.name)",
                message: error.localizedDescription
            )
        }

        rescanInstalled()
    }

    func launch(_ app: CatalogApp) {
        guard let installedApp = installedVersion(of: app) else { return }

        InstalledApps.launch(installedApp)
    }

    func revealInFinder(_ app: CatalogApp) {
        guard let installedApp = installedVersion(of: app) else { return }

        InstalledApps.revealInFinder(installedApp)
    }
}

/// Keeps the last good catalog on disk so Purser opens with content even when
/// the server is unreachable.
enum CatalogCache {
    private static var url: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Purser")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("catalog.json")
    }

    static func load() -> Catalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        return try? JSONDecoder().decode(Catalog.self, from: data)
    }

    static func save(_ catalog: Catalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }

        try? data.write(to: url, options: .atomic)
    }
}
