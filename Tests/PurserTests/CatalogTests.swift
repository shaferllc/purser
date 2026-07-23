@testable import Purser
import XCTest

final class CatalogTests: XCTestCase {
    /// Exactly what GET /api/v1/catalog serves, so a change in either half
    /// breaks a test rather than a user's install.
    private let json = """
    {
      "generated_at": "2026-07-23T13:24:30+00:00",
      "categories": [
        {"slug": "optimize", "name": "Optimize", "tagline": "Keep your Mac fast", "icon": "bolt"}
      ],
      "apps": [
        {
          "slug": "quay",
          "name": "Quay",
          "bundle_id": "com.tomshafer.quay",
          "tagline": "Save named Dock layouts.",
          "description": "Longer copy.",
          "developer": "Tom Shafer",
          "website": "https://quay.shafer.llc",
          "repository": "shaferllc/quay",
          "categories": ["optimize"],
          "platforms": ["mac"],
          "is_ai": false,
          "requires_membership": true,
          "rating": 95,
          "install_count": 12,
          "released_at": "2026-06-23",
          "icon_hues": [210, 260],
          "latest_release": {
            "version": "0.5.1",
            "build": "51",
            "minimum_os": "14.0",
            "size_bytes": 4823110,
            "sha256": "aaaa",
            "notes": "Preset editor.",
            "published_at": "2026-07-23T13:24:30+00:00",
            "download_url": "https://chandlery.test/api/v1/apps/quay/download"
          }
        },
        {
          "slug": "glade",
          "name": "Glade",
          "bundle_id": null,
          "tagline": "A small game.",
          "description": "Longer copy.",
          "developer": "Tom Shafer",
          "website": null,
          "repository": null,
          "categories": [],
          "platforms": ["mac"],
          "is_ai": false,
          "requires_membership": true,
          "rating": 95,
          "install_count": 0,
          "released_at": "2026-06-23",
          "icon_hues": [12, 88],
          "latest_release": null
        }
      ]
    }
    """

    private func decode() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
    }

    func testDecodesTheServerPayload() throws {
        let catalog = try decode()

        XCTAssertEqual(catalog.categories.first?.slug, "optimize")
        XCTAssertEqual(catalog.apps.count, 2)

        let quay = catalog.apps[0]
        XCTAssertEqual(quay.bundleID, "com.tomshafer.quay")
        XCTAssertEqual(quay.latestRelease?.version, "0.5.1")
        XCTAssertEqual(quay.latestRelease?.downloadURL, "https://chandlery.test/api/v1/apps/quay/download")
        XCTAssertEqual(quay.iconHues, [210, 260])
    }

    func testAnAppWithoutABundleOrReleaseIsNotInstallable() throws {
        let catalog = try decode()

        XCTAssertTrue(catalog.apps[0].isInstallable)
        XCTAssertFalse(catalog.apps[1].isInstallable)
    }

    func testSurvivesARoundTripThroughTheOfflineCache() throws {
        let catalog = try decode()
        let encoded = try JSONEncoder().encode(catalog)
        let restored = try JSONDecoder().decode(Catalog.self, from: encoded)

        XCTAssertEqual(restored.apps, catalog.apps)
    }

    func testFormatsReleaseSize() throws {
        XCTAssertNotNil(try decode().apps[0].latestRelease?.formattedSize)
    }
}
