import SwiftUI

struct UpdatesView: View {
    @Environment(Library.self) private var library

    var apps: [CatalogApp]
    @Binding var selection: CatalogApp?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Updates").font(.largeTitle.bold())
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !apps.isEmpty {
                        Button("Update All") { library.updateAll() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if apps.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.seal",
                        title: "Everything is current",
                        message: library.lastSyncedAt == nil
                            ? "Sync the catalog to check for new versions."
                            : "Checked \(library.lastSyncedAt!.formatted(date: .omitted, time: .shortened))."
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    VStack(spacing: 10) {
                        ForEach(apps) { app in
                            UpdateRow(app: app) { selection = app }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Updates")
    }

    private var subtitle: String {
        apps.isEmpty ? "No updates waiting." : "\(apps.count) app(s) have a newer version."
    }
}

private struct UpdateRow: View {
    @Environment(Library.self) private var library

    var app: CatalogApp
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Tapping the row opens the detail sheet; the controls on the right
            // keep their own clicks.
            HStack(spacing: 14) {
                AppIconView(app: app, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)

                    if let installed = library.installedVersion(of: app), let release = app.latestRelease {
                        Text("\(installed.version) → \(release.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if let notes = app.latestRelease?.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            InstallButton(app: app)
            AppActionsMenu(app: app)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
        .contextMenu { AppContextMenu(app: app) }
    }
}
