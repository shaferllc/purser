import SwiftUI

/// The storefront: one featured app up top, then rails you scroll sideways —
/// what's waiting to update, what's new, and each category.
struct DiscoverView: View {
    @Environment(Library.self) private var library

    var apps: [CatalogApp]
    @Binding var selection: CatalogApp?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discover").font(.largeTitle.bold())
                    Text("\(apps.count) apps, one membership.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let featured {
                    FeaturedBanner(app: featured) { selection = featured }
                }

                let updates = library.updatableApps.filter { apps.contains($0) }
                if !updates.isEmpty {
                    AppRail(title: "Updates waiting", symbol: "arrow.triangle.2.circlepath", apps: updates, selection: $selection)
                }

                AppRail(title: "New arrivals", symbol: "sparkle", apps: newest, selection: $selection)

                ForEach(library.catalog.categories) { category in
                    let inCategory = apps.filter { $0.categories.contains(category.slug) }
                    if !inCategory.isEmpty {
                        AppRail(title: category.name, subtitle: category.tagline, apps: inCategory, selection: $selection)
                    }
                }

                if apps.isEmpty {
                    EmptyStateView(symbol: "sailboat", title: "Nothing here", message: "No apps match what you're looking for.")
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(28)
        }
        .navigationTitle("Discover")
    }

    /// Something worth a click: the newest installable app you don't have yet,
    /// falling back to the newest of all.
    private var featured: CatalogApp? {
        newest.first { $0.isInstallable && library.installedVersion(of: $0) == nil } ?? newest.first
    }

    private var newest: [CatalogApp] {
        Array(apps.sorted { ($0.releasedAt ?? "") > ($1.releasedAt ?? "") }.prefix(12))
    }
}

// MARK: - Featured

private struct FeaturedBanner: View {
    var app: CatalogApp
    var onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        let colors = app.gradientColors

        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.75))

                Text(app.name)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(app.tagline)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    InstallButton(app: app, large: true)
                    Button("Learn More", action: onOpen)
                        .secondaryActionStyle()
                        .controlSize(.large)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)

            AppIconView(app: app, size: 132)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                .rotationEffect(.degrees(hovering ? -4 : 0))
                .scaleEffect(hovering ? 1.05 : 1)
        }
        .padding(34)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                // A soft light source so the flat gradient reads as depth.
                RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 10, endRadius: 520)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: colors[1].opacity(0.35), radius: 22, y: 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { over in withAnimation(.spring(duration: 0.4)) { hovering = over } }
    }
}

// MARK: - Rails

private struct AppRail: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var apps: [CatalogApp]
    @Binding var selection: CatalogApp?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(.tint)
                }
                Text(title).font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(apps) { app in
                        AppTile(app: app) { selection = app }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
    }
}

private struct AppTile: View {
    var app: CatalogApp
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                AppIconView(app: app, size: 64)
                    .shadow(color: app.gradientColors[1].opacity(0.3), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline).lineLimit(1)
                    Text(app.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            HStack {
                InstallButton(app: app)
                Spacer(minLength: 0)
                AppActionsMenu(app: app)
            }
        }
        .padding(14)
        .frame(width: 196, alignment: .leading)
        .cardSurface(cornerRadius: 18)
        .contextMenu { AppContextMenu(app: app) }
    }
}

// MARK: - Shared look

extension CatalogApp {
    /// The same deterministic two-hue gradient the Chandlery website draws.
    var gradientColors: [Color] {
        let hues = iconHues.count >= 2 ? iconHues : [210, 260]
        return [
            Color(hue: Double(hues[0]) / 360, saturation: 0.62, brightness: 0.78),
            Color(hue: Double(hues[1]) / 360, saturation: 0.70, brightness: 0.55),
        ]
    }
}

/// A content card that lifts toward the pointer. Content stays on a plain
/// surface; Liquid Glass is kept for the controls on top, as Apple intends.
private struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(.background.secondary, in: shape)
            .overlay(shape.strokeBorder(.separator.opacity(hovering ? 1 : 0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(hovering ? 0.14 : 0.04), radius: hovering ? 16 : 4, y: hovering ? 8 : 2)
            .scaleEffect(hovering ? 1.015 : 1)
            .onHover { over in withAnimation(.spring(duration: 0.3)) { hovering = over } }
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }

    /// Liquid Glass on macOS 26, the classic prominent button before it.
    @ViewBuilder
    func primaryActionStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
