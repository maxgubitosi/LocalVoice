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
IDENTITY=${DEVELOPER_ID_IDENTITY:-}
APP="LocalVoice.app"
DMG="LocalVoice-${VERSION}.dmg"
ENTITLEMENTS="Sources/LocalVoice/LocalVoice.entitlements"
INFO_PLIST="Sources/LocalVoice/Info.plist"

if [[ -z "$IDENTITY" ]]; then
    echo "error: DEVELOPER_ID_IDENTITY must be set to your Developer ID Application certificate name."
    exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg is required. Install it with: brew install create-dmg"
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$IDENTITY"; then
    echo "error: signing identity not found in keychain: $IDENTITY"
    exit 1
fi

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
if [[ "$PLIST_VERSION" != "$VERSION" ]]; then
    echo "error: $INFO_PLIST has CFBundleShortVersionString=$PLIST_VERSION, expected $VERSION."
    echo "Update the plist version before building this release."
    exit 1
fi

echo "==> Building app bundle…"
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
rm -f "$DMG"
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
