#!/bin/sh
# Builds build/MacOptimized-<version>.dmg with the app and an Applications shortcut.
#
#   SKIP_APP_BUILD=1   pack the existing build/MacOptimized.app (e.g. after it was notarized and stapled)
#   CODESIGN_IDENTITY  also passed to build-app.sh; when set, the DMG is signed with it too
set -eu
cd "$(dirname "$0")/.."

if [ "${SKIP_APP_BUILD:-0}" != "1" ]; then
  ./scripts/build-app.sh
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/MacOptimized.app/Contents/Info.plist)
DMG="build/MacOptimized-$VERSION.dmg"
STAGE=build/dmg

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/MacOptimized.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MacOptimized $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "$CODESIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
fi
echo "Built $DMG"
