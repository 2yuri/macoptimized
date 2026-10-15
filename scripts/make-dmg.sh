#!/bin/sh
# Builds build/MacOptimized-<version>.dmg with the app and an Applications shortcut.
set -eu
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/MacOptimized.app/Contents/Info.plist)
DMG="build/MacOptimized-$VERSION.dmg"
STAGE=build/dmg

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/MacOptimized.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MacOptimized $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
