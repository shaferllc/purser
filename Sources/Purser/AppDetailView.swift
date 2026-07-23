import SwiftUI

struct AppDetailView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var app: CatalogApp

    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(app.description)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if let release = app.latestRelease, let notes = release.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What's new in \(release.version)").font(.headline)
                            Text(notes)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    details
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 520)
        .confirmationDialog(
            "Remove \(app.name)?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                library.uninstall(app)
                dismiss()
            }
        } message: {
            Text(Preferences.shared.removeDataOnUninstall
                ? "The app and its settings will be moved to the Trash."
                : "The app will be moved to the Trash. Its settings will be left alone.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AppIconView(app: app, size: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title2.bold())
                Text(app.tagline).font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    InstallButton(app: app)

                    if library.installedVersion(of: app) != nil {
                        Button("Remove") { confirmingRemoval = true }
                            .controlSize(.small)
                    }
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            row("Developer", app.developer)

            if let installed = library.installedVersion(of: app) {
                row("Installed", installed.version)
                row("Location", installed.url.path)
            }

            if let release = app.latestRelease {
                row("Latest", release.version + (release.build.map { " (\($0))" } ?? ""))
                row("Size", release.formattedSize ?? "—")
                row("Requires", "macOS \(release.minimumOS) or later")
                row("Verified", release.sha256 == nil ? "No checksum published" : "sha256 checked on install")
            } else {
                row("Latest", "Not released yet")
            }

            if let website = app.website, let url = URL(string: website) {
                GridRow {
                    Text("Website").foregroundStyle(.secondary)
                    Link(website, destination: url)
                }
            }
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
