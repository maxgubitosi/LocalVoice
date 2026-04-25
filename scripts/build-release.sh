#!/bin/bash
# Usage: ./scripts/build-release.sh 1.0.0
#
# Prerequisites:
#   - Apple Developer ID Application certificate in keychain
#   - notarytool keychain profile named "notarytool"
#     (create with: xcrun notarytool store-credentials notarytool --apple-id <email> --team-id <TEAM_ID>)
#   - create-dmg installed: brew install create-dmg
#
set -euo pipefail

VERSION=${1:?"Usage: $0 <version>  (e.g. 1.0.0)"}
IDENTITY=${DEVELOPER_ID_IDENTITY:-"Developer ID Application: YOUR_NAME (TEAM_ID)"}
APP="LocalVoice.app"
DMG="LocalVoice-${VERSION}.dmg"
ENTITLEMENTS="Sources/LocalVoice/LocalVoice.entitlements"

echo "==> Building release binary…"
swift build -c release

echo "==> Creating app bundle…"
make bundle

echo "==> Re-signing with Developer ID + hardened runtime…"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP"

echo "==> Verifying signature…"
codesign --verify --deep --strict "$APP"
spctl --assess --type exec "$APP" 2>&1 || true

echo "==> Creating DMG…"
create-dmg \
    --volname "LocalVoice $VERSION" \
    --window-size 540 380 \
    --icon-size 128 \
    --app-drop-link 380 190 \
    --icon "LocalVoice.app" 160 190 \
    "$DMG" \
    "$APP"

echo "==> Notarizing DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "notarytool" --wait

echo "==> Stapling notarization ticket…"
xcrun stapler staple "$DMG"

echo ""
echo "Done: $DMG"
echo "Upload to GitHub Releases and update appcast.xml with the new version + URL."
