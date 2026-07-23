import SwiftUI

/// The day-to-day surface: launch what's installed, see what needs updating,
/// without opening the main window.
struct MenuBarView: View {
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !library.updatableApps.isEmpty {
            Text("\(library.updatableApps.count) update(s) available")

            Button("Update All") { library.updateAll() }

            Divider()
        }

        if library.installedApps.isEmpty {
            Text("No apps installed")
        } else {
            ForEach(library.installedApps) { app in
                Button {
                    library.launch(app)
                } label: {
                    Text(library.hasUpdate(app) ? "\(app.name) ●" : app.name)
                }
            }
        }

        Divider()

        Button("Open Purser") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .keyboardShortcut("o")

        Button("Check for Updates") {
            Task { await library.refresh() }
        }
        .disabled(library.isSyncing)

        Divider()

        Button("Quit Purser") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
