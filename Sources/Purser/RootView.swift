import SwiftUI

enum SidebarSection: Hashable {
    case discover
    case installed
    case updates
    case category(String)
}

struct RootView: View {
    @Environment(Library.self) private var library

    @State private var section: SidebarSection = .discover
    @State private var selection: CatalogApp?
    @State private var search = ""

    var body: some View {
        @Bindable var library = library

        NavigationSplitView {
            sidebar
        } detail: {
            content
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search apps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await library.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(library.isSyncing)
                .help("Sync the catalog")
            }
        }
        .sheet(item: $selection) { app in
            AppDetailView(app: app)
                .environment(library)
        }
        .alert(item: $library.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                Label("Discover", systemImage: "square.grid.2x2")
                    .tag(SidebarSection.discover)

                Label("Installed", systemImage: "internaldrive")
                    .badge(library.installedApps.count)
                    .tag(SidebarSection.installed)

                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    .badge(library.updatableApps.count)
                    .tag(SidebarSection.updates)
            }

            Section("Categories") {
                ForEach(library.catalog.categories) { category in
                    Label(category.name, systemImage: symbol(for: category))
                        .tag(SidebarSection.category(category.slug))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom) { accountFooter }
    }

    private var accountFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            if let account = library.account {
                HStack(spacing: 8) {
                    Image(systemName: account.membershipActive ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(account.membershipActive ? .green : .orange)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name).font(.callout.weight(.medium))
                        Text(account.membershipActive ? "Membership active" : "Membership lapsed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Not signed in")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = library.syncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch section {
        case .discover:
            AppGridView(
                title: "Discover",
                subtitle: "\(library.apps.count) apps, one membership.",
                apps: filtered(library.apps),
                selection: $selection
            )

        case .installed:
            AppGridView(
                title: "Installed",
                subtitle: library.installedApps.isEmpty
                    ? "Nothing from the catalog is installed yet."
                    : "\(library.installedApps.count) installed on this Mac.",
                apps: filtered(library.installedApps),
                selection: $selection
            )

        case .updates:
            UpdatesView(apps: filtered(library.updatableApps), selection: $selection)

        case let .category(slug):
            let category = library.catalog.categories.first { $0.slug == slug }

            AppGridView(
                title: category?.name ?? "Category",
                subtitle: category?.tagline,
                apps: filtered(library.apps(inCategory: slug)),
                selection: $selection
            )
        }
    }

    private func filtered(_ apps: [CatalogApp]) -> [CatalogApp] {
        let query = search.trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty else { return apps }

        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.tagline.localizedCaseInsensitiveContains(query)
        }
    }

    private func symbol(for category: CatalogCategory) -> String {
        switch category.slug {
        case "optimize": "bolt"
        case "work": "briefcase"
        case "create": "paintbrush"
        case "develop": "chevron.left.forwardslash.chevron.right"
        case "solve-with-ai": "sparkles"
        case "play": "face.smiling"
        default: "square.grid.2x2"
        }
    }
}
