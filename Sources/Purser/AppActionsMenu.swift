import SwiftUI

/// The overflow menu that appears on every installed app — Open, Show in
/// Finder, Remove. Uninstalling shouldn't be something you have to know a
/// right-click gesture to find.
struct AppActionsMenu: View {
    @Environment(Library.self) private var library

    var app: CatalogApp

    @State private var confirmingRemoval = false

    var body: some View {
        if library.installedVersion(of: app) != nil {
            Menu {
                Button("Open") { library.launch(app) }
                Button("Show in Finder") { library.revealInFinder(app) }

                Divider()

                Button("Remove…", role: .destructive) { confirmingRemoval = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
            .confirmationDialog(
                "Remove \(app.name)?",
                isPresented: $confirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) { library.uninstall(app) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(removalMessage)
            }
        }
    }

    private var removalMessage: String {
        Preferences.shared.removeDataOnUninstall
            ? "\(app.name) and its settings will be moved to the Trash."
            : "\(app.name) will be moved to the Trash. Its settings will be left alone."
    }
}
