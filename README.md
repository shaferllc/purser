# Purser

*pur·ser — the officer who keeps the ship's stores and accounts.*

A macOS app that keeps your apps: browse a catalog, install with one click,
and get told when something you already have has a newer version waiting.

## What it does

- **A catalog you can browse** — apps in a grid with icons, and a detail view
  for each one before you commit to installing it.
- **One-click install** — Purser fetches and installs the app, then tracks it
  so it knows what you have.
- **Update checks** — a scheduled sweep of everything installed. ⇧⌘U updates
  all of them; ⌘R refreshes the catalog by hand.
- **A menu bar item** — the bag icon fills in when something wants updating and
  stays hollow when everything is current, so the answer is available without
  opening the window.
- **Your library** — what's installed, what's updatable, and what you've
  removed, tracked separately from the catalog itself.

Credentials for the catalog are kept in the system Keychain, not in a
preferences file.

The catalog it reads is [Chandlery](../chandlery), the Setapp-style storefront
in this repo: Chandlery is the shop, Purser is the thing that puts apps on your
Mac. Point it somewhere else in **Settings → General → Server** — the default
is `https://chandlery.shafer.llc`, and `http://localhost:8000` while you're
developing against a local Chandlery.

## Safety

Purser installs software, so it is deliberately suspicious:

- **Checksums.** When a release publishes a sha256, a download that doesn't
  match is discarded rather than installed.
- **Identity.** The unpacked bundle's `CFBundleIdentifier` must equal the one
  the catalog advertised. A zip that claims to be Quay but unpacks something
  else never reaches `/Applications`.
- **Signature.** `codesign --verify --strict` has to pass. These apps are
  ad-hoc or self-signed rather than Developer ID signed, so this proves the
  bundle is intact, not that Apple vouches for it.
- **Credentials stay home.** The download endpoint lives on Chandlery and
  redirects to GitHub. Purser follows that redirect by hand, so the account's
  bearer token is never sent to whoever hosts the artifact.
- **Removal is reversible.** Uninstalling moves things to the Trash; Purser
  never deletes from your disk.
- **No privilege escalation.** If `/Applications` isn't writable it installs to
  `~/Applications` rather than asking for an admin password.

## How it talks to Chandlery

| Endpoint                           | What                                           |
| ---------------------------------- | ---------------------------------------------- |
| `GET /api/v1/catalog`              | Every published app + its latest stable release |
| `GET /api/v1/apps/{slug}`          | One app plus its last ten releases             |
| `GET /api/v1/apps/{slug}/download` | Membership check, then 302 to the artifact     |
| `POST /api/v1/sessions`            | Email + password → device token                |
| `GET /api/v1/account`              | Name, plan, whether the membership is live     |
| `DELETE /api/v1/sessions`          | Sign this device out                           |

The catalog is cached to `~/Library/Application Support/Purser/catalog.json`,
so Purser opens with content even when the server is unreachable.

## Shape of the code

| File                  | What lives there                                     |
| --------------------- | ---------------------------------------------------- |
| `Catalog.swift`       | The wire format, and version comparison              |
| `CatalogClient.swift` | Every request to Chandlery                           |
| `Installer.swift`     | Download → verify → unpack → check → swap into place |
| `InstalledApps.swift` | What's on this Mac, read fresh off disk each scan    |
| `Library.swift`       | The observable state the whole UI reads              |
| `Preferences.swift`   | Server, install location, launch at login            |
| `RootView.swift`      | Sidebar + content; `AppGridView`, `UpdatesView`      |
| `MenuBarView.swift`   | The menu bar extra                                   |

Two things worth knowing, both learned the hard way and both covered by tests:
`InstalledApps.read` parses `Contents/Info.plist` directly rather than going
through `Bundle(url:)`, which caches for the life of the process and kept
reporting the version an app had *before* it was updated; and an app sitting in
the Trash doesn't count as installed, however happily LaunchServices keeps
resolving its bundle identifier there.

## Build

```
./make-app.sh
```

Builds a release binary, generates the icon, assembles `Purser.app`, installs
it to /Applications, and launches it. For a distributable universal build with
a `.zip` and a `.dmg`:

```
./make-app.sh --dist
```

## Tests

```
swift test
```

macOS 14+, universal (Apple Silicon and Intel), MIT licensed.
