import Foundation

// The shape Chandlery serves from GET /api/v1/catalog. Everything here is a
// value type so it can cross actor boundaries and be cached to disk as-is.

struct Catalog: Codable, Sendable {
    var generatedAt: String
    var categories: [CatalogCategory]
    var apps: [CatalogApp]

    static let empty = Catalog(generatedAt: "", categories: [], apps: [])

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case categories, apps
    }
}

struct CatalogCategory: Codable, Sendable, Identifiable, Hashable {
    var slug: String
    var name: String
    var tagline: String?
    var icon: String?

    var id: String { slug }
}

struct CatalogApp: Codable, Sendable, Identifiable, Hashable {
    var slug: String
    var name: String
    var bundleID: String?
    var tagline: String
    var description: String
    var developer: String
    var website: String?
    var repository: String?
    var categories: [String]
    var platforms: [String]
    var isAI: Bool
    var requiresMembership: Bool
    var rating: Int
    var installCount: Int
    var releasedAt: String?
    var iconHues: [Int]
    var latestRelease: ReleaseInfo?

    var id: String { slug }

    /// An app is only installable once we know which bundle to look for and
    /// where to get it.
    var isInstallable: Bool { bundleID != nil && latestRelease != nil }

    enum CodingKeys: String, CodingKey {
        case slug, name, tagline, description, developer, website, repository
        case categories, platforms, rating
        case bundleID = "bundle_id"
        case isAI = "is_ai"
        case requiresMembership = "requires_membership"
        case installCount = "install_count"
        case releasedAt = "released_at"
        case iconHues = "icon_hues"
        case latestRelease = "latest_release"
    }
}

struct ReleaseInfo: Codable, Sendable, Hashable {
    var version: String
    var build: String?
    var minimumOS: String
    var sizeBytes: Int?
    var sha256: String?
    var notes: String?
    var publishedAt: String?
    var downloadURL: String

    enum CodingKeys: String, CodingKey {
        case version, build, notes, sha256
        case minimumOS = "minimum_os"
        case sizeBytes = "size_bytes"
        case publishedAt = "published_at"
        case downloadURL = "download_url"
    }
}

struct Account: Codable, Sendable, Equatable {
    var name: String
    var email: String
    var membershipPlan: String?
    var membershipExpiresAt: String?
    var membershipActive: Bool

    enum CodingKeys: String, CodingKey {
        case name, email
        case membershipPlan = "membership_plan"
        case membershipExpiresAt = "membership_expires_at"
        case membershipActive = "membership_active"
    }
}

// MARK: - Versions

enum Version {
    /// Compare two macOS-style version strings component by component, so
    /// "0.5" < "0.5.1" < "0.10". Non-numeric junk sorts as zero, which keeps a
    /// malformed version from ever looking newer than a real one.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)

        for index in 0 ..< max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0

            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }

        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix(while: \.isNumber)) ?? 0
        }
    }
}

// MARK: - Formatting

extension ReleaseInfo {
    var formattedSize: String? {
        guard let sizeBytes else { return nil }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        return formatter.string(fromByteCount: Int64(sizeBytes))
    }
}
