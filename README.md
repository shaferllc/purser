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
