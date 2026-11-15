#!/bin/bash
# Builds build/MacMouseButtons.app from the Swift package. Needs only the Xcode
# command line tools.
#
#   scripts/build-app.sh              build for this Mac's architecture
#   UNIVERSAL=1 scripts/build-app.sh  build for Apple silicon and Intel
#   CODESIGN_IDENTITY="..."           sign with a specific identity ("-" for ad hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacMouseButtons.app"
ARCHS=("$(uname -m)")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCHS=(arm64 x86_64); fi

# Every architecture builds to the same path, so set each binary aside
# before building the next.
STAGING="build/staging"
rm -rf "$APP" "$STAGING"
mkdir -p "$APP/Contents/MacOS" "$STAGING"

BINARIES=()
for arch in "${ARCHS[@]}"; do
    swift build -c release --arch "$arch" --product MacMouseButtons
    cp "$(swift build -c release --arch "$arch" --show-bin-path)/MacMouseButtons" "$STAGING/MacMouseButtons-$arch"
    BINARIES+=("$STAGING/MacMouseButtons-$arch")
done

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ ${#BINARIES[@]} -gt 1 ]]; then
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/MacMouseButtons"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/MacMouseButtons"
fi
rm -rf "$STAGING"

# macOS ties the Accessibility grant to the code signature. A Developer ID
# signature stays the same across rebuilds, so the grant survives. An ad hoc
# signature changes with every build, and the app must be removed from and
# re-added to the Accessibility list each time.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "No Developer ID certificate found: signing ad hoc."
fi

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/MacMouseButtons"))"
