import Foundation

/// A licence Chandlery issued this account: a perpetual purchase, or a
/// membership key that expires and is reissued for as long as the membership
/// lasts.
struct IssuedLicense: Codable, Sendable, Equatable {
    var product: String
    var key: String
    var source: String
    var expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case product, key, source
        case expiresAt = "expires_at"
    }

    var expiry: Date? { expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) } }
}

/// Puts an account's licence keys where each app looks for one — its own
/// `<product>.licenseKey` preference, which ShaferLicensing reads at launch.
/// That's what makes a membership unlock an app without anyone pasting a key.
///
/// It only ever replaces a key it wrote itself. A key someone bought and pasted
/// by hand outlives any membership, so overwriting it with a 30-day one would
/// lock them out the day they cancel.
enum LicenceHandoff {
    /// Reads and writes another app's preferences. Swapped for a dictionary in tests.
    struct Store {
        var read: (_ key: String, _ bundleID: String) -> String?
        var write: (_ key: String, _ value: String?, _ bundleID: String) -> Void

        static var system: Store {
            Store(
            read: { key, bundleID in
                CFPreferencesCopyAppValue(key as CFString, bundleID as CFString) as? String
            },
            write: { key, value, bundleID in
                CFPreferencesSetAppValue(key as CFString, value as CFString?, bundleID as CFString)
                CFPreferencesAppSynchronize(bundleID as CFString)
            }
            )
        }
    }

    /// product → the key Purser last wrote for it.
    static let ledgerKey = "handedOffLicenses"

    static func preferenceKey(for product: String) -> String { "\(product).licenseKey" }

    /// The strongest key per product: perpetual beats expiring, later beats earlier.
    static func best(_ licenses: [IssuedLicense]) -> [String: IssuedLicense] {
        licenses.reduce(into: [:]) { best, licence in
            guard let current = best[licence.product] else { return best[licence.product] = licence }

            switch (current.expiry, licence.expiry) {
            case (nil, _): break
            case (_, nil): best[licence.product] = licence
            case let (held?, offered?) where offered > held: best[licence.product] = licence
            default: break
            }
        }
    }

    /// Hands each installed app its best key. `bundleIDs` maps product → bundle
    /// identifier for the apps on this Mac. Returns the products it unlocked.
    @discardableResult
    static func apply(
        _ licenses: [IssuedLicense],
        bundleIDs: [String: String],
        store: Store = .system,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        var ledger = defaults.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]
        var unlocked: Set<String> = []

        for (product, licence) in best(licenses) {
            guard let bundleID = bundleIDs[product] else { continue }

            let key = preferenceKey(for: product)
            let current = store.read(key, bundleID) ?? ""

            // Someone else's key — a purchase pasted by hand — always wins.
            guard current.isEmpty || current == ledger[product] || current == licence.key else { continue }

            if current != licence.key { store.write(key, licence.key, bundleID) }

            ledger[product] = licence.key
            unlocked.insert(product)
        }

        defaults.set(ledger, forKey: ledgerKey)

        return unlocked
    }

    /// On sign-out: take back every key Purser handed out that's still in place.
    static func revoke(bundleIDs: [String: String], store: Store = .system, defaults: UserDefaults = .standard) {
        let ledger = defaults.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]

        for (product, written) in ledger {
            guard let bundleID = bundleIDs[product] else { continue }

            let key = preferenceKey(for: product)

            if store.read(key, bundleID) == written { store.write(key, nil, bundleID) }
        }

        defaults.removeObject(forKey: ledgerKey)
    }
}
