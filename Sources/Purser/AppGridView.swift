import SwiftUI

struct AppGridView: View {
    var title: String
    var subtitle: String?
    var apps: [CatalogApp]
    @Binding var selection: CatalogApp?

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.largeTitle.bold())

                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                }

                if apps.isEmpty {
                    EmptyStateView(
                        symbol: "sailboat",
                        title: "Nothing here",
                        message: "No apps match what you're looking for."
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(apps) { app in
                            AppCardView(app: app) { selection = app }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(title)
    }
}

struct AppCardView: View {
    @Environment(Library.self) private var library

    var app: CatalogApp
    var onOpen: () -> Void

    var body: some View {
        // Only the card's body opens the detail sheet. The footer holds real
        // controls, so it must keep its own clicks — wrapping the whole card in
        // a Button would swallow them.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AppIconView(app: app, size: 56)
                    .shadow(color: app.gradientColors[1].opacity(0.3), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name).font(.headline)

                        if library.hasUpdate(app) {
                            Text("Update")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    Text(app.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            HStack {
                if let installed = library.installedVersion(of: app) {
                    Label(installed.version, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let release = app.latestRelease {
                    Text(release.formattedSize ?? release.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not released yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                InstallButton(app: app)
                AppActionsMenu(app: app)
            }
        }
        .padding(16)
        .cardSurface(cornerRadius: 18)
        .contextMenu { AppContextMenu(app: app) }
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)

            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}
