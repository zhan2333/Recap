#!/bin/bash
#
#  package-release.sh
#  Recap
#
#  Created by Rio on 2026/8/25.
#
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project RecapApp.xcodeproj -scheme Recap -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build | grep -E "error:|BUILD" || true

DERIVED=$(xcodebuild -project RecapApp.xcodeproj -scheme Recap -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/{print $3; exit}')
APP="$DERIVED/Recap.app"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/Recap.app"

# Developer ID + hardened runtime when the certificate exists; ad-hoc fallback otherwise
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -n "${IDENTITY:-}" ]; then
  echo "signing with: $IDENTITY"
  codesign --force --timestamp --options runtime -s "$IDENTITY" "$STAGE/Recap.app/Contents/Frameworks/whisper.framework"
  codesign --force --timestamp --options runtime -s "$IDENTITY" "$STAGE/Recap.app/Contents/Resources/RecapShellPlugin.bundle"
  codesign --force --timestamp --options runtime -s "$IDENTITY" "$STAGE/Recap.app"
else
  echo "no Developer ID Application certificate — ad-hoc signing (users must right-click to open)"
  codesign --force -s - "$STAGE/Recap.app/Contents/Frameworks/whisper.framework"
  codesign --force -s - "$STAGE/Recap.app/Contents/Resources/RecapShellPlugin.bundle"
  codesign --force -s - "$STAGE/Recap.app"
fi
codesign --verify --deep --strict "$STAGE/Recap.app"

# Styled dmg: background art, Applications shortcut, Finder icon layout
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp scripts/dmg-background.tiff "$STAGE/.background/background.tiff"

mkdir -p dist
DMG="dist/Recap-$VERSION.dmg"
RW=$(mktemp -d)/rw.dmg
hdiutil detach -quiet /Volumes/Recap 2>/dev/null || true
hdiutil create -volname Recap -srcfolder "$STAGE" -ov -format UDRW "$RW" -quiet
hdiutil attach -readwrite -noverify -nobrowse -quiet "$RW"
osascript <<'EOS'
tell application "Finder"
  tell disk "Recap"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    set the bounds of container window to {200, 140, 800, 568}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Recap.app" of container window to {150, 205}
    set position of item "Applications" of container window to {450, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOS
sync
hdiutil detach -quiet /Volumes/Recap
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -o "$DMG" -quiet
rm -rf "$STAGE" "$(dirname "$RW")"

if [ -n "${IDENTITY:-}" ]; then
  if xcrun notarytool history --keychain-profile recap-notary >/dev/null 2>&1; then
    echo "notarizing…"
    xcrun notarytool submit "$DMG" --keychain-profile recap-notary --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  else
    echo "notary profile missing — run: xcrun notarytool store-credentials recap-notary --apple-id <AppleID> --team-id <TeamID>"
  fi
fi
echo "packaged: $DMG"
