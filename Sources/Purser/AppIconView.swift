import SwiftUI

/// The app's real icon once it's installed; before that, the same deterministic
/// gradient the Chandlery website draws, so the two agree.
struct AppIconView: View {
    @Environment(Library.self) private var library

    var app: CatalogApp
    var size: CGFloat

    var body: some View {
        Group {
            if let installed = library.installedVersion(of: app) {
                Image(nsImage: InstalledApps.icon(for: installed))
                    .resizable()
                    .interpolation(.high)
            } else {
                gradientIcon
            }
        }
        .frame(width: size, height: size)
    }

    private var gradientIcon: some View {
        let hues = app.iconHues.count >= 2 ? app.iconHues : [210, 260]

        return RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hue: Double(hues[0]) / 360, saturation: 0.62, brightness: 0.78),
                        Color(hue: Double(hues[1]) / 360, saturation: 0.70, brightness: 0.55),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
    }

    private var initials: String {
        app.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }
}
