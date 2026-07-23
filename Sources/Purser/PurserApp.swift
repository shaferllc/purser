import SwiftUI

@main
struct PurserApp: App {
    @State private var library = Library()
    @State private var preferences = Preferences.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(library)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    await library.refresh()
                    await scheduleUpdateChecks()
                }
        }
        .defaultSize(width: 1080, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Catalog") {
                    Task { await library.refresh() }
                }
                .keyboardShortcut("r")

                Button("Update All Apps") {
                    library.updateAll()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(library.updatableApps.isEmpty)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(library)
        } label: {
            // A filled bag when something wants updating, hollow when all is well.
            Image(systemName: library.updatableApps.isEmpty ? "bag" : "bag.badge.plus")
        }

        Settings {
            SettingsView()
                .environment(library)
        }
    }

    /// A quiet hourly poll — enough to notice a release the same day without
    /// hammering the server.
    private func scheduleUpdateChecks() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))

            guard preferences.checkForUpdatesAutomatically else { continue }

            await library.refresh()
        }
    }
}
