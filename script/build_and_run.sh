#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LEO"
BUNDLE_ID="com.varun.leo"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

# SwiftPM otherwise falls back to a global cache that may be unavailable in
# restricted development environments. Keep transient compiler state local to
# the system temporary directory, never inside the app bundle or source tree.
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/leo-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/private/tmp/leo-clang-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --disable-sandbox --product LEOApp
BUILD_BINARY="$(swift build --disable-sandbox --show-bin-path)/LEOApp"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/AppResources/PkgInfo" "$APP_CONTENTS/PkgInfo"
mkdir -p "$APP_RESOURCES/VoiceCues"
cp "$ROOT_DIR/AppResources/VoiceCues/"*.aiff "$APP_RESOURCES/VoiceCues/"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>LEO uses the microphone while you hold the voice hotkey to transcribe your request locally.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>LEO reads and creates calendar events only when you explicitly ask.</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
</dict>
</plist>
PLIST

# Keep the app identity stable across rebuilds so macOS Keychain access is not
# re-prompted for every source change. Falls back to ad-hoc signing only on
# machines without a local development identity.
SIGNING_IDENTITY="${LEO_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p' | head -n 1)}"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
fi

open_app() {
  # Give LaunchServices a moment to observe the freshly materialized bundle.
  sleep 1
  # Re-register the replaced bundle so LaunchServices does not retain the
  # previous executable record for this development path.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -R "$APP_BUNDLE" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
