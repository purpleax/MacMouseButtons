#!/bin/bash
# Builds a notarised, stapled build/MacMouseButtons-<version>.dmg ready to
# attach to a GitHub release. Needs Xcode (for notarytool and stapler), a
# Developer ID Application certificate, and a notarytool keychain profile:
#
#   xcrun notarytool store-credentials MacMouseButtons-notary
#
# Set NOTARY_PROFILE to use a profile with a different name.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-MacMouseButtons-notary}"
# notarytool and stapler ship with Xcode, not the command line tools.
if ! xcrun --find notarytool >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
if [[ -z "$IDENTITY" ]]; then
    echo "A Developer ID Application certificate is required to notarise." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="build/MacMouseButtons.app"
DMG="build/MacMouseButtons-$VERSION.dmg"

UNIVERSAL=1 TIMESTAMP=1 CODESIGN_IDENTITY="$IDENTITY" scripts/build-app.sh

# The disk image shows the app next to a shortcut to Applications.
STAGING="build/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/MacMouseButtons.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MacMouseButtons" -srcfolder "$STAGING" -format UDZO -quiet "$DMG"
rm -rf "$STAGING"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Built $DMG"
