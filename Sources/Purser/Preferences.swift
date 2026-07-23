import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    enum InstallLocation: String, CaseIterable, Identifiable {
        case system, user

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "/Applications"
            case .user: "~/Applications"
            }
        }

        var url: URL {
            switch self {
            case .system: URL(fileURLWithPath: "/Applications")
            case .user: Installer.userApplications()
            }
        }
    }

    var serverURLString: String {
        didSet { defaults.set(serverURLString, forKey: Key.serverURL) }
    }

    var checkForUpdatesAutomatically: Bool {
        didSet { defaults.set(checkForUpdatesAutomatically, forKey: Key.autoCheck) }
    }

    var installLocation: InstallLocation {
        didSet { defaults.set(installLocation.rawValue, forKey: Key.installLocation) }
    }

    var removeDataOnUninstall: Bool {
        didSet { defaults.set(removeDataOnUninstall, forKey: Key.removeData) }
    }

    var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    var serverURL: URL {
        URL(string: serverURLString.trimmingCharacters(in: .whitespaces))
            ?? URL(string: Default.serverURL)!
    }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let serverURL = "serverURL"
        static let autoCheck = "checkForUpdatesAutomatically"
        static let installLocation = "installLocation"
        static let removeData = "removeDataOnUninstall"
    }

    private enum Default {
        static let serverURL = "https://chandlery.shafer.llc"
    }

    private init() {
        serverURLString = defaults.string(forKey: Key.serverURL) ?? Default.serverURL
        checkForUpdatesAutomatically = defaults.object(forKey: Key.autoCheck) as? Bool ?? true
        removeDataOnUninstall = defaults.bool(forKey: Key.removeData)
        installLocation = InstallLocation(rawValue: defaults.string(forKey: Key.installLocation) ?? "")
            ?? (FileManager.default.isWritableFile(atPath: "/Applications") ? .system : .user)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The register call fails while running an unsigned debug build
            // from .build; reflect the real state rather than lying to the UI.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
