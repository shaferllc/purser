import SwiftUI

/// The one control that changes with an app's state: Install, Update, Open, or
/// a progress bar while work is in flight.
struct InstallButton: View {
    @Environment(Library.self) private var library

    var app: CatalogApp
    var large = false

    var body: some View {
        if let stage = library.stage(for: app) {
            HStack(spacing: 6) {
                if let fraction = stage.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 70)
                } else {
                    ProgressView().controlSize(.small)
                }

                Text(stage.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if library.hasUpdate(app) {
            Button("Update") { library.install(app) }
                .primaryActionStyle()
                .controlSize(large ? .large : .small)
        } else if library.installedVersion(of: app) != nil {
            Button("Open") { library.launch(app) }
                .secondaryActionStyle()
                .controlSize(large ? .large : .small)
        } else if app.isInstallable {
            Button("Install") { library.install(app) }
                .primaryActionStyle()
                .controlSize(large ? .large : .small)
        } else {
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct AppContextMenu: View {
    @Environment(Library.self) private var library

    var app: CatalogApp

    var body: some View {
        if library.installedVersion(of: app) != nil {
            Button("Open") { library.launch(app) }
            Button("Show in Finder") { library.revealInFinder(app) }
            Divider()
            Button("Remove…", role: .destructive) { library.uninstall(app) }
        } else if app.isInstallable {
            Button("Install") { library.install(app) }
        }

        if let website = app.website, let url = URL(string: website) {
            Divider()
            Button("Visit Website") { NSWorkspace.shared.open(url) }
        }
    }
}
