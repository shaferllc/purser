#!/bin/bash
# Usage:
#   ./make-app.sh          build for this Mac, install to /Applications, launch
#   ./make-app.sh --dist   build a universal dist/Purser.app plus a .zip and .dmg
#
# The version comes from the VERSION file; VERSION=x.y.z in the environment
# overrides it, which is how the release workflow stamps a build.
set -euo pipefail
cd "$(dirname "$0")"

DIST=0
[ "${1:-}" = "--dist" ] && DIST=1
SHORT_VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.1.0)}"
# CFBundleVersion has to be monotonic; BUILD=n pins it in the release workflow,
# otherwise the version's own digits stand in.
BUILD_VERSION="${BUILD:-$(echo "$SHORT_VERSION" | tr -cd '0-9')}"

if [ "$DIST" = "1" ]; then
  # Anything people download has to run on both architectures — an arm64-only
  # binary is a broken download for every Intel Mac. The local install path
  # stays single-arch because it only ever has to run on this machine.
  echo "› Building universal release binary…"
  swift build -c release --arch arm64 --arch x86_64
  BINARY=".build/apple/Products/Release/Purser"
else
  echo "› Building release binary…"
  swift build -c release
  BINARY=".build/release/Purser"
fi

if [ ! -f AppIcon.icns ] || [ make-icon.swift -nt AppIcon.icns ]; then
  echo "› Generating AppIcon.icns…"
  swift make-icon.swift
fi

STAGE="$(mktemp -d)"
APP="$STAGE/Purser.app"
echo "› Assembling in staging: $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY"     "$APP/Contents/MacOS/Purser"
cp AppIcon.icns  "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Purser</string>
    <key>CFBundleDisplayName</key>          <string>Purser</string>
    <key>CFBundleIdentifier</key>           <string>com.tomshafer.purser</string>
    <key>CFBundleVersion</key>              <string>${BUILD_VERSION}</string>
    <key>CFBundleShortVersionString</key>   <string>${SHORT_VERSION}</string>
    <key>CFBundleExecutable</key>           <string>Purser</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>   <array><string>MacOSX</string></array>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleIconName</key>             <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSHumanReadableCopyright</key>     <string>© 2026 Tom Shafer</string>
</dict>
</plist>
PLIST

xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

if [ "$DIST" = "1" ]; then
  rm -rf dist
  mkdir -p dist
  /bin/mv "$APP" dist/Purser.app
  rm -rf "$STAGE"

  echo "› Packaging dist/Purser-${SHORT_VERSION}.zip"
  /usr/bin/ditto -c -k --keepParent dist/Purser.app "dist/Purser-${SHORT_VERSION}.zip"

  # A DMG alongside the zip: it opens to a window holding Purser.app next to an
  # /Applications alias, so installing is one drag rather than "unzip, then
  # find where it went". UDZO is compressed and read-only.
  echo "› Packaging dist/Purser-${SHORT_VERSION}.dmg"
  DMG_ROOT="$(mktemp -d)"
  /bin/cp -R dist/Purser.app "$DMG_ROOT/Purser.app"
  /bin/ln -s /Applications "$DMG_ROOT/Applications"
  /usr/bin/hdiutil create \
    -volname "Purser ${SHORT_VERSION}" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ -format UDZO -ov -quiet \
    "dist/Purser-${SHORT_VERSION}.dmg"
  rm -rf "$DMG_ROOT"
  echo "› Packaged: dist/Purser-${SHORT_VERSION}.dmg"
else
  DEST="/Applications/Purser.app"
  echo "› Installing to $DEST"
  /usr/bin/pkill -x Purser 2>/dev/null || true
  /bin/sleep 0.3
  rm -rf "$DEST"
  /bin/mv "$APP" "$DEST"
  rm -rf "$STAGE"
  open "$DEST"
  echo "› Installed and launched: $DEST"
fi
