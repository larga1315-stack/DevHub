#!/usr/bin/env bash
# Builds DevHub.app (release) into ./build and optionally installs it to ~/Applications.
#
#   ./scripts/build-app.sh            # build only
#   ./scripts/build-app.sh --install  # build and copy to ~/Applications
#
# Signing: ad-hoc by default (fine for your own Mac). For public releases set
# DEVHUB_SIGN_IDENTITY="Developer ID Application: …" and notarize (needs a paid Apple Developer account).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="DevHub"
BUNDLE_ID="${DEVHUB_BUNDLE_ID:-com.devhub.app}"
VERSION="${DEVHUB_VERSION:-0.2.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
SIGN_IDENTITY="${DEVHUB_SIGN_IDENTITY:--}"

echo "▶︎ swift build (release)…"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>he</string>
    <key>NSHumanReadableCopyright</key><string>DevHub</string>
</dict>
</plist>
PLIST

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

echo "▶︎ codesign ($([[ "$SIGN_IDENTITY" == "-" ]] && echo ad-hoc || echo "$SIGN_IDENTITY"))…"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
    # /Applications is what Finder's "Applications" sidebar shows; fall back to ~/Applications.
    DEST="/Applications"
    if [[ ! -w "$DEST" ]]; then
        DEST="$HOME/Applications"
        mkdir -p "$DEST"
    fi
    rm -rf "$HOME/Applications/$APP_NAME.app"   # remove copy from older installs
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "$DEST/$APP_NAME.app"
    cp -R "$APP" "$DEST/"
    echo "✓ הותקן ב-$DEST/$APP_NAME.app"
    open "$DEST/$APP_NAME.app"
fi
