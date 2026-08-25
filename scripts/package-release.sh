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
# dyld rejects mixed ad-hoc identities ("different Team IDs") — re-sign everything as one
codesign --force -s - "$STAGE/Recap.app/Contents/Frameworks/whisper.framework"
codesign --force -s - "$STAGE/Recap.app/Contents/Resources/RecapShellPlugin.bundle"
codesign --force -s - "$STAGE/Recap.app"
codesign --verify --deep --strict "$STAGE/Recap.app"

mkdir -p dist
hdiutil create -volname Recap -srcfolder "$STAGE/Recap.app" -ov -format UDZO "dist/Recap-$VERSION.dmg"
rm -rf "$STAGE"
echo "packaged: dist/Recap-$VERSION.dmg"
