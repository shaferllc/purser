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
            licenses = (try? await client.licenses()) ?? licenses
        }

        rescanInstalled()
        handOffLicenses()
    }

    // MARK: - Licences

    /// Keys Chandlery issued this account — what lets a membership unlock apps.
    var licenses: [IssuedLicense] = []
    private(set) var unlockedProducts: Set<String> = []

    func isUnlocked(_ app: CatalogApp) -> Bool { unlockedProducts.contains(app.slug) }

    /// product (the app's slug) → bundle identifier, for the apps on this Mac.
    private var installedBundleIDs: [String: String] {
        Dictionary(uniqueKeysWithValues: installedApps.compactMap { app in app.bundleID.map { (app.slug, $0) } })
    }

    private func handOffLicenses() {
        unlockedProducts = LicenceHandoff.apply(licenses, bundleIDs: installedBundleIDs)
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
        LicenceHandoff.revoke(bundleIDs: installedBundleIDs)
        licenses = []
        unlockedProducts = []
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
        var target = app
        var attempt = 0

        while true {
            attempt += 1

            let destination = Installer.destination(
                updating: installedVersion(of: target),
                fallback: preferences.installLocation.url
            )

            do {
                let url = try await client.resolveDownload(for: target)

                let outcome = try await Installer.install(
                    target,
                    from: url,
                    into: destination,
                    progress: { [weak self] stage in
                        Task { @MainActor in self?.stages[slug] = stage }
                    }
                )

                installed[outcome.app.bundleID] = outcome.app
                handOffLicenses()

                if let warning = outcome.warning {
                    alert = AlertMessage(title: "Installed \(app.name)", message: warning)
                }
            } catch {
                // Usually this just means a new release landed since the last
                // sync, so the checksum we hold describes an artifact that has
                // been replaced. Re-sync once and try the new one before
                // putting an error in front of anyone.
                if attempt == 1, isStaleCatalog(error) {
                    await refresh()

                    if let fresh = catalog.apps.first(where: { $0.slug == slug }),
                       fresh.latestRelease != target.latestRelease
                    {
                        target = fresh
                        continue
                    }
                }

                alert = AlertMessage(
                    title: "Couldn't install \(app.name)",
                    message: error.localizedDescription
                )
            }

            break
        }

        stages[slug] = nil
        rescanInstalled()
    }

    /// Failures that a fresh catalog would plausibly fix: the artifact didn't
    /// match the checksum we were given, or the release we asked for is gone.
    private func isStaleCatalog(_ error: Error) -> Bool {
        if case .checksumMismatch = error as? InstallError { return true }
        if case let .http(status, _) = error as? ClientError, status == 404 { return true }

        return false
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
